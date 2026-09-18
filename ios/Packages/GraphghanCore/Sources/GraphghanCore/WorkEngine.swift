public enum EventKind: String, Codable, Sendable {
    case advance, back, jump
}

/// How many cells one tap counts inside a fill (spec §3 decision 4). Raw values are what
/// `Project.countStep` stores; `wholeRun` is 0 so the default 10 is a real step.
public enum CountStep: Int, Codable, Sendable, CaseIterable {
    case one = 1, five = 5, ten = 10, twenty = 20, wholeRun = 0
    public static let `default`: CountStep = .ten
}

public enum WorkAction: Equatable, Sendable {
    case advance
    case back
    case jump(row: Int, run: Int = 0, stitch: Int = 0)
}

public struct WorkStep: Equatable, Sendable {
    public let cursor: Cursor
    public let kind: EventKind
    /// The step moved the cursor onto a different pass (advance across a row, or a jump).
    public let startedNewRow: Bool
    /// The step completed the last run of the last pass.
    public let finished: Bool
    /// The step landed on a boundary position: the row is worked and the turn is next.
    public let atBoundary: Bool
    /// Runs the step walked past: 1 for an ordinary run, the unit's period for a repetition (#81),
    /// 0 for a counting step inside a fill, a turn, or a jump. The event log does not carry it (an
    /// event records the cursor after the action, and every derived number comes from cursors);
    /// haptics and the screens read it.
    public let runsWalked: Int
    public init(cursor: Cursor, kind: EventKind, startedNewRow: Bool, finished: Bool, atBoundary: Bool = false, runsWalked: Int = 1) {
        self.cursor = cursor; self.kind = kind; self.startedNewRow = startedNewRow; self.finished = finished; self.atBoundary = atBoundary
        self.runsWalked = runsWalked
    }
}

/// The one place cursor movement is defined. Screens, intents and the Live Activity all call this.
public enum WorkEngine {
    public static func isFinished(_ cursor: Cursor, in seq: WorkSequence) -> Bool {
        guard let last = seq.passes.last else { return false }
        return cursor.row == seq.passes.count && cursor.run == last.runs.count
    }

    /// The run under the cursor is a fill segment, so taps count cells rather than runs.
    public static func isCounting(_ cursor: Cursor, in seq: WorkSequence) -> Bool {
        guard let pass = seq.pass(at: cursor.row), cursor.run < pass.runs.count else { return false }
        return Segments.segment(containing: cursor.run, in: pass)?.kind == .fill
    }

    /// Cells per tap for `run`: the step, or the whole run.
    public static func stride(_ step: CountStep, for run: Run) -> Int {
        step == .wholeRun ? run.count : step.rawValue
    }

    /// The cursor Back lands on when it re-enters `runIndex` of `pass` from the run after it: the
    /// fill's last step boundary, so advance and back walk the same stitches; stitch 0 elsewhere.
    private static func landing(row: Int, runIndex: Int, in seq: WorkSequence, step: CountStep) -> Cursor {
        let pass = seq.passes[row - 1]
        let run = pass.runs[runIndex]
        guard Segments.segment(containing: runIndex, in: pass)?.kind == .fill else { return Cursor(row: row, run: runIndex) }
        let s = stride(step, for: run)
        let last = run.count - (run.count % s)
        return Cursor(row: row, run: runIndex, stitch: max(0, last < run.count ? last : run.count - s))
    }

    /// The first run of the repetition that contains `run`, when `run` sits inside a repeat
    /// segment of `pass`; nil elsewhere.
    static func repetitionStart(of run: Int, in pass: Pass) -> (start: Int, segment: Segment)? {
        guard let seg = Segments.segment(containing: run, in: pass), seg.kind == .repeat, seg.period > 0 else { return nil }
        return (run - (run - seg.runs.lowerBound) % seg.period, seg)
    }

    /// `perRepetition` (#81): inside a repeat segment an advance walks to the next repetition and
    /// Back returns to the start of the previous one, so the border costs a tap per unit rather
    /// than a tap per run. Off, every run is its own tap as before. Jumps are never grouped: the
    /// panel's parts and the band's long-press land on the run that was chosen.
    public static func apply(_ action: WorkAction, to cursor: Cursor, in seq: WorkSequence, step: CountStep = .default, perRepetition: Bool = true) -> WorkStep? {
        guard seq.isValid(cursor) else { return nil }
        switch action {
        case .advance:
            if isFinished(cursor, in: seq) { return nil }
            let pass = seq.passes[cursor.row - 1]
            let runs = pass.runs.count
            if cursor.run < runs {
                if isCounting(cursor, in: seq) {
                    let next = cursor.stitch + stride(step, for: pass.runs[cursor.run])
                    if next < pass.runs[cursor.run].count {
                        return WorkStep(cursor: Cursor(row: cursor.row, run: cursor.run, stitch: next), kind: .advance, startedNewRow: false, finished: false, runsWalked: 0)
                    }
                }
                // Inside a repetition the tap walks the rest of the unit; a partial unit (after a
                // jump onto one of its runs) still lands on the next repetition's first run.
                var target = cursor.run + 1
                if perRepetition, let (start, seg) = repetitionStart(of: cursor.run, in: pass) {
                    target = min(start + seg.period, seg.runs.upperBound)
                }
                if target < runs {
                    return WorkStep(cursor: Cursor(row: cursor.row, run: target), kind: .advance, startedNewRow: false, finished: false, runsWalked: target - cursor.run)
                }
                if seq.hasBoundaryStep(after: cursor.row) {
                    return WorkStep(cursor: Cursor(row: cursor.row, run: runs), kind: .advance, startedNewRow: false, finished: false, atBoundary: true, runsWalked: runs - cursor.run)
                }
            }
            let walked = cursor.run < runs ? runs - cursor.run : 0
            if cursor.row < seq.passes.count {
                return WorkStep(cursor: Cursor(row: cursor.row + 1, run: 0), kind: .advance, startedNewRow: true, finished: false, runsWalked: walked)
            }
            return WorkStep(cursor: Cursor(row: cursor.row, run: runs), kind: .advance, startedNewRow: false, finished: true, runsWalked: walked)
        case .back:
            let pass = seq.passes[cursor.row - 1]
            if cursor.run < pass.runs.count, cursor.stitch > 0 {
                let s = stride(step, for: pass.runs[cursor.run])
                return WorkStep(cursor: Cursor(row: cursor.row, run: cursor.run, stitch: max(0, cursor.stitch - s)), kind: .back, startedNewRow: false, finished: false, runsWalked: 0)
            }
            if cursor.run > 0 {
                // The run before the cursor is inside a repetition: Back lands on that repetition's
                // first run, the mirror of the advance that walked it (a fill is never a repeat).
                if perRepetition, let (start, _) = repetitionStart(of: cursor.run - 1, in: pass) {
                    return WorkStep(cursor: Cursor(row: cursor.row, run: start), kind: .back, startedNewRow: false, finished: false, runsWalked: cursor.run - start)
                }
                return WorkStep(cursor: landing(row: cursor.row, runIndex: cursor.run - 1, in: seq, step: step), kind: .back, startedNewRow: false, finished: false)
            }
            if cursor.row > 1 {
                let prevRuns = seq.passes[cursor.row - 2].runs.count
                if seq.hasBoundaryStep(after: cursor.row - 1) {
                    return WorkStep(cursor: Cursor(row: cursor.row - 1, run: prevRuns), kind: .back, startedNewRow: false, finished: false, atBoundary: true, runsWalked: 0)
                }
                return WorkStep(cursor: landing(row: cursor.row - 1, runIndex: max(0, prevRuns - 1), in: seq, step: step), kind: .back, startedNewRow: false, finished: false)
            }
            return nil
        case .jump(let row, let run, let stitch):
            guard let pass = seq.pass(at: row), run >= 0, run < pass.runs.count, stitch >= 0, stitch < pass.runs[run].count else { return nil }
            var target = Cursor(row: row, run: run)
            if Segments.segment(containing: run, in: pass)?.kind == .fill {
                let s = stride(step, for: pass.runs[run])
                target.stitch = stitch - (stitch % s)
            }
            return WorkStep(cursor: target, kind: .jump, startedNewRow: row != cursor.row, finished: false, runsWalked: 0)
        }
    }
}

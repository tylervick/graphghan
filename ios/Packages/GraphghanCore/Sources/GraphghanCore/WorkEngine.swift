public enum EventKind: String, Codable, Sendable {
    case advance, back, jump
}

public enum WorkAction: Equatable, Sendable {
    case advance
    case back
    case jump(row: Int, run: Int = 0)
}

public struct WorkStep: Equatable, Sendable {
    public let cursor: Cursor
    public let kind: EventKind
    /// The step moved the cursor onto a different pass (advance across a row, or a jump).
    public let startedNewRow: Bool
    /// The step completed the last run of the last pass.
    public let finished: Bool
    public init(cursor: Cursor, kind: EventKind, startedNewRow: Bool, finished: Bool) {
        self.cursor = cursor; self.kind = kind; self.startedNewRow = startedNewRow; self.finished = finished
    }
}

/// The one place cursor movement is defined. Screens, intents and the Live Activity all call this.
public enum WorkEngine {
    public static func isFinished(_ cursor: Cursor, in seq: WorkSequence) -> Bool {
        guard let last = seq.passes.last else { return false }
        return cursor.row == seq.passes.count && cursor.run == last.runs.count
    }

    public static func apply(_ action: WorkAction, to cursor: Cursor, in seq: WorkSequence) -> WorkStep? {
        guard seq.isValid(cursor) else { return nil }
        switch action {
        case .advance:
            if isFinished(cursor, in: seq) { return nil }
            let runs = seq.passes[cursor.row - 1].runs.count
            if cursor.run + 1 < runs {
                return WorkStep(cursor: Cursor(row: cursor.row, run: cursor.run + 1), kind: .advance, startedNewRow: false, finished: false)
            }
            if cursor.row < seq.passes.count {
                return WorkStep(cursor: Cursor(row: cursor.row + 1, run: 0), kind: .advance, startedNewRow: true, finished: false)
            }
            return WorkStep(cursor: Cursor(row: cursor.row, run: runs), kind: .advance, startedNewRow: false, finished: true)
        case .back:
            if cursor.run > 0 {
                return WorkStep(cursor: Cursor(row: cursor.row, run: cursor.run - 1), kind: .back, startedNewRow: false, finished: false)
            }
            if cursor.row > 1 {
                let prevRuns = seq.passes[cursor.row - 2].runs.count
                return WorkStep(cursor: Cursor(row: cursor.row - 1, run: max(0, prevRuns - 1)), kind: .back, startedNewRow: false, finished: false)
            }
            return nil
        case .jump(let row, let run):
            guard let pass = seq.pass(at: row), run >= 0, run < pass.runs.count else { return nil }
            return WorkStep(cursor: Cursor(row: row, run: run), kind: .jump, startedNewRow: row != cursor.row, finished: false)
        }
    }
}

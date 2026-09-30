import Foundation

public enum PieceModel: Sendable {
    case chart(WorkSequence)
    case written(WrittenSequence)
}

public struct PieceSummary: Equatable, Sendable {
    public let key: PieceKey
    public let isWritten: Bool
    public let finished: Bool
    public let percent: Double?
    public let cellsDone: Int?
    public let totalCells: Int?
    public let rowsDone: Int?
    public let totalRows: Int?
    public let stitchesDone: Int?
    public let totalStitches: Int?
}

public struct ProjectSession: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let cells: Int
    public let rows: Int
}

public struct ProjectSummary: Equatable, Sendable {
    public let pieces: [PieceSummary]
    public let piecesDone: Int
    public let piecesTotal: Int
    public let assemblyDone: Int
    public let assemblyTotal: Int
    public let sessions: [ProjectSession]
    public let activeSeconds: Int
    public let stitchesPerHour: Double?
}

/// A pieced project's numbers (progress schema 2, spec 2026-09-25 §5.4). Mirrors
/// graphghan.progress.summarize_project; no project percent (§3.4).
public enum ProjectPace {
    static func roundTenth(_ x: Double) -> Double { (x * 10).rounded(.toNearestOrEven) / 10 }

    public static func pieceSummary(key: PieceKey, cursor: Cursor, finished: Bool, model: PieceModel) -> PieceSummary {
        switch model {
        case .chart(let seq):
            let total = seq.totalCells
            let done = seq.cellsBefore(cursor) ?? 0
            let stitch = seq.cellKind == .stitch
            return PieceSummary(key: key, isWritten: false, finished: finished,
                                percent: total > 0 ? roundTenth(100 * Double(done) / Double(total)) : 0, cellsDone: done, totalCells: total,
                                rowsDone: nil, totalRows: nil, stitchesDone: stitch ? done : nil, totalStitches: stitch ? total : nil)
        case .written(let seq):
            let done = seq.rowsDone(at: cursor.row, finished: finished)
            let percent = seq.totalRows.map { $0 > 0 ? roundTenth(100 * Double(done) / Double($0)) : 0 }
            let stTotal = seq.totalStitches
            let stDone = stTotal.map { finished ? $0 : (seq.stitchesBefore(row: cursor.row) ?? 0) }
            return PieceSummary(key: key, isWritten: true, finished: finished, percent: percent, cellsDone: nil, totalCells: nil,
                                rowsDone: done, totalRows: seq.totalRows, stitchesDone: stDone, totalStitches: stTotal)
        }
    }

    /// A piece copy's running state, carried across sessions rather than reset by a gap: the
    /// cursor after its last event, and whether that event was a *finishing* advance (an
    /// `.advance` on a written piece whose row didn't move). Mirrors Python's `last` dict in
    /// `summarize_project`, which is why un-finishing (back) then re-finishing across a gap, with
    /// the row never moving, adds no rows to the later session -- pinned by
    /// `ProjectPaceTests.refinishingAfterAGapAddsNoRows`, mirroring
    /// `test_refinishing_after_a_gap_adds_no_rows` in `tests/test_progress_project.py`.
    private struct PieceState { var cursor: Cursor; var finished: Bool }
    private struct OpenSession {
        var start: Date
        var end: Date
        var from: [PieceKey: PieceState] = [:]
        var to: [PieceKey: PieceState] = [:]
    }

    public static func summarize(_ doc: ProjectProgressDocument, manifest: PatternManifest, models: [String: PieceModel],
                                 gap: TimeInterval = Pace.sessionGap) -> ProjectSummary {
        let pieces = doc.pieces.compactMap { p in
            models[p.piece].map { pieceSummary(key: p.key, cursor: p.cursor, finished: p.finished != nil, model: $0) }
        }

        // Sessions over every event, split by time; each piece's worked amount across the
        // session. An event naming a piece the manifest doesn't know (no entry in `models`) is
        // skipped outright: it neither opens nor extends a session, and never updates `last`.
        var last: [PieceKey: PieceState] = [:]
        var sessions: [OpenSession] = []
        var current: OpenSession?
        // Sorted by (t, recorded index): same-second events keep their recorded order, as
        // Python's stable sort does -- Swift's `sorted` makes no stability promise.
        let ordered = doc.events.enumerated()
            .sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }
            .map(\.element)
        for e in ordered {
            guard let model = models[e.piece] else { continue }
            if current == nil || e.t.timeIntervalSince(current!.end) > gap {
                if let c = current { sessions.append(c) }
                current = OpenSession(start: e.t, end: e.t)
            }
            let key = e.key
            let before = last[key] ?? PieceState(cursor: .start, finished: false)
            if current!.from[key] == nil { current!.from[key] = before }
            let isWritten: Bool = { if case .written = model { return true } else { return false } }()
            let finishing = e.kind == .advance && e.row == before.cursor.row && isWritten
            let state = PieceState(cursor: e.cursor, finished: finishing)
            current!.to[key] = state
            current!.end = e.t
            last[key] = state
        }
        if let c = current { sessions.append(c) }

        var out: [ProjectSession] = []
        var active = 0, chartActive = 0, chartStitches = 0
        for s in sessions {
            var cells = 0, rows = 0, touchedChart = false
            for (key, from) in s.from {
                guard let to = s.to[key] else { continue }
                switch models[key.piece] {
                case .chart(let seq)?:
                    touchedChart = true
                    let n = max(0, (seq.cellsBefore(to.cursor) ?? 0) - (seq.cellsBefore(from.cursor) ?? 0))
                    cells += n
                    if seq.cellKind == .stitch { chartStitches += n }
                case .written(let seq)?:
                    let before = seq.rowsDone(at: from.cursor.row, finished: from.finished)
                    let after = seq.rowsDone(at: to.cursor.row, finished: to.finished)
                    rows += max(0, after - before)
                case nil:
                    break
                }
            }
            let secs = Int(s.end.timeIntervalSince(s.start).rounded(.down))
            active += secs
            if touchedChart { chartActive += secs }
            out.append(ProjectSession(start: s.start, end: s.end, cells: cells, rows: rows))
        }
        return ProjectSummary(pieces: pieces, piecesDone: pieces.filter(\.finished).count, piecesTotal: manifest.piecesTotal,
                              assemblyDone: doc.assemblyDone.count, assemblyTotal: manifest.assembly.count, sessions: out,
                              activeSeconds: active,
                              stitchesPerHour: chartActive > 0 ? roundTenth(Double(chartStitches) / (Double(chartActive) / 3600)) : nil)
    }
}

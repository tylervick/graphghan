import Foundation

/// One row of a written piece as the Work screen shows it: the entry's text, labelled with its
/// place in a range ("R 27 - 86 (5 of 60)").
public struct WrittenPass: Equatable, Sendable {
    public let label: String
    public let text: String
    public let count: Int?
    public let code: String?
    /// Index of the printed entry this row belongs to.
    public let entry: Int
    public init(label: String, text: String, count: Int?, code: String?, entry: Int) {
        self.label = label; self.text = text; self.count = count; self.code = code; self.entry = entry
    }
}

/// A written piece in working order: one pass per row, no runs, no stitch cursor (spec §6.4).
public struct WrittenSequence: Sendable {
    public let document: RowsDocument
    public init(_ document: RowsDocument) { self.document = document }

    /// The last row, or nil when the last entry is open-ended ("until desired length").
    public var totalRows: Int? { document.entries.last?.to }
    public var isOpen: Bool { totalRows == nil }
    private var allCounted: Bool { document.entries.allSatisfy { $0.count != nil } }
    /// Only for a closed piece whose every entry prints its count; nil otherwise (§Cells rule).
    public var totalStitches: Int? {
        guard !isOpen, allCounted else { return nil }
        return document.entries.reduce(0) { $0 + $1.count! * ($1.to! - $1.from + 1) }
    }

    public func pass(at row: Int) -> WrittenPass? {
        guard row >= 1 else { return nil }
        for (i, e) in document.entries.enumerated() where row >= e.from && (e.to.map { row <= $0 } ?? true) {
            let k = row - e.from + 1
            let label: String
            if let to = e.to { label = to == e.from ? e.label : "\(e.label) (\(k) of \(to - e.from + 1))" }
            else { label = "\(e.label) (\(k))" }
            return WrittenPass(label: label, text: e.text, count: e.count, code: e.code, entry: i)
        }
        return nil
    }

    /// Rows worked at a cursor on `row`: the rows before it, or all of them once finished
    /// (`row` itself for an open-ended piece). Mirrors graphghan.progress._rows_done.
    public func rowsDone(at row: Int, finished: Bool) -> Int {
        finished ? (totalRows ?? row) : row - 1
    }

    /// Stitches in rows 1 ..< `row`, when every entry prints its count.
    public func stitchesBefore(row: Int) -> Int? {
        guard allCounted else { return nil }
        return document.entries.reduce(0) { sum, e in
            let last = min(e.to ?? (row - 1), row - 1)
            return sum + max(0, last - e.from + 1) * e.count!
        }
    }
}

/// Cursor movement on a written piece: whole rows, `run` always 0 (spec §5.4). Done on a closed
/// piece's last row finishes it and stays there; an open-ended piece never finishes on Done.
public enum WrittenEngine {
    /// `finished` says the piece is already finished: Back then un-finishes it in place.
    public static func apply(_ action: WorkAction, to cursor: Cursor, in seq: WrittenSequence, finished: Bool = false) -> WorkStep? {
        let row = cursor.row
        switch action {
        case .advance:
            if let total = seq.totalRows, row >= total {
                guard !finished else { return nil }
                return WorkStep(cursor: Cursor(row: total, run: 0), kind: .advance, startedNewRow: false, finished: true)
            }
            return WorkStep(cursor: Cursor(row: row + 1, run: 0), kind: .advance, startedNewRow: true, finished: false)
        case .back:
            if finished { return WorkStep(cursor: Cursor(row: row, run: 0), kind: .back, startedNewRow: false, finished: false) }
            guard row > 1 else { return nil }
            return WorkStep(cursor: Cursor(row: row - 1, run: 0), kind: .back, startedNewRow: true, finished: false)
        case .jump(let target, _, _):
            guard target >= 1, seq.totalRows.map({ target <= $0 }) ?? true else { return nil }
            return WorkStep(cursor: Cursor(row: target, run: 0), kind: .jump, startedNewRow: target != row, finished: false)
        }
    }
}

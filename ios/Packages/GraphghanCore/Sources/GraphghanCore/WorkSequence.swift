import Foundation

/// Where the crocheter is: 1-based pass, 0-based run, and how many cells of that run are worked.
/// `run == runs.count` is the boundary position (every run worked, the turn not yet taken); on the
/// last pass that is the finished state. `stitch` is `0 ..< count` inside a run and 0 at the boundary.
public struct Cursor: Equatable, Hashable, Codable, Sendable {
    public var row: Int
    public var run: Int
    public var stitch: Int
    public init(row: Int, run: Int, stitch: Int = 0) { self.row = row; self.run = run; self.stitch = stitch }
    public static let start = Cursor(row: 1, run: 0)

    enum CodingKeys: String, CodingKey { case row, run, stitch }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        row = try c.decode(Int.self, forKey: .row)
        run = try c.decode(Int.self, forKey: .run)
        stitch = try c.decodeIfPresent(Int.self, forKey: .stitch) ?? 0
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(row, forKey: .row)
        try c.encode(run, forKey: .run)
        if stitch != 0 { try c.encode(stitch, forKey: .stitch) }   // schema 1 stays byte-identical for old documents
    }
}

public enum Side: String, Codable, Sendable, Equatable {
    case rs = "RS"
    case ws = "WS"
    public var other: Side { self == .rs ? .ws : .rs }
}

public enum Direction: String, Codable, Sendable, Equatable {
    case rtl, ltr
    public var flipped: Direction { self == .rtl ? .ltr : .rtl }
}

public struct Run: Equatable, Hashable, Sendable {
    public let code: String
    public let count: Int
    /// Leftmost grid column of the run regardless of reading direction; nil for explicit passes that omit it.
    public let x0: Int?
    public init(code: String, count: Int, x0: Int?) { self.code = code; self.count = count; self.x0 = x0 }
}

public struct Pass: Equatable, Sendable {
    public let label: String
    public let side: Side?
    public let direction: Direction?
    public let gridRow: Int?
    public let runs: [Run]
    public init(label: String, side: Side?, direction: Direction?, gridRow: Int?, runs: [Run]) {
        self.label = label; self.side = side; self.direction = direction; self.gridRow = gridRow; self.runs = runs
    }
    public var cells: Int { runs.reduce(0) { $0 + $1.count } }
}

public enum SequenceError: Error, Equatable {
    case unsupportedTechnique(String)
    case malformedPasses(String)
}

/// The chart in working order. Explicit `passes` win; `rows` and `rounds` are derived; anything
/// else has no working order (display only). Mirrors graphghan.chartdoc.sequence.
public struct WorkSequence: Sendable {
    public let passes: [Pass]
    public let cellKind: CellKind
    /// `"rows"`, `"rounds"`, or nil when explicit passes were given.
    public let technique: String?
    /// The chart states a `turn` boundary (`gauge.boundary.kind == "turn"`).
    public let turnBoundary: Bool
    public let totalCells: Int
    private let before: [Int]  // cells before pass i (0-based)

    /// The stitch count, when a cell is a stitch. Nil otherwise: the number exists but this reader
    /// cannot compute it, and a wrong number is worse than none (#44).
    public var totalStitches: Int? { cellKind == .stitch ? totalCells : nil }

    public init(passes: [Pass], cellKind: CellKind = .stitch, technique: String? = nil, turnBoundary: Bool = false) {
        self.passes = passes
        self.cellKind = cellKind
        self.technique = technique
        self.turnBoundary = turnBoundary
        var before: [Int] = []
        var total = 0
        for p in passes { before.append(total); total += p.cells }
        self.before = before
        self.totalCells = total
    }

    /// A pass has a boundary step when flat work turns after it, or the chart says so; never after
    /// the last pass, and never in the round -- worked in a spiral there is nothing to turn, whatever
    /// `gauge.boundary` declares for the flat parts of the same pattern (spec §4.4).
    public func hasBoundaryStep(after row: Int) -> Bool {
        guard row >= 1, row < passes.count else { return false }
        return technique != "rounds" && (technique == "rows" || turnBoundary)
    }

    public init(chart: Chart) throws {
        // Python's `sequence()` uses `isinstance(doc.get("passes"), list)`: anything else -- a
        // number, a string, an object -- falls through to technique derivation rather than failing.
        if let raw = chart.document.passes, raw.arrayValue != nil {
            self.init(passes: try WorkSequence.explicitPasses(raw, chart: chart), cellKind: chart.cellKind, technique: nil, turnBoundary: chart.stitch?.boundary?.kind == .turn)
            return
        }
        let doc = chart.document
        let type = doc.techniqueType
        guard type == "rows" || type == "rounds" else { throw SequenceError.unsupportedTechnique(type) }
        let firstSide = Side(rawValue: doc.techniqueFirstSide) ?? .rs
        let rsDirection = Direction(rawValue: doc.techniqueRSDirection) ?? .rtl
        // Python: `y = h - k if start == "bottom" else k - 1`; only the literal "bottom" (the
        // default when the key is absent) works from the bottom up.
        let fromBottom = doc.techniqueStart == "bottom"
        let label = type == "rows" ? "Row" : "Round"
        var passes: [Pass] = []
        passes.reserveCapacity(chart.height)
        for k in stride(from: 1, through: chart.height, by: 1) {
            let y = fromBottom ? chart.height - k : k - 1
            let side: Side
            let direction: Direction
            if type == "rows" {
                side = k % 2 == 1 ? firstSide : firstSide.other
                direction = side == .rs ? rsDirection : rsDirection.flipped
            } else {
                side = firstSide
                direction = rsDirection
            }
            var runs = chart.runsByRow[y].map { Run(code: chart.palette[$0.colorIndex].code, count: $0.count, x0: $0.x0) }
            if direction == .rtl { runs.reverse() }
            passes.append(Pass(label: "\(label) \(k)", side: side, direction: direction, gridRow: y, runs: runs))
        }
        self.init(passes: passes, cellKind: chart.cellKind, technique: type, turnBoundary: chart.stitch?.boundary?.kind == .turn)
    }

    private static func explicitPasses(_ raw: JSONValue, chart: Chart) throws -> [Pass] {
        guard let list = raw.arrayValue else { throw SequenceError.malformedPasses("passes is not a list") }
        return try list.enumerated().map { i, item in
            guard let o = item.objectValue else { throw SequenceError.malformedPasses("passes[\(i)] is not an object") }
            guard let runsRaw = o["runs"]?.arrayValue else { throw SequenceError.malformedPasses("passes[\(i)].runs is not a list") }
            let runs = try runsRaw.enumerated().map { j, r -> Run in
                guard let ro = r.objectValue, let code = ro["code"]?.stringValue, let count = ro["count"]?.intValue, count >= 1 else {
                    throw SequenceError.malformedPasses("passes[\(i)].runs[\(j)] is malformed")
                }
                guard chart.colorIndex(of: code) != nil else { throw SequenceError.malformedPasses("passes[\(i)].runs[\(j)] uses unknown code \(code)") }
                return Run(code: code, count: count, x0: ro["x0"]?.intValue)
            }
            guard !runs.isEmpty else { throw SequenceError.malformedPasses("passes[\(i)].runs is empty") }
            let side = o["side"]?.stringValue.flatMap(Side.init(rawValue:))
            let direction = o["direction"]?.stringValue.flatMap(Direction.init(rawValue:))
            // A grid row outside the chart would index `chart.runsByRow` out of bounds in the
            // strip drawing, so refuse it here rather than crashing at the hook.
            let gridRow = o["grid_row"]?.intValue
            if let gridRow, gridRow < 0 || gridRow >= chart.height {
                throw SequenceError.malformedPasses("passes[\(i)].grid_row out of range")
            }
            return Pass(label: o["label"]?.stringValue ?? "", side: side, direction: direction, gridRow: gridRow, runs: runs)
        }
    }

    public var isEmpty: Bool { passes.isEmpty }

    public func pass(at row: Int) -> Pass? {
        guard row >= 1, row <= passes.count else { return nil }
        return passes[row - 1]
    }

    public func isValid(_ cursor: Cursor) -> Bool {
        guard let p = pass(at: cursor.row), cursor.run >= 0, cursor.run <= p.runs.count, cursor.stitch >= 0 else { return false }
        if cursor.run < p.runs.count { return cursor.stitch < p.runs[cursor.run].count }
        return cursor.stitch == 0
    }

    /// Cells completed at the cursor: every earlier pass, the runs before `run`, and `stitch` cells of the run in hand.
    public func cellsBefore(_ cursor: Cursor) -> Int? {
        guard isValid(cursor) else { return nil }
        let p = passes[cursor.row - 1]
        return before[cursor.row - 1] + p.runs.prefix(cursor.run).reduce(0) { $0 + $1.count } + cursor.stitch
    }

    /// The pass list in the shape Python's `chartdoc.sequence` returns, for hashing against fixtures.
    public var jsonValue: JSONValue {
        .array(passes.map { p in
            .object([
                "label": .string(p.label),
                "side": p.side.map { .string($0.rawValue) } ?? .null,
                "direction": p.direction.map { .string($0.rawValue) } ?? .null,
                "grid_row": p.gridRow.map(JSONValue.int) ?? .null,
                "runs": .array(p.runs.map { r in
                    .object(["code": .string(r.code), "count": .int(r.count), "x0": r.x0.map(JSONValue.int) ?? .null])
                }),
            ])
        })
    }
}

import Foundation

/// Where the crocheter is: the 1-based pass and the 0-based run within it.
/// `run == runs.count` on the last pass means the chart is finished.
public struct Cursor: Equatable, Hashable, Codable, Sendable {
    public var row: Int
    public var run: Int
    public init(row: Int, run: Int) { self.row = row; self.run = run }
    public static let start = Cursor(row: 1, run: 0)
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
    public var stitches: Int { runs.reduce(0) { $0 + $1.count } }
}

public enum SequenceError: Error, Equatable {
    case unsupportedTechnique(String)
    case malformedPasses(String)
}

/// The chart in working order. Explicit `passes` win; `rows` and `rounds` are derived; anything
/// else has no working order (display only). Mirrors graphghan.chartdoc.sequence.
public struct WorkSequence: Sendable {
    public let passes: [Pass]
    public let totalStitches: Int
    private let before: [Int]  // stitches before pass i (0-based)

    public init(passes: [Pass]) {
        self.passes = passes
        var before: [Int] = []
        var total = 0
        for p in passes { before.append(total); total += p.stitches }
        self.before = before
        self.totalStitches = total
    }

    public init(chart: Chart) throws {
        if let raw = chart.document.passes {
            self.init(passes: try WorkSequence.explicitPasses(raw, chart: chart))
            return
        }
        let doc = chart.document
        let type = doc.techniqueType
        guard type == "rows" || type == "rounds" else { throw SequenceError.unsupportedTechnique(type) }
        let firstSide = Side(rawValue: doc.techniqueFirstSide) ?? .rs
        let rsDirection = Direction(rawValue: doc.techniqueRSDirection) ?? .rtl
        let fromBottom = doc.techniqueStart != "top"
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
        self.init(passes: passes)
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
            return Pass(label: o["label"]?.stringValue ?? "", side: side, direction: direction, gridRow: o["grid_row"]?.intValue, runs: runs)
        }
    }

    public var isEmpty: Bool { passes.isEmpty }

    public func pass(at row: Int) -> Pass? {
        guard row >= 1, row <= passes.count else { return nil }
        return passes[row - 1]
    }

    public func isValid(_ cursor: Cursor) -> Bool {
        guard let p = pass(at: cursor.row) else { return false }
        return cursor.run >= 0 && cursor.run <= p.runs.count
    }

    /// Stitches completed when the cursor sits at (row, run): every earlier pass plus the runs before `run`.
    public func stitchesBefore(_ cursor: Cursor) -> Int? {
        guard isValid(cursor) else { return nil }
        let p = passes[cursor.row - 1]
        return before[cursor.row - 1] + p.runs.prefix(cursor.run).reduce(0) { $0 + $1.count }
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

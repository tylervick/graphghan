/// A run of consecutive passes that look alike to the person working them (look-ahead spec §3):
/// the braid strip, the plain rows above it, a line of lettering with the sky around it.
public struct Stretch: Equatable, Sendable {
    public enum Kind: String, Sendable { case plain, `repeat`, pattern }
    /// 1-based passes, as `Cursor.row`.
    public let rows: ClosedRange<Int>
    public let kind: Kind
    /// Palette codes by total cells across the stretch, most first; ties by palette order.
    public let colours: [String]
    public init(rows: ClosedRange<Int>, kind: Kind, colours: [String]) {
        self.rows = rows; self.kind = kind; self.colours = colours
    }
}

/// Pure partition of a sequence's passes into stretches. The thresholds are the spec's, chosen
/// against Craigh na Dun; `StretchesTests` pins its 24 stretches.
public enum Stretches {
    /// Two neighbouring rows whose run counts differ by this factor or more are different
    /// stretches: a plain row of 3 runs against a braid row of 53, not a lettering row of 23
    /// against one of 35.
    public static let boundaryRatio = 3.0
    /// A stretch shorter than this is a blip in the stretch before it (row 41 of Craigh na Dun,
    /// the one row where Purple and Charcoal meet).
    public static let minimumLength = 2
    /// A row of this many runs or fewer is plain.
    public static let plainMaxRuns = 3

    /// `codes` is the palette order, for ties in `colours`.
    public static func of(_ sequence: WorkSequence, codes: [String]) -> [Stretch] {
        let passes = sequence.passes
        guard !passes.isEmpty else { return [] }
        var ranges: [ClosedRange<Int>] = [1...1]
        for i in 1..<passes.count {
            if boundary(passes[i - 1], passes[i]) {
                ranges.append((i + 1)...(i + 1))
            } else {
                ranges[ranges.count - 1] = ranges[ranges.count - 1].lowerBound...(i + 1)
            }
        }
        var merged: [ClosedRange<Int>] = []
        for range in ranges {
            if let last = merged.last, range.count < minimumLength {
                merged[merged.count - 1] = last.lowerBound...range.upperBound
            } else {
                merged.append(range)
            }
        }
        return merged.map { range in
            let rows = range.map { passes[$0 - 1] }
            return Stretch(rows: range, kind: kind(of: rows), colours: colours(of: rows, codes: codes))
        }
    }

    /// Index into `stretches` of the one containing pass `row`, or nil.
    public static func index(containing row: Int, in stretches: [Stretch]) -> Int? {
        stretches.firstIndex { $0.rows.contains(row) }
    }

    /// A colour joins or leaves, or the run count jumps by `boundaryRatio`; an empty pass is a
    /// boundary on either side.
    private static func boundary(_ a: Pass, _ b: Pass) -> Bool {
        if Set(a.runs.map(\.code)) != Set(b.runs.map(\.code)) { return true }
        let lo = min(a.runs.count, b.runs.count), hi = max(a.runs.count, b.runs.count)
        if lo == 0 { return hi > 0 }
        return Double(hi) / Double(lo) >= boundaryRatio
    }

    private static func kind(of rows: [Pass]) -> Stretch.Kind {
        if rows.allSatisfy({ $0.runs.count <= plainMaxRuns }) { return .plain }
        let repeated = rows.allSatisfy { pass in
            Segments.of(pass).contains { segment in
                segment.kind == .repeat && segment.runs.reduce(0) { $0 + pass.runs[$1].count } * 2 >= pass.cells
            }
        }
        return repeated ? .repeat : .pattern
    }

    private static func colours(of rows: [Pass], codes: [String]) -> [String] {
        var cells: [String: Int] = [:]
        for pass in rows { for run in pass.runs { cells[run.code, default: 0] += run.count } }
        func order(_ code: String) -> Int { codes.firstIndex(of: code) ?? codes.count }
        return cells.keys.sorted { a, b in
            cells[a]! != cells[b]! ? cells[a]! > cells[b]! : order(a) < order(b)
        }
    }
}

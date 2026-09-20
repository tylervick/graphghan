import Foundation

/// The chart the written rows describe, when there is no picture to check them against (phone
/// import spec §4.3): a port of `prose.written_to_grid` and its checks, sentence for sentence.
public enum RowsChart {
    public struct Row: Sendable {
        public let row: Int
        public let runs: [(code: String, count: Int)]
        public let total: Int?
        public init(row: Int, runs: [(code: String, count: Int)], total: Int?) {
            self.row = row
            self.runs = runs
            self.total = total
        }
    }

    public struct Problems: Error, Equatable, Sendable {
        public let sentences: [String]
        public init(sentences: [String]) { self.sentences = sentences }
    }

    /// Working direction of a written row: row 1 starts at the printed corner; rows alternate.
    static func readsRightToLeft(row: Int, row1: String) -> Bool {
        let startsRight = row1.hasSuffix("right")
        return row % 2 == 1 ? startsRight : !startsRight
    }

    static func gridRow(row: Int, height: Int, row1: String) -> Int {
        row1.hasPrefix("bottom") ? height - row : row - 1
    }

    /// The chart rows, top to bottom, in the format's run strings, or every problem found.
    public static func rowStrings(rows: [Row], codes: [String], width: Int, height: Int, row1: String = "bottom-right") -> Result<[String], Problems> {
        var problems = totalProblems(rows, width: width) + numberProblems(rows, height: height)
        let known = Set(codes)
        for r in rows {
            if let bad = r.runs.first(where: { !known.contains($0.code) }) {
                let list = codes.map { "\"\($0)\"" }.joined(separator: ", ")
                problems.append("row \(r.row) uses code '\(bad.code)', not in the palette [\(list)]")
            }
        }
        if !problems.isEmpty { return .failure(Problems(sentences: problems)) }
        var grid = [[(code: String, count: Int)]](repeating: [], count: height)
        for r in rows {
            let runs = readsRightToLeft(row: r.row, row1: row1) ? Array(r.runs.reversed()) : r.runs
            grid[gridRow(row: r.row, height: height, row1: row1)] = runs
        }
        return .success(grid.map { ChartWriter.runString($0) })
    }

    /// Every written row whose runs do not sum to the chart width, or to its own printed total.
    static func totalProblems(_ rows: [Row], width: Int) -> [String] {
        rows.compactMap { r in
            let total = r.runs.reduce(0) { $0 + $1.count }
            if let printed = r.total, printed != total { return "row \(r.row): runs sum to \(total) but the pattern prints \(printed) sts" }
            if total != width { return "row \(r.row): runs sum to \(total), chart width is \(width)" }
            return nil
        }
    }

    static func numberProblems(_ rows: [Row], height: Int) -> [String] {
        var counts: [Int: Int] = [:]
        for r in rows { counts[r.row, default: 0] += 1 }
        var out: [String] = []
        let dup = counts.filter { $0.value > 1 }.keys.sorted()
        if !dup.isEmpty { out.append("row " + dup.map(String.init).joined(separator: ", ") + " printed twice") }
        let present = Set(counts.keys)
        let missing = height >= 1 ? (1...height).filter { !present.contains($0) } : []
        if !missing.isEmpty { out.append("missing rows \(ranges(missing)) of \(height)") }
        let beyond = present.filter { $0 > height }.sorted()
        if !beyond.isEmpty { out.append("rows \(ranges(beyond)) are beyond the chart height \(height)") }
        return out
    }

    /// "2-3", "5, 7-9": the Python `_ranges`.
    static func ranges(_ nums: [Int]) -> String {
        var out: [String] = []
        var i = 0
        while i < nums.count {
            var j = i
            while j + 1 < nums.count, nums[j + 1] == nums[j] + 1 { j += 1 }
            out.append(j > i ? "\(nums[i])-\(nums[j])" : "\(nums[i])")
            i = j + 1
        }
        return out.joined(separator: ", ")
    }

    /// Loud colours no palette entry is near, for a key colour the pages give no hex for.
    public static let placeholders = ["#ff00ff", "#00ffff", "#ffff00", "#ff8000", "#8000ff", "#00ff80", "#ff0080", "#0080ff"]

    public static func placeholderHex(avoiding taken: [String]) -> String {
        let have = taken.compactMap(rgb)
        for candidate in placeholders {
            guard let c = rgb(candidate) else { continue }
            if have.allSatisfy({ distance($0, c) > 60 }) { return candidate }
        }
        return placeholders[placeholders.count - 1]
    }

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        guard hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (Double((v >> 16) & 0xff), Double((v >> 8) & 0xff), Double(v & 0xff))
    }

    /// Euclidean RGB distance: a stand-in for the Python Lab distance, enough to keep placeholders
    /// away from real colours (60 of 441 is roughly the Lab 20 the Python uses).
    static func distance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
    }
}

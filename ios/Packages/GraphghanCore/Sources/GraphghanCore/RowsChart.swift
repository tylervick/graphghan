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

    public static let mismatchLimit = 0.10  // MISMATCH_LIMIT: more rows than this disagreeing means the orientation is wrong

    /// The written grid as palette indexes in display order, nil in the rows not given (`written_to_grid`
    /// over a prefix): a stopped check compares only what was read. Problems are the Python's,
    /// except that missing rows are not a problem here.
    static func writtenGrid(rows: [Row], codes: [String], width: Int, height: Int, row1: String) -> Result<[UInt8?], Problems> {
        var problems = totalProblems(rows, width: width)
        var counts: [Int: Int] = [:]
        for r in rows { counts[r.row, default: 0] += 1 }
        let dup = counts.filter { $0.value > 1 }.keys.sorted()
        if !dup.isEmpty { problems.append("row " + dup.map(String.init).joined(separator: ", ") + " printed twice") }
        let beyond = counts.keys.filter { $0 > height || $0 < 1 }.sorted()
        if !beyond.isEmpty { problems.append("rows \(ranges(beyond)) are beyond the chart height \(height)") }
        guard codes.count <= Int(UInt8.max) + 1 else {
            problems.append("palette has \(codes.count) codes; at most \(Int(UInt8.max) + 1) are supported")
            return .failure(Problems(sentences: problems))
        }
        var index: [String: UInt8] = [:]
        for (i, code) in codes.enumerated() {
            guard index[code] == nil else { problems.append("palette code '\(code)' appears twice"); return .failure(Problems(sentences: problems)) }
            index[code] = UInt8(i)
        }
        for r in rows {
            if let bad = r.runs.first(where: { index[$0.code] == nil }) {
                problems.append("row \(r.row) uses code '\(bad.code)', not in the palette [\(codes.map { "\"\($0)\"" }.joined(separator: ", "))]")
            }
        }
        if !problems.isEmpty { return .failure(Problems(sentences: problems)) }
        var grid = [UInt8?](repeating: nil, count: width * height)
        for r in rows {
            var cells: [UInt8] = []
            for run in r.runs { cells += [UInt8](repeating: index[run.code]!, count: run.count) }
            if readsRightToLeft(row: r.row, row1: row1) { cells.reverse() }
            let y = gridRow(row: r.row, height: height, row1: row1)
            for (x, c) in cells.enumerated() { grid[y * width + x] = c }
        }
        return .success(grid)
    }

    /// The written rows against the grid read off the chart (`_match_by_rows` then
    /// `cross_check`): the chart's colour clusters are paired with the key's codes by a majority
    /// vote over the cells the rows put in them, then each written row is compared with its grid
    /// row. Disagreements are row numbers; a pairing that fails, or more than a tenth of the rows
    /// disagreeing, means the rows cannot be compared and says why.
    public static func crossCheck(rows: [Row], codes: [String], grid: [UInt8], width: Int, height: Int, row1: String = "bottom-right") -> CheckOutcome {
        let written: [UInt8?]
        switch writtenGrid(rows: rows, codes: codes, width: width, height: height, row1: row1) {
        case .success(let g): written = g
        case .failure(let p): return .incomparable(p.sentences.joined(separator: "; "))
        }
        guard grid.count == width * height else { return .incomparable("the chart has \(grid.count) cells, not \(width) × \(height)") }
        // Majority vote: which key code each chart colour is, over the cells the rows cover.
        var warnings: [String] = []
        let clusterCount = Int(grid.max() ?? 0) + 1
        var mapping: [Int: Int] = [:]
        for g in 0..<clusterCount {
            var counts = [Int](repeating: 0, count: codes.count)
            var total = 0
            for i in 0..<grid.count where Int(grid[i]) == g { if let w = written[i] { counts[Int(w)] += 1; total += 1 } }
            guard total > 0 else { continue }
            let k = counts.indices.max { counts[$0] != counts[$1] ? counts[$0] < counts[$1] : $0 > $1 }!  // first of the most frequent
            let share = Double(counts[k]) / Double(total)
            if share < 0.9 {
                warnings.append("chart colour \(g) is '\(codes[k])' in \(Int((share * 100).rounded()))% of its cells and other codes elsewhere; the rows and the picture disagree there")
            }
            mapping[g] = k
        }
        let claimed = mapping.values.sorted()
        if Set(claimed).count != claimed.count {
            let dup = Set(claimed.filter { k in claimed.filter { $0 == k }.count > 1 }).map { codes[$0] }.sorted()
            return .incomparable("two chart colours both read as [\(dup.map { "\"\($0)\"" }.joined(separator: ", "))] in the written rows; the picture has more colours than the key, or a row is wrong")
        }
        let coveredRows = (0..<height).filter { y in written[y * width] != nil }
        let unmatched = (0..<clusterCount).filter { g in mapping[g] == nil && coveredRows.contains { y in (0..<width).contains { Int(grid[y * width + $0]) == g } } }
        if !unmatched.isEmpty {
            return .incomparable("chart colours \(unmatched) fall on no written row; the picture and the rows do not line up")
        }
        // Compare, row by row, the rows that were written.
        var mismatches: [Int] = []
        var flippedTB = true, flippedLR = true, rotated = true
        for y in coveredRows {
            let row = row1.hasPrefix("bottom") ? height - y : y + 1
            var differ = false
            for x in 0..<width {
                let g = mapping[Int(grid[y * width + x])]
                if let w = written[y * width + x], Int(w) != g { differ = true }
                let tb = mapping[Int(grid[(height - 1 - y) * width + x])], lr = mapping[Int(grid[y * width + (width - 1 - x)])]
                let rt = mapping[Int(grid[(height - 1 - y) * width + (width - 1 - x)])]
                if let w = written[y * width + x] {
                    if Int(w) != tb { flippedTB = false }
                    if Int(w) != lr { flippedLR = false }
                    if Int(w) != rt { rotated = false }
                }
            }
            if differ { mismatches.append(row) }
        }
        mismatches.sort()
        if mismatches.count > max(1, Int((mismatchLimit * Double(coveredRows.count)).rounded(.up))) {
            var hint = ""
            if flippedTB { hint = " The grid matches when flipped top to bottom: chart.row1 probably starts at the other edge." }
            else if flippedLR { hint = " The grid matches when flipped left to right: chart.row1 probably starts at the other corner." }
            else if rotated { hint = " The grid matches when rotated: chart.row1 is probably the opposite corner." }
            return .incomparable("\(mismatches.count) of \(coveredRows.count) rows disagree with the chart; the row-1 position or direction is probably wrong, not the rows.\(hint)")
        }
        return .compared(disagree: mismatches, warnings: warnings)
    }
}

/// What a row check found (phone import spec §4.2): the rows that disagree, or why no comparison
/// could be made.
public enum CheckOutcome: Sendable, Equatable {
    case compared(disagree: [Int], warnings: [String])
    case incomparable(String)
}

import Foundation

/// The line-finding half of `rasterchart.py`: from an edge mask to candidate lines, clusters and a
/// pitch. Axis 0 of a mask is "down the line"; each column of the mask is a candidate position.
enum GridLines {
    static let bridge = 3          // BRIDGE
    static let mergePx = 8         // MERGE_PX
    static let gapTolerance = 0.25 // GAP_TOLERANCE

    typealias Line = (centre: Double, segments: [(Int, Int)])

    /// Binary closing down axis 0 with radius `bridge`: gaps up to twice it inside a run vanish
    /// (`_close`). Dilate by `bridge`, erode by `bridge` (a shift past the edge counts as set, as
    /// the Python's `~_shift(ones)` term does), and keep only what the dilation or the mask had.
    static func close(_ mask: Mask, bridge: Int) -> Mask {
        guard bridge > 0 else { return mask }
        let n = mask.rows, m = mask.cols
        var d = mask
        for y in 0..<n { for x in 0..<m where !mask[y, x] {
            for s in 1...bridge where (y - s >= 0 && mask[y - s, x]) || (y + s < n && mask[y + s, x]) { d[y, x] = true; break }
        } }
        var e = d
        for y in 0..<n { for x in 0..<m where d[y, x] {
            for s in 1...bridge where (y - s >= 0 && !d[y - s, x]) || (y + s < n && !d[y + s, x]) { e[y, x] = false; break }
        } }
        for y in 0..<n { for x in 0..<m { e[y, x] = e[y, x] && (d[y, x] || mask[y, x]) } }
        return e
    }

    /// Per column: the longest run of True down it after closing (`_longest_runs`, first value).
    static func longestRuns(_ mask: Mask, bridge: Int) -> [Int] {
        let closed = close(mask, bridge: bridge)
        var best = [Int](repeating: 0, count: mask.cols)
        for x in 0..<mask.cols {
            var run = 0
            for y in 0..<mask.rows {
                if closed[y, x] { run += 1; best[x] = max(best[x], run) } else { run = 0 }
            }
        }
        return best
    }

    /// Per column: the longest run (short gaps bridged) and every run at least `minPx` long, as
    /// (start, end) inclusive (`_runs`).
    static func runs(_ mask: Mask, minPx: Int) -> (best: [Int], segments: [[(Int, Int)]]) {
        let closed = close(mask, bridge: bridge)
        var best = [Int](repeating: 0, count: mask.cols)
        var segments = [[(Int, Int)]](repeating: [], count: mask.cols)
        for x in 0..<mask.cols {
            var start = -1
            for y in 0...mask.rows {
                let on = y < mask.rows && closed[y, x]
                if on, start < 0 { start = y }
                if !on, start >= 0 {
                    let length = y - start
                    best[x] = max(best[x], length)
                    if length >= minPx { segments[x].append((start, y - 1)) }
                    start = -1
                }
            }
        }
        return (best, segments)
    }

    /// Candidate columns (long edge runs) merged within `mergePx` of each other (`_lines`).
    static func lines(_ mask: Mask, minPx: Int) -> [Line] {
        let (best, segments) = runs(mask, minPx: minPx)
        guard let top = best.max(), top >= minPx else { return [] }
        let floor = max(Double(minPx), Double(top) * 0.25)
        let keep = (0..<mask.cols).filter { Double(best[$0]) >= floor }
        guard let first = keep.first else { return [] }
        var out: [Line] = []
        var group = [first]
        for x in keep.dropFirst() {
            if x - group[group.count - 1] <= mergePx { group.append(x) } else { out.append(merge(group, best, segments)); group = [x] }
        }
        out.append(merge(group, best, segments))
        return out
    }

    static func merge(_ group: [Int], _ best: [Int], _ segments: [[(Int, Int)]]) -> Line {
        let weight = group.reduce(0.0) { $0 + Double(best[$1]) }
        let centre = group.reduce(0.0) { $0 + Double($1) * Double(best[$1]) } / weight
        return (centre, group.flatMap { segments[$0] })
    }

    /// Split a sorted line list where the gap jumps past three times the median gap (`_clusters`).
    static func clusters(_ lines: [Line]) -> [[Line]] {
        guard lines.count >= 2 else { return lines.isEmpty ? [] : [lines] }
        let gaps = zip(lines.dropFirst(), lines).map { $0.centre - $1.centre }
        let limit = 3 * median(gaps)
        var groups: [[Line]] = []
        var current = [lines[0]]
        for (line, gap) in zip(lines.dropFirst(), gaps) {
            if gap > limit { groups.append(current); current = [line] } else { current.append(line) }
        }
        groups.append(current)
        return groups
    }

    /// The cell pitch of a line cluster: the mean of the gaps within 0.6–1.4 of the median gap, so
    /// a lost line (a double gap) or a bold line's two edges (a tiny gap) drop out (`_pitch`).
    static func pitch(_ positions: [Double]) -> Double? {
        guard positions.count >= 3 else { return nil }
        let gaps = zip(positions.dropFirst(), positions).map { $0 - $1 }
        let p = median(gaps)
        guard p > 0 else { return nil }
        let unit = gaps.filter { $0 > 0.6 * p && $0 < 1.4 * p }
        return unit.isEmpty ? p : unit.reduce(0, +) / Double(unit.count)
    }

    /// numpy's median: the middle value, or the mean of the two middle values.
    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// A line belongs to a grid spanning lo..hi on the other axis when one of its segments covers
    /// at least half of that span, or lies at least half inside it (`_fits`).
    static func fits(_ line: Line, lo: Double, hi: Double) -> Bool {
        for (s, e) in line.segments {
            let overlap = min(Double(e), hi) - max(Double(s), lo)
            if overlap >= 0.5 * (hi - lo) || overlap >= 0.5 * Double(e - s) { return true }
        }
        return false
    }
}

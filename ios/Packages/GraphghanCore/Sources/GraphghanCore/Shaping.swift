import Foundation

/// How a pass's stitched span changed from the pass before, in cells, at each edge named in the
/// pass's own reading direction: `start` is the right edge of a right-to-left pass and the left of
/// a left-to-right one; positive is gained, negative lost (spec 2026-09-25 §5.1). Derived from the
/// grid, never stored: the chart says how many and where, not how. Mirrors graphghan.chartdoc.shaping.
public struct Shaping: Equatable, Sendable {
    public let start: Int
    public let end: Int
    public init(start: Int, end: Int) { self.start = start; self.end = end }

    /// "+1 at start, +1 at end"; an unchanged edge is left out; nil when neither edge changed.
    public var sentence: String? {
        var parts: [String] = []
        if start != 0 { parts.append("\(Self.signed(start)) at start") }
        if end != 0 { parts.append("\(Self.signed(end)) at end") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\u{2212}\(-n)" }
}

extension WorkSequence {
    /// The grid columns a pass's runs cover, `hi` exclusive; nil when a run has no `x0`.
    static func span(_ runs: [Run]) -> (lo: Int, hi: Int)? {
        guard !runs.isEmpty else { return nil }
        var lo = Int.max, hi = Int.min
        for r in runs {
            guard let x0 = r.x0 else { return nil }
            lo = min(lo, x0)
            hi = max(hi, x0 + r.count)
        }
        return (lo, hi)
    }

    /// Pass `row`'s shaping against pass `row - 1`; nil for pass 1 or without grid columns or a direction.
    public func shaping(at row: Int) -> Shaping? {
        guard row >= 2, let p = pass(at: row), let q = pass(at: row - 1), let direction = p.direction,
              let cur = Self.span(p.runs), let prev = Self.span(q.runs) else { return nil }
        let left = prev.lo - cur.lo, right = cur.hi - prev.hi
        return direction == .ltr ? Shaping(start: left, end: right) : Shaping(start: right, end: left)
    }
}

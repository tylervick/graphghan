import CoreGraphics
import GraphghanCore

/// Where the whole view's marks sit (look-ahead spec §5.1, §5.2): row ticks, a hairline before
/// each stretch, the current stretch's bracket, and the labels that fit. Pure; every y is in the
/// band's coordinates, so `ChartBand.drawWhole` only draws what this returns.
///
/// A pass occupies the band of its grid row; a pass without one gets no mark of any kind.
struct LookAheadLayout {
    static let tickLength: CGFloat = 6
    static let labelSpacing: CGFloat = 14
    static let maxLabels = 8
    /// The bracket sits 8…14 pt in from the trailing edge; labels end 24 pt in.
    static let bracketInset: CGFloat = 8
    static let labelInset: CGFloat = 24

    struct Tick: Equatable { let y: CGFloat; let row: Int }
    struct Hairline: Equatable { let y: CGFloat; let ahead: Bool }
    struct Label: Equatable { let y: CGFloat; let text: String; let codes: [String]; let current: Bool }

    let ticks: [Tick]
    let hairlines: [Hairline]
    let bracket: ClosedRange<CGFloat>?
    let labels: [Label]

    init(rect: CGRect, chartHeight: Int, sequence: WorkSequence, stretches: [Stretch], row: Int) {
        let ch = rect.height / CGFloat(max(1, chartHeight))
        func gridRow(_ pass: Int) -> Int? { sequence.pass(at: pass)?.gridRow }
        func top(_ g: Int) -> CGFloat { rect.minY + CGFloat(g) * ch }
        func bottom(_ g: Int) -> CGFloat { rect.minY + CGFloat(g + 1) * ch }
        /// The outer edges of a stretch: the min and max over its passes' bands.
        func span(_ s: Stretch) -> ClosedRange<CGFloat>? {
            let rows = s.rows.compactMap(gridRow)
            guard rows.count == s.rows.count, let lo = rows.min(), let hi = rows.max() else { return nil }
            return top(lo)...bottom(hi)
        }

        let interval = Self.tickInterval(passCount: sequence.passes.count)
        ticks = stride(from: interval, through: sequence.passes.count, by: interval).compactMap { r in
            gridRow(r).map { Tick(y: top($0) + ch / 2, row: r) }
        }

        // One stretch is the whole chart: nothing to bracket or label (as the header shows no line).
        let current = stretches.count > 1 ? Stretches.index(containing: row, in: stretches) : nil
        var lines: [Hairline] = []
        for (i, s) in stretches.enumerated() where i > 0 {
            // the edge of the stretch's first pass facing the pass before it
            guard let g = gridRow(s.rows.lowerBound), let before = gridRow(s.rows.lowerBound - 1) else { continue }
            lines.append(Hairline(y: before > g ? bottom(g) : top(g), ahead: current.map { i >= $0 } ?? false))
        }
        hairlines = lines

        bracket = current.flatMap { span(stretches[$0]) }

        var kept: [Label] = []
        if let current {
            for (i, s) in stretches.enumerated() where i >= current {
                guard let sp = span(s) else { continue }
                let y = (sp.lowerBound + sp.upperBound) / 2
                if let last = kept.last, abs(last.y - y) < Self.labelSpacing { continue }
                kept.append(Label(y: y, text: Self.labelText(s), codes: s.colours, current: i == current))
                if kept.count == Self.maxLabels { break }
            }
        }
        labels = kept
    }

    /// Every 20 passes over 60, every 10 over 20, else every 5.
    static func tickInterval(passCount: Int) -> Int {
        passCount > 60 ? 20 : passCount > 20 ? 10 : 5
    }

    /// "Rows 5–14 · 10", "Row 41 · 1".
    static func labelText(_ stretch: Stretch) -> String {
        let rows = stretch.rows
        let range = rows.count == 1 ? "Row \(rows.lowerBound)" : "Rows \(rows.lowerBound)\u{2013}\(rows.upperBound)"
        return "\(range) · \(rows.count)"
    }
}

import CoreGraphics
import GraphghanCore

/// Where the whole view's marks sit (look-ahead spec §5.1, §5.2): row ticks, a hairline before
/// each stretch, the current stretch's bracket, and the labels that fit. Pure; every y is in the
/// band's coordinates, so `ChartBand.drawWhole` only draws what this returns.
///
/// A pass occupies the band of its grid row; a pass without one gets no mark of any kind.
///
/// Zoomed in (look-ahead zoom spec §5, #250) the rect is larger than the band and `visible` is the
/// part of it on screen: ticks come closer together, and the labels are chosen and placed among
/// what can be seen. With no `visible` and a zoom of 1 this is the fitted view, as it always was.
struct LookAheadLayout {
    static let tickLength: CGFloat = 6
    /// A label pill's height; label centres sit at least this far apart, so two never overlap.
    static let labelHeight: CGFloat = 16
    static let labelSpacing: CGFloat = labelHeight
    static let maxLabels = 8
    /// A label names a range, so a stretch gets one only when it has rows to range over.
    static let labelMinRows = 2
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

    init(rect: CGRect, chartHeight: Int, sequence: WorkSequence, stretches: [Stretch], row: Int,
         visible: ClosedRange<CGFloat>? = nil, zoom: CGFloat = 1) {
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

        let interval = Self.tickInterval(passCount: sequence.passes.count, zoom: zoom)
        ticks = stride(from: interval, through: sequence.passes.count, by: interval).compactMap { r in
            gridRow(r).map { Tick(y: top($0) + ch / 2, row: r) }
        }.filter { tick in visible.map { $0.contains(tick.y) } ?? true }

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
            for (i, s) in stretches.enumerated() where i >= current && s.rows.count >= Self.labelMinRows {
                guard var sp = span(s) else { continue }
                if let visible {
                    // What can be seen of the stretch carries its label, so one taller than the band
                    // is still named; a sliver too thin to hold a pill is left to its hairline.
                    let lo = max(sp.lowerBound, visible.lowerBound), hi = min(sp.upperBound, visible.upperBound)
                    guard hi - lo >= min(Self.labelHeight, sp.upperBound - sp.lowerBound) else { continue }
                    sp = lo...hi
                }
                let y = (sp.lowerBound + sp.upperBound) / 2
                if let last = kept.last, abs(last.y - y) < Self.labelSpacing { continue }
                kept.append(Label(y: y, text: Self.labelText(s), codes: s.colours, current: i == current))
                if kept.count == Self.maxLabels { break }
            }
        }
        labels = kept
    }

    /// Every 20 passes over 60, every 10 over 20, else every 5. Zoomed in, the passes are that many
    /// times further apart, so the count is taken as that many times smaller.
    static func tickInterval(passCount: Int, zoom: CGFloat = 1) -> Int {
        let count = zoom > 1 ? Int((CGFloat(passCount) / zoom).rounded(.up)) : passCount
        return count > 60 ? 20 : count > 20 ? 10 : 5
    }

    /// "Rows 5–14 · 10", "Row 41 · 1".
    static func labelText(_ stretch: Stretch) -> String {
        let rows = stretch.rows
        let range = rows.count == 1 ? "Row \(rows.lowerBound)" : "Rows \(rows.lowerBound)\u{2013}\(rows.upperBound)"
        return "\(range) · \(rows.count)"
    }
}

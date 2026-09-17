import CoreGraphics
import GraphghanCore

/// Where everything in the band sits, in content coordinates (grid column × cell), and how far the
/// content is shifted so the current run reads (spec §5.3). Pure, so the rules are value tests.
struct BandLayout {
    static let cell: CGFloat = 8
    static let currentRowHeight: CGFloat = 96
    static let rowHeight: CGFloat = 48
    static let rowsAbove = 2
    static let rulerHeight: CGFloat = 22
    static let rulerEvery = 10

    let width: CGFloat
    let height: CGFloat
    let chartWidth: Int
    let rowsBelow: Int
    let offsetX: CGFloat
    let ring: CGRect?
    let ticks: [(x: CGFloat, label: Int)]
    let bracket: (x0: CGFloat, x1: CGFloat, label: String)?
    let boundaryX: CGFloat?

    init(width: CGFloat, height: CGFloat, chart: Chart, pass: Pass, cursor: Cursor, segmentLabel: String?) {
        self.width = width
        self.height = height
        chartWidth = chart.width
        let cell = Self.cell
        let content = CGFloat(chart.width) * cell
        let fixed = CGFloat(Self.rowsAbove) * Self.rowHeight + Self.currentRowHeight + Self.rulerHeight
        rowsBelow = max(1, Int((height - fixed) / Self.rowHeight))
        let ltr = pass.direction != .rtl
        func clamp(_ x: CGFloat) -> CGFloat { min(max(0, x), max(0, content - width)) }

        if cursor.run < pass.runs.count, let x0 = pass.runs[cursor.run].x0 {
            let run = pass.runs[cursor.run]
            let x1 = x0 + run.count
            let w = CGFloat(run.count) * cell
            ring = CGRect(x: CGFloat(x0) * cell, y: 0, width: w, height: Self.currentRowHeight)
            if w <= width * 0.8 {
                offsetX = clamp(CGFloat(x0) * cell + w / 2 - width / 2)
            } else {
                let end = CGFloat(ltr ? x1 : x0) * cell
                offsetX = clamp(ltr ? end - width * 0.75 : end - width * 0.25)
            }
            if run.count >= Self.rulerEvery {
                ticks = stride(from: 0, through: run.count, by: Self.rulerEvery).map { k in
                    (x: CGFloat(ltr ? x0 + k : x1 - k) * cell, label: k)
                }
            } else {
                ticks = []
            }
            if let label = segmentLabel, let seg = Segments.segment(containing: cursor.run, in: pass), seg.kind == .braid || seg.kind == .repeat {
                let lo = seg.runs.compactMap { pass.runs[$0].x0 }.min() ?? x0
                let hi = seg.runs.compactMap { i in pass.runs[i].x0.map { $0 + pass.runs[i].count } }.max() ?? x1
                bracket = (x0: CGFloat(lo) * cell, x1: CGFloat(hi) * cell, label: label)
            } else {
                bracket = nil
            }
            boundaryX = nil
        } else {
            ring = nil
            ticks = []
            bracket = nil
            let endX = CGFloat(ltr ? chart.width : 0) * cell
            boundaryX = endX
            offsetX = clamp(ltr ? endX - width : 0)
        }
    }

    func rowTop(_ k: Int) -> CGFloat {
        if k < 0 { return CGFloat(Self.rowsAbove + k) * Self.rowHeight }
        if k == 0 { return CGFloat(Self.rowsAbove) * Self.rowHeight }
        return CGFloat(Self.rowsAbove) * Self.rowHeight + Self.currentRowHeight + CGFloat(k - 1) * Self.rowHeight
    }
    func rowHeight(_ k: Int) -> CGFloat { k == 0 ? Self.currentRowHeight : Self.rowHeight }
    func rowOpacity(_ k: Int) -> Double { k < 0 ? 0.3 : k <= 1 ? 1 : 0.75 }

    /// The grid column under a view x, clamped to the chart.
    func cellAt(x: CGFloat) -> Int {
        min(max(0, Int((x + offsetX) / Self.cell)), chartWidth - 1)
    }

    /// The whole chart at true aspect, as wide as the band and vertically centred (spec §5.3).
    static func wholeChartRect(chart: Chart, in size: CGSize) -> CGRect {
        let aspect = CGFloat(chart.width) / CGFloat(chart.height)
        var w = size.width
        var h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

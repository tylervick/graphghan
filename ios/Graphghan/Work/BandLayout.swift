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
    /// The unworked part of the current run: from the hook to the run's end in reading direction.
    /// The whole run at stitch 0; what is left once a fill has been counted into (#74).
    let ring: CGRect?
    /// Where the hook is inside the current run, in content x, with the cells worked so far.
    /// Nil without a ring.
    let hook: (x: CGFloat, stitch: Int)?
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

        if cursor.run == pass.runs.count {
            ring = nil
            hook = nil
            ticks = []
            bracket = nil
            let endX = CGFloat(ltr ? chart.width : 0) * cell
            boundaryX = endX
            offsetX = clamp(ltr ? endX - width : 0)
        } else {
            let run = pass.runs[cursor.run]
            if let x0 = run.x0 {
                let x1 = x0 + run.count
                let w = CGFloat(run.count) * cell
                let hookX = CGFloat(ltr ? x0 + cursor.stitch : x1 - cursor.stitch) * cell
                hook = (x: hookX, stitch: cursor.stitch)
                ring = ltr
                    ? CGRect(x: hookX, y: 0, width: CGFloat(x1) * cell - hookX, height: Self.currentRowHeight)
                    : CGRect(x: CGFloat(x0) * cell, y: 0, width: hookX - CGFloat(x0) * cell, height: Self.currentRowHeight)
                if w <= width * 0.8 {
                    offsetX = clamp(CGFloat(x0) * cell + w / 2 - width / 2)
                } else {
                    offsetX = clamp(Self.longRunOffset(hook: hookX, end: CGFloat(ltr ? x1 : x0) * cell, width: width, ltr: ltr))
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
                // No grid column: no geometry (a run with no x0 is legal for explicit-passes
                // charts; it is not the row-end boundary).
                ring = nil
                hook = nil
                boundaryX = nil
                ticks = []
                bracket = nil
                offsetX = 0
            }
        }
    }

    /// Where a run wider than 80% of the band scrolls to (spec §5.3, amended by #74). The hook
    /// sits a quarter of the way in from the edge it works from, so what has been counted and
    /// what comes next are both on screen. Once the remainder is half a width or less, the run's
    /// end is pinned at three quarters instead, as the spec had it, and the landmark comes into
    /// frame. The two offsets are equal at exactly half a width, so the band never jumps from one
    /// rule to the other. `hook` and `end` are content x.
    static func longRunOffset(hook: CGFloat, end: CGFloat, width: CGFloat, ltr: Bool) -> CGFloat {
        let left = ltr ? end - hook : hook - end
        if left <= width * 0.5 { return ltr ? end - width * 0.75 : end - width * 0.25 }
        return ltr ? hook - width * 0.25 : hook - width * 0.75
    }

    /// Row tops: the rows above, the current row, then the ruler strip (spec §5.3: "under the
    /// current row", #72), then the rows below.
    func rowTop(_ k: Int) -> CGFloat {
        if k < 0 { return CGFloat(Self.rowsAbove + k) * Self.rowHeight }
        if k == 0 { return CGFloat(Self.rowsAbove) * Self.rowHeight }
        return CGFloat(Self.rowsAbove) * Self.rowHeight + Self.currentRowHeight + Self.rulerHeight + CGFloat(k - 1) * Self.rowHeight
    }
    /// Where the ruler's ticks start: just under the current row.
    var rulerTop: CGFloat { rowTop(0) + Self.currentRowHeight + 4 }
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

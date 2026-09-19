import CoreGraphics
import GraphghanCore

/// How the band lays the chart out (#87). `fabric` is the spec's band: rows as they lie in the
/// blanket, so a right-to-left row scrolls right to left. `ribbon` unrolls the chart in working
/// order: every row reads left to right and the turn is a fold you pass, at the cost of the band
/// being a mirror image of the fabric on every other row. A per-project setting; the experiment is
/// which one she works from.
enum BandStyle: String, Codable, CaseIterable, Sendable {
    case fabric, ribbon
    static let `default`: BandStyle = .fabric

    var title: String {
        switch self {
        case .fabric: "Follows the fabric"
        case .ribbon: "Reads one way"
        }
    }
    var other: BandStyle { self == .fabric ? .ribbon : .fabric }
}

/// Where everything in the band sits, in content coordinates (grid column × cell), and how far the
/// content is shifted so the current run reads (spec §5.3). Pure, so the rules are value tests.
///
/// Content x runs left to right. In `fabric` style content column c is grid column c. In `ribbon`
/// style on a right-to-left pass the window is mirrored, so grid column c sits at content
/// `width - c` and the pass reads left to right like every other; the rows above and below are
/// mirrored with it, which is what folding the ribbon back at each turn does to them, so the row
/// below still lines up stitch for stitch under the current one and the landmark keeps its ruler.
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
    let style: BandStyle
    /// Grid columns are drawn right to left: `ribbon` style on a right-to-left pass.
    let mirrored: Bool
    /// The pass reads toward increasing content x: a left-to-right pass, or any mirrored one.
    let flowsRight: Bool
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

    init(width: CGFloat, height: CGFloat, chart: Chart, pass: Pass, cursor: Cursor, segmentLabel: String?, style: BandStyle = .fabric) {
        self.width = width
        self.height = height
        self.style = style
        chartWidth = chart.width
        let cell = Self.cell
        let content = CGFloat(chart.width) * cell
        let fixed = CGFloat(Self.rowsAbove) * Self.rowHeight + Self.currentRowHeight + Self.rulerHeight
        rowsBelow = max(1, Int((height - fixed) / Self.rowHeight))
        let ltr = pass.direction != .rtl
        let mirrored = style == .ribbon && !ltr
        self.mirrored = mirrored
        let flow = ltr || mirrored
        flowsRight = flow
        func clamp(_ x: CGFloat) -> CGFloat { min(max(0, x), max(0, content - width)) }
        // content x of the boundary between grid columns c-1 and c
        func edge(_ c: Int) -> CGFloat { mirrored ? CGFloat(chart.width - c) * cell : CGFloat(c) * cell }

        if cursor.run == pass.runs.count {
            ring = nil
            hook = nil
            ticks = []
            bracket = nil
            let endX = edge(ltr ? chart.width : 0)
            boundaryX = endX
            offsetX = clamp(flow ? endX - width : 0)
        } else {
            let run = pass.runs[cursor.run]
            if let x0 = run.x0 {
                let x1 = x0 + run.count
                let w = CGFloat(run.count) * cell
                let hookX = edge(ltr ? x0 + cursor.stitch : x1 - cursor.stitch)
                let endX = edge(ltr ? x1 : x0)
                hook = (x: hookX, stitch: cursor.stitch)
                ring = flow
                    ? CGRect(x: hookX, y: 0, width: endX - hookX, height: Self.currentRowHeight)
                    : CGRect(x: endX, y: 0, width: hookX - endX, height: Self.currentRowHeight)
                if w <= width * 0.8 {
                    offsetX = clamp((edge(x0) + edge(x1)) / 2 - width / 2)
                } else {
                    offsetX = clamp(Self.longRunOffset(hook: hookX, end: endX, width: width, ltr: flow))
                }
                if run.count >= Self.rulerEvery {
                    ticks = stride(from: 0, through: run.count, by: Self.rulerEvery).map { k in
                        (x: edge(ltr ? x0 + k : x1 - k), label: k)
                    }
                } else {
                    ticks = []
                }
                if let label = segmentLabel, let seg = Segments.segment(containing: cursor.run, in: pass), seg.kind == .braid || seg.kind == .repeat {
                    let lo = seg.runs.compactMap { pass.runs[$0].x0 }.min() ?? x0
                    let hi = seg.runs.compactMap { i in pass.runs[i].x0.map { $0 + pass.runs[i].count } }.max() ?? x1
                    bracket = (x0: min(edge(lo), edge(hi)), x1: max(edge(lo), edge(hi)), label: label)
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
    /// rule to the other. `hook` and `end` are content x; `ltr` is the flow in content x.
    static func longRunOffset(hook: CGFloat, end: CGFloat, width: CGFloat, ltr: Bool) -> CGFloat {
        let left = ltr ? end - hook : hook - end
        if left <= width * 0.5 { return ltr ? end - width * 0.75 : end - width * 0.25 }
        return ltr ? hook - width * 0.25 : hook - width * 0.75
    }

    /// Content x of the boundary between grid columns `c - 1` and `c`; mirrored in ribbon style
    /// on a right-to-left pass.
    func edge(_ c: Int) -> CGFloat {
        mirrored ? CGFloat(chartWidth - c) * Self.cell : CGFloat(c) * Self.cell
    }

    /// The content rect of a run at grid column `x0` with `count` cells, at a row top and height.
    func runRect(x0: Int, count: Int, top: CGFloat, height: CGFloat) -> CGRect {
        let a = edge(x0), b = edge(x0 + count)
        return CGRect(x: min(a, b), y: top, width: abs(b - a), height: height)
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
        let content = min(max(0, Int((x + offsetX) / Self.cell)), chartWidth - 1)
        return mirrored ? chartWidth - 1 - content : content
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

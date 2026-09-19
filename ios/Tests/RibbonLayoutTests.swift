import CoreGraphics
import Testing
import GraphghanCore
@testable import Graphghan

/// `BandLayout` in `ribbon` style (#87): a right-to-left pass is mirrored so it reads left to
/// right in content coordinates; a left-to-right pass is laid out exactly as the fabric band.
@Suite struct RibbonLayoutTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))   // 189 × 184
    static let seq = try! WorkSequence(chart: chart)
    static let w: CGFloat = 366
    static let maxOffset = CGFloat(189 * 8) - w
    static func layout(_ cursor: Cursor, style: BandStyle, label: String? = nil) -> BandLayout {
        BandLayout(width: w, height: 420, chart: chart, pass: seq.pass(at: cursor.row)!, cursor: cursor, segmentLabel: label, style: style)
    }
    static func clamp(_ x: CGFloat) -> CGFloat { min(max(0, x), maxOffset) }
    /// Row 43 is worked right to left; its one fill.
    static let pass43 = seq.pass(at: 43)!
    static let fill43 = pass43.runs.firstIndex { $0.count >= 20 }!
    static var run43: Run { pass43.runs[fill43] }

    @Test func aLeftToRightPassIsTheFabricBand() {
        for cursor in [Cursor(row: 42, run: 8), Cursor(row: 42, run: 10, stitch: 40), Cursor(row: 42, run: Self.seq.pass(at: 42)!.runs.count)] {
            let fabric = Self.layout(cursor, style: .fabric), ribbon = Self.layout(cursor, style: .ribbon)
            #expect(!ribbon.mirrored && ribbon.flowsRight)
            #expect(fabric.offsetX == ribbon.offsetX && fabric.ring == ribbon.ring && fabric.boundaryX == ribbon.boundaryX)
            #expect(fabric.hook?.x == ribbon.hook?.x && fabric.ticks.map(\.x) == ribbon.ticks.map(\.x))
        }
    }

    @Test func aRightToLeftPassIsMirroredToReadLeftToRight() {
        let l = Self.layout(Cursor(row: 43, run: Self.fill43), style: .ribbon)
        #expect(l.mirrored && l.flowsRight)
        #expect(Self.layout(Cursor(row: 43, run: Self.fill43), style: .fabric).mirrored == false)
        // grid column c sits at content (189 - c) × 8: the row's right edge is content 0
        #expect(l.edge(189) == 0 && l.edge(0) == CGFloat(189 * 8))
        let r = l.runRect(x0: 10, count: 5, top: 0, height: 1)
        #expect(r.minX == CGFloat((189 - 15) * 8) && r.width == 40)
    }

    /// The hook, ring, ticks and anchor for the row 43 fill, all in content x that increases in
    /// working order: the run starts at its grid right edge, which is content (189 - x1) × 8.
    @Test func fillGeometryFlowsRight() {
        let run = Self.run43
        let x0 = run.x0!, x1 = x0 + run.count
        let start = CGFloat(189 - x1) * 8, end = CGFloat(189 - x0) * 8
        let table: [(stitch: Int, hook: CGFloat, ringMinX: CGFloat, ringWidth: CGFloat, offset: CGFloat)] = [
            (0, start, start, end - start, Self.clamp(start - Self.w * 0.25)),
            (30, start + 240, start + 240, end - start - 240, Self.clamp(start + 240 - Self.w * 0.25)),
            (run.count - 5, end - 40, end - 40, 40, Self.clamp(end - Self.w * 0.75)),
        ]
        for row in table {
            let l = Self.layout(Cursor(row: 43, run: Self.fill43, stitch: row.stitch), style: .ribbon)
            #expect(l.hook?.x == row.hook && l.hook?.stitch == row.stitch, "stitch \(row.stitch)")
            #expect(l.ring?.minX == row.ringMinX && l.ring?.width == row.ringWidth, "stitch \(row.stitch)")
            #expect(abs(l.offsetX - row.offset) < 0.5, "stitch \(row.stitch)")
        }
        let l = Self.layout(Cursor(row: 43, run: Self.fill43), style: .ribbon)
        #expect(l.ticks.first?.x == start && l.ticks.first?.label == 0)
        #expect(l.ticks[1].x == start + 80)   // the ruler counts to the right
        // the fabric band, for contrast, counts from the grid right edge leftward
        #expect(Self.layout(Cursor(row: 43, run: Self.fill43), style: .fabric).ticks[1].x == CGFloat(x1 - 10) * 8)
    }

    @Test func bracketAndBoundaryMirror() {
        // the border braid at the grid's left edge on row 43 sits at the ribbon's right end
        let l = Self.layout(Cursor(row: 43, run: Self.pass43.runs.count - 2), style: .ribbon, label: "border braid")
        let b = try! #require(l.bracket)
        let braidStart = Self.pass43.runs[Self.pass43.runs.count - 8].x0! + Self.pass43.runs[Self.pass43.runs.count - 8].count
        #expect(b.x1 == CGFloat(189 * 8) && b.x0 == CGFloat(189 - braidStart) * 8 && b.x0 < b.x1)
        // the turn is at the right end, in view
        let t = Self.layout(Cursor(row: 43, run: Self.pass43.runs.count), style: .ribbon)
        #expect(t.boundaryX == CGFloat(189 * 8) && t.offsetX == Self.maxOffset)
        #expect(Self.layout(Cursor(row: 43, run: Self.pass43.runs.count), style: .fabric).boundaryX == 0)
    }

    @Test func cellAtInvertsTheMirror() {
        let l = Self.layout(Cursor(row: 43, run: Self.fill43, stitch: 30), style: .ribbon)
        // the hook sits a quarter in from the left; the column under it is the hook's column
        let hookCol = Self.run43.x0! + Self.run43.count - 30
        #expect(l.cellAt(x: Self.w * 0.25) == hookCol || l.cellAt(x: Self.w * 0.25) == hookCol - 1)
        #expect(l.cellAt(x: -1000) == 188 && l.cellAt(x: 100_000) == 0)
    }

    @Test func styleTitlesAndDefault() {
        #expect(BandStyle.default == .fabric && BandStyle.fabric.other == .ribbon && BandStyle.ribbon.other == .fabric)
        #expect(BandStyle.fabric.title == "Follows the fabric" && BandStyle.ribbon.title == "Reads one way")
    }
}

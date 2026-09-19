import CoreGraphics
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct BandLayoutTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))   // 189 × 184
    static let seq = try! WorkSequence(chart: chart)
    static let pass42 = seq.pass(at: 42)!   // ltr; run 10 = 117 C at x0 36; run 2 = 4 Y at x0 4
    static func layout(_ cursor: Cursor, width: CGFloat = 366, height: CGFloat = 420, label: String? = nil) -> BandLayout {
        BandLayout(width: width, height: height, chart: chart, pass: seq.pass(at: cursor.row)!, cursor: cursor, segmentLabel: label)
    }

    @Test func rowsBelowFillTheHeight() {
        // 420 = 2×48 above + 96 + 22 ruler + 206 left → 4 rows below (4×48 = 192)
        #expect(Self.layout(Cursor(row: 42, run: 8)).rowsBelow == 4)
        #expect(Self.layout(Cursor(row: 42, run: 8), height: 250).rowsBelow == 1)   // never fewer than one
        let l = Self.layout(Cursor(row: 42, run: 8))
        // the ruler strip sits between the current row and the first row below (#72)
        #expect(l.rowTop(-2) == 0 && l.rowTop(0) == 96 && l.rowHeight(0) == 96 && l.rulerTop == 196 && l.rowTop(1) == 214 && l.rowHeight(1) == 48)
        #expect(l.rowOpacity(-1) == 0.3 && l.rowOpacity(0) == 1 && l.rowOpacity(1) == 1 && l.rowOpacity(2) == 0.75)
    }

    @Test func shortRunIsCentred() {
        let l = Self.layout(Cursor(row: 42, run: 2))   // 4 Y at x0 4: 32 pt wide, centre at 48 → clamped to 0
        #expect(l.offsetX == 0)
        let ring = try! #require(l.ring)
        #expect(ring.minX == 4 * 8 && ring.width == 4 * 8)
        // a run in the middle of the row is centred on the view
        let mid = Self.layout(Cursor(row: 42, run: 11))   // 11 P at x0 153: centre 158.5 cells = 1268 pt
        #expect(abs(mid.offsetX - (1268 - 183)) < 0.5)
    }

    /// #74: a long run follows the hook (a quarter in from the edge it works from) until the
    /// remainder is half a width, then pins its end at three quarters as before. 117 C on row 42:
    /// x0 36..153, ltr, so the hook is at (36 + stitch) × 8 and the end at 1224.
    @Test func longRunFollowsTheHookThenPinsItsEnd() {
        let table: [(stitch: Int, offset: CGFloat)] = [
            (0, 288 - 91.5),      // hook at the run's start, 936 pt left → hook anchored
            (40, 608 - 91.5),     // 616 pt left → still the hook
            (94, 1040 - 91.5),    // 184 pt left, just over half of 366 → the hook, one step before the switch
            (95, 1224 - 274.5),   // 176 pt left → the end pinned; 1 pt on from the previous offset, no jump
            (100, 1224 - 274.5),
            (110, 1224 - 274.5),
        ]
        for row in table {
            let l = Self.layout(Cursor(row: 42, run: 10, stitch: row.stitch))
            #expect(abs(l.offsetX - row.offset) < 0.5, "stitch \(row.stitch)")
        }
        // rtl (row 43): the hook is x1 - stitch, a quarter in from the right; the end is x0 at one quarter from the left
        let pass43 = Self.seq.pass(at: 43)!
        let i = pass43.runs.firstIndex { $0.count >= 20 }!
        let run = pass43.runs[i]
        let x0 = CGFloat(run.x0!) * 8, x1 = CGFloat(run.x0! + run.count) * 8
        let maxOffset = CGFloat(189 * 8 - 366)
        func clamp(_ x: CGFloat) -> CGFloat { min(max(0, x), maxOffset) }
        let rtl: [(stitch: Int, offset: CGFloat)] = [
            (0, clamp(x1 - 274.5)),
            (40, clamp(x1 - 320 - 274.5)),
            (run.count - 10, clamp(x0 - 91.5)),
            (run.count - 1, clamp(x0 - 91.5)),
        ]
        for row in rtl {
            let l = Self.layout(Cursor(row: 43, run: i, stitch: row.stitch))
            #expect(abs(l.offsetX - row.offset) < 0.5, "rtl stitch \(row.stitch)")
        }
        // the two rules meet exactly at half a width, from either side
        let w: CGFloat = 366
        #expect(BandLayout.longRunOffset(hook: 1224 - w / 2, end: 1224, width: w, ltr: true) == 1224 - w * 0.75)
        #expect(BandLayout.longRunOffset(hook: 1224 - w / 2 - 0.001, end: 1224, width: w, ltr: true) - (1224 - w * 0.75) < 0.01)
        #expect(BandLayout.longRunOffset(hook: 100 + w / 2, end: 100, width: w, ltr: false) == 100 - w * 0.25)
        #expect(BandLayout.longRunOffset(hook: 100 + w / 2 + 0.001, end: 100, width: w, ltr: false) - (100 - w * 0.25) < 0.01)
    }

    /// #74: the ring is the remainder, and the hook sits where the count stands.
    @Test func ringShrinksToTheRemainder() {
        let start = Self.layout(Cursor(row: 42, run: 10))
        #expect(start.ring?.minX == CGFloat(36 * 8) && start.ring?.width == CGFloat(117 * 8))
        #expect(start.hook?.x == CGFloat(36 * 8) && start.hook?.stitch == 0)
        let mid = Self.layout(Cursor(row: 42, run: 10, stitch: 40))
        #expect(mid.ring?.minX == CGFloat((36 + 40) * 8) && mid.ring?.width == CGFloat(77 * 8))
        #expect(mid.hook?.x == CGFloat((36 + 40) * 8) && mid.hook?.stitch == 40)
        // rtl: the run starts at its right edge, so the remainder keeps x0 and loses width
        let pass = Self.seq.pass(at: 43)!
        let i = pass.runs.firstIndex { $0.count >= 20 }!
        let run = pass.runs[i]
        let r = Self.layout(Cursor(row: 43, run: i, stitch: 30))
        #expect(r.ring?.minX == CGFloat(run.x0! * 8) && r.ring?.width == CGFloat((run.count - 30) * 8))
        #expect(r.hook?.x == CGFloat((run.x0! + run.count - 30) * 8) && r.hook?.stitch == 30)
    }

    @Test func longRunTicksEveryTen() {
        let l = Self.layout(Cursor(row: 42, run: 10))
        #expect(l.ticks.map(\.label) == [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110])
        // Cast on the right: a bare Int arithmetic literal here trips a Swift Testing `#expect`
        // macro defect (Xcode 26.2 / Swift 6.2.3) that reports a false failure for
        // `CGFloat == <Int arithmetic expression>` at top level, confirmed with a minimal
        // reproduction outside this module; the values are exactly equal.
        #expect(l.ticks[1].x == CGFloat((36 + 10) * 8))
        #expect(Self.layout(Cursor(row: 42, run: 8)).ticks.isEmpty)   // 7 C: under ten, no ruler
    }

    @Test func rtlLongRunCountsFromItsRightEdge() {
        // row 41 is rtl; take its first run of 20+ if any, else synthesise: use row 43 (rtl) run index of the 117 C mirror
        let pass = Self.seq.pass(at: 43)!
        let i = pass.runs.firstIndex { $0.count >= 20 }!
        let run = pass.runs[i]
        let l = Self.layout(Cursor(row: 43, run: i))
        #expect(l.ticks.first?.x == CGFloat(run.x0! + run.count) * 8)   // the start, in reading direction, is the right edge
        // At stitch 0 the hook is that right edge, anchored three quarters from the left (#74) …
        let maxOffset = CGFloat(189 * 8 - 366)
        #expect(abs(l.offsetX - min(CGFloat(run.x0! + run.count) * 8 - 366 * 0.75, maxOffset)) < 0.5)
        // … and near the end the end (left edge) sits at one quarter from the left, as before.
        let near = Self.layout(Cursor(row: 43, run: i, stitch: run.count - 5))
        #expect(abs(near.offsetX - max(0, CGFloat(run.x0!) * 8 - 366 * 0.25)) < 0.5)
    }

    @Test func bracketSpansTheSegment() {
        let l = Self.layout(Cursor(row: 42, run: 2), label: "border braid")
        let b = try! #require(l.bracket)
        #expect(b.x0 == 0 && b.x1 == CGFloat(Self.pass42.runs[7].x0! + Self.pass42.runs[7].count) * 8 && b.label == "border braid")
        #expect(Self.layout(Cursor(row: 42, run: 8)).bracket == nil)
    }

    @Test func boundaryMarksTheRowEnd() {
        let l = Self.layout(Cursor(row: 42, run: Self.pass42.runs.count))
        #expect(l.ring == nil && l.hook == nil && l.boundaryX == 189 * 8)
        // Cast on the right: see the note in longRunKeepsItsEndAtThreeQuarters above.
        #expect(l.offsetX == CGFloat(189 * 8 - 366))   // the end is in view
    }

    @Test func cellAtInvertsTheOffset() {
        let l = Self.layout(Cursor(row: 42, run: 10, stitch: 110))   // end pinned at three quarters
        #expect(l.cellAt(x: 366 * 0.75) == 153 || l.cellAt(x: 366 * 0.75) == 152)
        #expect(l.cellAt(x: -1000) == 0 && l.cellAt(x: 100_000) == 188)
    }

    @Test func wholeChartFitsTrueAspect() {
        let r = BandLayout.wholeChartRect(chart: Self.chart, in: CGSize(width: 366, height: 420))
        #expect(abs(r.width / r.height - 189.0 / 184.0) < 0.01 && r.width == 366)
        #expect(abs(r.midY - 210) < 0.5)
    }

    @Test func runWithoutAColumnHasNoGeometry() {
        // explicit-passes.chart.json gives every run an x0 (checked by hand); synthesize a pass
        // whose run omits it instead, per the fix-round-1 ruling's fallback.
        let pass = Pass(label: "Row 1", side: .rs, direction: .ltr, gridRow: 0, runs: [Run(code: "A", count: 3, x0: nil)])
        let l = BandLayout(width: 366, height: 420, chart: Self.chart, pass: pass, cursor: Cursor(row: 1, run: 0), segmentLabel: nil)
        #expect(l.ring == nil && l.hook == nil && l.boundaryX == nil && l.ticks.isEmpty && l.bracket == nil && l.offsetX == 0)
    }
}

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
        #expect(l.rowTop(-2) == 0 && l.rowTop(0) == 96 && l.rowHeight(0) == 96 && l.rowTop(1) == 192 && l.rowHeight(1) == 48)
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

    @Test func longRunKeepsItsEndAtThreeQuarters() {
        let l = Self.layout(Cursor(row: 42, run: 10))   // 117 C, x0 36..153, ltr: end at x 153 → 1224 pt
        #expect(abs(l.offsetX - (1224 - 366 * 0.75)) < 0.5)
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
        #expect(abs(l.offsetX - (CGFloat(run.x0!) * 8 - 366 * 0.25)) < 0.5)   // the end (left edge) sits at one quarter from the left
    }

    @Test func bracketSpansTheSegment() {
        let l = Self.layout(Cursor(row: 42, run: 2), label: "border braid")
        let b = try! #require(l.bracket)
        #expect(b.x0 == 0 && b.x1 == CGFloat(Self.pass42.runs[7].x0! + Self.pass42.runs[7].count) * 8 && b.label == "border braid")
        #expect(Self.layout(Cursor(row: 42, run: 8)).bracket == nil)
    }

    @Test func boundaryMarksTheRowEnd() {
        let l = Self.layout(Cursor(row: 42, run: Self.pass42.runs.count))
        #expect(l.ring == nil && l.boundaryX == 189 * 8)
        // Cast on the right: see the note in longRunKeepsItsEndAtThreeQuarters above.
        #expect(l.offsetX == CGFloat(189 * 8 - 366))   // the end is in view
    }

    @Test func cellAtInvertsTheOffset() {
        let l = Self.layout(Cursor(row: 42, run: 10))
        #expect(l.cellAt(x: 366 * 0.75) == 153 || l.cellAt(x: 366 * 0.75) == 152)
        #expect(l.cellAt(x: -1000) == 0 && l.cellAt(x: 100_000) == 188)
    }

    @Test func wholeChartFitsTrueAspect() {
        let r = BandLayout.wholeChartRect(chart: Self.chart, in: CGSize(width: 366, height: 420))
        #expect(abs(r.width / r.height - 189.0 / 184.0) < 0.01 && r.width == 366)
        #expect(abs(r.midY - 210) < 0.5)
    }
}

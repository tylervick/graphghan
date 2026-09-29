import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct ShapedRowTextTests {
    static let chart = try! Chart.load(TestFixtures.data("shaped-basic.chart.json"))
    static let seq = try! WorkSequence(chart: chart)

    @Test func captionIsTheRowsStitchesAndItsShaping() {
        #expect(ShapedRowText.caption(chart: Self.chart, sequence: Self.seq, row: 1) == "3 sts")
        #expect(ShapedRowText.caption(chart: Self.chart, sequence: Self.seq, row: 2) == "5 sts · +1 at start, +1 at end")
        #expect(ShapedRowText.caption(chart: Self.chart, sequence: Self.seq, row: 4) == "6 sts · \u{2212}1 at start")
        #expect(ShapedRowText.caption(chart: Self.chart, sequence: Self.seq, row: 5) == "3 sts · \u{2212}2 at start, \u{2212}1 at end")
    }

    @Test func aRectangleHasNoCaption() throws {
        let chart = try Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
        #expect(ShapedRowText.caption(chart: chart, sequence: try WorkSequence(chart: chart), row: 42) == nil)
    }

    @Test func writtenIsThePassesOwnText() {
        #expect(ShapedRowText.written(chart: Self.chart, row: 2) == "R 2: ch 1, turn, 1 inc, 1 sc, 1 inc [5]")
        #expect(ShapedRowText.written(chart: Self.chart, row: 6) == nil)
    }
}

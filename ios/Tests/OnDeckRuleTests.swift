import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct OnDeckRuleTests {
    // two-letter-codes: Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3
    static let chart = try! Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static func name(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].name }
    static func hex(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].hex }

    @Test func nextRunInRow() {
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 0), chart: Self.chart, sequence: Self.seq)
        #expect(d?.text == "then 7 \(Self.name("Gd"))")
        #expect(d?.hex == Self.hex("Gd"))
    }

    @Test func lastRunInRowNamesNextRowsColor() {
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: Self.chart, sequence: Self.seq)
        #expect(d?.text == "next row starts in \(Self.name("Gd"))")
        #expect(d?.hex == Self.hex("Gd"))
    }

    @Test func lastRunOfPatternHasNothingOnDeck() {
        #expect(OnDeckRule.onDeck(cursor: Cursor(row: 2, run: 2), chart: Self.chart, sequence: Self.seq) == nil)
    }
}

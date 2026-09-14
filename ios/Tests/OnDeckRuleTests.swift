import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct OnDeckRuleTests {
    // two-letter-codes: Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3 ; no stitch fields
    static let chart = try! Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static func name(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].name }
    static func hex(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].hex }

    /// The same two rows with an authored stitch, boundary and foundation.
    static func authored(boundary: String, foundation: String? = "\"foundation\":{\"chain\":13,\"first_stitch_in\":2},") -> Chart {
        let rows = ["7Gd2G3Y", "2G7Gd3Kb"]
        let id = ChartID.compute(codes: ["G", "Gd", "Kb", "Y"], rows: rows, technique: .object(["type": .string("rows")]), passes: nil)
        let json = """
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\(id)","width":12,"height":2},
         "palette":[{"code":"G","name":"Green","hex":"#1E4D3A"},{"code":"Gd","name":"Gold","hex":"#D9A21B"},
                    {"code":"Kb","name":"Charcoal","hex":"#2B2F33"},{"code":"Y","name":"Cream","hex":"#F2E8D5"}],
         "rows":["7Gd2G3Y","2G7Gd3Kb"],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"},"stitch":"sc","terms":"US","boundary":\(boundary)},
         "technique":{"type":"rows"},\(foundation ?? "")"instructions":[]}
        """
        return try! Chart.load(Data(json.utf8))
    }

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

    @Test func turnBoundaryPrependsTheChain() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":1}"#)
        let seq = try WorkSequence(chart: chart)
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: chart, sequence: seq)
        #expect(d?.text == "ch 1, turn — next row starts in Gold")
        #expect(d?.hex == "#D9A21B")
    }

    @Test func chainColorAndCountsAsStitchAreSpelledOut() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":2,"counts_as_stitch":true,"color":"next"}"#)
        let seq = try WorkSequence(chart: chart)
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: chart, sequence: seq)
        #expect(d?.text == "ch 2 in Gold, turn — next row starts in Gold (counts as a st)")
    }

    @Test func zeroChainStillSaysTurn() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":0}"#)
        let seq = try WorkSequence(chart: chart)
        #expect(OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: chart, sequence: seq)?.text == "turn — next row starts in Gold")
    }

    @Test func otherBoundaryKindsLeaveTheLineAlone() throws {
        let chart = Self.authored(boundary: #"{"kind":"join","chain":3}"#)
        let seq = try WorkSequence(chart: chart)
        #expect(OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: chart, sequence: seq)?.text == "next row starts in Gold")
    }

    @Test func foundationShowsAtTheStartOnly() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":1}"#)
        let seq = try WorkSequence(chart: chart)
        let start = OnDeckRule.onDeck(cursor: .start, chart: chart, sequence: seq)
        #expect(start?.text == "Chain 13, first sc in the 2nd chain")
        #expect(start?.hex == "#2B2F33")  // Row 1 reads right to left: Kb first
        let second = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 1), chart: chart, sequence: seq)
        #expect(second?.text == "then 2 Green")
    }

    @Test func noFoundationMeansTodaysText() throws {
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":1}"#, foundation: nil)
        let seq = try WorkSequence(chart: chart)
        #expect(OnDeckRule.onDeck(cursor: .start, chart: chart, sequence: seq)?.text == "then 7 Gold")
    }

    @Test func ordinals() {
        #expect(OnDeckRule.ordinal(1) == "1st" && OnDeckRule.ordinal(2) == "2nd" && OnDeckRule.ordinal(3) == "3rd")
        #expect(OnDeckRule.ordinal(4) == "4th" && OnDeckRule.ordinal(11) == "11th" && OnDeckRule.ordinal(12) == "12th")
        #expect(OnDeckRule.ordinal(13) == "13th" && OnDeckRule.ordinal(22) == "22nd" && OnDeckRule.ordinal(103) == "103rd")
    }
}

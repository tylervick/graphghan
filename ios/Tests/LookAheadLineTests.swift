import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct LookAheadLineTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))
    private func line(_ row: Int) -> String? { LookAheadLine.text(row: row, stretches: Self.stretches, sequence: Self.seq, chart: Self.chart) }

    @Test func theCraighNaDunExamples() {
        #expect(line(1) == "1 more row like this · then Deep Green joins for 2 rows")
        #expect(line(5) == "9 more rows like this · then plain rows for 2 rows")
        #expect(line(13) == "1 more row like this · then plain rows for 2 rows")
        #expect(line(14) == "Last row like this · then plain rows for 2 rows")
        #expect(line(16) == "Last row like this · then busier rows for 4 rows")
        #expect(line(20) == "Last row like this · then Cream joins for 2 rows")
        #expect(line(22) == "Last row like this · then Charcoal joins for 19 rows")
        #expect(line(45) == "Last row like this · then Purple ends for 6 rows")
        #expect(line(170) == "Last row like this · then the repeat rows for 10 rows")
    }

    @Test func theLastStretchCountsDownToTheEnd() {
        #expect(line(183) == "1 more row like this · then Craigh na Dun Blanket is done")
        #expect(line(184) == nil)
    }

    @Test func aLongTitleIsTheBlanket() {
        #expect(LookAheadLine.ending(title: "Craigh na Dun Blanket") == "then Craigh na Dun Blanket is done")
        #expect(LookAheadLine.ending(title: "A Very Long Pattern Title Indeed") == "then the blanket is done")
        #expect(LookAheadLine.ending(title: "") == "then the blanket is done")
    }

    @Test func oneStretchHasNoLine() {
        let one = [Stretch(rows: 1...184, kind: .pattern, colours: ["C"])]
        #expect(LookAheadLine.text(row: 42, stretches: one, sequence: Self.seq, chart: Self.chart) == nil)
        #expect(LookAheadLine.text(row: 42, stretches: [], sequence: Self.seq, chart: Self.chart) == nil)
    }

    @Test func sentencesNameTheRowsAndColours() {
        #expect(LookAheadLine.sentence(for: Self.stretches[3], chart: Self.chart) == "Rows 15 to 16, 2 plain rows in Deep Green and Gold.")
        #expect(LookAheadLine.sentence(for: Self.stretches[4], chart: Self.chart) == "Rows 17 to 20, 4 rows in Deep Green and Gold.")
        #expect(LookAheadLine.sentence(for: Self.stretches[2], chart: Self.chart) == "Rows 5 to 14, 10 repeat rows in Gold and Deep Green.")
        #expect(LookAheadLine.sentence(for: Stretch(rows: 7...7, kind: .pattern, colours: ["C", "K", "G"]), chart: Self.chart) == "Row 7, 1 row in Cream, Charcoal and Deep Green.")
    }

    @Test func spokenIsTheLineAndTheNextTwoStretches() {
        #expect(LookAheadLine.spoken(row: 14, stretches: Self.stretches, sequence: Self.seq, chart: Self.chart)
                == "Last row like this, then plain rows for 2 rows. Rows 15 to 16, 2 plain rows in Deep Green and Gold. Rows 17 to 20, 4 rows in Deep Green and Gold.")
        #expect(LookAheadLine.spoken(row: 184, stretches: Self.stretches, sequence: Self.seq, chart: Self.chart) == nil)
    }
}

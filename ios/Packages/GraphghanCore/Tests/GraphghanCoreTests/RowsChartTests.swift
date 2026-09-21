import Foundation
import Testing
@testable import GraphghanCore

/// The rows-only assembler (phone import spec §4.3): the port of the Python `written_to_grid`
/// and its checks, so a chart built from written rows on the phone is the one the Mac builds.
@Suite struct RowsChartTests {
    typealias Row = RowsChart.Row

    @Test func rowsBecomeTheGridInDisplayOrderWithRSRowsReversed() throws {
        // Row 1 (RS, right to left) "2 A, 1 B" is drawn as B A A left to right; row 2 (WS) as written.
        let rows = [Row(row: 1, runs: [("A", 2), ("B", 1)], total: 3), Row(row: 2, runs: [("B", 3)], total: nil)]
        let strings = try RowsChart.rowStrings(rows: rows, codes: ["A", "B"], width: 3, height: 2).get()
        #expect(strings == ["3B", "1B2A"])
    }

    @Test func aRowThatDoesNotSumToTheWidthIsNamed() {
        let rows = [Row(row: 1, runs: [("A", 2)], total: nil), Row(row: 2, runs: [("A", 3)], total: nil)]
        let result = RowsChart.rowStrings(rows: rows, codes: ["A"], width: 3, height: 2)
        #expect(result == .failure(RowsChart.Problems(sentences: ["row 1: runs sum to 2, chart width is 3"])))
    }

    @Test func aPrintedTotalThatDisagreesWithTheRunsIsNamedFirst() {
        let rows = [Row(row: 1, runs: [("A", 3)], total: 4)]
        let result = RowsChart.rowStrings(rows: rows, codes: ["A"], width: 3, height: 1)
        #expect(result == .failure(RowsChart.Problems(sentences: ["row 1: runs sum to 3 but the pattern prints 4 sts"])))
    }

    @Test func duplicateMissingAndBeyondRowsAreNamed() {
        let rows = [Row(row: 1, runs: [("A", 1)], total: nil), Row(row: 1, runs: [("A", 1)], total: nil), Row(row: 5, runs: [("A", 1)], total: nil)]
        let result = RowsChart.rowStrings(rows: rows, codes: ["A"], width: 1, height: 3)
        #expect(result == .failure(RowsChart.Problems(sentences: ["row 1 printed twice", "missing rows 2-3 of 3", "rows 5 are beyond the chart height 3"])))
    }

    @Test func aCodeNotInThePaletteIsNamed() {
        let rows = [Row(row: 1, runs: [("Q", 1)], total: nil)]
        let result = RowsChart.rowStrings(rows: rows, codes: ["A"], width: 1, height: 1)
        #expect(result == .failure(RowsChart.Problems(sentences: ["row 1 uses code 'Q', not in the palette [\"A\"]"])))
    }

    @Test func theOwnPDFsRowsRebuildTheMacsChart() throws {
        let reading = try ChartWriterTests.reading("craigh-na-dun-final-sc")
        let rows = reading.rows.map { Row(row: $0.row, runs: $0.runs.map { ($0.code, $0.count) }, total: $0.total) }
        let strings = try RowsChart.rowStrings(rows: rows, codes: reading.palette.map(\.code), width: reading.width, height: reading.height).get()
        let id = ChartID.compute(codes: reading.palette.map(\.code), rows: strings, technique: ChartWriter.techniqueRows, passes: nil)
        #expect(id == "sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f")
    }

    @Test func placeholdersAreLoudAndFarFromTheTakenColours() {
        #expect(RowsChart.placeholderHex(avoiding: []) == "#ff00ff")
        #expect(RowsChart.placeholderHex(avoiding: ["#ff00ff"]) == "#00ffff")
        #expect(RowsChart.placeholders.count == 8)
    }
}

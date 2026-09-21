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

    // MARK: the cross-check (phone import spec §4.2, §6.3)

    /// The Craigh chart's own written rows against its own cells: nothing disagrees.
    @Test func theOwnRowsAgreeWithTheOwnCells() throws {
        let reading = try ChartWriterTests.reading("craigh-na-dun-final-sc")
        let chart = try Chart.load(ChartWriter.encode(ChartWriter.draft(from: reading, id: "x")).data)
        let rows = reading.rows.map { Row(row: $0.row, runs: $0.runs.map { ($0.code, $0.count) }, total: $0.total) }
        let outcome = RowsChart.crossCheck(rows: rows, codes: reading.palette.map(\.code), grid: chart.cells, width: chart.width, height: chart.height)
        #expect(outcome == .compared(disagree: [], warnings: []))
    }

    @Test func aWrongRowIsNamedAndAPrefixIsComparedAlone() throws {
        let reading = try ChartWriterTests.reading("craigh-na-dun-final-sc")
        let chart = try Chart.load(ChartWriter.encode(ChartWriter.draft(from: reading, id: "x")).data)
        var rows = reading.rows.map { Row(row: $0.row, runs: $0.runs.map { ($0.code, $0.count) }, total: $0.total) }
        // Row 40 with its first two runs swapped in width: same total, different cells.
        let i = rows.firstIndex { $0.row == 40 }!
        var runs = rows[i].runs
        runs[0] = (runs[0].code, runs[0].count - 1)
        runs[1] = (runs[1].code, runs[1].count + 1)
        rows[i] = Row(row: 40, runs: runs, total: rows[i].total)
        #expect(RowsChart.crossCheck(rows: rows, codes: reading.palette.map(\.code), grid: chart.cells, width: chart.width, height: chart.height)
                == .compared(disagree: [40], warnings: []))
        // The first 50 rows alone (a stopped check): still row 40, no "missing rows" problem.
        let prefix = rows.filter { $0.row <= 50 }
        #expect(RowsChart.crossCheck(rows: prefix, codes: reading.palette.map(\.code), grid: chart.cells, width: chart.width, height: chart.height)
                == .compared(disagree: [40], warnings: []))
    }

    @Test func tooManyDisagreementsMeanTheOrientationIsWrong() {
        // Two colours, 4 × 20, rows alternating AAAB / BBBA. Three wrong rows are more than a tenth
        // and refused; two are named. (A whole-chart flip cannot be tested here: the majority
        // vote that pairs chart colours with codes absorbs it on a two-colour chart, as the
        // Python's does.)
        var grid: [UInt8] = []
        for y in 0..<20 { grid += y % 2 == 0 ? [0, 0, 0, 1] : [1, 1, 1, 0] }
        func rows(wrong: [Int]) -> [Row] {
            (1...20).map { r in
                let y = 20 - r
                var runs: [(code: String, count: Int)] = y % 2 == 0 ? [("A", 3), ("B", 1)] : [("B", 3), ("A", 1)]
                if wrong.contains(r) { runs = y % 2 == 0 ? [("A", 1), ("B", 1), ("A", 1), ("B", 1)] : [("B", 1), ("A", 1), ("B", 1), ("A", 1)] }
                if r % 2 == 1 { runs.reverse() }  // RS rows are written right to left
                return Row(row: r, runs: runs, total: nil)
            }
        }
        #expect(RowsChart.crossCheck(rows: rows(wrong: [5, 9, 13]), codes: ["A", "B"], grid: grid, width: 4, height: 20)
                == .incomparable("3 of 20 rows disagree with the chart; the row-1 position or direction is probably wrong, not the rows."))
        #expect(RowsChart.crossCheck(rows: rows(wrong: [5, 9]), codes: ["A", "B"], grid: grid, width: 4, height: 20)
                == .compared(disagree: [5, 9], warnings: []))
    }

    @Test func aPaletteWithADuplicateOrTooManyCodesIsIncomparableNotACrash() {
        let grid: [UInt8] = [0, 1, 0, 1]
        #expect(RowsChart.crossCheck(rows: [Row(row: 1, runs: [("A", 2)], total: nil)], codes: ["A", "A"], grid: grid, width: 2, height: 2)
                == .incomparable("palette code 'A' appears twice"))
        let many = (0..<257).map { "C\($0)" }
        #expect(RowsChart.crossCheck(rows: [Row(row: 1, runs: [("C0", 2)], total: nil)], codes: many, grid: grid, width: 2, height: 2)
                == .incomparable("palette has 257 codes; at most 256 are supported"))
    }

    @Test func rowsThatDoNotAssembleOrPairAreIncomparable() {
        let grid: [UInt8] = [0, 1, 0, 1]
        #expect(RowsChart.crossCheck(rows: [Row(row: 1, runs: [("A", 1)], total: nil)], codes: ["A", "B"], grid: grid, width: 2, height: 2)
                == .incomparable("row 1: runs sum to 1, chart width is 2"))
        // Both chart colours read as A in the rows: the picture has more colours than the key.
        #expect(RowsChart.crossCheck(rows: [Row(row: 1, runs: [("A", 2)], total: nil), Row(row: 2, runs: [("A", 2)], total: nil)], codes: ["A", "B"], grid: grid, width: 2, height: 2)
                == .incomparable("two chart colours both read as [\"A\"] in the written rows; the picture has more colours than the key, or a row is wrong"))
    }
}

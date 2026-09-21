import Foundation
import PDFKit
import Testing
@testable import GraphghanCore

/// A region on a page becomes the chart the library stores; our own PDF's chart page becomes
/// the slice of the chart the Mac exported, colours clustered rather than read from the key.
@Suite struct GridChartTests {
    @Test func theSyntheticGridBecomesAChartWithCodesByFrequency() throws {
        let (img, answer) = try GridReaderTests.fixture("one-grid")
        let region = try #require(try GridReader.findRegions(img).first)
        let (draft, cells, warnings) = try GridChart.draft(image: img, region: region, title: "Synthetic")
        #expect(draft.width == 37 && draft.height == 29 && draft.rows.count == 29 && warnings.isEmpty)
        #expect(draft.palette.map(\.code) == ["A", "B", "C", "D"] && draft.palette.map(\.hex) == answer.cluster!.hexes)
        #expect(draft.palette.map(\.name) == answer.cluster!.hexes.compactMap(GridColours.nameColour))
        #expect(cells.map(Int.init) == answer.cluster!.cells.flatMap { $0 })
        #expect(ImportRecord(json: draft.ext) == ImportRecord(grid: true, check: .noRows, rowsChecked: 0, rowsTotal: 0, rowsDisagree: [], gaugePrinted: false, problem: nil))
        let (data, id) = ChartWriter.encode(draft)
        let chart = try Chart.load(data)
        #expect(chart.id == id && chart.cells == cells && chart.document.gauge.stitch == "sc")
    }

    @Test func theRecordsSentencesAreTheSpecs() {
        func rec(_ check: ImportRecord.Check, _ checked: Int = 77, _ disagree: [Int] = [], problem: String? = nil) -> ImportRecord {
            ImportRecord(grid: true, check: check, rowsChecked: checked, rowsTotal: 77, rowsDisagree: disagree, gaugePrinted: false, problem: problem)
        }
        #expect(rec(.noRows).sentence == nil && rec(.finished).sentence == nil)
        #expect(rec(.finished, 77, [12, 40, 41]).sentence == "Rows 12, 40 and 41 disagree with the chart. The chart is as drawn; check those rows against the PDF.")
        #expect(rec(.finished, 77, [12]).sentence == "Row 12 disagrees with the chart. The chart is as drawn; check those rows against the PDF.")
        #expect(rec(.stopped, 34).sentence == "Written rows checked up to row 34; 35–77 not checked.")
        #expect(rec(.stopped, 77).sentence == nil && rec(.stopped, 77, [3]).sentence == "Row 3 disagrees with the chart. The chart is as drawn; check those rows against the PDF.")  // stopped after the last row
        #expect(rec(.unavailable, 0).sentence == "Written rows not checked on this iPhone.")
        #expect(rec(.finished, 77, problem: "written rows give 30x77, the chart reads 29x77").sentence == "Written rows could not be compared with the chart: written rows give 30x77, the chart reads 29x77.")
        let json = rec(.stopped, 34, [3]).json()
        #expect(ImportRecord(json: json) == rec(.stopped, 34, [3]) && json["graphghan"]?["import"]?["rows_total"]?.intValue == 77)
    }

    @Test func theOwnPDFsChartPageIsTheSliceTheMacExported() throws {
        let doc = try #require(PDFDocument(url: Fixtures.importPDF("craigh-na-dun-final-sc")))
        let (page, header) = try #require(PageRender.firstChartPage(doc))
        let img = try #require(PageRender.image(page, scale: 4))
        let region = try #require(try GridReader.findRegions(img).first)
        let (draft, cells, _) = try GridChart.draft(image: img, region: region, title: "Craigh")
        #expect(draft.width == header.cols && draft.height == header.rows)
        // The Mac's chart, sliced to this page: columns a-b, rows c-d, row 1 at the bottom right.
        let mac = try Chart.load(try Fixtures.data("craigh-na-dun.chart.json"))  // the final-sc chart, 189×184
        var want: [UInt8] = []
        for y in (mac.height - header.rowTo)..<(mac.height - header.rowFrom + 1) {
            for x in (mac.width - header.colTo)..<(mac.width - header.colFrom + 1) { want.append(mac.cells[y * mac.width + x]) }
        }
        // Clusters are by frequency, the Mac's palette by the pattern: compare through the hexes.
        let macHex = mac.palette.map(\.hex)
        let draftHex = draft.palette.map(\.hex)
        #expect(cells.map { draftHex[Int($0)] } == want.map { macHex[Int($0)] })
    }
}

/// The busy sentence (#176). How far the check got before the model stopped answering is the
/// number that tells a refusal which began at once apart from one which set in part way down, so
/// the sentence carries it whenever there is one.
@Suite struct ImportRecordBusyTests {
    func record(checked: Int, total: Int) -> ImportRecord {
        ImportRecord(grid: true, check: .finished, rowsChecked: checked, rowsTotal: total,
                     rowsDisagree: [], gaugePrinted: false, problem: ImportRecord.modelBusy)
    }

    @Test func refusedFromTheStartSaysOnlyThatTheModelIsBusy() {
        #expect(record(checked: 0, total: 77).sentence == "The on-device model is busy; try the check again in a minute.")
        #expect(record(checked: 0, total: 0).sentence == ImportRecord.modelBusySentence)
    }

    @Test func refusedPartWayDownSaysHowFarItGot() {
        #expect(record(checked: 43, total: 77).sentence
            == "The on-device model is busy; 43 of 77 written rows were checked. Try the check again in a minute.")
    }

    /// Anything else keeps reporting itself as it stands.
    @Test func anotherProblemIsStillReportedVerbatim() {
        var other = record(checked: 43, total: 77)
        other.problem = "row 5: no colour named"
        #expect(other.sentence == "Written rows could not be compared with the chart: row 5: no colour named.")
    }
}

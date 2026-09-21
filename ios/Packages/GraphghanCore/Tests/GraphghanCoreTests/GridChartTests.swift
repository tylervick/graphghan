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
        let (draft, cells, warnings) = GridChart.draft(image: img, region: region, title: "Synthetic")
        #expect(draft.width == 37 && draft.height == 29 && draft.rows.count == 29 && warnings.isEmpty)
        #expect(draft.palette.map(\.code) == ["A", "B", "C", "D"] && draft.palette.map(\.hex) == answer.cluster!.hexes)
        #expect(draft.palette.map(\.name) == answer.cluster!.hexes.map(GridColours.nameColour))
        #expect(cells.map(Int.init) == answer.cluster!.cells.flatMap { $0 })
        #expect(ImportRecord(json: draft.ext) == ImportRecord(grid: true, check: .none, rowsChecked: 0, rowsTotal: 0, rowsDisagree: [], gaugePrinted: false, problem: nil))
        let (data, id) = ChartWriter.encode(draft)
        let chart = try Chart.load(data)
        #expect(chart.id == id && chart.cells == cells && chart.document.gauge.stitch == "sc")
    }

    @Test func theRecordsSentencesAreTheSpecs() {
        func rec(_ check: ImportRecord.Check, _ checked: Int = 77, _ disagree: [Int] = [], problem: String? = nil) -> ImportRecord {
            ImportRecord(grid: true, check: check, rowsChecked: checked, rowsTotal: 77, rowsDisagree: disagree, gaugePrinted: false, problem: problem)
        }
        #expect(rec(.none).sentence == nil && rec(.finished).sentence == nil)
        #expect(rec(.finished, 77, [12, 40, 41]).sentence == "Rows 12, 40 and 41 disagree with the chart. The chart is as drawn; check those rows against the PDF.")
        #expect(rec(.finished, 77, [12]).sentence == "Row 12 disagrees with the chart. The chart is as drawn; check those rows against the PDF.")
        #expect(rec(.stopped, 34).sentence == "Written rows checked up to row 34; 35–77 not checked.")
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
        let (draft, cells, _) = GridChart.draft(image: img, region: region, title: "Craigh")
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

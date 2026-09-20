import Foundation
import PDFKit
import Testing
@testable import GraphghanCore

/// A chart document the phone writes decodes like one the Mac wrote and hashes to the same id
/// (phone import spec §5.3).
@Suite struct ChartWriterTests {
    static func reading(_ name: String) throws -> OwnPDFReading {
        let doc = try #require(PDFDocument(url: Fixtures.importPDF(name)))
        let texts = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        return try OwnPDFReader.read(pageTexts: texts, title: title)
    }

    @Test func runStringsRoundTrip() {
        #expect(ChartWriter.runString([(code: "Y", count: 189)]) == "189Y")
        #expect(ChartWriter.runString([(code: "Y", count: 1), (code: "G", count: 187), (code: "Y", count: 1)]) == "1Y187G1Y")
        #expect(RunString.parse("1Y187G1Y")!.map { "\($0.count)\($0.code)" } == ["1Y", "187G", "1Y"])
    }

    @Test func theOwnPDFWritesTheChartTheMacExported() throws {
        let draft = ChartWriter.draft(from: try Self.reading("craigh-na-dun-final-sc"), id: "craigh-na-dun")
        let (data, id) = ChartWriter.encode(draft)
        let chart = try Chart.load(data)
        #expect(chart.id == id)
        // fixtures/bundle/craigh-na-dun.graphghan, charts/final-sc/chart.json
        #expect(id == "sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f")
        #expect(chart.width == 189 && chart.height == 184 && chart.palette.count == 5 && chart.title == "Craigh na Dun Blanket")
        #expect(chart.document.gauge.hook == "5 mm (US H-8)" && chart.document.gauge.boundary?.chain == 1)
        #expect(chart.document.pattern.author == "Tyler Vick" && chart.document.pattern.version == "1.0.0")
    }

    @Test func encodingIsCanonicalAndStable() throws {
        let draft = ChartWriter.draft(from: try Self.reading("craigh-na-dun-final-hdc"), id: "craigh-na-dun")
        let a = ChartWriter.encode(draft)
        let b = ChartWriter.encode(draft)
        #expect(a.data == b.data && a.id == b.id)
        let text = String(decoding: a.data, as: UTF8.self)
        #expect(text.hasPrefix("{\"chart\":{") && !text.contains("\n"))
        #expect(a.id == "sha256:2b8df35ef492162668789c9dd128123590a5ca9e3e2758b361baf571e52d6f7f")  // fixtures/bundle/craigh-na-dun.graphghan, charts/final-hdc/chart.json
    }
}

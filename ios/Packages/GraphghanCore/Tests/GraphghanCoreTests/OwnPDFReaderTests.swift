import Foundation
import PDFKit
import Testing
@testable import GraphghanCore

/// Our own PDFs read exactly from their text layer (phone import spec §4.1), against the two
/// committed round-trip fixtures. PDFKit here is the test's way to get page texts; the reader
/// itself never sees a PDF.
@Suite struct OwnPDFReaderTests {
    static func texts(_ name: String) throws -> (texts: [String], title: String) {
        let doc = try #require(PDFDocument(url: Fixtures.importPDF(name)))
        let texts = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        return (texts, title)
    }

    @Test func recognisesItsOwnCoverAndNothingElse() throws {
        let (texts, _) = try Self.texts("craigh-na-dun-final-sc")
        #expect(OwnPDFReader.isOwn(pageTexts: texts))
        #expect(!OwnPDFReader.isOwn(pageTexts: ["Row 1: 3 A, 4 B", "Key\nA red"]))
        #expect(!OwnPDFReader.isOwn(pageTexts: []))
    }

    @Test func readsTheCoverKeyChartHeadersAndRows() throws {
        let (texts, title) = try Self.texts("craigh-na-dun-final-sc")
        let r = try OwnPDFReader.read(pageTexts: texts, title: title)
        #expect(r.pattern.title == "Craigh na Dun Blanket")
        #expect(r.pattern.author == "Tyler Vick" && r.pattern.license == "CC-BY-NC-SA-4.0" && r.pattern.version == "1.0.0")
        #expect(r.pattern.dedication == "For Meaghan")
        #expect(r.pattern.quote == "Lord, you gave me a rare woman, and God! I loved her well.")
        #expect(r.gauge?.stitches == 14 && r.gauge?.rows == 16 && r.gauge?.over.value == 4 && r.gauge?.over.unit == "in")
        #expect(r.gauge?.hook == "5 mm (US H-8)" && r.gauge?.yarnWeight == "worsted (#4)" && r.gauge?.stitchName == "single crochet")
        #expect(r.gauge?.chain == 1)
        #expect(r.finishedSize?.width == 54 && r.finishedSize?.height == 46 && r.finishedSize?.unit == "in")
        #expect(r.width == 189 && r.height == 184)
        #expect(r.palette.map(\.code) == ["C", "K", "G", "P", "Y"])
        #expect(r.palette[0].name == "Cream" && r.palette[0].hex == "#f2e8d5" && r.palette[0].yarnNote == "Aran / off-white")
        #expect(r.rows.count == 184 && r.rows.first?.row == 1 && r.rows.last?.row == 184)
        #expect(r.rows[0].runs.map { "\($0.count)\($0.code)" } == ["189Y"])
        #expect(r.rows.allSatisfy { row in row.runs.reduce(0) { $0 + $1.count } == row.total && row.total == 189 })
    }

    @Test func theHdcFixtureReadsToo() throws {
        let (texts, title) = try Self.texts("craigh-na-dun-final-hdc")
        let r = try OwnPDFReader.read(pageTexts: texts, title: title)
        #expect(r.width == 176 && r.rows.count == r.height && r.rows.allSatisfy { $0.total == 176 } && r.gauge?.stitchName == "half double crochet")
    }

    @Test func aRowItCannotReadNamesThePageAndTheText() throws {
        var (texts, title) = try Self.texts("craigh-na-dun-final-sc")
        let page = try #require(texts.firstIndex { $0.hasPrefix("Written rows") })
        texts[page] = texts[page].replacingOccurrences(of: "Row 1 (RS): 189 Y (189 sts)", with: "Row 1 (RS): 189 Y and a bit (189 sts)")
        #expect(throws: OwnPDFError.badRow(page: page + 1, text: "Row 1 (RS): 189 Y and a bit (189 sts)")) {
            try OwnPDFReader.read(pageTexts: texts, title: title)
        }
    }

    @Test func aMissingChartHeaderIsRefused() throws {
        let (texts, title) = try Self.texts("craigh-na-dun-final-sc")
        let stripped = texts.map { $0.hasPrefix("Chart ") ? "" : $0 }
        #expect(throws: OwnPDFError.noChartHeader) { try OwnPDFReader.read(pageTexts: stripped, title: title) }
    }

    @Test func theCoverTitleBeatsTheMetadataTitle() throws {
        let (texts, _) = try Self.texts("craigh-na-dun-final-sc")
        let blank = try OwnPDFReader.read(pageTexts: texts, title: "")
        let wrong = try OwnPDFReader.read(pageTexts: texts, title: "craigh-na-dun-final-sc")
        #expect(blank.pattern.title == "Craigh na Dun Blanket" && blank.pattern.dedication == "For Meaghan")
        #expect(wrong.pattern.title == "Craigh na Dun Blanket" && wrong.rows.count == 184)
    }

    @Test func aChartBeyondTheSizeCapIsRefusedBeforeAnythingIsBuilt() throws {
        let (texts, title) = try Self.texts("craigh-na-dun-final-sc")
        let huge = texts.map { $0.replacingOccurrences(of: "of 189, rows", with: "of 2189, rows") }
        #expect(throws: OwnPDFError.tooLarge(width: 2189, height: 184)) { try OwnPDFReader.read(pageTexts: huge, title: title) }
    }
}

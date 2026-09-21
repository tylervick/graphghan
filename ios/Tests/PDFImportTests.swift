import Foundation
import PDFKit
import Testing
import UIKit
import GraphghanCore
import ProseReaderKit
@testable import Graphghan

/// A PDF from bytes to a pattern in the library (phone import spec §4.1, §4.3, §5.3), and the
/// sentences for what cannot be read (§5.4). The written-row reader is a stub: the model never
/// runs in a test (§9).
@MainActor
@Suite struct PDFImportTests {
    struct Base {
        let charts: ChartLibrary
        let local: LocalPatternStore
        let chartsDir: URL
        let localDir: URL
        func importer(rowReader: (any RowReading)? = nil, modelUnavailable: String? = nil) -> PDFImporter {
            PDFImporter(charts: charts, local: local, rowReader: rowReader, modelUnavailable: modelUnavailable)
        }
    }

    func make() async throws -> Base {
        let chartsDir = try temporaryDirectory()
        let localDir = try temporaryDirectory()
        return Base(charts: ChartLibrary(directory: chartsDir), local: LocalPatternStore(directory: localDir), chartsDir: chartsDir, localDir: localDir)
    }

    /// A canned answer standing in for the model (phone import spec §9).
    struct StubRowReader: RowReading {
        let document: ProseDocument
        let delayPerRow: Duration
        func read(pages: [String], progress: (@Sendable (ReaderProgress) -> Void)?) async -> ProseDocument {
            let total = RowText.rowCount(in: pages)
            for i in 0..<total {
                if Task.isCancelled { return ProseDocument() }
                try? await Task.sleep(for: delayPerRow)
                progress?(ReaderProgress(page: 1, rowsSoFar: i + 1, rowsTotal: total, seconds: Double(i)))
            }
            return document
        }
    }

    static let twoRowText = "Key\nA red\nB blue\nRow 1: 2 A, 1 B\nRow 2: 3 B\n"

    static func twoRowDocument() -> ProseDocument {
        var doc = ProseDocument()
        doc.pattern = ["title": "Two Rows"]
        doc.palette = [.init(code: "A", name: "red", hex: "#ff0000", key_label: "red"), .init(code: "B", name: "blue", hex: "#0000ff", key_label: "blue")]
        doc.chart = .init(width: 3, height: 2, row1: "bottom-right")
        doc.written_rows = [
            .init(row: 1, page: 1, text: "Row 1: 2 A, 1 B", runs: [[.code("A"), .count(2)], [.code("B"), .count(1)]], total: nil, error: nil),
            .init(row: 2, page: 1, text: "Row 2: 3 B", runs: [[.code("B"), .count(3)]], total: nil, error: nil),
        ]
        return doc
    }

    // MARK: our own PDF (PR 1)

    @Test func ourOwnPDFReadsToTheMacsChartAndSaves() async throws {
        let base = try await make()
        let importer = base.importer()
        let reading = try await importer.read(try TestFixtures.importPDF("craigh-na-dun-final-sc"), fileName: "craigh-na-dun-final-sc.pdf")
        #expect(reading.width == 189 && reading.height == 184 && reading.colours == 5 && reading.source == .ownPDF)
        #expect(reading.bundle.manifest.id == "craigh-na-dun-blanket" && reading.bundle.manifest.title == "Craigh na Dun Blanket")
        #expect(reading.bundle.charts.first?.chart.id == "sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f")
        #expect(reading.bundle.manifest.dedication.hasPrefix("Imported from craigh-na-dun-final-sc.pdf on "))
        #expect(!reading.preview.isEmpty)
        // Nothing is written by a read.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: base.chartsDir.path)) ?? []).isEmpty)
        let manifest = try await importer.save(reading)
        #expect(manifest.id == "craigh-na-dun-blanket")
        let stored = (try? FileManager.default.contentsOfDirectory(atPath: base.chartsDir.path)) ?? []
        #expect(stored.count == 1)
        #expect(FileManager.default.fileExists(atPath: base.localDir.appendingPathComponent("craigh-na-dun-blanket/pattern.json").path))
        #expect(FileManager.default.fileExists(atPath: base.localDir.appendingPathComponent("craigh-na-dun-blanket/charts/final-sc/preview.png").path))
        #expect(FileManager.default.fileExists(atPath: base.localDir.appendingPathComponent("craigh-na-dun-blanket/preview.png").path))
    }

    @Test func aFileThatIsNotAPDFCannotBeOpened() async throws {
        let importer = try await make().importer()
        await #expect(throws: PDFImportError.cannotOpen) { try await importer.read(Data("hello".utf8), fileName: "x.pdf") }
        #expect(PDFImportError.cannotOpen.message == "That PDF couldn't be opened.")
    }

    @Test func aPDFWithNeitherChartNorRowsReportsNothingFound() async throws {
        let importer = try await make().importer()
        let pdf = try #require(PDFTestDocuments.plain(text: "A page of prose about crochet, with no rows and no chart on it at all."))
        await #expect(throws: PDFImportError.nothingFound) { try await importer.read(pdf, fileName: "other.pdf") }
        #expect(PDFImportError.nothingFound.message == "No chart or written rows were found in this PDF.")
    }

    @Test func tooBigIsRefusedBeforeReading() async throws {
        let importer = try await make().importer()
        let big = Data(count: PDFImporter.maximumBytes + 1)
        await #expect(throws: PDFImportError.tooBig) { try await importer.read(big, fileName: "big.pdf") }
        #expect(PDFImportError.tooBig.message == "That file is too big to be a pattern.")
    }

    @Test func theSlugComesFromTheTitleAndStaysUniqueWithinTheStore() async throws {
        let importer = try await make().importer()
        let data = try TestFixtures.importPDF("craigh-na-dun-final-sc")
        let first = try await importer.read(data, fileName: "a.pdf")
        _ = try await importer.save(first)
        let second = try await importer.read(data, fileName: "b.pdf")
        #expect(second.bundle.manifest.id == "craigh-na-dun-blanket-2")
        #expect(PDFImporter.slug("Café au Lait: A Blanket!") == "cafe-au-lait-a-blanket")
    }

    // MARK: written rows alone (PR 2)

    @Test func writtenRowsWithNoChartBecomeAChartThroughTheReader() async throws {
        let importer = try await make().importer(rowReader: StubRowReader(document: Self.twoRowDocument(), delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        let seen = Progress()
        let reading = try await importer.read(pdf, fileName: "two-rows.pdf") { p in Task { await seen.add(p) } }
        #expect(reading.width == 3 && reading.height == 2 && reading.colours == 2)
        #expect(reading.bundle.manifest.title == "Two Rows" && reading.bundle.manifest.id == "two-rows")
        #expect(reading.bundle.charts[0].chart.document.rows == ["3B", "1B2A"])  // RS row 1 reversed, drawn last
        #expect(reading.source == .writtenRows(count: 2, gaugePrinted: false))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await seen.items.contains(.rows(done: 0, of: 2, secondsElapsed: 0)))  // before the first row
        #expect(await seen.items.contains(.rows(done: 2, of: 2, secondsElapsed: 0)))
        let ext = reading.bundle.charts[0].chart.document.ext?["graphghan"]?["import"]
        #expect(ext?["source"]?.stringValue == "pdf" && ext?["grid"]?.boolValue == false && ext?["check"]?.stringValue == "none")
        #expect(ext?["gauge_printed"]?.boolValue == false)
    }

    @Test func aRowThatDoesNotAssembleIsReportedNotWritten() async throws {
        var doc = Self.twoRowDocument()
        doc.written_rows?[1].runs = [[.code("B"), .count(2)]]
        let base = try await make()
        let importer = base.importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        await #expect(throws: PDFImportError.rowsDoNotAssemble(["row 2: runs sum to 2, chart width is 3"])) { try await importer.read(pdf, fileName: "x.pdf") }
        #expect(PDFImportError.rowsDoNotAssemble(["row 2: runs sum to 2, chart width is 3"]).message == "The written rows in this PDF don't add up: row 2: runs sum to 2, chart width is 3.")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: base.chartsDir.path)) ?? []).isEmpty)
    }

    @Test func aKeyColourWithNoHexGetsAPlaceholder() async throws {
        var doc = Self.twoRowDocument()
        doc.palette?[1].hex = nil
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        let reading = try await importer.read(pdf, fileName: "x.pdf")
        #expect(reading.bundle.charts[0].chart.palette.map(\.hex) == ["#ff0000", "#ff00ff"])
    }

    @Test func withoutAModelWrittenRowsNeedAppleIntelligence() async throws {
        let importer = try await make().importer(rowReader: nil, modelUnavailable: "on-device model unavailable")
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        await #expect(throws: PDFImportError.needsAppleIntelligence) { try await importer.read(pdf, fileName: "x.pdf") }
        #expect(PDFImportError.needsAppleIntelligence.message.hasPrefix("Reading written rows needs Apple Intelligence on this iPhone."))
    }

    @Test func aPageOfPicturesWithNoTextIsNamed() async throws {
        let importer = try await make().importer(rowReader: StubRowReader(document: Self.twoRowDocument(), delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.imageOnly())
        await #expect(throws: PDFImportError.rowsArePictures) { try await importer.read(pdf, fileName: "scan.pdf") }
        #expect(PDFImportError.rowsArePictures.message == "This pattern's rows are printed as a picture; the app can't read that yet.")
    }

    @Test func cancellingTheReadThrowsCancelledAndWritesNothing() async throws {
        let base = try await make()
        let importer = base.importer(rowReader: StubRowReader(document: Self.twoRowDocument(), delayPerRow: .seconds(1)))
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        let task = Task { try await importer.read(pdf, fileName: "x.pdf") }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: PDFImportError.cancelled) { try await task.value }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: base.chartsDir.path)) ?? []).isEmpty)
    }
}

/// Progress events collected off the importer's callback.
actor Progress {
    var items: [PDFImportProgress] = []
    func add(_ p: PDFImportProgress) { items.append(p) }
}

/// PDFs made in the test, for the paths that are not our own PDF.
enum PDFTestDocuments {
    static let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)

    static func plain(text: String) -> Data? {
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            (text as NSString).draw(in: bounds.insetBy(dx: 36, dy: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        }
    }

    /// One page that is only a picture: what a Canva export of the rows looks like to PDFKit.
    static func imageOnly() -> Data? {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            image.draw(in: CGRect(x: 100, y: 100, width: 400, height: 400))
        }
    }
}

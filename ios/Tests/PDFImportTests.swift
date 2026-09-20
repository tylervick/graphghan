import Foundation
import PDFKit
import Testing
import UIKit
import GraphghanCore
@testable import Graphghan

/// A PDF our own exporter wrote, from bytes to a pattern in the library (phone import spec §4.1,
/// §5.3), and the sentences for what is not that (§5.4).
@MainActor
@Suite struct PDFImportTests {
    func make() async throws -> (importer: PDFImporter, charts: URL, local: URL) {
        let charts = try temporaryDirectory()
        let local = try temporaryDirectory()
        return (PDFImporter(charts: ChartLibrary(directory: charts), local: LocalPatternStore(directory: local)), charts, local)
    }

    @Test func ourOwnPDFReadsToTheMacsChartAndSaves() async throws {
        let (importer, chartsDir, localDir) = try await make()
        let reading = try await importer.read(try TestFixtures.importPDF("craigh-na-dun-final-sc"), fileName: "craigh-na-dun-final-sc.pdf")
        #expect(reading.width == 189 && reading.height == 184 && reading.colours == 5)
        #expect(reading.bundle.manifest.id == "craigh-na-dun-blanket" && reading.bundle.manifest.title == "Craigh na Dun Blanket")
        #expect(reading.bundle.charts.first?.chart.id == "sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f")
        #expect(reading.bundle.manifest.dedication.hasPrefix("Imported from craigh-na-dun-final-sc.pdf on "))
        #expect(!reading.preview.isEmpty)
        // Nothing is written by a read.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: chartsDir.path)) ?? []).isEmpty)
        let manifest = try await importer.save(reading)
        #expect(manifest.id == "craigh-na-dun-blanket")
        let stored = (try? FileManager.default.contentsOfDirectory(atPath: chartsDir.path)) ?? []
        #expect(stored.count == 1)
        #expect(FileManager.default.fileExists(atPath: localDir.appendingPathComponent("craigh-na-dun-blanket/pattern.json").path))
        #expect(FileManager.default.fileExists(atPath: localDir.appendingPathComponent("craigh-na-dun-blanket/charts/final-sc/preview.png").path))
        #expect(FileManager.default.fileExists(atPath: localDir.appendingPathComponent("craigh-na-dun-blanket/preview.png").path))
    }

    @Test func aFileThatIsNotAPDFCannotBeOpened() async throws {
        let (importer, _, _) = try await make()
        await #expect(throws: PDFImportError.cannotOpen) { try await importer.read(Data("hello".utf8), fileName: "x.pdf") }
        #expect(PDFImportError.cannotOpen.message == "That PDF couldn't be opened.")
    }

    @Test func aPDFThatIsNotOursReportsNothingFoundForNow() async throws {
        let (importer, _, _) = try await make()
        let pdf = try #require(PDFTestDocuments.plain(text: "Row 1: 3 A, 4 B\nRow 2: 7 A"))
        await #expect(throws: PDFImportError.nothingFound) { try await importer.read(pdf, fileName: "other.pdf") }
        #expect(PDFImportError.nothingFound.message == "No chart or written rows were found in this PDF.")
    }

    @Test func tooBigIsRefusedBeforeReading() async throws {
        let (importer, _, _) = try await make()
        let big = Data(count: PDFImporter.maximumBytes + 1)
        await #expect(throws: PDFImportError.tooBig) { try await importer.read(big, fileName: "big.pdf") }
        #expect(PDFImportError.tooBig.message == "That file is too big to be a pattern.")
    }

    @Test func theSlugComesFromTheTitleAndStaysUniqueWithinTheStore() async throws {
        let (importer, _, _) = try await make()
        let data = try TestFixtures.importPDF("craigh-na-dun-final-sc")
        let first = try await importer.read(data, fileName: "a.pdf")
        _ = try await importer.save(first)
        let second = try await importer.read(data, fileName: "b.pdf")
        #expect(second.bundle.manifest.id == "craigh-na-dun-blanket-2")
        #expect(PDFImporter.slug("Café au Lait: A Blanket!") == "cafe-au-lait-a-blanket")
    }
}

/// A PDF made in the test from plain text, for the paths that are not ours.
enum PDFTestDocuments {
    static func plain(text: String) -> Data? {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            (text as NSString).draw(in: bounds.insetBy(dx: 36, dy: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        }
    }
}

import Foundation
import Testing
import GraphghanCore
import ProseReaderKit
@testable import Graphghan

/// The import sheet's states, driven through `AppModel` the way the app drives them (phone import
/// spec §5.2), without a screen.
@MainActor
@Suite struct PDFImportSheetTests {
    func make(rowReader: (any RowReading)? = nil, modelUnavailable: String? = nil) async throws -> AppModel {
        let container = try makeInMemoryContainer()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: StubClient())
        return AppModel(context: container.mainContext, patterns: patterns,
                        charts: ChartLibrary(directory: try temporaryDirectory()), localPatterns: LocalPatternStore(directory: try temporaryDirectory()),
                        rowReader: .some(rowReader), modelUnavailable: .some(modelUnavailable))
    }

    @Test func ourOwnPDFGoesReadingThenFoundThenAdds() async throws {
        let model = try await make()
        await model.importPDF(data: try TestFixtures.importPDF("craigh-na-dun-final-sc"), fileName: "craigh.pdf")
        let state = try #require(model.pdfImport)
        #expect(state.stage == .found && state.reading?.width == 189 && state.preview != nil)
        #expect(model.libraryItems.isEmpty)  // nothing saved yet
        await model.addImportedPDF()
        #expect(model.pdfImport == nil && model.tab == .patterns)
        #expect(model.libraryItems.contains { $0.source == .local && $0.slug == "craigh-na-dun-blanket" })
        #expect(model.libraryPath.first?.slug == "craigh-na-dun-blanket")
    }

    @Test func cancelLeavesTheLibraryUntouched() async throws {
        let model = try await make()
        await model.importPDF(data: try TestFixtures.importPDF("craigh-na-dun-final-sc"), fileName: "craigh.pdf")
        model.cancelPDFImport()
        #expect(model.pdfImport == nil && model.libraryItems.isEmpty)
    }

    @Test func aBadFileFailsWithItsSentence() async throws {
        let model = try await make()
        await model.importPDF(data: Data("nope".utf8), fileName: "nope.pdf")
        #expect(model.pdfImport?.stage == .failed("That PDF couldn't be opened."))
        model.cancelPDFImport()
        #expect(model.pdfImport == nil)
    }

    @Test func aURLIsRoutedByItsExtension() async throws {
        let model = try await make()
        let dir = try temporaryDirectory()
        let pdf = dir.appendingPathComponent("craigh.pdf")
        try TestFixtures.importPDF("craigh-na-dun-final-sc").write(to: pdf)
        await model.importFile(at: pdf)
        #expect(model.pdfImport?.stage == .found)
        model.cancelPDFImport()
        let bundle = dir.appendingPathComponent("craigh.graphghan")
        try TestFixtures.bundle("craigh-na-dun").write(to: bundle)
        await model.importFile(at: bundle)
        #expect(model.libraryItems.contains { $0.source == .local && $0.slug == "craigh-na-dun" })
    }

    @Test func cancelIsIgnoredWhileASaveRuns() async throws {
        let model = try await make()
        await model.importPDF(data: try TestFixtures.importPDF("craigh-na-dun-final-sc"), fileName: "craigh.pdf")
        let state = try #require(model.pdfImport)
        state.stage = .saving  // what the button does before it starts the save
        model.cancelPDFImport()
        #expect(model.pdfImport != nil)
        await model.addImportedPDF()
        #expect(model.pdfImport == nil && model.libraryItems.contains { $0.slug == "craigh-na-dun-blanket" })
    }

    // MARK: written rows (PR 2)

    @Test func writtenRowsShowProgressThenTheChart() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.twoRowDocument(), delayPerRow: .milliseconds(50)))
        let pdf = try #require(PDFTestDocuments.plain(text: PDFImportTests.twoRowText))
        let task = Task { await model.importPDF(data: pdf, fileName: "two-rows.pdf") }
        try await Task.sleep(for: .milliseconds(70))
        if case .readingRows(_, let of, _) = model.pdfImport?.stage { #expect(of == 2) } else { Issue.record("expected readingRows, got \(String(describing: model.pdfImport?.stage))") }
        await task.value
        #expect(model.pdfImport?.stage == .found && model.pdfImport?.reading?.source == .writtenRows(count: 2, gaugePrinted: false))
        #expect(PDFImportSheet.minutes(for: 77) == 4 && PDFImportSheet.minutes(for: 2) == 1)
    }

    @Test func cancelDuringTheReadClosesTheSheetAndWritesNothing() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.twoRowDocument(), delayPerRow: .seconds(1)))
        let pdf = try #require(PDFTestDocuments.plain(text: PDFImportTests.twoRowText))
        let task = Task { await model.importPDF(data: pdf, fileName: "two-rows.pdf") }
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.pdfImport?.isCancellable == true)
        model.cancelPDFImport()
        await task.value
        #expect(model.pdfImport == nil && model.libraryItems.isEmpty)
    }

    @Test func withoutAModelTheSheetSaysSo() async throws {
        let model = try await make(rowReader: nil, modelUnavailable: "on-device model unavailable")
        let pdf = try #require(PDFTestDocuments.plain(text: PDFImportTests.twoRowText))
        await model.importPDF(data: pdf, fileName: "two-rows.pdf")
        #expect(model.pdfImport?.stage == .failed(PDFImportError.needsAppleIntelligence.message))
        #expect(model.pdfImport?.isCancellable == false)
    }
}

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
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.twoRowDocument(), delayPerRow: .milliseconds(300)))
        let pdf = try #require(PDFTestDocuments.plain(text: PDFImportTests.twoRowText))
        let task = Task { await model.importPDF(data: pdf, fileName: "two-rows.pdf") }
        let stage = try #require(await Self.readingRows(of: model))
        if case .readingRows(_, let of, _) = stage { #expect(of == 2) } else { Issue.record("expected readingRows, got \(stage)") }
        await task.value
        #expect(model.pdfImport?.stage == .found && model.pdfImport?.reading?.source == .writtenRows(count: 2, gaugePrinted: false))
        #expect(PDFImportSheet.minutes(for: 77) == 4 && PDFImportSheet.minutes(for: 2) == 1)
    }

    @Test func cancelDuringTheReadClosesTheSheetAndWritesNothing() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.twoRowDocument(), delayPerRow: .seconds(1)))
        let pdf = try #require(PDFTestDocuments.plain(text: PDFImportTests.twoRowText))
        let task = Task { await model.importPDF(data: pdf, fileName: "two-rows.pdf") }
        _ = try #require(await Self.readingRows(of: model))
        #expect(model.pdfImport?.isCancellable == true)
        model.cancelPDFImport()
        await task.value
        #expect(model.pdfImport == nil && model.libraryItems.isEmpty)
    }

    /// The sheet's rows state once the model has reported the row count, or nil after two seconds.
    static func readingRows(of model: AppModel) async -> PDFImportState.Stage? {
        for _ in 0..<200 {
            if case .readingRows = model.pdfImport?.stage { return model.pdfImport?.stage }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    @Test func withoutAModelTheSheetSaysSo() async throws {
        let model = try await make(rowReader: nil, modelUnavailable: "on-device model unavailable")
        let pdf = try #require(PDFTestDocuments.plain(text: PDFImportTests.twoRowText))
        await model.importPDF(data: pdf, fileName: "two-rows.pdf")
        #expect(model.pdfImport?.stage == .failed(PDFImportError.needsAppleIntelligence.message))
        #expect(model.pdfImport?.isCancellable == false)
    }

    // MARK: a chart in the PDF (PR 3)

    @Test func aChartIsFoundThenTheCheckRunsUnderneathAndFinishes() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(wrongRow: 3), delayPerRow: .milliseconds(20)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let state = try #require(model.pdfImport)
        #expect(state.stage == .found && state.reading?.source == .grid(page: 1, rowsToCheck: 15))
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        let done = try #require(await Self.checkState(of: model) { if case .done = $0 { return true }; return false })
        guard case .done(let record) = done else { return }
        #expect(record.check == .finished && record.rowsDisagree == [3])
        #expect(record.sentence == "Row 3 disagrees with the chart. The chart is as drawn; check those rows against the PDF.")
        await model.addImportedPDF()
        #expect(model.pdfImport == nil)
        #expect(model.libraryItems.contains { $0.source == .local && $0.slug == "drawn" })
        let manifest = try await model.manifest(for: "drawn", path: nil)
        let chart = try await model.charts.chart(id: manifest.charts[0].id)
        #expect(ImportRecord(json: chart.document.ext) == record)
    }

    @Test func skipStopsTheCheckAndAddSavesWhatWasChecked() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(300)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        model.skipPDFCheck()
        let done = try #require(await Self.checkState(of: model) { if case .done = $0 { return true }; return false })
        guard case .done(let record) = done else { return }
        #expect(record.check == .stopped && record.rowsTotal == 15 && record.rowsChecked < 15)
        #expect(record.sentence?.hasPrefix("Written rows checked up to row \(record.rowsChecked); \(record.rowsChecked + 1)–15 not checked.") == true)
    }

    @Test func addingBeforeTheCheckEndsSavesItAsStopped() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(300)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        await model.addImportedPDF()
        let manifest = try await model.manifest(for: "drawn", path: nil)
        let chart = try await model.charts.chart(id: manifest.charts[0].id)
        let record = try #require(ImportRecord(json: chart.document.ext))
        #expect(record.check == .stopped && record.rowsTotal == 15)
    }

    @Test func withoutAModelTheChartIsSavedUnchecked() async throws {
        let model = try await make(rowReader: nil, modelUnavailable: "needs iOS 26")
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let done = try #require(await Self.checkState(of: model) { if case .done = $0 { return true }; return false })
        guard case .done(let record) = done else { return }
        #expect(record.check == .unavailable && record.sentence == "Written rows not checked on this iPhone.")
        await model.addImportedPDF()
        #expect(model.libraryItems.contains { $0.slug == "drawn" })
    }

    @Test func cancelDuringTheCheckWritesNothing() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(300)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        model.cancelPDFImport()
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.pdfImport == nil && model.libraryItems.isEmpty)
    }

    /// The sheet's check stage once `test` accepts it, or nil after three seconds.
    static func checkState(of model: AppModel, _ test: (PDFImportState.CheckStage) -> Bool) async -> PDFImportState.CheckStage? {
        for _ in 0..<300 {
            if let s = model.pdfImport?.check, test(s) { return s }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }
}

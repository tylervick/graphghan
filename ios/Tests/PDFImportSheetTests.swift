import Foundation
import SwiftUI
import Testing
import GraphghanCore
import ProseReaderKit
@testable import Graphghan

/// The import sheet's states, driven through `AppModel` the way the app drives them (phone import
/// spec §5.2), without a screen.
/// Serialized: `IdleTimer` is one counter for the whole app, so two of these running at once
/// would see each other's holds and the screen-awake tests would race.
@MainActor
@Suite(.serialized) struct PDFImportSheetTests {
    func make(rowReader: (any RowReading)? = nil, modelUnavailable: String? = nil) async throws -> AppModel {
        let container = try makeInMemoryContainer()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: StubClient())
        return AppModel(context: container.mainContext, patterns: patterns,
                        charts: ChartLibrary(directory: try temporaryDirectory()), rows: RowsLibrary(directory: try temporaryDirectory()),
                        localPatterns: LocalPatternStore(directory: try temporaryDirectory()),
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

    // MARK: the review list (#206)

    /// `OutlineReviewSection`'s rows outside the sheet's `ScrollView` -- `ImageRenderer` cannot
    /// flatten one, the way `project-pieces-rows` snapshots `PieceRow` outside its `List`.
    /// It pins layout and labels only: text fields and steppers render as placeholders (#67).
    @Test @MainActor func reviewRowsSnapshot() throws {
        let draft = OutlineDraftTests.draft()
        let view = VStack(alignment: .leading, spacing: 14) {
            OutlineReviewSection(draft: .constant(draft), leftOut: [
                "text after R 2 (page 7)", "text after R 104 (page 10)", "text after R 15 (page 12)",
            ])
        }
        .padding(16)
        .background(Color.ground.weave())
        #expect(try Snapshots.assert(view, named: "pdf-import-review-rows", size: CGSize(width: 390, height: 760)))
    }

    /// The bag's two charts and their rows, read with no model (no check runs): a pieced reading.
    func readBag(_ model: AppModel) async throws -> PDFImportState {
        let rows = "Front\n" + PDFTestDocuments.colourRows + "\nBack\n" + PDFTestDocuments.colourRows
        await model.importPDF(data: try #require(PDFTestDocuments.twoCharts(rowsText: rows, distinctBack: true)), fileName: "bag.pdf")
        return try #require(model.pdfImport)
    }

    /// The review list names every piece and what was left out; #209's "One chart was imported;
    /// the other was left out" above it would contradict it.
    @Test func aPiecedReadingShowsNoOneChartLeftOutSentence() async throws {
        let state = try await readBag(try await make(rowReader: nil, modelUnavailable: "needs iOS 26"))
        #expect(state.draft != nil && state.reading?.contents?.sentence != nil)
        #expect(state.leftOutSentence == nil)
        // Without a review list the sentence is the only word on what was left out.
        state.draft = nil
        #expect(state.leftOutSentence == state.reading?.contents?.sentence)
    }

    /// Nothing to add once the maker has removed every piece.
    @Test func addIsDisabledWithNoPieces() async throws {
        let state = try await readBag(try await make(rowReader: nil, modelUnavailable: "needs iOS 26"))
        #expect(state.canAdd)
        for piece in state.draft?.pieces ?? [] { state.draft?.remove(piece.id) }
        #expect(!state.canAdd)
        state.draft = nil  // a one-chart reading has no list and always adds
        #expect(state.canAdd)
    }

    /// A chart piece's check line shows what the one-chart sheet shows for the same record: a
    /// problem as a copyable report (#176), a busy model with its battery note and "Why?".
    @Test(arguments: [
        ImportRecord(grid: true, check: .finished, rowsChecked: 0, rowsTotal: 15, rowsDisagree: [], gaugePrinted: false, problem: ImportRecord.modelBusy),
        ImportRecord(grid: true, check: .finished, rowsChecked: 0, rowsTotal: 15, rowsDisagree: [], gaugePrinted: false, problem: "the rows are 12 stitches wide, the chart 15"),
        ImportRecord(grid: true, check: .finished, rowsChecked: 15, rowsTotal: 15, rowsDisagree: [], gaugePrinted: false, problem: nil),
    ])
    func aPieceCheckShowsWhatTheOneChartSheetShows(record: ImportRecord) async throws {
        let state = try await readBag(try await make(rowReader: nil, modelUnavailable: "needs iOS 26"))
        state.onBatteryAtCheck = true
        let front = try #require(state.draft?.pieces.first { $0.isChart })
        let chart = try #require(state.chartIndex(ofPiece: front.id))
        state.pieceChecks[chart] = .done(record)
        state.check = .done(record)  // the one-chart path, given the same record
        let oneChart = try #require(state.checkShown)
        #expect(state.pieceChecksShown[front.id] == oneChart)
        let busy = record.problem == ImportRecord.modelBusy
        #expect(oneChart.copyable == (record.problem != nil) && oneChart.askWhy == busy && oneChart.batteryNote == busy)
        #expect(oneChart.sentence == PDFImportState.checkSentence(record))
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

    /// Review Focus 3, the checking half: Skip during the second chart piece's check leaves the
    /// first piece's finished record and settles the second as stopped, before Skip returns, and
    /// the cancelled task writes nothing over it afterwards. The saving half is Task 8's.
    @Test func skippingTheSecondPiecesCheckKeepsTheFirst() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(60)))
        let rows = "Front\n" + PDFTestDocuments.colourRows + "\nBack\n" + PDFTestDocuments.colourRows
        // A Back one cell different from the Front: two charts, each saved with its own record.
        await model.importPDF(data: try #require(PDFTestDocuments.twoCharts(rowsText: rows, distinctBack: true)), fileName: "bag.pdf")
        let state = try #require(model.pdfImport)
        #expect(state.check == .none && state.pieceCheckPlan.map(\.chart) == [0, 1])
        var secondRunning = false
        for _ in 0..<500 {
            if case .running = state.pieceChecks[1] { secondRunning = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(secondRunning)
        #expect(state.pieceChecking?.line.hasPrefix("Checking Back: written row ") == true)
        model.skipPDFCheck()
        func expectSettled() throws {
            guard case .done(let first) = state.pieceChecks[0], case .done(let second) = state.pieceChecks[1] else {
                Issue.record("not settled: \(state.pieceChecks)"); return
            }
            #expect(first.check == .finished && first.rowsChecked == 15 && first.rowsDisagree.isEmpty)
            #expect(second.check == .stopped && second.rowsTotal == 15 && second.rowsChecked < 15)
            #expect(state.pieceChecks.keys.sorted() == [0, 1])
        }
        try expectSettled()
        try await Task.sleep(for: .milliseconds(300))
        try expectSettled()
        #expect(state.pieceChecking == nil)
        let lines = state.pieceCheckLines
        #expect(lines.count == 2 && lines.values.contains("Written rows agree with the chart."))
        #expect(lines.values.contains { $0.hasPrefix("Written rows checked up to row ") })
        // The cancelled task has ended and let the screen go; nothing of it reaches the next test.
        await state.checkTask?.value
        try expectSettled()
        // Add saves both pieces as one pattern, each chart with its own record.
        await model.addImportedPDF()
        #expect(model.pdfImport == nil)
        #expect(model.libraryItems.contains { $0.source == .local && $0.slug == "bag" })
        let manifest = try await model.manifest(for: "bag", path: nil)
        #expect(manifest.schema == 2)
        let pieces = try #require(manifest.pieces)
        let front = try await model.charts.chart(id: try #require(pieces[0].chart))
        let back = try await model.charts.chart(id: try #require(pieces[1].chart))
        #expect(ImportRecord(json: front.document.ext)?.check == .finished)
        #expect(ImportRecord(json: back.document.ext)?.check == .stopped)
    }

    /// Skip while the first piece is read: the second piece's turn never comes, so it is settled
    /// as stopped at row 0 and the reader is never asked for it.
    @Test func skippingTheFirstPiecesCheckNeverAsksForTheSecond() async throws {
        let asked = Asked()
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(60), asked: asked))
        let rows = "Front\n" + PDFTestDocuments.colourRows + "\nBack\n" + PDFTestDocuments.colourRows
        await model.importPDF(data: try #require(PDFTestDocuments.twoCharts(rowsText: rows)), fileName: "bag.pdf")
        let state = try #require(model.pdfImport)
        var firstRunning = false
        for _ in 0..<500 {
            if case .running = state.pieceChecks[0] { firstRunning = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(firstRunning)
        model.skipPDFCheck()
        await state.checkTask?.value
        guard case .done(let second) = state.pieceChecks[1] else { Issue.record("not settled: \(state.pieceChecks)"); return }
        #expect(second.check == .stopped && second.rowsChecked == 0 && second.rowsTotal == 15)
        #expect(await asked.sections.count == 1)
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

    /// A busy model on the sheet (#176): the maker sees one sentence to act on, "Why?" is offered
    /// so the three probes can be run on the phone that refused, and the chart still adds.
    @Test func aBusyModelLeavesASentenceAndTheChartStillAdds() async throws {
        let doc = PDFImportTests.refusedByABusyModel(PDFImportTests.chartDocument())
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: doc, delayPerRow: .zero))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let done = try #require(await Self.checkState(of: model) { if case .done = $0 { return true }; return false })
        guard case .done(let record) = done else { return }
        #expect(record.problem == ImportRecord.modelBusy)
        #expect(record.sentence == "The on-device model is busy; try the check again in a minute.")
        let state = try #require(model.pdfImport)
        #expect(state.stage == .found)
        #expect(!state.appStateAtCheck.isEmpty)  // what the scene was doing, for the probe's report
        #expect(state.probe == nil && !state.probing)  // asked only when "Why?" is tapped
        await model.addImportedPDF()
        #expect(model.libraryItems.contains { $0.slug == "drawn" })
    }

    /// Without a reader to ask, "Why?" still answers rather than doing nothing.
    @Test func theProbeSaysWhyWhenThereIsNoReaderToAsk() async throws {
        let model = try await make(rowReader: nil, modelUnavailable: "needs iOS 26")
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        await model.runModelProbe()
        let probe = try #require(model.pdfImport?.probe)
        #expect(probe.steps.count == 1 && probe.steps[0].ok == false && probe.steps[0].detail == "needs iOS 26")
        #expect(probe.steps[0].kind == .availability)
        #expect(probe.finding == "There is no model to ask on this iPhone, so nothing below was run.")
        #expect(probe.text.contains("the app was"))
        await Self.settle(model.pdfImport)
    }

    /// The screen is held awake while the check runs and let go when it ends, so a 77-row read
    /// does not stop at the lock screen (#176).
    /// Reads this import's own holds, not `IdleTimer.count`, which other suites' imports running
    /// in parallel move too (#227).
    @Test func theScreenIsHeldAwakeOnlyWhileTheCheckRuns() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(100)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let state = try #require(model.pdfImport)
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        #expect(state.screenHolds == 1)
        await Self.settle(state)
        #expect(state.screenHolds == 0)
    }

    /// The measurement asks the model for minutes and holds the screen awake, so neither Cancel
    /// nor "Add to library" may leave it running behind a closed sheet (#176, CodeRabbit review).
    @Test func cancelStopsTheLimitMeasurement() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .zero))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let state = try #require(model.pdfImport)
        let running = Task { try? await Task.sleep(for: .seconds(60)) }
        state.measureTask = Task { _ = await running.value }
        model.cancelPDFImport()
        #expect(state.measureTask?.isCancelled == true)
        running.cancel()
    }

    /// Without a model there is nothing to measure, and the button is never offered; asking for
    /// it anyway does nothing rather than hanging on a hold it never releases.
    @Test func theMeasurementDoesNothingWhereThereIsNoModel() async throws {
        let model = try await make(rowReader: nil, modelUnavailable: "needs iOS 26")
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        // The check's own hold outlives `importPDF`, which does not await it; let it land first.
        await Self.settle(model.pdfImport)
        await model.measureModelLimit()
        #expect(model.pdfImport?.limits == nil && model.pdfImport?.measuring == false)
        #expect(model.pdfImport?.screenHolds == 0)
    }

    /// Sharing a second PDF while a check is still reading must stop the first one: a session
    /// answers one request at a time, and two readers asking at once is a documented way to be
    /// told the model is rate limited (#176).
    @Test func aSecondImportStopsTheFirstOnesCheck() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(300)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "first.pdf")
        let first = try #require(model.pdfImport)
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "second.pdf")
        #expect(first.checkTask?.isCancelled == true)
        #expect(model.pdfImport !== first && model.pdfImport?.fileName == "second.pdf")
        let second = model.pdfImport
        model.cancelPDFImport()
        await Self.settle(first)
        await Self.settle(second)
    }

    @Test func cancelDuringTheCheckWritesNothing() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.chartDocument(), delayPerRow: .milliseconds(300)))
        await model.importPDF(data: try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        _ = try #require(await Self.checkState(of: model) { if case .running = $0 { return true }; return false })
        let state = model.pdfImport
        model.cancelPDFImport()
        await Self.settle(state)
        #expect(model.pdfImport == nil && model.libraryItems.isEmpty)
    }

    /// Waits for everything an import started (the read, the check, the measurement) to end. The
    /// check holds the screen awake from its own task, which `importPDF` does not await, so a test
    /// that returns while one runs hands its hold to the next test (#227).
    static func settle(_ state: PDFImportState?) async {
        await state?.task?.value
        await state?.checkTask?.value
        await state?.measureTask?.value
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

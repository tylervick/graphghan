import Foundation
import PDFKit
import Testing
import UIKit
import CoreGraphics
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
        /// Like `ProseReader`, a cancelled read returns the rows read so far.
        func read(pages: [String], progress: (@Sendable (ReaderProgress) -> Void)?) async -> ProseDocument {
            let total = RowText.rowCount(in: pages)
            for i in 0..<total {
                if Task.isCancelled {
                    var partial = document
                    partial.written_rows = Array((document.written_rows ?? []).prefix(i))
                    return partial
                }
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

    /// What the reader hands back when the model refused every row it was asked (#176). The row
    /// numbers are gone because `ProseReader` records a failure as row 0, which is why the field
    /// report on #176 reads "row 0" for all 77 of them.
    static func refusedByABusyModel(_ doc: ProseDocument) -> ProseDocument {
        var doc = doc
        doc.written_rows = (doc.written_rows ?? []).map {
            .init(row: 0, page: $0.page, text: $0.text, runs: [], total: nil, error: ReaderFailure.modelBusy)
        }
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

    @Test func aRowTheReaderCouldNotReadIsNamedNotDropped() async throws {
        // No stated height: dropping the unread last row would infer a one-row chart and pass it.
        var doc = Self.twoRowDocument()
        doc.chart = nil
        doc.written_rows?[1].runs = []
        doc.written_rows?[1].error = "no colour named"
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        await #expect(throws: PDFImportError.rowsDoNotAssemble(["row 2: no colour named"])) { try await importer.read(pdf, fileName: "x.pdf") }
    }

    /// A model that refused every row is a state that passes, not a pattern the app cannot read:
    /// the maker gets one sentence to act on rather than the raw `GenerationError` text (#176).
    @Test func aRowsOnlyReadTheModelRefusedForBeingBusyGetsASentenceToActOn() async throws {
        let doc = Self.refusedByABusyModel(Self.twoRowDocument())
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        await #expect(throws: PDFImportError.modelBusy) { try await importer.read(pdf, fileName: "x.pdf") }
        #expect(PDFImportError.modelBusy.message == "The on-device model is busy; try the check again in a minute.")
        #expect(!PDFImportError.modelBusy.message.contains("row 0"))
    }

    @Test func aRowLostToSomethingOtherThanABusyModelIsStillReportedAsItStands() async throws {
        var doc = Self.refusedByABusyModel(Self.twoRowDocument())
        doc.written_rows?[1].error = "no colour named"
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        await #expect(throws: PDFImportError.rowsDoNotAssemble(["row 0: the on-device model is busy", "row 0: no colour named"])) {
            try await importer.read(pdf, fileName: "x.pdf")
        }
    }

    @Test func aChartBiggerThanTheAppWorksIsRefusedBeforeAnyGridIsBuilt() async throws {
        var doc = Self.twoRowDocument()
        doc.chart = .init(width: 3, height: OwnPDFReader.maximumSide + 1)
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        await #expect(throws: PDFImportError.badRow(.tooLarge(width: 3, height: OwnPDFReader.maximumSide + 1))) { try await importer.read(pdf, fileName: "x.pdf") }
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

    // MARK: a chart in the PDF (PR 3)

    /// The synthetic chart the tests draw: 20 × 15, four colours, the first three columns one
    /// colour (where lines hide) and the last two rows another, as the Python fixtures do.
    nonisolated static let chartWidth = 20, chartHeight = 15
    nonisolated static let chartHexes = ["#f2e8d5", "#2b2f33", "#1e4d3a", "#d9a21b"]
    nonisolated static func chartCell(x: Int, y: Int) -> Int {  // y from the top
        if x < 3 { return 1 }
        if y >= chartHeight - 2 { return 3 }
        return (x * 7 + y * 3) % 4
    }

    /// The written rows for that chart, numbered from the bottom, odd rows written right to left.
    static func chartDocument(wrongRow: Int? = nil) -> ProseDocument {
        var doc = ProseDocument()
        doc.pattern = ["title": "Drawn Chart"]
        doc.palette = chartHexes.enumerated().map { .init(code: ["A", "B", "C", "D"][$0.offset], name: "", hex: $0.element) }
        doc.chart = .init(width: chartWidth, height: chartHeight)
        var rows: [ProseDocument.Row] = []
        for r in 1...chartHeight {
            let y = chartHeight - r
            var cells = (0..<chartWidth).map { chartCell(x: $0, y: y) }
            if r == wrongRow { cells[5] = (cells[5] + 1) % 4 }
            if r % 2 == 1 { cells.reverse() }
            var runs: [[ProseDocument.RunValue]] = []
            for c in cells {
                let code = ["A", "B", "C", "D"][c]
                if let last = runs.last, case .code(let lc) = last[0], lc == code, case .count(let n) = last[1] { runs[runs.count - 1] = [.code(code), .count(n + 1)] }
                else { runs.append([.code(code), .count(1)]) }
            }
            rows.append(.init(row: r, page: 2, text: "Row \(r)", runs: runs))
        }
        doc.written_rows = rows
        return doc
    }

    @Test func aChartPageBecomesTheChartBeforeAnyRowIsRead() async throws {
        let base = try await make()
        let importer = base.importer(rowReader: StubRowReader(document: Self.chartDocument(), delayPerRow: .zero))
        let pdf = try #require(PDFTestDocuments.chart(rows: true))
        let reading = try await importer.read(pdf, fileName: "drawn.pdf")
        #expect(reading.width == Self.chartWidth && reading.height == Self.chartHeight && reading.colours == 4)
        #expect(reading.source == .grid(page: 1, rowsToCheck: Self.chartHeight))
        #expect(reading.bundle.manifest.id == "drawn" && reading.bundle.manifest.title == "drawn")  // no key page read yet: the file's stem
        // The PDF's colours come back through a colour-space conversion a few steps lighter
        // (#2b2f33 reads #393e42), so each read colour is matched to the nearest drawn one, which
        // must pair them one to one; then every cell must be the drawn cell.
        let chart = reading.bundle.charts[0].chart
        func dist(_ a: String, _ b: String) -> Int {
            let p = GridColours.rgb(a)!, q = GridColours.rgb(b)!
            return abs(Int(p.0) - Int(q.0)) + abs(Int(p.1) - Int(q.1)) + abs(Int(p.2) - Int(q.2))
        }
        let nearest = chart.palette.map { entry in Self.chartHexes.indices.min { dist(entry.hex, Self.chartHexes[$0]) < dist(entry.hex, Self.chartHexes[$1]) }! }
        #expect(Set(nearest).count == 4, "palette \(chart.palette.map(\.hex)) pairs as \(nearest)")
        var wrong: [String] = []
        for y in 0..<Self.chartHeight { for x in 0..<Self.chartWidth {
            let got = nearest[Int(chart.cells[y * Self.chartWidth + x])], want = Self.chartCell(x: x, y: y)
            if got != want { wrong.append("(\(x),\(y)) \(got) not \(want)") }
        } }
        #expect(wrong.isEmpty, "\(wrong.count) cells: \(wrong.prefix(6))")
        #expect(ImportRecord(json: chart.document.ext)?.check == .noRows && ImportRecord(json: chart.document.ext)?.grid == true)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: base.chartsDir.path)) ?? []).isEmpty)
    }

    @Test func theCheckFinishesCleanOrNamesTheRow() async throws {
        let pdf = try #require(PDFTestDocuments.chart(rows: true))
        let clean = try await make().importer(rowReader: StubRowReader(document: Self.chartDocument(), delayPerRow: .zero))
        let reading = try await clean.read(pdf, fileName: "drawn.pdf")
        let seen = Progress()
        let record = await clean.check(reading) { p in Task { await seen.add(p) } }
        #expect(record == ImportRecord(grid: true, check: .finished, rowsChecked: 15, rowsTotal: 15, rowsDisagree: [], gaugePrinted: false, problem: nil))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await seen.items.contains(.checking(done: 15, of: 15)))
        let wrong = try await make().importer(rowReader: StubRowReader(document: Self.chartDocument(wrongRow: 5), delayPerRow: .zero))
        let record2 = await wrong.check(try await wrong.read(pdf, fileName: "drawn.pdf"), progress: nil)
        #expect(record2.check == .finished && record2.rowsDisagree == [5] && record2.problem == nil)
    }

    @Test func aRowTheReaderCouldNotReadMakesTheCheckIncomparableNotSilentlyClean() async throws {
        var doc = Self.chartDocument()
        doc.written_rows?[4].runs = []
        doc.written_rows?[4].error = "no colour named"
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let record = await importer.check(try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf"), progress: nil)
        #expect(record.check == .finished && record.problem == "row 5: no colour named" && record.rowsDisagree.isEmpty)
        #expect(record.sentence == "Written rows could not be compared with the chart: row 5: no colour named.")
    }

    /// The same on the check: the chart from the grid is still there and still saveable, and the
    /// record carries the short reason rather than 15 copies of `GenerationError` (#176).
    @Test func aCheckTheModelRefusedForBeingBusySaysSoAndKeepsTheChart() async throws {
        let doc = Self.refusedByABusyModel(Self.chartDocument())
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let reading = try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let record = await importer.check(reading, progress: nil)
        #expect(record.check == .finished && record.rowsTotal == Self.chartHeight && record.rowsChecked == 0)
        #expect(record.problem == ImportRecord.modelBusy)
        #expect(record.sentence == "The on-device model is busy; try the check again in a minute.")
        #expect(record.rowsDisagree.isEmpty)
        // The chart the grid read is untouched: "Add to library" still saves it.
        #expect(reading.width == Self.chartWidth && reading.height == Self.chartHeight)
    }

    /// One row lost to a busy model among rows that read is still "try again in a minute": that
    /// is the whole of what a maker should do about it, and the record's `rows_checked` still
    /// says how far the check got. A row lost to anything else keeps its own reason.
    @Test func oneRowLostToABusyModelAmongGoodOnesStillAsksForAnotherTry() async throws {
        var doc = Self.chartDocument()
        doc.written_rows?[4].runs = []
        doc.written_rows?[4].error = ReaderFailure.modelBusy
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let record = await importer.check(try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf"), progress: nil)
        #expect(record.problem == ImportRecord.modelBusy && record.rowsChecked == Self.chartHeight)
        #expect(record.sentence == "The on-device model is busy; 15 of 15 written rows were checked. Try the check again in a minute.")
        doc.written_rows?[6].runs = []
        doc.written_rows?[6].error = "no colour named"
        let mixed = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let second = await mixed.check(try await mixed.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf"), progress: nil)
        #expect(second.problem == "row 5: the on-device model is busy; row 7: no colour named")
    }

    /// The reader writes these words and the record matches them across a package boundary, so
    /// they have to stay the same words.
    @Test func theReadersWordsForABusyModelAreTheOnesTheRecordMatches() {
        #expect(ImportRecord.modelBusy == ReaderFailure.modelBusy)
    }

    @Test func withoutAModelTheCheckIsUnavailableAndWithoutRowsThereIsNone() async throws {
        let none = try await make().importer(rowReader: nil, modelUnavailable: "needs iOS 26")
        let reading = try await none.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        #expect(reading.source == .grid(page: 1, rowsToCheck: Self.chartHeight))
        #expect(await none.check(reading, progress: nil).check == .unavailable)
        let noRows = try await none.read(try #require(PDFTestDocuments.chart(rows: false)), fileName: "drawn.pdf")
        #expect(noRows.source == .grid(page: 1, rowsToCheck: 0))
        #expect(await none.check(noRows, progress: nil).check == .noRows)
    }

    @Test func aCancelledCheckIsStoppedAtTheRowsRead() async throws {
        let importer = try await make().importer(rowReader: StubRowReader(document: Self.chartDocument(), delayPerRow: .milliseconds(200)))
        let reading = try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let task = Task { await importer.check(reading, progress: nil) }
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()
        let record = await task.value
        #expect(record.check == .stopped && record.rowsTotal == 15 && record.rowsChecked < 15 && record.problem == nil)
    }

    @Test func savingWithARecordWritesItIntoTheChart() async throws {
        let base = try await make()
        let importer = base.importer()
        let reading = try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf")
        let record = ImportRecord(grid: true, check: .stopped, rowsChecked: 4, rowsTotal: 15, rowsDisagree: [2], gaugePrinted: false, problem: nil)
        let manifest = try await importer.save(reading, record: record)
        let stored = try await base.charts.chart(id: manifest.charts[0].id)
        #expect(ImportRecord(json: stored.document.ext) == record && stored.id == reading.bundle.charts[0].chart.id)
    }

    @Test func theRenderScaleFitsTheBudget() {
        #expect(PageRenderer.scale(for: CGRect(x: 0, y: 0, width: 612, height: 792)) == 4)
        #expect(PageRenderer.scale(for: CGRect(x: 0, y: 0, width: 3000, height: 3000)) == 2)
        #expect(PageRenderer.scale(for: CGRect(x: 0, y: 0, width: 7000, height: 7000)) == nil)
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

    /// A page with the synthetic chart drawn at 12 pt cells (48 px at 4×), grid lines 0.5 pt with
    /// every fifth bold, numbers above and beside; with `rows`, a second page of written rows.
    static func chart(rows: Bool) -> Data? {
        let cell: CGFloat = 12, ox: CGFloat = 60, oy: CGFloat = 80
        let w = PDFImportTests.chartWidth, h = PDFImportTests.chartHeight
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cg = ctx.cgContext
            for y in 0..<h { for x in 0..<w {
                let rgb = GridColours.rgb(PDFImportTests.chartHexes[PDFImportTests.chartCell(x: x, y: y)])!
                cg.setFillColor(CGColor(red: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255, blue: CGFloat(rgb.2) / 255, alpha: 1))
                cg.fill(CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell, width: cell, height: cell))
            } }
            for x in 0...w {
                let bold = (w - x) % 5 == 0
                cg.setStrokeColor(bold ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 0.55, alpha: 1))
                cg.setLineWidth(bold ? 1 : 0.5)
                cg.move(to: CGPoint(x: ox + CGFloat(x) * cell, y: oy)); cg.addLine(to: CGPoint(x: ox + CGFloat(x) * cell, y: oy + CGFloat(h) * cell)); cg.strokePath()
            }
            for y in 0...h {
                let bold = (h - y) % 5 == 0
                cg.setStrokeColor(bold ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 0.55, alpha: 1))
                cg.setLineWidth(bold ? 1 : 0.5)
                cg.move(to: CGPoint(x: ox, y: oy + CGFloat(y) * cell)); cg.addLine(to: CGPoint(x: ox + CGFloat(w) * cell, y: oy + CGFloat(y) * cell)); cg.strokePath()
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 6)]
            for x in 0..<w { ("\(w - x)" as NSString).draw(at: CGPoint(x: ox + CGFloat(x) * cell + 2, y: oy - 9), withAttributes: attrs) }
            for y in 0..<h { ("\(h - y)" as NSString).draw(at: CGPoint(x: ox - 14, y: oy + CGFloat(y) * cell + 3), withAttributes: attrs) }
            if rows {
                ctx.beginPage()
                let text = (1...h).map { "Row \($0): sc across in the colours shown" }.joined(separator: "\n")
                (text as NSString).draw(in: bounds.insetBy(dx: 36, dy: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
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

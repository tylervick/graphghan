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
        let rows: RowsLibrary
        let chartsDir: URL
        let localDir: URL
        let rowsDir: URL
        func importer(rowReader: (any RowReading)? = nil, modelUnavailable: String? = nil, pieceReader: any PieceReading = FoundOutline()) -> PDFImporter {
            PDFImporter(charts: charts, local: local, rows: rows, rowReader: rowReader, modelUnavailable: modelUnavailable, pieceReader: pieceReader)
        }
    }

    func make() async throws -> Base {
        let chartsDir = try temporaryDirectory()
        let localDir = try temporaryDirectory()
        let rowsDir = try temporaryDirectory()
        return Base(charts: ChartLibrary(directory: chartsDir), local: LocalPatternStore(directory: localDir), rows: RowsLibrary(directory: rowsDir),
                    chartsDir: chartsDir, localDir: localDir, rowsDir: rowsDir)
    }

    /// A canned answer standing in for the model (phone import spec §9).
    struct StubRowReader: RowReading {
        let document: ProseDocument
        let delayPerRow: Duration
        var asked: Asked? = nil
        /// Like `ProseReader`, a cancelled read returns the rows read so far, and a section limits the rows to it.
        func read(pages: [String], section: RowSection?, progress: (@Sendable (ReaderProgress) -> Void)?) async -> ProseDocument {
            await asked?.record(section)
            let total = section?.rows ?? RowText.rowCount(in: pages)
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
        // One sentence now, a few rows named and the rest counted (#179).
        await #expect(throws: PDFImportError.rowsDoNotAssemble(["row 0: the on-device model is busy; row 0: no colour named"])) {
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

    // MARK: a PDF of several pieces (pieces spec §7.1, #206)

    @Test func aPageWithTwoChartsIsReadAsPieces() async throws {
        let rows = "Front\n" + PDFTestDocuments.colourRows + "\nBack\n" + PDFTestDocuments.colourRows
        let reading = try await make().importer().read(try #require(PDFTestDocuments.twoCharts(rowsText: rows)), fileName: "bag.pdf")
        let pieced = try #require(reading.pieced)
        #expect(pieced.charts.count == 2 && pieced.charts.map(\.found.page) == [1, 1] && pieced.charts[0].found.x0 < pieced.charts[1].found.x0)
        #expect(pieced.outline.pieces.map(\.title) == ["Front", "Back"])
        #expect(pieced.charts.allSatisfy { $0.draft.written?.count == 15 })
        #expect(pieced.charts.allSatisfy { $0.width == Self.chartWidth && $0.height == Self.chartHeight && $0.colours == 4 && !$0.preview.isEmpty })
        #expect(pieced.sections.count == 2)
        #expect(reading.pdf.count > 0)
    }

    /// Each chart piece is checked against the rows the outline paired it with, not against the
    /// first set as tall as it (pieces spec §7.2): the Front against the Front's, the Back the Back's.
    @Test func eachChartPieceIsCheckedAgainstItsOwnRows() async throws {
        let rows = "Front\n" + PDFTestDocuments.colourRows + "\nBack\n" + PDFTestDocuments.colourRows
        let asked = Asked()
        let importer = try await make().importer(rowReader: StubRowReader(document: Self.chartDocument(), delayPerRow: .zero, asked: asked))
        let reading = try await importer.read(try #require(PDFTestDocuments.twoCharts(rowsText: rows)), fileName: "bag.pdf")
        let pieced = try #require(reading.pieced)
        var records: [ImportRecord] = []
        for piece in pieced.outline.pieces {
            guard case .chart(let c) = piece.kind, let s = piece.pairedSection else { continue }
            records.append(await importer.check(chart: pieced.charts[c], section: pieced.sections[s], pageTexts: reading.pageTexts, progress: nil))
        }
        let sections = await asked.sections.compactMap { $0 }
        #expect(sections.count == 2 && sections.allSatisfy { $0.rows == 15 })
        #expect(sections == [pieced.sections[0], pieced.sections[1]])
        let first = try #require(sections.first?.blocks.first), second = try #require(sections.last?.blocks.first)
        // Both runs print the same words; the Front's comes first on the page, the Back's after it.
        #expect((first.page, first.index) < (second.page, second.index))
        #expect(first.text.hasPrefix("Row 1: 3 B") && second.text.hasPrefix("Row 1: 3 B"))
        #expect(records.allSatisfy { $0.check == .finished && $0.rowsTotal == 15 && $0.rowsDisagree.isEmpty && $0.problem == nil })
    }

    @Test func oneChartAndNothingElseIsReadAsToday() async throws {
        let pdf = try #require(PDFTestDocuments.chart(rows: true))
        let reading = try await make().importer().read(pdf, fileName: "x.pdf")
        #expect(reading.pieced == nil)
        #expect(reading.pdf == pdf)
    }

    // MARK: saving a pieced PDF (pieces spec §7.5, #206)

    static let strapPage = "Strap\nR 1: 6 sc [6]\nR 2 - R 10: ch 1, turn, 6 sc [6]"

    /// The bag: Front and Back side by side, their rows on page 2, a written Strap on page 3.
    /// With `assembly`, a fourth page of prose no piece uses: an assembly step.
    func readBag(_ importer: PDFImporter, assembly: Bool = false) async throws -> PDFImportReading {
        let rows = "Front\n" + PDFTestDocuments.colourRows + "\nBack\n" + PDFTestDocuments.colourRows
        let more = [Self.strapPage] + (assembly ? ["Sew the strap to the top corners of the bag, one end to each side panel."] : [])
        let pdf = try #require(PDFTestDocuments.twoCharts(rowsText: rows, morePages: more, distinctBack: true))
        return try await importer.read(pdf, fileName: "bag.pdf")
    }

    func files(_ dir: URL) -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] }

    @Test func aPiecedImportSavesManifest2WithItsPDF() async throws {
        let base = try await make()
        let importer = base.importer()
        let reading = try await readBag(importer)
        let pieced = try #require(reading.pieced)
        let draft = OutlineDraft(pieced.outline, charts: pieced.charts)
        #expect(draft.pieces.map(\.title) == ["Front", "Back", "Strap"])
        let manifest = try await importer.savePieced(reading, draft: draft, records: [:])
        let local = try #require(await base.local.manifest(for: manifest.id))
        #expect(local.schema == 2 && local.id == "bag")
        #expect(local.pieces?.map(\.id) == ["front", "back", "strap"])
        #expect(local.charts.map(\.variant) == ["front", "back"] && Set(local.charts.map(\.id)).count == 2)
        for entry in local.charts { #expect(await base.charts.hasChart(id: entry.id)) }
        let strap = try #require(local.pieces?.last)
        #expect(strap.rows == "pieces/strap.rows.json" && strap.chart == nil)
        let document = try await base.rows.document(id: try #require(strap.rowsID))
        #expect(document.title == "Strap" && document.entries.map(\.from) == [1, 2] && document.entries.last?.to == 10)
        #expect(local.pieces?.prefix(2).allSatisfy { $0.chart != nil } == true)
        #expect(await base.local.sourcePDF(for: manifest.id) == reading.pdf)
        #expect(await base.local.preview(for: manifest.id, path: "preview.png") != nil)
        for entry in local.charts { #expect(await base.local.preview(for: manifest.id, path: entry.preview) != nil) }
    }

    /// Review Focus 1: one chart left and nothing else saves as manifest 1, as a one-chart PDF does.
    @Test func removingAllButOneChartSavesAsToday() async throws {
        let base = try await make()
        let importer = base.importer()
        let reading = try await readBag(importer)
        let pieced = try #require(reading.pieced)
        var draft = OutlineDraft(pieced.outline, charts: pieced.charts)
        for piece in draft.pieces.dropFirst() { draft.remove(piece.id) }
        for step in draft.assembly { draft.removeStep(step.id) }
        #expect(draft.isSingleChart)
        let manifest = try await importer.savePieced(reading, draft: draft, records: [:])
        let local = try #require(await base.local.manifest(for: manifest.id))
        #expect(local.schema == 1 && local.pieces == nil && local.charts.count == 1)
        #expect(local.charts[0].width == Self.chartWidth && local.charts[0].height == Self.chartHeight)
        #expect(await base.charts.hasChart(id: local.charts[0].id))
        #expect(files(base.rowsDir).isEmpty)
        #expect(await base.local.sourcePDF(for: manifest.id) == reading.pdf)
    }

    /// Review Focus 4: a written piece that does not start at row 1 is refused, and nothing is
    /// written -- no chart, no rows, no pattern directory, no stray `source.pdf`.
    @Test func aFailedPiecedSaveWritesNothing() async throws {
        let base = try await make()
        let importer = base.importer()
        var reading = try await readBag(importer)
        let pieced = try #require(reading.pieced)
        var outline = pieced.outline
        let strap = try #require(outline.pieces.firstIndex { $0.title == "Strap" })
        outline.pieces[strap].entries = outline.pieces[strap].entries.filter { $0.from != 1 }
        #expect(outline.pieces[strap].entries.first?.from == 2)
        reading.pieced = PiecedReading(outline: outline, charts: pieced.charts, sections: pieced.sections, pdf: pieced.pdf)
        let draft = OutlineDraft(outline, charts: pieced.charts)
        do {
            _ = try await importer.savePieced(reading, draft: draft, records: [:])
            Issue.record("a strap starting at row 2 saved")
        } catch PDFImportError.rowsDoNotAssemble(let why) {
            #expect(why.count == 1 && why[0].hasPrefix("Strap: ") && why[0].contains("gap"), "\(why)")
        }
        #expect(files(base.chartsDir).isEmpty)
        #expect(files(base.rowsDir).isEmpty)
        #expect(files(base.localDir).isEmpty)
    }

    /// A chart piece is saved with its own check's record; one with none, as not checked.
    @Test func eachChartPieceIsSavedWithItsOwnRecord() async throws {
        let base = try await make()
        let importer = base.importer()
        let reading = try await readBag(importer)
        let pieced = try #require(reading.pieced)
        let draft = OutlineDraft(pieced.outline, charts: pieced.charts)
        let finished = ImportRecord(grid: true, check: .finished, rowsChecked: 15, rowsTotal: 15, rowsDisagree: [], gaugePrinted: false, problem: nil)
        let manifest = try await importer.savePieced(reading, draft: draft, records: [0: finished, 7: finished])
        let local = try #require(await base.local.manifest(for: manifest.id))
        let front = try await base.charts.chart(id: try #require(local.pieces?[0].chart))
        let back = try await base.charts.chart(id: try #require(local.pieces?[1].chart))
        #expect(ImportRecord(json: front.document.ext) == finished)
        let unchecked = try #require(ImportRecord(json: back.document.ext))
        #expect(unchecked.rowsTotal == 15 && unchecked.rowsChecked == 0 && unchecked.check == .unavailable)
    }

    /// A piece or step renamed to blank is saved as "Piece N" or "Step N", by its place in the list.
    @Test func blankTitlesSaveAsTheirPlace() async throws {
        let base = try await make()
        let importer = base.importer()
        let reading = try await readBag(importer, assembly: true)
        let pieced = try #require(reading.pieced)
        var draft = OutlineDraft(pieced.outline, charts: pieced.charts)
        #expect(draft.assembly.map(\.title) == ["Page 4"])
        draft.rename(draft.pieces[2].id, to: "   ")
        draft.renameStep(draft.assembly[0].id, to: "")
        let manifest = try await importer.savePieced(reading, draft: draft, records: [:])
        let local = try #require(await base.local.manifest(for: manifest.id))
        #expect(local.pieces?.map(\.title) == ["Front", "Back", "Piece 3"])
        #expect(local.pieces?.map(\.id) == ["front", "back", "piece"])
        #expect(local.assembly.map(\.title) == ["Step 1"] && local.assembly.first?.pages == [4])
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

    /// Construction rows, no colour in any of them (the cactus blanket, #198): nothing to check,
    /// and the model is never asked.
    @Test func aChartWhoseRowsNameNoColourHasNoRowsToCheck() async throws {
        let construction = (1...Self.chartHeight).map { "Row \($0): ch 1, turn, 1 dc in each of next 2 ch. Turn." }.joined(separator: "\n")
        let asked = Asked()
        let importer = try await make().importer(rowReader: StubRowReader(document: Self.chartDocument(), delayPerRow: .zero, asked: asked))
        let reading = try await importer.read(try #require(PDFTestDocuments.chart(rows: true, rowsText: construction)), fileName: "drawn.pdf")
        #expect(reading.source == .grid(page: 1, rowsToCheck: 0))
        #expect(await importer.check(reading, progress: nil).check == .noRows)
        #expect(await asked.sections.isEmpty)
    }

    /// Orca's shape (#176, #197): a body in one colour and a shorter run of colour rows, both
    /// counting from row 1, before the rows the chart draws. Only the chart's rows are read.
    @Test func theCheckReadsOnlyTheRowsAsTallAsTheChart() async throws {
        let body = (1...4).map { $0 == 1 ? "Row 1: (Black) ch 7, 6 sc [6]" : "Row \($0): ch 1, turn, 6 sc [6]" }.joined(separator: "\n")
        let strap = (1...5).map { "Row \($0): 2 B, 4 A" }.joined(separator: "\n")
        let asked = Asked()
        let importer = try await make().importer(rowReader: StubRowReader(document: Self.chartDocument(), delayPerRow: .zero, asked: asked))
        let pdf = try #require(PDFTestDocuments.chart(rows: true, rowsText: [body, strap, PDFTestDocuments.colourRows].joined(separator: "\n")))
        let reading = try await importer.read(pdf, fileName: "drawn.pdf")
        #expect(reading.source == .grid(page: 1, rowsToCheck: Self.chartHeight))
        let record = await importer.check(reading, progress: nil)
        #expect(record.check == .finished && record.rowsDisagree == [] && record.problem == nil)
        let section = try #require(await asked.sections.first ?? nil)
        #expect(section.rows == Self.chartHeight && section.lastRow == Self.chartHeight && section.blocks.first?.text.hasPrefix("Row 1: 3 B") == true)
    }

    /// What the import left out, as the sheet says it (#206): every chart the pages draw and every
    /// set of written rows counting from row 1, less the chart imported and the set that is its own.
    @Test func theSheetSaysWhatTheImportLeftOut() {
        func say(_ charts: Int, _ sets: Int, _ matched: Bool) -> String? { PDFContents(charts: charts, rowSets: sets, rowSetMatched: matched).sentence }
        #expect(say(1, 0, false) == nil && say(1, 1, true) == nil)
        #expect(say(2, 9, true) == "This PDF has 2 charts and 9 sets of written rows. One chart was imported; the other chart and 8 sets of written rows were left out.")
        #expect(say(1, 3, false) == "This PDF has 1 chart and 3 sets of written rows. The chart was imported; the 3 sets of written rows were left out.")
        #expect(say(1, 2, true) == "This PDF has 1 chart and 2 sets of written rows. The chart was imported; 1 set of written rows was left out.")
        #expect(say(1, 1, false) == "This PDF has 1 chart and 1 set of written rows. The chart was imported; the set of written rows was left out.")
        #expect(say(2, 0, false) == "This PDF has 2 charts. One was imported; the other was left out.")
        #expect(say(3, 1, true) == "This PDF has 3 charts and 1 set of written rows. One chart was imported; the other 2 charts were left out.")
    }

    /// The synthetic page with a body, a strap and the chart's own rows: one chart, three sets,
    /// the chart's set matched, so two sets were left out. A page with only the chart says nothing.
    @Test func aChartPageCountsTheSetsOfRowsItLeftOut() async throws {
        let body = (1...4).map { $0 == 1 ? "Row 1: (Black) ch 7, 6 sc [6]" : "Row \($0): ch 1, turn, 6 sc [6]" }.joined(separator: "\n")
        let strap = (1...5).map { "Row \($0): 2 B, 4 A" }.joined(separator: "\n")
        let importer = try await make().importer(rowReader: nil)
        let pdf = try #require(PDFTestDocuments.chart(rows: true, rowsText: [body, strap, PDFTestDocuments.colourRows].joined(separator: "\n")))
        let reading = try await importer.read(pdf, fileName: "drawn.pdf")
        #expect(reading.contents == PDFContents(charts: 1, rowSets: 3, rowSetMatched: true))
        let bare = try await importer.read(try #require(PDFTestDocuments.chart(rows: false)), fileName: "bare.pdf")
        #expect(bare.contents == PDFContents(charts: 1, rowSets: 0, rowSetMatched: false) && bare.contents?.sentence == nil)
    }

    /// The chart's own rows become its `written` text only when they print rows 1...height once
    /// each, in order, one to a block; anything else would misalign a row with its text.
    @Test func writtenRowsNeedEveryRowOnceInOrder() {
        let page = "R 1 [←]: (Black) ch 4, 3 sc [3]\nR 2 [→]: (Black) ch 1, turn, 1 inc, 1 sc, 1 inc [5]\nR 3 [←]: (White) ch 1, turn, 5 sc [5]"
        let section = RowText.sections(in: [page]).first
        #expect(PDFImporter.writtenRows(section, height: 3)?.count == 3)
        #expect(PDFImporter.writtenRows(section, height: 3)?.first?.hasPrefix("R 1") == true)
        #expect(PDFImporter.writtenRows(section, height: 4) == nil)
        let ranged = RowText.sections(in: ["R 1: (Black) ch 4, 3 sc [3]\nR 2 - R 3: (Black) ch 1, turn, 3 sc [3]"]).first
        #expect(PDFImporter.writtenRows(ranged, height: 3) == nil)
        #expect(PDFImporter.writtenRows(nil, height: 3) == nil)
        // A wide range's head reduces to its first row under `rowNumbers`, but it still names more
        // than one row, so it must not stand in as that row's own text (CodeRabbit review).
        let wideRange = RowText.sections(in: ["Rows 1-302: (Black) ch 4, 3 sc [3]"]).first
        #expect(PDFImporter.writtenRows(wideRange, height: 1) == nil)
    }

    /// A row the reader could not read is named, never passed off as clean -- and no longer
    /// cancels the comparison of the rows that did read (#176). Two rows a model fumbles should
    /// not cost the maker the other seventy-five.
    @Test func aRowTheReaderCouldNotReadIsNamedWhileTheRestAreStillChecked() async throws {
        var doc = Self.chartDocument()
        doc.written_rows?[4].runs = []
        doc.written_rows?[4].error = "no colour named"
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let record = await importer.check(try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf"), progress: nil)
        #expect(record.check == .finished && record.problem == "row 5: no colour named")
        #expect(record.rowsUnread == 1 && record.rowsDisagree.isEmpty)
        #expect(record.sentence == "1 written row couldn't be read (row 5: no colour named). The rest agree with the chart.")
    }

    /// The same, with one of the rows that did read disagreeing: both facts are reported.
    @Test func anUnreadRowAndADisagreeingRowAreBothReported() async throws {
        var doc = Self.chartDocument(wrongRow: 3)
        doc.written_rows?[4].runs = []
        doc.written_rows?[4].error = "no colour named"
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let record = await importer.check(try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf"), progress: nil)
        #expect(record.rowsUnread == 1 && record.rowsDisagree == [3])
        #expect(record.sentence?.hasPrefix("1 written row couldn't be read (row 5: no colour named).") == true)
        #expect(record.sentence?.contains("Row 3 disagrees with the chart.") == true)
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

    /// A read that loses many rows names a few and counts the rest: naming all 77 put fifteen
    /// thousand characters in a view sized for a sentence, and the same string into the chart
    /// (#179).
    @Test func manyUnreadRowsAreNamedAFewAndCounted() {
        #expect(PDFImporter.unreadSentence(["row 1: a", "row 2: b"]) == "row 1: a; row 2: b")
        #expect(PDFImporter.unreadSentence(["row 1: a", "row 2: b", "row 3: c"]) == "row 1: a; row 2: b; row 3: c")
        #expect(PDFImporter.unreadSentence((1...77).map { "row \($0): why" })
            == "row 1: why; row 2: why; row 3: why; and 74 more")
        #expect(PDFImporter.unreadSentence((1...77).map { "row \($0): why" }).count < 200)
    }

    /// A comparison that cannot run reports itself as one, and never as agreement: on a device
    /// it said "2 written rows couldn't be read (...). The rest agree with the chart" while
    /// `crossCheck` had returned incomparable and nothing had been compared (#176).
    @Test func aCheckThatCannotCompareSaysSoAndClaimsNoAgreement() async throws {
        var doc = Self.chartDocument()
        // A code the palette does not carry makes the whole comparison incomparable.
        doc.written_rows?[2].runs = [[.code("RS"), .count(Self.chartWidth)]]
        let importer = try await make().importer(rowReader: StubRowReader(document: doc, delayPerRow: .zero))
        let record = await importer.check(try await importer.read(try #require(PDFTestDocuments.chart(rows: true)), fileName: "drawn.pdf"), progress: nil)
        let sentence = try #require(record.sentence)
        #expect(record.rowsChecked == 0, "nothing was compared, so nothing was checked")
        #expect(!sentence.contains("agree"), "\(sentence)")
        #expect(sentence.hasPrefix("Written rows could not be compared with the chart:"))
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
/// The section each read was asked for.
actor Asked {
    var sections: [RowSection?] = []
    func record(_ s: RowSection?) { sections.append(s) }
}

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
    /// Written rows the way a pattern prints them: every row names its colours.
    static let colourRows = (1...PDFImportTests.chartHeight).map { "Row \($0): 3 B, 17 A" }.joined(separator: "\n")

    /// The chart page, then with `rows` a page of written rows: `rowsText` when given, else `colourRows`.
    static func chart(rows: Bool, rowsText: String? = nil) -> Data? {
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            drawChart(ctx.cgContext, ox: 60, oy: 80)
            if rows {
                ctx.beginPage()
                let text = rowsText ?? colourRows
                (text as NSString).draw(in: bounds.insetBy(dx: 36, dy: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
        }
    }

    /// Two of the synthetic charts side by side on page 1 (x 40 and 330), then a page of `rowsText`,
    /// then a page for each of `morePages`.
    /// The second sits lower: two grids whose lines align across a 50 pt gap read as one grid of
    /// 44 columns, gap and all, which is the grid reader's business, not the importer's. With
    /// `distinctBack`, the second chart differs from the first in one cell of its top row (row 15),
    /// so the two are two charts in a content-addressed library, and a check stopped before row
    /// 15 still finds the rows it read agree.
    static func twoCharts(rowsText: String, morePages: [String] = [], distinctBack: Bool = false) -> Data? {
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            drawChart(ctx.cgContext, ox: 40, oy: 80)
            drawChart(ctx.cgContext, ox: 330, oy: 400, changed: distinctBack ? (x: 10, y: 0) : nil)
            for text in [rowsText] + morePages {
                ctx.beginPage()
                (text as NSString).draw(in: bounds.insetBy(dx: 36, dy: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            }
        }
    }

    /// The synthetic chart at 12 pt cells with its origin at (`ox`, `oy`).
    static func drawChart(_ cg: CGContext, ox: CGFloat, oy: CGFloat, changed: (x: Int, y: Int)? = nil) {
        let cell: CGFloat = 12
        let w = PDFImportTests.chartWidth, h = PDFImportTests.chartHeight
        for y in 0..<h { for x in 0..<w {
            var c = PDFImportTests.chartCell(x: x, y: y)
            if let changed, changed == (x, y) { c = (c + 2) % 4 }
            let rgb = GridColours.rgb(PDFImportTests.chartHexes[c])!
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

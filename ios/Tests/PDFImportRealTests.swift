import CryptoKit
import Foundation
import PDFKit
import Testing
import GraphghanCore
import ProseReaderKit
@testable import Graphghan

/// The real pattern PDFs (`fixtures/import/real/`, gitignored, on the mini only) through the
/// phone's grid path, to the hashes `manifest.toml` pins (phone import spec §8 item 3, §11). A
/// file that is absent skips and says so, as the Python test does.
@MainActor
@Suite struct PDFImportRealTests {
    struct Entry: Sendable { let id: String; let file: String; let width: Int; let height: Int; let hash: String; let phoneHash: String? }

    /// The fixtures with a pinned hash and a page-wide chart: cactus, Santa, and Orca's two.
    nonisolated static func entries() throws -> [Entry] {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/manifest.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [Entry] = []
        var fields: [String: String] = [:]
        func flush() {
            if let id = fields["id"], let file = fields["file"], let w = fields["width"].flatMap(Int.init), let h = fields["height"].flatMap(Int.init),
               let hash = fields["rows_sha256"], !hash.isEmpty, fields["prose"] == nil {
                out.append(Entry(id: id, file: file, width: w, height: h, hash: hash, phoneHash: fields["phone_rows_sha256"]))
            }
            fields = [:]
        }
        for line in text.split(separator: "\n") {
            if line.hasPrefix("[[fixture]]") { flush(); continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            fields[key] = value
        }
        flush()
        return out
    }

    static func importer() throws -> PDFImporter {
        PDFImporter(charts: ChartLibrary(directory: try temporaryDirectory()), local: LocalPatternStore(directory: try temporaryDirectory()),
                    rows: RowsLibrary(directory: try temporaryDirectory()), rowReader: nil, modelUnavailable: nil, pieceReader: FoundOutline())
    }

    @Test(arguments: try entries())
    func aRealPDFReadsToThePinnedHash(entry: Entry) async throws {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/\(entry.file)")
        guard let data = try? Data(contentsOf: url) else {
            print("SKIP real fixture \(entry.file) is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = try Self.importer()
        let started = Date()
        let reading = try await importer.read(data, fileName: entry.file)
        let seconds = Date().timeIntervalSince(started)
        print("real \(entry.id): \(reading.width)x\(reading.height) in \(String(format: "%.1f", seconds)) s, \(reading.source)")
        print("real \(entry.id): palette \(reading.draft.palette.map(\.hex)); rows \(reading.draft.rows.prefix(3)) … \(reading.draft.rows.suffix(2)); warnings \(reading.warnings)")
        #expect(reading.width == entry.width && reading.height == entry.height, "\(entry.id)")
        let hash = SHA256.hash(data: Data(reading.draft.rows.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
        // Orca's page holds the front and the back at the same size; the phone takes the first
        // largest region, so either of the two pinned hashes is right. A fixture may pin the
        // phone's own hash where PDFKit's render differs from pdfium's (the manifest says why).
        let sibling = try Self.entries().filter { $0.file == entry.file && $0.width == entry.width && $0.height == entry.height }
            .flatMap { [$0.hash] + ($0.phoneHash.map { [$0] } ?? []) }
        #expect(sibling.contains(hash), "\(entry.id): \(hash)")
    }

    /// The written rows a real chart is checked by (#176, #197, #198). Orca prints its body, strap
    /// and both panels: only one panel's 77 rows are the chart's. The cactus prints c2c
    /// construction rows with no colour in them: nothing to check.
    @Test(arguments: [("EN_OrcaCrossbodyBagPDFPattern.pdf", 77), ("ys-bernat-corner-to-corner-crochet-cactus-blanket.pdf", 0)])
    func aRealChartChecksOnlyItsOwnRows(file: String, rows: Int) async throws {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/\(file)")
        guard let data = try? Data(contentsOf: url) else {
            print("SKIP real fixture \(file) is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = try Self.importer()
        let reading = try await importer.read(data, fileName: file)
        guard case .grid(_, let toCheck) = reading.source else { Issue.record("\(file) read no grid"); return }
        #expect(toCheck == rows, "\(file)")
    }

    /// Orca's panel is shaped (#176): 9 stitches at row 1, 29 at its widest, 3 at row 77, on a
    /// 29-wide chart. The hand transcript of its written rows (`…-front.prose.json`, the Python's
    /// ground truth) against the grid the phone reads off page 9: every row compared, none
    /// disagreeing. This is spec §11's check with the model taken out.
    @Test func orcasWrittenRowsAgreeWithItsShapedChart() async throws {
        let dir = TestFixtures.root.appendingPathComponent("fixtures/import/real")
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("EN_OrcaCrossbodyBagPDFPattern.pdf")),
              let truth = try? Data(contentsOf: dir.appendingPathComponent("onhand-en-orcacrossbodybagpdfpattern-front.prose.json")) else {
            print("SKIP Orca's PDF or its transcript is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = try Self.importer()
        let chart = try await importer.read(data, fileName: "orca.pdf").bundle.charts[0].chart
        let doc = try JSONDecoder().decode(ProseDocument.self, from: truth)
        let rows = (doc.written_rows ?? []).map { r in
            RowsChart.Row(row: r.row, runs: r.runs.compactMap { run -> (code: String, count: Int)? in
                guard case .code(let c) = run.first, case .count(let n) = run.last else { return nil }
                return (c, n)
            }, total: r.total)
        }
        #expect(rows.count == 77)
        let outcome = RowsChart.crossCheck(rows: rows, codes: (doc.palette ?? []).map(\.code), grid: chart.cells, width: chart.width, height: chart.height,
                                           row1: doc.chart?.row1 ?? "bottom-right")
        #expect(outcome == .compared(disagree: [], warnings: []), "\(outcome)")
    }

    /// Orca's light blue is the background its panel is drawn on, not a yarn (#205): the palette
    /// keeps it, marked "no stitch", so the grid stays 29 wide, and the sheet counts three colours.
    /// The cactus's corners are one colour too, but its sky rows are stitched: all of it stays yarn.
    @Test(arguments: [("EN_OrcaCrossbodyBagPDFPattern.pdf", 3, 1), ("ys-bernat-corner-to-corner-crochet-cactus-blanket.pdf", 2, 0)])
    func aShapedChartsBackgroundIsNoStitch(file: String, colours: Int, noStitch: Int) async throws {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/\(file)")
        guard let data = try? Data(contentsOf: url) else {
            print("SKIP real fixture \(file) is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = try Self.importer()
        let reading = try await importer.read(data, fileName: file)
        let marked = reading.bundle.charts[0].chart.palette.filter { $0.use == ChartDraft.Palette.noStitch }
        #expect(reading.colours == colours && marked.count == noStitch, "\(file): \(reading.colours) colours, \(marked.map(\.hex)) no stitch")
        #expect(reading.bundle.manifest.charts[0].colors == colours, "\(file)")
    }

    /// What the sheet says a real PDF left out (#206). Orca draws its front and back panels side by
    /// side on page 9 and prints nine sets of written rows (both panels, the body, the strap and
    /// the small parts); the cactus prints three sets of construction and edging rows; Santa one chart.
    @Test(arguments: [
        ("EN_OrcaCrossbodyBagPDFPattern.pdf",
         "This PDF has 2 charts and 9 sets of written rows. One chart was imported; the other chart and 8 sets of written rows were left out."),
        ("ys-bernat-corner-to-corner-crochet-cactus-blanket.pdf",
         "This PDF has 1 chart and 3 sets of written rows. The chart was imported; the 3 sets of written rows were left out."),
        ("mdc-c2c-santa-blanket.pdf", nil),
    ] as [(String, String?)])
    func aRealPDFSaysWhatItLeftOut(file: String, sentence: String?) async throws {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/\(file)")
        guard let data = try? Data(contentsOf: url) else {
            print("SKIP real fixture \(file) is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = try Self.importer()
        let reading = try await importer.read(data, fileName: file)
        #expect(reading.contents?.sentence == sentence, "\(file): \(String(describing: reading.contents))")
    }

    /// Orca's front panel is a shaped piece (#37): chart schema 3, 9 stitches at row 1 from grid
    /// column 6, 29 at the widest, 3 at row 77, 1805 stitches in all (the Python's grid read of
    /// page 9 region 1), and its own 77 written rows as the chart's `written` text.
    @Test func orcaIsAShapedPiece() async throws {
        let file = "EN_OrcaCrossbodyBagPDFPattern.pdf"
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/\(file)")
        guard let data = try? Data(contentsOf: url) else {
            print("SKIP real fixture \(file) is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = try Self.importer()
        let reading = try await importer.read(data, fileName: file)
        let chart = reading.bundle.charts[0].chart
        #expect(chart.document.schema == 3 && chart.isShaped && reading.colours == 3)
        let seq = try WorkSequence(chart: chart)
        #expect(seq.passes.count == 77)
        #expect(seq.passes[0].cells == 9 && seq.passes[0].runs.compactMap(\.x0).min() == 6)
        #expect(seq.passes.map(\.cells).max() == 29 && seq.passes[76].cells == 3)
        #expect(seq.totalCells == 1805)
        #expect(reading.bundle.manifest.charts[0].stitches == 1805)
        #expect(chart.written?.count == 77)
        #expect(chart.written?.first?.hasPrefix("R 1") == true)
    }

    /// The outline code finds in Orca's text (spec §7.3), with page 9's two 29 × 77 regions standing in.
    @Test func orcasOutline() async throws {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/EN_OrcaCrossbodyBagPDFPattern.pdf")
        guard let doc = PDFDocument(url: url) else { print("SKIP real fixture EN_OrcaCrossbodyBagPDFPattern.pdf is absent; see fixtures/import/real/README.md"); return }
        let pages = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        let found = FoundParts(charts: [FoundChart(page: 9, x0: 100, cols: 29, rows: 77), FoundChart(page: 9, x0: 1200, cols: 29, rows: 77)],
                               sections: RowText.sections(in: pages), pageTexts: pages,
                               palette: [.init(code: "A", name: "black", hex: "#201b18"), .init(code: "B", name: "white", hex: "#ffffff")])
        let o = await FoundOutline().outline(pages: pages, found: found)
        #expect(o.pieces.map(\.title) == ["Rows, page 7, R 1–2", "Front Panel", "Back Panel", "Head Tail", "Dorsal Fin", "Pectoral Fin (Front)",
                                          "Pectoral Fin (Back)", "Tail", "Rows, page 12, R 1–15"])
        #expect(o.pieces[1].pairedSection == 7 && o.pieces[2].pairedSection == 8)
        #expect(o.pieces[3].entries.map { [$0.from, $0.to ?? -1] } == [[1, 1], [2, 26], [27, 86], [87, 104]])
        #expect(o.pieces[8].entries.map { [$0.from, $0.to ?? -1] } == [[1, 1], [2, 7], [8, 15]])
        #expect(o.assembly == [AssemblyOutline(title: "Page 8", text: nil, pages: [8]), AssemblyOutline(title: "Pages 13–16", text: nil, pages: [13, 14, 15, 16])])
        #expect(o.leftOut == ["text after R 2 (page 7)", "text after R 104 (page 10)", "text after R 15 (page 12)"])
        #expect(o.pieces[8].entries[2].text == "same as")   // a known limit of code-only reading: the line's rest was split off (#200 would read it)
    }

    /// Orca read whole (spec §7.1): page 9's two 29 × 77 regions, left to right, both shaped
    /// pieces, each with its own 77 written rows, and the outline `orcasOutline` pins.
    @Test func orcaIsReadAsPieces() async throws {
        let file = "EN_OrcaCrossbodyBagPDFPattern.pdf"
        guard let data = try? Data(contentsOf: TestFixtures.root.appendingPathComponent("fixtures/import/real/\(file)")) else {
            print("SKIP real fixture \(file) is absent; see fixtures/import/real/README.md")
            return
        }
        let reading = try await Self.importer().read(data, fileName: file)
        let pieced = try #require(reading.pieced)
        #expect(pieced.charts.count == 2 && pieced.charts.map(\.found.page) == [9, 9] && pieced.charts[0].found.x0 < pieced.charts[1].found.x0)
        for chart in pieced.charts {
            let loaded = try Chart.load(ChartWriter.encode(chart.draft).0)
            #expect(loaded.document.schema == 3 && loaded.isShaped && chart.width == 29 && chart.height == 77)
            #expect(chart.draft.written?.count == 77)
        }
        #expect(pieced.outline.pieces.map(\.title) == ["Rows, page 7, R 1–2", "Front Panel", "Back Panel", "Head Tail", "Dorsal Fin", "Pectoral Fin (Front)",
                                                       "Pectoral Fin (Back)", "Tail", "Rows, page 12, R 1–15"])
        #expect(reading.pdf == data)
    }

    /// Orca end to end (pieces spec §10, Task 10): the maker drops the page-7 "how to read a
    /// graph" example and the page-8 assembly step it belongs to, renames "Head Tail" to "Side
    /// Panel" and the tail's written rows to "Tail (Black)", then saves with no checks run.
    @Test func orcaImportsAsAPiecedPattern() async throws {
        let file = "EN_OrcaCrossbodyBagPDFPattern.pdf"
        guard let data = try? Data(contentsOf: TestFixtures.root.appendingPathComponent("fixtures/import/real/\(file)")) else {
            print("SKIP real fixture \(file) is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = try Self.importer()
        let started = Date()
        let reading = try await importer.read(data, fileName: file)
        let seconds = Date().timeIntervalSince(started)
        print("orca pieced read: \(String(format: "%.1f", seconds)) s")
        let pieced = try #require(reading.pieced)
        var draft = OutlineDraft(pieced.outline, charts: pieced.charts)

        let example = try #require(draft.pieces.first { $0.title == "Rows, page 7, R 1–2" })
        draft.remove(example.id)
        let page8 = try #require(draft.assembly.first { $0.title == "Page 8" })
        draft.removeStep(page8.id)
        let headTail = try #require(draft.pieces.first { $0.title == "Head Tail" })
        draft.rename(headTail.id, to: "Side Panel")
        let tailRows = try #require(draft.pieces.first { $0.title == "Rows, page 12, R 1–15" })
        draft.rename(tailRows.id, to: "Tail (Black)")

        let manifest = try await importer.savePieced(reading, draft: draft, records: [:])
        #expect(manifest.schema == 2)
        let pieces = try #require(manifest.pieces)
        #expect(pieces.map(\.id) == ["front-panel", "back-panel", "side-panel", "dorsal-fin", "pectoral-fin-front", "pectoral-fin-back", "tail", "tail-black"],
                "\(pieces.map(\.id))")

        #expect(manifest.charts.count == 2, "\(manifest.charts.map(\.variant))")
        for entry in manifest.charts {
            let chart = try await importer.charts.chart(id: entry.id)
            #expect(chart.document.schema == 3 && chart.isShaped && chart.width == 29 && chart.height == 77, "\(entry.variant)")
            #expect(chart.written?.count == 77, "\(entry.variant)")
        }

        let sidePanel = try #require(pieces.first { $0.id == "side-panel" })
        let rowsID = try #require(sidePanel.rowsID)
        let rowsDoc = try await importer.rows.document(id: rowsID)
        #expect(rowsDoc.entries.count == 4 && rowsDoc.entries.last?.to == 104, "\(rowsDoc.entries)")

        #expect(manifest.assembly.map(\.title) == ["Pages 13–16"], "\(manifest.assembly.map(\.title))")

        #expect(await importer.local.sourcePDF(for: manifest.id) == data)
    }
}

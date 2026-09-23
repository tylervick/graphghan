import CryptoKit
import Foundation
import Testing
import GraphghanCore
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

    @Test(arguments: try entries())
    func aRealPDFReadsToThePinnedHash(entry: Entry) async throws {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/\(entry.file)")
        guard let data = try? Data(contentsOf: url) else {
            print("SKIP real fixture \(entry.file) is absent; see fixtures/import/real/README.md")
            return
        }
        let importer = PDFImporter(charts: ChartLibrary(directory: try temporaryDirectory()), local: LocalPatternStore(directory: try temporaryDirectory()),
                                   rowReader: nil, modelUnavailable: nil)
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
        let importer = PDFImporter(charts: ChartLibrary(directory: try temporaryDirectory()), local: LocalPatternStore(directory: try temporaryDirectory()),
                                   rowReader: nil, modelUnavailable: nil)
        let reading = try await importer.read(data, fileName: file)
        guard case .grid(_, let toCheck) = reading.source else { Issue.record("\(file) read no grid"); return }
        #expect(toCheck == rows, "\(file)")
    }
}

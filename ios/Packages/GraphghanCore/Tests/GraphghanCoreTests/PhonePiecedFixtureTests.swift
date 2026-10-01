import Foundation
import Testing
@testable import GraphghanCore

/// `fixtures/chart-format/phone-pieced/`: a pieced pattern as the phone's own writers put it on
/// disk -- `ManifestWriter.encodePieced`, `ChartWriter.encode` (a shaped, schema 3 chart with its
/// written rows and import record) and `RowsWriter.encode` -- from fixed inputs. Byte-pinned here;
/// `tests/test_conformance.py` validates the same files against the schemas and the Python
/// validators, so a phone-written pieced pattern is checked by both sides (spec §9).
///
/// Re-record after a deliberate writer change with
/// `GRAPHGHAN_RECORD_FIXTURES=1 swift test --filter PhonePiecedFixtureTests`.
@Suite struct PhonePiecedFixtureTests {
    static let directory = Fixtures.directory.appendingPathComponent("phone-pieced", isDirectory: true)
    static let chartPath = "charts/panel-sc/chart.json"
    static let rowsPath = "pieces/strap.rows.json"

    /// The panel: shaped-basic's grid (N is the ground), its written rows (row 1 first) and a
    /// finished check's record, as a pieced PDF import saves a chart piece.
    static func chartDraft() -> ChartDraft {
        var gauge = ChartDraft.Gauge()
        gauge.stitch = "sc"
        var draft = ChartDraft(pattern: .init(id: "phone-pieced", title: "Phone pieced", version: "1.0.0"),
                               palette: [.init(code: "A", name: "black", hex: "#201b18"),
                                         .init(code: "B", name: "white", hex: "#ffffff"),
                                         .init(code: "N", name: "light blue", hex: "#a4dade", use: ChartDraft.Palette.noStitch)],
                               rows: ["2N3A2N", "1N2A1B3A", "3A1B3A", "1N5A1N", "2N3A2N"], width: 7, height: 5, gauge: gauge,
                               ext: ImportRecord(grid: true, check: .finished, rowsChecked: 5, rowsTotal: 5, rowsDisagree: [],
                                                 gaugePrinted: false, problem: nil).json())
        draft.written = ["Row 1: 3 black", "Row 2: 5 black", "Row 3: 3 black, 1 white, 3 black",
                         "Row 4: 2 black, 1 white, 3 black", "Row 5: 3 black"]
        return draft
    }

    /// The bundle's three JSON files, by manifest-relative path, plus what was built from them.
    static func build() throws -> (files: [String: Data], chart: Chart) {
        let draft = chartDraft()
        let (chartData, chartID) = ChartWriter.encode(draft)
        let chart = try Chart.load(chartData)
        let strap = [RowsDocument.Entry(label: "R 1", from: 1, to: 1, text: "(Black) ch 7, 6 sc [6]", count: 6, code: "A", repeatText: nil),
                     RowsDocument.Entry(label: "R 2 - R 10", from: 2, to: 10, text: "ch 1, turn, 6 sc [6]", count: 6, code: nil, repeatText: nil)]
        let (rowsData, rowsID) = RowsWriter.encode(title: "Strap", palette: [draft.palette[0]], entries: strap, pages: [3])
        let input = ManifestChartInput(chart: chart, chartID: chartID, variant: "panel", gaugeKey: "sc", palette: draft.palette)
        let manifest = ManifestWriter.encodePieced(
            id: "phone-pieced", title: "Phone pieced", version: "1.0.0", dedication: "Imported from phone-pieced.pdf on 1 Oct 2026",
            charts: [input],
            pieces: [PieceEntry(id: "panel", title: "Panel", make: 2, chart: chartID, rows: nil, rowsID: nil, pages: [1, 2]),
                     PieceEntry(id: "strap", title: "Strap", make: 1, chart: nil, rows: rowsPath, rowsID: rowsID, pages: [3])],
            assembly: [AssemblyEntry(title: "Pages 4–5", text: nil, pages: [4, 5])],
            palette: draft.palette)
        return ([PatternBundle.manifestName: manifest, chartPath: chartData, rowsPath: rowsData], chart)
    }

    /// Each file as committed: the writer's bytes and the newline every committed text file ends
    /// with (the `newlines` hook adds one).
    @Test func theWritersReproduceTheFixture() throws {
        let files = try Self.build().files.mapValues { $0 + Data("\n".utf8) }
        if ProcessInfo.processInfo.environment["GRAPHGHAN_RECORD_FIXTURES"] == "1" {
            for (path, data) in files {
                let url = Self.directory.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
        }
        for (path, data) in files {
            let committed = try Data(contentsOf: Self.directory.appendingPathComponent(path))
            #expect(committed == data, "\(path) differs from what the phone writes")
        }
    }

    /// What the phone writes opens as a bundle: the manifest checks pass and every file loads
    /// and matches its id. The previews are made here, not committed (a PNG is not the format).
    @Test func theFixtureReadsAsABundle() throws {
        let (files, chart) = try Self.build()
        let manifest = try JSONDecoder().decode(PatternManifest.self, from: files[PatternBundle.manifestName]!)
        try PatternBundle.validate(manifest)
        let preview = try #require(ChartPreview.png(chart))
        var items = files.map { ZipBuilder.Item($0.key, $0.value) }
        items += [manifest.preview, manifest.charts[0].preview].map { ZipBuilder.Item($0, preview) }
        let bundle = try PatternBundle.read(ZipBuilder(items: items).build())
        #expect(bundle.charts.count == 1 && bundle.charts[0].chart.document.schema == 3)
        #expect(bundle.manifest.pieces?.map(\.id) == ["panel", "strap"] && bundle.manifest.pieces?[0].make == 2)
        #expect(bundle.rows.map(\.document.title) == ["Strap"])
    }
}

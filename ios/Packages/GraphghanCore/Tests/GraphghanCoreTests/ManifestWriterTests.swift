import CryptoKit
import Foundation
import Testing
@testable import GraphghanCore

/// A manifest the phone writes decodes as `PatternManifest` and carries what the library shows.
@Suite struct ManifestWriterTests {
    /// `ManifestWriter.encode`'s single-chart bytes must not move when its entry-building is
    /// factored out for `encodePieced` to share: pinned against the SHA-256 recorded from today's
    /// output (before the refactor) for the `minimal-rows` fixture.
    @Test func encodesSingleChartBytesUnchanged() throws {
        let chart = try Chart.load(Fixtures.data("minimal-rows.chart.json"))
        let palette = chart.palette.map { ChartDraft.Palette(code: $0.code, name: $0.name, hex: $0.hex) }
        let data = ManifestWriter.encode(id: "minimal", title: "Minimal", version: "1.0.0", dedication: "",
                                         chart: chart, chartID: chart.id, variant: "final", gaugeKey: "sc", palette: palette)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(hash == "a83cfc222607db93c2180de72078f967170c9ac1a07b6fbf9319aee030ccb2a7")
    }

    @Test func aPiecedManifestReadsAsSchema2() throws {
        let chart = try Chart.load(Fixtures.data("shaped-basic.chart.json"))
        let input = ManifestChartInput(chart: chart, chartID: chart.id, variant: "front-panel", gaugeKey: "sc",
                                       palette: chart.palette.map { .init(code: $0.code, name: $0.name, hex: $0.hex) })
        let pieces = [PieceEntry(id: "front-panel", title: "Front Panel", make: 1, chart: chart.id, rows: nil, rowsID: nil, pages: [9, 17]),
                      PieceEntry(id: "dorsal-fin", title: "Dorsal Fin", make: 1, chart: nil, rows: "pieces/dorsal-fin.rows.json",
                                 rowsID: "sha256:" + String(repeating: "b", count: 64), pages: [11])]
        let data = ManifestWriter.encodePieced(id: "orca", title: "Orca", version: "0.1.0", dedication: "", charts: [input], pieces: pieces,
                                               assembly: [AssemblyEntry(title: "Pages 13–16", text: nil, pages: [13, 14, 15, 16])], palette: input.palette)
        let m = try JSONDecoder().decode(PatternManifest.self, from: data)
        #expect(m.schema == 2 && m.charts.count == 1 && m.charts[0].isDefault && m.charts[0].path == "charts/front-panel-sc/chart.json")
        #expect(m.pieces?.map(\.id) == ["front-panel", "dorsal-fin"] && m.pieces?[1].rows == "pieces/dorsal-fin.rows.json")
        #expect(m.assembly.map(\.title) == ["Pages 13–16"] && m.assembly[0].text == nil)
    }

    @Test func aWrittenManifestDecodesWithTheLibrarysFields() throws {
        let draft = ChartDraft(pattern: .init(id: "orca", title: "Orca", version: "0.1.0"),
                               palette: [.init(code: "A", name: "black", hex: "#000000"), .init(code: "B", name: "white", hex: "#ffffff")],
                               rows: ["2A1B", "1A2B", "3A"], width: 3, height: 3, gauge: .init())
        let (data, id) = ChartWriter.encode(draft)
        let chart = try Chart.load(data)
        let bytes = ManifestWriter.encode(id: "orca", title: "Orca", version: "0.1.0", dedication: "Imported from Orca.pdf on 20 Sep 2026",
                                          chart: chart, chartID: id, variant: "final", gaugeKey: "sc", palette: draft.palette)
        let m = try JSONDecoder().decode(PatternManifest.self, from: bytes)
        #expect(m.schema == 1 && m.id == "orca" && m.title == "Orca" && m.version == "0.1.0" && m.preview == "preview.png")
        #expect(m.dedication == "Imported from Orca.pdf on 20 Sep 2026" && m.author == "" && m.license == "")
        #expect(m.palette.map(\.code) == ["A", "B"])
        let c = try #require(m.charts.first)
        #expect(c.id == id && c.isDefault && c.path == "charts/final-sc/chart.json" && c.preview == "charts/final-sc/preview.png")
        #expect(c.width == 3 && c.height == 3 && c.colors == 2 && c.stitches == 9 && c.stitch == "")
        #expect(c.changesPerRow.max == 1 && abs(c.changesPerRow.mean - 0.7) < 0.001)  // rows have 1, 1, 0 changes
        #expect(c.yardsEst > 0 && c.size?.unit == "in")
        #expect(m.updated == "1980-01-01T00:00:00Z")
    }

    /// A shaped piece's background (#205) is written as chart schema 3: `"stitch": false` beside
    /// `use: "no stitch"`, in the id (it changes the sequence), and out of every manifest number.
    @Test func aNoStitchColourIsWrittenAsSchema3AndNotCounted() throws {
        let draft = ChartDraft(pattern: .init(id: "orca", title: "Orca", version: "0.1.0"),
                               palette: [.init(code: "A", name: "light blue", hex: "#a4dade", use: ChartDraft.Palette.noStitch),
                                         .init(code: "B", name: "black", hex: "#000000")],
                               rows: ["1A1B1A", "3B"], width: 3, height: 2, gauge: .init())
        let (data, id) = ChartWriter.encode(draft)
        let chart = try Chart.load(data)
        #expect(chart.document.schema == 3 && chart.noStitchIndex == 0)
        #expect(chart.palette.map(\.use) == ["no stitch", nil] && chart.palette.map(\.stitch) == [false, nil])
        let plain = ChartDraft(pattern: draft.pattern, palette: draft.palette.map { .init(code: $0.code, name: $0.name, hex: $0.hex) },
                               rows: draft.rows, width: 3, height: 2, gauge: .init())
        #expect(ChartWriter.encode(plain).id != id)                                   // the id includes it
        #expect(try Chart.load(ChartWriter.encode(plain).data).document.schema == 2)  // a rectangle stays schema 2
        let bytes = ManifestWriter.encode(id: "orca", title: "Orca", version: "0.1.0", dedication: "", chart: chart, chartID: id,
                                          variant: "final", gaugeKey: "sc", palette: draft.palette)
        let m = try JSONDecoder().decode(PatternManifest.self, from: bytes)
        #expect(m.charts.first?.colors == 1 && m.charts.first?.stitches == 4)
    }
}

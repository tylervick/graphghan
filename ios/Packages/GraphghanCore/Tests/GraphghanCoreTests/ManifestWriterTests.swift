import Foundation
import Testing
@testable import GraphghanCore

/// A manifest the phone writes decodes as `PatternManifest` and carries what the library shows.
@Suite struct ManifestWriterTests {
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
}

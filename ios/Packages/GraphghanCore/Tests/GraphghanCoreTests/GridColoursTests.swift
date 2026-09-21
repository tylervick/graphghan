import Foundation
import Testing
@testable import GraphghanCore

/// The colour half of `rasterchart.py`: cells snapped to a known palette, a palette clustered from
/// the cells by frequency, and colour names; held to the Python answers on the fixtures.
@Suite struct GridColoursTests {
    static let palette = ["#f2e8d5", "#2b2f33", "#1e4d3a", "#d9a21b"]

    @Test(arguments: ["one-grid", "two-grids", "symbols"])
    func snappedCellsMatchThePythonAnswer(name: String) throws {
        let (img, answer) = try GridReaderTests.fixture(name)
        let region = try #require(try GridReader.findRegions(img).first)
        let samples = GridReader.readRegion(img, region)
        let cells = try GridColours.snapToPalette(samples, hexes: try #require(answer.palette))
        #expect(cells.map { $0.map(Int.init) } == answer.cells, "\(name)")
    }

    @Test(arguments: ["one-grid", "two-grids", "symbols"])
    func clusteredPaletteMatchesThePythonAnswer(name: String) throws {
        let (img, answer) = try GridReaderTests.fixture(name)
        let region = try #require(try GridReader.findRegions(img).first)
        let (cells, hexes, warnings) = GridColours.clusterPalette(GridReader.readRegion(img, region))
        let want = try #require(answer.cluster)
        #expect(hexes == want.hexes && warnings == want.warnings, "\(name)")
        #expect(cells.map { $0.map(Int.init) } == want.cells, "\(name)")
    }

    @Test func snapRefusesAForeignColourByCell() {
        var samples = [[(UInt8, UInt8, UInt8)]](repeating: [(UInt8, UInt8, UInt8)](repeating: (0xf2, 0xe8, 0xd5), count: 3), count: 2)
        samples[1][2] = (255, 0, 255)
        #expect(throws: GridColoursError.foreignColour(column: 3, row: 2, hex: "#ff00ff", nearest: "#2b2f33", distance: 122)) {
            try GridColours.snapToPalette(samples, hexes: Self.palette)  // the nearest and the distance are the Python's answer
        }
    }

    @Test func clusterOrdersCodesByFrequencyAndFlagsBleed() {
        // Python's test_cluster_orders_codes_by_frequency_and_flags_bleed: 30×30, top ten rows the
        // third colour, one stray cell of the second.
        let rgb = Self.palette.map { GridColours.rgb($0)! }
        var samples = [[(UInt8, UInt8, UInt8)]](repeating: [(UInt8, UInt8, UInt8)](repeating: rgb[0], count: 30), count: 30)
        for y in 0..<10 { for x in 0..<30 { samples[y][x] = rgb[2] } }
        samples[0][0] = rgb[1]
        let (cells, hexes, warnings) = GridColours.clusterPalette(samples)
        #expect(hexes[0] == Self.palette[0] && hexes[1] == Self.palette[2] && hexes[2] == Self.palette[1])
        #expect(cells[15][0] == 0 && cells[5][5] == 1 && cells[0][0] == 2)
        #expect(warnings.first?.contains("1 cell") == true)
    }

    @Test func colourNamesAndCodes() {
        #expect(GridColours.nameColour("#d9a21b") == "gold" && GridColours.nameColour("#ffffff") == "white")
        #expect(GridColours.code(0) == "A" && GridColours.code(25) == "Z" && GridColours.code(26) == "AA" && GridColours.code(27) == "AB")
        #expect(GridColours.hex((0x2b, 0x2f, 0x33)) == "#2b2f33" && GridColours.rgb("#2b2f33")! == (0x2b, 0x2f, 0x33))
    }
}

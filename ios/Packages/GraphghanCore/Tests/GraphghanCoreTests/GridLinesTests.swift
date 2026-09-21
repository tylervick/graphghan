import Foundation
import Testing
@testable import GraphghanCore

/// The line finder's parts against hand-drawn masks (`rasterchart.py` `_close`, `_runs`,
/// `_lines`, `_clusters`, `_pitch`, `_fits`), and the image type against a fixture PNG.
@Suite struct GridLinesTests {
    /// A (rows × cols) mask from strings of "#" and ".".
    static func mask(_ rows: [String]) -> Mask {
        Mask(rows: rows.count, cols: rows[0].count, bits: rows.flatMap { $0.map { $0 == "#" } })
    }

    @Test func aFixturePNGDecodesToRGBBytes() throws {
        let img = try #require(GridImage(png: try Data(contentsOf: Fixtures.grid("one-grid", ext: "png"))))
        #expect(img.width == 80 * 2 + 37 * 24 && img.height == 60 * 2 + 29 * 24)
        #expect(img.pixel(x: 1, y: 1) == (255, 255, 255))  // page white
        #expect(img.rgb.count == img.width * img.height * 3)
        #expect(img.grey().count == img.width * img.height)
        // Orientation: the column numbers are printed above the grid (y = 46..56), nothing below it.
        let white: (UInt8, UInt8, UInt8) = (255, 255, 255)
        #expect((0..<img.width).contains { img.pixel(x: $0, y: 50) != white })
        #expect(!(0..<img.width).contains { img.pixel(x: $0, y: img.height - 1 - 50) != white })
    }

    @Test func closingBridgesGapsUpToTwiceTheRadiusDownAColumn() {
        // Column 0: a run with a 2-pixel gap (bridged at radius 1); column 1: a 3-pixel gap (kept).
        let m = Self.mask(["##", "##", "..", "..", "##", "..", "##", "##"])
        let c = GridLines.close(m, bridge: 1)
        #expect((0..<8).map { c.bits[$0 * 2] } == [true, true, true, true, true, true, true, true])
        let m2 = Self.mask(["#", "#", ".", ".", ".", "#", "#"])
        let c2 = GridLines.close(m2, bridge: 1)
        #expect((0..<7).map { c2.bits[$0] } == [true, true, false, false, false, true, true])
    }

    @Test func runsReportTheLongestAndEverySegmentAtLeastMinPx() {
        // A gap of seven survives the closing (radius 3 bridges up to six); a gap of five would not.
        let m = Self.mask(["#.", "#.", "#.", "..", "..", "..", "..", "..", "..", "..", "#.", "#."])
        let (best, segments) = GridLines.runs(m, minPx: 2)
        #expect(best == [3, 0])
        #expect(segments[0].map { [$0.0, $0.1] } == [[0, 2], [10, 11]] && segments[1].isEmpty)
        let bridged = GridLines.runs(Self.mask(["#", "#", "#", ".", ".", ".", ".", ".", "#", "#"]), minPx: 2)
        #expect(bridged.best == [10] && bridged.segments[0].map { [$0.0, $0.1] } == [[0, 9]])
    }

    @Test func linesMergeNeighbouringColumnsWithinMergePx() {
        // Three long columns at x = 2, 3 (one bold line) and x = 20 (a thin one), 50 rows tall.
        var rows: [String] = []
        for _ in 0..<50 { rows.append(String((0..<30).map { $0 == 2 || $0 == 3 || $0 == 20 ? "#" : "." })) }
        let lines = GridLines.lines(Self.mask(rows), minPx: 40)
        #expect(lines.count == 2)
        #expect(abs(lines[0].centre - 2.5) < 0.01 && abs(lines[1].centre - 20) < 0.01)
        #expect(lines[0].segments.count == 2 && lines[1].segments.map { [$0.0, $0.1] } == [[0, 49]])
    }

    @Test func clustersSplitWhereTheGapJumpsAndPitchIsTheMeanUnitGap() {
        let lines: [GridLines.Line] = [10, 20, 30, 40, 200, 210, 220].map { (centre: Double($0), segments: []) }
        let groups = GridLines.clusters(lines)
        #expect(groups.map { $0.count } == [4, 3])
        #expect(GridLines.pitch([0, 11, 22, 34, 45]) == 11.25)  // gaps 11, 11, 12, 11: the mean, not the median
        #expect(GridLines.pitch([0, 12, 24, 48, 60]) == 12)     // the 24 is a lost line, dropped
        #expect(GridLines.pitch([0, 5]) == nil)
    }

    @Test func aLineFitsAGridWhenASegmentCoversHalfOfItOrLiesHalfInside() {
        #expect(GridLines.fits((centre: 0, segments: [(0, 60)]), lo: 0, hi: 100))
        #expect(GridLines.fits((centre: 0, segments: [(90, 110)]), lo: 0, hi: 100))   // half inside
        #expect(GridLines.fits((centre: 0, segments: [(0, 40)]), lo: 0, hi: 100))     // wholly inside, though short
        #expect(!GridLines.fits((centre: 0, segments: [(90, 200)]), lo: 0, hi: 100))  // mostly outside
    }
}

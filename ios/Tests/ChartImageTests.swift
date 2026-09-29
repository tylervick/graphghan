import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct ChartImageTests {
    @Test func onePixelPerCell() throws {
        let chart = try Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
        let image = try #require(ChartImage.make(chart))
        #expect(image.width == 12 && image.height == 2)
        #expect(ChartImage.rgb("#D9A21B") == (0xD9, 0xA2, 0x1B))
        #expect(HexColor.isLight("#F2E8D5") && !HexColor.isLight("#2B2F33"))
    }

    @Test func theGroundIsClear() throws {
        let chart = try Chart.load(TestFixtures.data("shaped-basic.chart.json"))
        let image = try #require(ChartImage.make(chart))
        #expect(image.alphaInfo == .premultipliedLast)
        let bytes = try #require(image.dataProvider?.data as Data?)
        #expect(bytes[3] == 0 && bytes[2 * 4 + 3] == 255)   // (0, 0) the ground, (2, 0) a stitch
    }
}

import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct ChartImageTests {
    @Test func onePixelPerCell() throws {
        let chart = try Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
        let image = try #require(ChartImage.make(chart))
        #expect(image.width == 12 && image.height == 2)
        #expect(ChartImage.rgb("#D9A21B") == (0xD9, 0xA2, 0x1B))
        #expect(ChartImage.isLight("#F2E8D5") && !ChartImage.isLight("#2B2F33"))
    }
}

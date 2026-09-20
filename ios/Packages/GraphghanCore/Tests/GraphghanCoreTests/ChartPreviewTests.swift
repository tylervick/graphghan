import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GraphghanCore

@Suite struct ChartPreviewTests {
    @Test func aPreviewIsAPNGOfTheRightShape() throws {
        let draft = ChartDraft(pattern: .init(id: "t", title: "T", version: "0.1.0"),
                               palette: [.init(code: "A", name: "black", hex: "#000000"), .init(code: "B", name: "white", hex: "#ffffff")],
                               rows: ["2A1B", "3B"], width: 3, height: 2, gauge: .init())
        let chart = try Chart.load(ChartWriter.encode(draft).data)
        let png = try #require(ChartPreview.png(chart, maxSide: 300))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let (w, h) = ChartPreview.size(width: 3, height: 2, aspect: chart.cellAspect, maxSide: 300)
        #expect(image.width == w && image.height == h && w == 300)
        #expect(CGImageSourceGetType(source) as String? == "public.png")
        // The top-left cell is black, the bottom-right white.
        let bytes = try #require(image.dataProvider?.data as Data?)
        #expect(bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0)
        let lastPixel = (h - 1) * image.bytesPerRow + (w - 1) * 4
        #expect(bytes[lastPixel] == 255 && bytes[lastPixel + 1] == 255)
    }

    @Test func aSmallChartIsNotScaledBelowOnePixelPerCell() {
        let (w, h) = ChartPreview.size(width: 1000, height: 10, aspect: 1, maxSide: 300)
        #expect(w == 1000 && h == 10)
    }
}

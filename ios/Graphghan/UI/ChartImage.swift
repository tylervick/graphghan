import CoreGraphics
import SwiftUI
import GraphghanCore

enum ChartImage {
    static func rgb(_ hex: String) -> (r: UInt8, g: UInt8, b: UInt8) {
        let c = HexColor.rgb(hex)
        return (UInt8(c.r * 255), UInt8(c.g * 255), UInt8(c.b * 255))
    }

    static func color(_ hex: String) -> Color { HexColor.color(hex) }

    /// One pixel per cell, RGBA premultiplied, top row first; a shaped piece's ground is clear.
    /// Scale it with nearest-neighbour to keep cells crisp.
    static func make(_ chart: Chart) -> CGImage? {
        guard let bytes = ChartPreview.pixels(chart), let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: chart.width, height: chart.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: chart.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

import CoreGraphics
import SwiftUI
import GraphghanCore

enum ChartImage {
    static func rgb(_ hex: String) -> (r: UInt8, g: UInt8, b: UInt8) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return (0x88, 0x88, 0x88) }
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    static func color(_ hex: String) -> Color {
        let c = rgb(hex)
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// Same rule as the PWA: perceived luminance under 140 gets white text.
    static func isLight(_ hex: String) -> Bool {
        let c = rgb(hex)
        return (Double(c.r) * 299 + Double(c.g) * 587 + Double(c.b) * 114) / 1000 >= 140
    }

    /// One pixel per cell, RGBA, top row first. Scale it with nearest-neighbour to keep cells crisp.
    static func make(_ chart: Chart) -> CGImage? {
        let palette = chart.palette.map { rgb($0.hex) }
        var bytes = [UInt8](repeating: 255, count: chart.width * chart.height * 4)
        for (i, cell) in chart.cells.enumerated() {
            let c = palette[Int(cell)]
            bytes[i * 4] = c.r; bytes[i * 4 + 1] = c.g; bytes[i * 4 + 2] = c.b
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: chart.width, height: chart.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: chart.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

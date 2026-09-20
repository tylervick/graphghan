import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The library preview of a chart the phone imported: one pixel per cell, nearest-neighbour
/// scaled, rows at the fabric's proportion (`export.py` `preview_image`).
public enum ChartPreview {
    public static func png(_ chart: Chart, maxSide: Int = 512) -> Data? {
        let w = chart.width
        let h = chart.height
        guard w > 0, h > 0, chart.cells.count == w * h else { return nil }
        let rgb: [(UInt8, UInt8, UInt8)] = chart.palette.map { entry in
            let v = UInt32(entry.hex.dropFirst(), radix: 16) ?? 0
            return (UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff))
        }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let index = Int(chart.cells[i])
            let p = index < rgb.count ? rgb[index] : (0, 0, 0)
            pixels[i * 4] = p.0
            pixels[i * 4 + 1] = p.1
            pixels[i * 4 + 2] = p.2
            pixels[i * 4 + 3] = 255
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cells = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent)
        else { return nil }
        let (outW, outH) = size(width: w, height: h, aspect: chart.cellAspect, maxSide: maxSide)
        guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: info.rawValue)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cells, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// The pixel size: the long side at most `maxSide`, never below one pixel per cell, rows at
    /// `aspect` times a cell's width.
    public static func size(width w: Int, height h: Int, aspect: Double, maxSide: Int) -> (Int, Int) {
        let scale = max(1, min(Double(maxSide) / Double(w), Double(maxSide) / (Double(h) * aspect)))
        return (max(w, Int((Double(w) * scale).rounded())), max(1, Int((Double(h) * aspect * scale).rounded())))
    }
}

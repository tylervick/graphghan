import CoreGraphics
import Foundation
import ImageIO

/// An RGB byte image the grid reader works on: what PDFKit rendered a page to, or a fixture PNG.
/// Row-major, three bytes a pixel; `MAX_PIXELS` (`GridReader.maxPixels`) bounds it.
public struct GridImage: Sendable {
    public let width: Int
    public let height: Int
    public let rgb: [UInt8]

    public init(width: Int, height: Int, rgb: [UInt8]) {
        precondition(rgb.count == width * height * 3)
        self.width = width
        self.height = height
        self.rgb = rgb
    }

    /// A PNG (or any image ImageIO reads) as RGB bytes, alpha dropped over white.
    public init?(png data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(cgImage: image)
    }

    public init?(cgImage image: CGImage) {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let drawn = rgba.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: info) else { return false }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        // A bitmap context's first row in memory is the top of what was drawn, so the bytes are
        // already top-down like the Python array; the orientation test in GridLinesTests holds this.
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgb[i * 3] = rgba[i * 4]
            rgb[i * 3 + 1] = rgba[i * 4 + 1]
            rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        self.init(width: w, height: h, rgb: rgb)
    }

    public func pixel(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 3
        return (rgb[i], rgb[i + 1], rgb[i + 2])
    }

    /// Pillow's "L": `0.299 R + 0.587 G + 0.114 B`, rounded to a byte, as a Float per pixel.
    public func grey() -> [Float] {
        var out = [Float](repeating: 0, count: width * height)
        rgb.withUnsafeBufferPointer { p in
            out.withUnsafeMutableBufferPointer { o in
                for i in 0..<(width * height) {
                    let v = 0.299 * Double(p[i * 3]) + 0.587 * Double(p[i * 3 + 1]) + 0.114 * Double(p[i * 3 + 2])
                    o[i] = Float(Int(v + 0.5))
                }
            }
        }
        return out
    }
}

/// A boolean (rows × cols) array, row-major: the Python `mask` of shape (n, m).
struct Mask: Sendable {
    let rows: Int
    let cols: Int
    var bits: [Bool]

    init(rows: Int, cols: Int, bits: [Bool]) {
        precondition(bits.count == rows * cols)
        self.rows = rows
        self.cols = cols
        self.bits = bits
    }

    init(rows: Int, cols: Int) { self.init(rows: rows, cols: cols, bits: [Bool](repeating: false, count: rows * cols)) }

    subscript(y: Int, x: Int) -> Bool {
        get { bits[y * cols + x] }
        set { bits[y * cols + x] = newValue }
    }

    func transposed() -> Mask {
        var out = Mask(rows: cols, cols: rows)
        for y in 0..<rows { for x in 0..<cols where bits[y * cols + x] { out.bits[x * rows + y] = true } }
        return out
    }
}

import CoreGraphics
import Foundation
import GraphghanCore
import PDFKit

/// A PDF page as the grid reader's image, under the render budget (phone import spec §5.1): the
/// importer's 4× (288 dpi, a 10 pt cell is 40 px), halved until the bitmap is at most
/// `GridReader.maxPixels`; a page over the budget at 1× is not rendered.
enum PageRenderer {
    static let renderScale: CGFloat = 4  // RENDER_SCALE

    static func scale(for box: CGRect) -> CGFloat? {
        var s = renderScale
        while s >= 1 {
            if Double(box.width * s) * Double(box.height * s) <= Double(GridReader.maxPixels) { return s }
            s /= 2
        }
        return nil
    }

    static func image(_ page: PDFPage) -> GridImage? {
        let box = page.bounds(for: .mediaBox)
        guard let scale = scale(for: box) else { return nil }
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard w > 0, h > 0 else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage() else { return nil }
        return GridImage(cgImage: image)
    }
}

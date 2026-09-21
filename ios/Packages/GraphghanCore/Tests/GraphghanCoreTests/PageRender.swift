import CoreGraphics
import Foundation
import PDFKit
@testable import GraphghanCore

/// PDFKit on macOS rendering a page for the tests, the way the app's `PageRenderer` will on iOS.
enum PageRender {
    struct Header { let cols: Int; let rows: Int; let colFrom: Int; let colTo: Int; let rowFrom: Int; let rowTo: Int }

    static let headerRe = try! NSRegularExpression(pattern: #"^Chart (\d+) of (\d+): columns (\d+)-(\d+) of (\d+), rows (\d+)-(\d+) of (\d+)"#)

    /// The first page whose text starts with the own-PDF chart header, and the cells it declares.
    static func firstChartPage(_ doc: PDFDocument) -> (PDFPage, Header)? {
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let text = page.string else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let m = headerRe.firstMatch(in: text, range: range) else { continue }
            func n(_ k: Int) -> Int { Int(text[Range(m.range(at: k), in: text)!])! }
            return (page, Header(cols: n(4) - n(3) + 1, rows: n(7) - n(6) + 1, colFrom: n(3), colTo: n(4), rowFrom: n(6), rowTo: n(7)))
        }
        return nil
    }

    static func image(_ page: PDFPage, scale: CGFloat) -> GridImage? {
        let box = page.bounds(for: .mediaBox)
        let w = Int(box.width * scale), h = Int(box.height * scale)
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

import Foundation
import PDFKit
import Testing
@testable import GraphghanCore

/// `find_regions` on the images Python drew, held to the answers it recorded
/// (`fixtures/import/grid/<name>.json`), and on our own PDF's chart page rendered by PDFKit.
@Suite struct GridReaderTests {
    struct Answer: Decodable {
        struct R: Decodable { let cols: Int; let rows: Int; let pitch: [Double]; let bbox: [Int]; let noise: Double }
        struct Cluster: Decodable { let hexes: [String]; let warnings: [String]; let cells: [[Int]] }
        let regions: [R]
        let palette: [String]?
        let cells: [[Int]]?
        let cluster: Cluster?
    }

    static func fixture(_ name: String) throws -> (GridImage, Answer) {
        let img = try #require(GridImage(png: try Data(contentsOf: Fixtures.grid(name, ext: "png"))))
        let answer = try JSONDecoder().decode(Answer.self, from: try Data(contentsOf: Fixtures.grid(name, ext: "json")))
        return (img, answer)
    }

    static func expectSame(_ got: [Region], _ want: [Answer.R], _ name: String) {
        #expect(got.count == want.count, "\(name): \(got.map { $0.describe() })")
        for (g, w) in zip(got, want) {
            #expect(g.cols == w.cols && g.rows == w.rows, "\(name): \(g.describe())")
            #expect(abs(g.pitch.0 - w.pitch[0]) < 0.05 && abs(g.pitch.1 - w.pitch[1]) < 0.05, "\(name): pitch \(g.pitch) vs \(w.pitch)")
            let b = g.bbox
            #expect(abs(b.0 - w.bbox[0]) <= 1 && abs(b.1 - w.bbox[1]) <= 1 && abs(b.2 - w.bbox[2]) <= 1 && abs(b.3 - w.bbox[3]) <= 1, "\(name): bbox \(b) vs \(w.bbox)")
            #expect(abs(g.noise - w.noise) < 0.05, "\(name): noise \(g.noise) vs \(w.noise)")
        }
    }

    @Test(arguments: ["one-grid", "two-grids", "symbols", "text-page"])
    func regionsMatchThePythonAnswer(name: String) throws {
        let (img, answer) = try Self.fixture(name)
        let started = Date()
        let regions = try GridReader.findRegions(img)
        print("GridReader.findRegions \(name) \(img.width)x\(img.height): \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        Self.expectSame(regions, answer.regions, name)
    }

    /// Python's test_a_photo_is_not_a_chart: noise under a fence of lines every 30 px. The noise is
    /// this test's own (numpy's generator is not reproduced), so only "no grid" is asserted.
    @Test func aPhotoUnderAFenceOfLinesIsNotAChart() throws {
        var rgb = [UInt8](repeating: 0, count: 600 * 600 * 3)
        var seed: UInt32 = 1
        for i in rgb.indices { seed = seed &* 1_664_525 &+ 1_013_904_223; rgb[i] = UInt8(truncatingIfNeeded: seed >> 24) }
        for y in 0..<600 { for x in 0..<600 where x % 30 < 2 || y % 30 < 2 { let i = (y * 600 + x) * 3; rgb[i] = 0; rgb[i + 1] = 0; rgb[i + 2] = 0 } }
        #expect(try GridReader.findRegions(GridImage(width: 600, height: 600, rgb: rgb)).isEmpty)
    }

    @Test func anOversizedImageIsRefused() {
        let img = GridImage(width: 8000, height: 6000, rgb: [UInt8](repeating: 255, count: 8000 * 6000 * 3))
        #expect(throws: GridReaderError.tooLarge(width: 8000, height: 6000)) { try GridReader.findRegions(img) }
    }

    /// Our own PDF's first chart page says which columns and rows it holds; the grid reader must
    /// find exactly that many cells on PDFKit's render (the Python does the same on pdfium's).
    @Test func theOwnPDFsChartPageReadsToItsHeader() throws {
        let doc = try #require(PDFDocument(url: Fixtures.importPDF("craigh-na-dun-final-sc")))
        let (page, header) = try #require(PageRender.firstChartPage(doc))
        let img = try #require(PageRender.image(page, scale: 4))
        let started = Date()
        let regions = try GridReader.findRegions(img)
        print("GridReader.findRegions craigh page \(img.width)x\(img.height): \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        let r = try #require(regions.first)
        #expect(r.cols == header.cols && r.rows == header.rows, "\(r.describe())")
        #expect(r.noise < GridReader.maxNoise)
    }
}

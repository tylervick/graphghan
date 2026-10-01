import Foundation
import Testing
@testable import GraphghanCore

/// A written-rows document the phone writes decodes back as `RowsDocument`, with the same id.
@Suite struct RowsWriterTests {
    @Test func aWrittenDocumentLoadsBackWithTheSameID() throws {
        let entries = [RowsDocument.Entry(label: "R 1", from: 1, to: 1, text: "(Black) ch 7, 6 sc [6]", count: 6, code: "A", repeatText: nil),
                       RowsDocument.Entry(label: "R 2 - R 26", from: 2, to: 26, text: "ch 1, turn, 6 sc [6]", count: 6, code: nil, repeatText: nil)]
        let (data, id) = RowsWriter.encode(title: "Side Panel", palette: [.init(code: "A", name: "black", hex: "#201b18")], entries: entries, pages: [10])
        let doc = try RowsDocument.load(data)
        #expect(doc.id == id && doc.title == "Side Panel" && doc.entries == entries && doc.pages == [10])
    }

    @Test func theIDMatchesTheFixtureThePythonWrote() throws {
        let fixture = try RowsDocument.load(Fixtures.pieces("pieces/strip.rows.json"))
        let palette = fixture.palette.map { ChartDraft.Palette(code: $0.code, name: $0.name, hex: $0.hex) }
        let (data, id) = RowsWriter.encode(title: fixture.title, palette: palette, entries: fixture.entries, pages: fixture.pages)
        #expect(id == fixture.id)
        #expect(try RowsDocument.load(data) == fixture)
    }
}

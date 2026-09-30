import Foundation
import Testing
@testable import GraphghanCore

@Suite struct RowsDocumentTests {
    @Test(arguments: ["pieces/strip.rows.json", "pieces/fin.rows.json", "pieces/strap.rows.json"])
    func everyFixtureRowsDocumentLoads(_ path: String) throws {
        let doc = try RowsDocument.load(Fixtures.pieces(path))
        #expect(doc.id == RowsDocument.computeID(doc.entries))
    }

    @Test func theStripReadsAsPrinted() throws {
        let doc = try RowsDocument.load(Fixtures.pieces("pieces/strip.rows.json"))
        #expect(doc.title == "Strip" && doc.entries.count == 3 && doc.pages == [3])
        #expect(doc.entries[1] == .init(label: "R 2 - R 4", from: 2, to: 4, text: "ch 1, turn, 6 sc [6]", count: 6, code: nil, repeatText: nil))
    }

    @Test func theIDMatchesThePythons() throws {
        // The Python wrote each fixture's id with rowsdoc.rows_id; the Swift id must agree byte for byte.
        let raw = try JSONSerialization.jsonObject(with: Fixtures.pieces("pieces/strap.rows.json")) as! [String: Any]
        let doc = try RowsDocument.load(Fixtures.pieces("pieces/strap.rows.json"))
        #expect(RowsDocument.computeID(doc.entries) == raw["id"] as? String)
    }

    @Test func theRefusalFixturesAreRefused() throws {
        let dir = Fixtures.directory.appendingPathComponent("refused")
        #expect(throws: RowsError.gap(row: 2)) { try RowsDocument.load(Data(contentsOf: dir.appendingPathComponent("rows-gap.rows.json"))) }
        #expect(throws: RowsError.openNotLast(entry: 0)) { try RowsDocument.load(Data(contentsOf: dir.appendingPathComponent("rows-open-not-last.rows.json"))) }
    }
}

import Testing
@testable import GraphghanCore

@Suite struct WrittenSequenceTests {
    static func seq(_ path: String) throws -> WrittenSequence { WrittenSequence(try RowsDocument.load(Fixtures.pieces(path))) }

    @Test func aRangeIsOnePassPerRow() throws {
        let s = try Self.seq("pieces/strip.rows.json")
        #expect(s.totalRows == 5 && !s.isOpen && s.totalStitches == 30)
        #expect(s.pass(at: 1)?.label == "R 1")
        #expect(s.pass(at: 3) == WrittenPass(label: "R 2 - R 4 (2 of 3)", text: "ch 1, turn, 6 sc [6]", count: 6, code: nil, entry: 1))
        #expect(s.pass(at: 6) == nil && s.pass(at: 0) == nil)
        #expect(s.stitchesBefore(row: 3) == 12)
    }

    /// Review focus 3: an open-ended piece has no total anywhere.
    @Test func openEndedHasNoTotal() throws {
        let s = try Self.seq("pieces/strap.rows.json")
        #expect(s.isOpen && s.totalRows == nil && s.totalStitches == nil)
        #expect(s.pass(at: 57)?.label == "2. (56)")
        #expect(s.rowsDone(at: 10, finished: false) == 9 && s.rowsDone(at: 10, finished: true) == 10)
    }

    @Test func aMissingCountWithholdsStitches() throws {
        let s = try Self.seq("pieces/fin.rows.json")
        #expect(s.totalRows == 3 && s.totalStitches == nil && s.stitchesBefore(row: 2) == nil)
        #expect(s.rowsDone(at: 3, finished: true) == 3)
    }
}

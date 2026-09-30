import Testing
@testable import GraphghanCore

@Suite struct WrittenEngineTests {
    static let strip = try! WrittenSequence(RowsDocument.load(Fixtures.pieces("pieces/strip.rows.json")))
    static let strap = try! WrittenSequence(RowsDocument.load(Fixtures.pieces("pieces/strap.rows.json")))

    @Test func advanceMovesOneRow() {
        let step = WrittenEngine.apply(.advance, to: Cursor(row: 2, run: 0), in: Self.strip)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 0), kind: .advance, startedNewRow: true, finished: false))
    }

    @Test func doneOnTheLastRowFinishesAndStays() {
        let step = WrittenEngine.apply(.advance, to: Cursor(row: 5, run: 0), in: Self.strip)
        #expect(step == WorkStep(cursor: Cursor(row: 5, run: 0), kind: .advance, startedNewRow: false, finished: true))
    }

    /// Review focus 1: Back after the finishing Done stays on the last row (the service un-finishes the piece).
    @Test func backAfterFinishingStaysOnTheLastRow() {
        let step = WrittenEngine.apply(.back, to: Cursor(row: 5, run: 0), in: Self.strip, finished: true)
        #expect(step == WorkStep(cursor: Cursor(row: 5, run: 0), kind: .back, startedNewRow: false, finished: false))
        #expect(WrittenEngine.apply(.back, to: Cursor(row: 5, run: 0), in: Self.strip)?.cursor == Cursor(row: 4, run: 0))
        #expect(WrittenEngine.apply(.back, to: Cursor(row: 1, run: 0), in: Self.strip) == nil)
    }

    @Test func jumpStaysInsideAClosedPiece() {
        #expect(WrittenEngine.apply(.jump(row: 4), to: Cursor(row: 1, run: 0), in: Self.strip)?.cursor == Cursor(row: 4, run: 0))
        #expect(WrittenEngine.apply(.jump(row: 9), to: Cursor(row: 1, run: 0), in: Self.strip) == nil)
    }

    @Test func anOpenPieceNeverFinishesOnDone() {
        let step = WrittenEngine.apply(.advance, to: Cursor(row: 400, run: 0), in: Self.strap)
        #expect(step?.cursor == Cursor(row: 401, run: 0) && step?.finished == false)
        #expect(WrittenEngine.apply(.jump(row: 1000), to: Cursor(row: 1, run: 0), in: Self.strap)?.cursor.row == 1000)
    }
}

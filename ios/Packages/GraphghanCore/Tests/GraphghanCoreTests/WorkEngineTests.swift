import Testing
@testable import GraphghanCore

@Suite struct WorkEngineTests {
    // 12 passes; rows 1,2,11,12 have 1 run; rows 3-10 have 3 runs.
    static let seq = try! WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))

    @Test func advanceWithinRow() {
        let step = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 0), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 1), kind: .advance, startedNewRow: false, finished: false))
    }

    @Test func advanceAcrossRow() {
        let step = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 2), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 4, run: 0), kind: .advance, startedNewRow: true, finished: false))
        #expect(WorkEngine.apply(.advance, to: .start, in: Self.seq)?.cursor == Cursor(row: 2, run: 0))
    }

    @Test func advanceAtTheEndFinishes() {
        let last = Cursor(row: 12, run: 0)
        let step = WorkEngine.apply(.advance, to: last, in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 12, run: 1), kind: .advance, startedNewRow: false, finished: true))
        #expect(WorkEngine.isFinished(Cursor(row: 12, run: 1), in: Self.seq))
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 12, run: 1), in: Self.seq) == nil)
    }

    @Test func backWithinAndAcrossRows() {
        #expect(WorkEngine.apply(.back, to: Cursor(row: 3, run: 2), in: Self.seq)?.cursor == Cursor(row: 3, run: 1))
        let step = WorkEngine.apply(.back, to: Cursor(row: 4, run: 0), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 2), kind: .back, startedNewRow: false, finished: false))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 12, run: 1), in: Self.seq)?.cursor == Cursor(row: 12, run: 0))
    }

    @Test func backAtTheStartIsNoOp() {
        #expect(WorkEngine.apply(.back, to: .start, in: Self.seq) == nil)
    }

    @Test func jump() {
        #expect(WorkEngine.apply(.jump(row: 7), to: .start, in: Self.seq) == WorkStep(cursor: Cursor(row: 7, run: 0), kind: .jump, startedNewRow: true, finished: false))
        #expect(WorkEngine.apply(.jump(row: 0), to: .start, in: Self.seq) == nil)
        #expect(WorkEngine.apply(.jump(row: 13), to: .start, in: Self.seq) == nil)
        // jumping within the current row (tapping a chip) is not a new row
        #expect(WorkEngine.apply(.jump(row: 3, run: 2), to: Cursor(row: 3, run: 0), in: Self.seq)
            == WorkStep(cursor: Cursor(row: 3, run: 2), kind: .jump, startedNewRow: false, finished: false))
        #expect(WorkEngine.apply(.jump(row: 3, run: 3), to: .start, in: Self.seq) == nil)  // run == runs.count only via advance
    }

    @Test func invalidCursorIsRejected() {
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 99, run: 0), in: Self.seq) == nil)
        #expect(WorkEngine.apply(.back, to: Cursor(row: 3, run: 9), in: Self.seq) == nil)
    }
}

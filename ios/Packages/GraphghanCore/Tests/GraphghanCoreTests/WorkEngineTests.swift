import Testing
@testable import GraphghanCore

@Suite struct WorkEngineTests {
    // 12 passes (rows, so every pass but the last has a boundary step); rows 1,2,11,12 have one run of 14;
    // rows 3-10 have 2A 10B 2A. No run reaches 20, so nothing counts.
    static let seq = try! WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))
    // Craigh na Dun row 42 (ltr): run 10 is 117 C, a fill.
    static let craigh = try! WorkSequence(chart: Chart.load(Fixtures.data("craigh-na-dun.chart.json")))
    static let fill = Cursor(row: 42, run: 10)

    @Test func advanceWithinRow() {
        let step = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 0), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 1), kind: .advance, startedNewRow: false, finished: false))
    }

    @Test func advanceReachesTheBoundaryThenTheNextRow() {
        let toBoundary = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 2), in: Self.seq)
        #expect(toBoundary == WorkStep(cursor: Cursor(row: 3, run: 3), kind: .advance, startedNewRow: false, finished: false, atBoundary: true))
        let turned = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 3), in: Self.seq)
        #expect(turned == WorkStep(cursor: Cursor(row: 4, run: 0), kind: .advance, startedNewRow: true, finished: false))
        #expect(WorkEngine.apply(.advance, to: .start, in: Self.seq)?.cursor == Cursor(row: 1, run: 1))
    }

    @Test func roundsHaveNoBoundaryStep() throws {
        let rounds = try WorkSequence(chart: Chart.load(Fixtures.data("minimal-rounds.chart.json")))
        let last = rounds.passes[0].runs.count - 1
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 1, run: last), in: rounds)?.cursor == Cursor(row: 2, run: 0))
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
        // from a row's first run, Back returns to the previous row's boundary position
        let step = WorkEngine.apply(.back, to: Cursor(row: 4, run: 0), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 3), kind: .back, startedNewRow: false, finished: false, atBoundary: true))
        // and from the boundary to the row's last run
        #expect(WorkEngine.apply(.back, to: Cursor(row: 3, run: 3), in: Self.seq)?.cursor == Cursor(row: 3, run: 2))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 12, run: 1), in: Self.seq)?.cursor == Cursor(row: 12, run: 0))
    }

    @Test func backAtTheStartIsNoOp() {
        #expect(WorkEngine.apply(.back, to: .start, in: Self.seq) == nil)
    }

    @Test func jump() {
        #expect(WorkEngine.apply(.jump(row: 7), to: .start, in: Self.seq) == WorkStep(cursor: Cursor(row: 7, run: 0), kind: .jump, startedNewRow: true, finished: false))
        #expect(WorkEngine.apply(.jump(row: 0), to: .start, in: Self.seq) == nil)
        #expect(WorkEngine.apply(.jump(row: 13), to: .start, in: Self.seq) == nil)
        #expect(WorkEngine.apply(.jump(row: 3, run: 2), to: Cursor(row: 3, run: 0), in: Self.seq)
            == WorkStep(cursor: Cursor(row: 3, run: 2), kind: .jump, startedNewRow: false, finished: false))
        #expect(WorkEngine.apply(.jump(row: 3, run: 3), to: .start, in: Self.seq) == nil)  // the boundary is reached only by advancing
        // a stitch offset on a run that is not a fill is ignored
        #expect(WorkEngine.apply(.jump(row: 3, run: 1, stitch: 4), to: .start, in: Self.seq)?.cursor == Cursor(row: 3, run: 1))
    }

    @Test func fillCountsByTheStep() {
        #expect(WorkEngine.isCounting(Self.fill, in: Self.craigh))
        #expect(!WorkEngine.isCounting(Cursor(row: 42, run: 8), in: Self.craigh))
        let ten = WorkEngine.apply(.advance, to: Self.fill, in: Self.craigh, step: .ten)
        #expect(ten?.cursor == Cursor(row: 42, run: 10, stitch: 10) && ten?.startedNewRow == false)
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 42, run: 10, stitch: 110), in: Self.craigh, step: .ten)?.cursor == Cursor(row: 42, run: 11))  // 120 ≥ 117
        #expect(WorkEngine.apply(.advance, to: Self.fill, in: Self.craigh, step: .wholeRun)?.cursor == Cursor(row: 42, run: 11))
        #expect(WorkEngine.apply(.advance, to: Self.fill, in: Self.craigh, step: .one)?.cursor == Cursor(row: 42, run: 10, stitch: 1))
    }

    @Test(arguments: CountStep.allCases) func advanceAndBackAreInversesAlongAFill(_ step: CountStep) {
        var forward: [Cursor] = [Self.fill]
        while let s = WorkEngine.apply(.advance, to: forward.last!, in: Self.craigh, step: step), s.cursor.run == 10 { forward.append(s.cursor) }
        let afterFill = WorkEngine.apply(.advance, to: forward.last!, in: Self.craigh, step: step)!.cursor
        #expect(afterFill == Cursor(row: 42, run: 11))
        var back = afterFill
        for expected in forward.reversed() {
            back = WorkEngine.apply(.back, to: back, in: Self.craigh, step: step)!.cursor
            #expect(back == expected)
        }
        #expect(WorkEngine.stride(step, for: Self.craigh.pass(at: 42)!.runs[10]) == (step == .wholeRun ? 117 : step.rawValue))
    }

    @Test func backIntoAFillLandsOnItsLastStep() {
        #expect(WorkEngine.apply(.back, to: Cursor(row: 42, run: 11), in: Self.craigh, step: .ten)?.cursor == Cursor(row: 42, run: 10, stitch: 110))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 42, run: 11), in: Self.craigh, step: .wholeRun)?.cursor == Cursor(row: 42, run: 10))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 42, run: 11), in: Self.craigh, step: .one)?.cursor == Cursor(row: 42, run: 10, stitch: 116))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 42, run: 10, stitch: 10), in: Self.craigh, step: .ten)?.cursor == Self.fill)
    }

    @Test func jumpIntoAFillRoundsDownToTheStep() {
        #expect(WorkEngine.apply(.jump(row: 42, run: 10, stitch: 47), to: .start, in: Self.craigh, step: .ten)?.cursor == Cursor(row: 42, run: 10, stitch: 40))
        #expect(WorkEngine.apply(.jump(row: 42, run: 10, stitch: 47), to: .start, in: Self.craigh, step: .wholeRun)?.cursor == Self.fill)
        #expect(WorkEngine.apply(.jump(row: 42, run: 10, stitch: 117), to: .start, in: Self.craigh) == nil)
    }

    @Test func invalidCursorIsRejected() {
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 99, run: 0), in: Self.seq) == nil)
        #expect(WorkEngine.apply(.back, to: Cursor(row: 3, run: 9), in: Self.seq) == nil)
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 3, run: 0, stitch: 2), in: Self.seq) == nil)  // 2A has no stitch 2
        #expect(WorkEngine.apply(.jump(row: 1), to: Cursor(row: 99, run: 0), in: Self.seq) == nil)
    }

    @Test func emptySequenceIsNeverFinished() {
        #expect(!WorkEngine.isFinished(.start, in: WorkSequence(passes: [])))
    }
}

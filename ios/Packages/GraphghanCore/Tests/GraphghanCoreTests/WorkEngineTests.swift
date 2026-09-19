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
        #expect(turned == WorkStep(cursor: Cursor(row: 4, run: 0), kind: .advance, startedNewRow: true, finished: false, runsWalked: 0))
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
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 3), kind: .back, startedNewRow: false, finished: false, atBoundary: true, runsWalked: 0))
        // and from the boundary to the row's last run
        #expect(WorkEngine.apply(.back, to: Cursor(row: 3, run: 3), in: Self.seq)?.cursor == Cursor(row: 3, run: 2))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 12, run: 1), in: Self.seq)?.cursor == Cursor(row: 12, run: 0))
    }

    @Test func backAtTheStartIsNoOp() {
        #expect(WorkEngine.apply(.back, to: .start, in: Self.seq) == nil)
    }

    @Test func jump() {
        #expect(WorkEngine.apply(.jump(row: 7), to: .start, in: Self.seq) == WorkStep(cursor: Cursor(row: 7, run: 0), kind: .jump, startedNewRow: true, finished: false, runsWalked: 0))
        #expect(WorkEngine.apply(.jump(row: 0), to: .start, in: Self.seq) == nil)
        #expect(WorkEngine.apply(.jump(row: 13), to: .start, in: Self.seq) == nil)
        #expect(WorkEngine.apply(.jump(row: 3, run: 2), to: Cursor(row: 3, run: 0), in: Self.seq)
            == WorkStep(cursor: Cursor(row: 3, run: 2), kind: .jump, startedNewRow: false, finished: false, runsWalked: 0))
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

    // MARK: repeats (#81)

    // Craigh na Dun Row 178: runs 0-2 plain, then `1G 3Y 1G 2Y` ×22 (runs 3..<91), then four plain runs.
    // Row 179: four plain runs, then `5Y 2G` ×22 (runs 4..<48), then five plain runs.
    static let rep178 = Segments.of(craigh.pass(at: 178)!).first { $0.kind == .repeat }!

    /// Taps from a row's first run to its boundary position.
    private static func tapsToTheTurn(row: Int, perRepetition: Bool) -> Int {
        var cursor = Cursor(row: row, run: 0)
        var taps = 0
        while let step = WorkEngine.apply(.advance, to: cursor, in: craigh, perRepetition: perRepetition), !step.atBoundary {
            cursor = step.cursor; taps += 1
            precondition(cursor.row == row)
        }
        return taps + 1
    }

    @Test func aTapPerRepetitionCutsTheBorderRows() {
        #expect(Self.rep178.period == 4 && Self.rep178.repetitions == 22 && Self.rep178.runs == 3..<91)
        #expect(Self.tapsToTheTurn(row: 178, perRepetition: true) == 29)
        #expect(Self.tapsToTheTurn(row: 178, perRepetition: false) == 95)
        #expect(Self.tapsToTheTurn(row: 179, perRepetition: true) == 31)
        #expect(Self.tapsToTheTurn(row: 179, perRepetition: false) == 53)
    }

    @Test func advanceWalksOneRepetition() {
        // from the first run of repetition 1 to the first run of repetition 2, four runs on
        let step = WorkEngine.apply(.advance, to: Cursor(row: 178, run: 3), in: Self.craigh)
        #expect(step == WorkStep(cursor: Cursor(row: 178, run: 7), kind: .advance, startedNewRow: false, finished: false, runsWalked: 4))
        // a partial repetition (after a jump onto its third run) still lands on the next one's first run
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 178, run: 5), in: Self.craigh)?.cursor == Cursor(row: 178, run: 7))
        // the last repetition leaves the segment
        let last = WorkEngine.apply(.advance, to: Cursor(row: 178, run: 87), in: Self.craigh)
        #expect(last == WorkStep(cursor: Cursor(row: 178, run: 91), kind: .advance, startedNewRow: false, finished: false, runsWalked: 4))
        // the run before the segment is an ordinary tap into it
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 178, run: 2), in: Self.craigh) == WorkStep(cursor: Cursor(row: 178, run: 3), kind: .advance, startedNewRow: false, finished: false))
        // off: one run, as before
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 178, run: 3), in: Self.craigh, perRepetition: false)?.cursor == Cursor(row: 178, run: 4))
    }

    @Test func backReturnsToTheStartOfTheRepetitionBefore() {
        // from the first run of repetition 2 to the first run of repetition 1
        #expect(WorkEngine.apply(.back, to: Cursor(row: 178, run: 7), in: Self.craigh) == WorkStep(cursor: Cursor(row: 178, run: 3), kind: .back, startedNewRow: false, finished: false, runsWalked: 4))
        // from inside a repetition, to its own start
        #expect(WorkEngine.apply(.back, to: Cursor(row: 178, run: 9), in: Self.craigh)?.cursor == Cursor(row: 178, run: 7))
        // from the run after the segment, to the last repetition's start
        #expect(WorkEngine.apply(.back, to: Cursor(row: 178, run: 91), in: Self.craigh)?.cursor == Cursor(row: 178, run: 87))
        // from the first repetition's start, the ordinary run before the segment
        #expect(WorkEngine.apply(.back, to: Cursor(row: 178, run: 3), in: Self.craigh) == WorkStep(cursor: Cursor(row: 178, run: 2), kind: .back, startedNewRow: false, finished: false))
        // off: one run
        #expect(WorkEngine.apply(.back, to: Cursor(row: 178, run: 7), in: Self.craigh, perRepetition: false)?.cursor == Cursor(row: 178, run: 6))
    }

    @Test func advanceAndBackAreInversesAlongARepeat() {
        var cursor = Cursor(row: 178, run: 0)
        var forward: [Cursor] = [cursor]
        while let step = WorkEngine.apply(.advance, to: cursor, in: Self.craigh), !step.atBoundary { cursor = step.cursor; forward.append(cursor) }
        var backward: [Cursor] = [cursor]
        while cursor != Cursor(row: 178, run: 0), let step = WorkEngine.apply(.back, to: cursor, in: Self.craigh) { cursor = step.cursor; backward.append(cursor) }
        #expect(backward.reversed() == forward)
    }

    @Test func runsWalkedNamesWhatATapDid() {
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 3, run: 0), in: Self.seq)?.runsWalked == 1)
        #expect(WorkEngine.apply(.advance, to: Self.fill, in: Self.craigh, step: .ten)?.runsWalked == 0)
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 3, run: 3), in: Self.seq)?.runsWalked == 0)   // the turn
        #expect(WorkEngine.apply(.jump(row: 7), to: .start, in: Self.seq)?.runsWalked == 0)
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

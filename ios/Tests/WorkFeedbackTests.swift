import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct WorkFeedbackTests {
    // two-letter-codes (rows): Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3
    static let seq = try! WorkSequence(chart: Chart.load(TestFixtures.data("two-letter-codes.chart.json")))
    static let craigh = try! WorkSequence(chart: Chart.load(TestFixtures.data("craigh-na-dun.chart.json")))

    @Test func runWithinRow() {
        let step = WorkEngine.apply(.advance, to: .start, in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: step, in: Self.seq) == .run)
    }

    @Test func theTurnIsTheRowHaptic() {
        let toBoundary = WorkEngine.apply(.advance, to: Cursor(row: 1, run: 2), in: Self.seq)!
        #expect(toBoundary.atBoundary && WorkFeedbackRule.feedback(for: toBoundary, in: Self.seq) == .row)
        // the tap after the turn is an ordinary run (the row haptic already fired at the turn)
        let turned = WorkEngine.apply(.advance, to: Cursor(row: 1, run: 3), in: Self.seq)!
        #expect(turned.startedNewRow && WorkFeedbackRule.feedback(for: turned, in: Self.seq) == .run)
        let toY = WorkEngine.apply(.advance, to: Cursor(row: 2, run: 1), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: toY, in: Self.seq) == .newColor)
    }

    @Test func roundsKeepTheRowHapticOnTheNewRow() throws {
        let rounds = try WorkSequence(chart: Chart.load(TestFixtures.data("minimal-rounds.chart.json")))
        let last = rounds.passes[0].runs.count - 1
        let step = WorkEngine.apply(.advance, to: Cursor(row: 1, run: last), in: rounds)!
        #expect(step.startedNewRow && WorkFeedbackRule.feedback(for: step, in: rounds) == .row)
    }

    @Test func aFillStepIsLighterThanARun() {
        let step = WorkEngine.apply(.advance, to: Cursor(row: 42, run: 10), in: Self.craigh, step: .ten)!
        #expect(step.cursor.stitch == 10 && WorkFeedbackRule.feedback(for: step, in: Self.craigh) == .step)
        let completes = WorkEngine.apply(.advance, to: Cursor(row: 42, run: 10, stitch: 110), in: Self.craigh, step: .ten)!
        #expect(WorkFeedbackRule.feedback(for: completes, in: Self.craigh) == .run)
    }

    @Test func backAndFinished() {
        let back = WorkEngine.apply(.back, to: Cursor(row: 2, run: 1), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: back, in: Self.seq) == nil)
        let done = WorkEngine.apply(.advance, to: Cursor(row: 2, run: 2), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: done, in: Self.seq) == .finished)
    }
}

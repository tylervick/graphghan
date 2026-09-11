import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct WorkFeedbackTests {
    // two-letter-codes: Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3
    static let seq = try! WorkSequence(chart: Chart.load(TestFixtures.data("two-letter-codes.chart.json")))

    @Test func runWithinRow() {
        let step = WorkEngine.apply(.advance, to: .start, in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: step, from: .start, in: Self.seq) == .run)   // Gd: row 1 has no previous row → plain run
    }

    @Test func rowBoundaryAndNewColor() {
        let toRow2 = WorkEngine.apply(.advance, to: Cursor(row: 1, run: 2), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: toRow2, from: Cursor(row: 1, run: 2), in: Self.seq) == .row)  // Gd was used in row 1
        let toY = WorkEngine.apply(.advance, to: Cursor(row: 2, run: 1), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: toY, from: Cursor(row: 2, run: 1), in: Self.seq) == .newColor)  // Y not in row 1
    }

    @Test func backAndFinished() {
        let back = WorkEngine.apply(.back, to: Cursor(row: 2, run: 1), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: back, from: Cursor(row: 2, run: 1), in: Self.seq) == nil)
        let done = WorkEngine.apply(.advance, to: Cursor(row: 2, run: 2), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: done, from: Cursor(row: 2, run: 2), in: Self.seq) == .finished)
    }
}

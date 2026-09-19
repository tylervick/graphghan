import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

/// App Intents spec §3.4, sentence by sentence. Sequences are built by hand: a twenty-cell fill
/// needs no fixture.
struct WorkIntentDialogTests {
    static let a = Run(code: "A", count: 3, x0: nil)
    static let b = Run(code: "B", count: 4, x0: nil)
    /// Two rows of three short runs, worked flat, so a boundary step sits after row 1.
    static let rows = WorkSequence(passes: [
        Pass(label: "Row 1", side: .rs, direction: .rtl, gridRow: 1, runs: [a, b, a]),
        Pass(label: "Row 2", side: .ws, direction: .ltr, gridRow: 0, runs: [b, a, b]),
    ], technique: "rows")
    /// One row whose only run is a fill.
    static let fill = WorkSequence(passes: [Pass(label: "Row 1", side: .rs, direction: .rtl, gridRow: 0, runs: [Run(code: "A", count: 20, x0: nil)])], technique: "rows")

    func said(_ action: WorkAction, from cursor: Cursor, in seq: WorkSequence, step: CountStep = .default) throws -> WorkIntentDialog.Text {
        let s = try #require(WorkEngine.apply(action, to: cursor, in: seq, step: step))
        return WorkIntentDialog.text(for: s, in: seq)
    }

    @Test func landingOnANewRun() throws {
        let t = try said(.advance, from: .start, in: Self.rows)
        #expect(t == WorkIntentDialog.Text("Row 1, run 2 of 3."))
    }

    @Test func insideAFillSaysWhatIsLeft() throws {
        let t = try said(.advance, from: .start, in: Self.fill)
        #expect(t == WorkIntentDialog.Text("Row 1, run 1, ten left in it.", supporting: "Row 1, run 1"))
        // Back from there lands mid-run too, and says so the same way.
        let back = try said(.back, from: Cursor(row: 1, run: 0, stitch: 10), in: Self.fill, step: .five)
        #expect(back.full == "Row 1, run 1, fifteen left in it.")
    }

    @Test func theRowIsWorkedAndTheTurnIsNext() throws {
        let t = try said(.advance, from: Cursor(row: 1, run: 2), in: Self.rows)
        #expect(t == WorkIntentDialog.Text("End of row 1. Turn.", supporting: "Row 1, turn"))
    }

    @Test func afterTheTurnItIsTheNextRow() throws {
        let t = try said(.advance, from: Cursor(row: 1, run: 3), in: Self.rows)
        #expect(t == WorkIntentDialog.Text("Row 2, run 1 of 3."))
    }

    @Test func theLastOne() throws {
        let t = try said(.advance, from: Cursor(row: 2, run: 2), in: Self.rows)
        #expect(t.full == "That's the last one. The blanket is done.")
    }

    @Test func backOntoThePreviousRow() throws {
        let t = try said(.back, from: Cursor(row: 2, run: 0), in: Self.rows)
        #expect(t == WorkIntentDialog.Text("End of row 1. Turn.", supporting: "Row 1, turn"))
    }

    @Test func nowhereToGoAndNoProject() {
        #expect(WorkIntentDialog.text(for: .nowhereToGo(.back)).full == "You're at the beginning.")
        #expect(WorkIntentDialog.text(for: .nowhereToGo(.advance)).full == "You've already finished this one.")
        #expect(WorkIntentDialog.text(for: .noProject).full == "You don't have a project going.")
        #expect(WorkIntentDialog.text(for: .chartUnavailable(title: "Craigh na Dun")).full == "Couldn't open the chart for Craigh na Dun.")
    }

    @Test func smallCountsAreWords() {
        #expect(WorkIntentDialog.spelled(8) == "eight")
        #expect(WorkIntentDialog.spelled(20) == "twenty")
        #expect(WorkIntentDialog.spelled(21) == "21")
    }

    @Test func aDialogIsBuiltForEveryOutcome() throws {
        _ = WorkIntentDialog.dialog(for: .noProject)
        _ = WorkIntentDialog.dialog(for: .nowhereToGo(.back))
        _ = WorkIntentDialog.dialog(for: .ambiguous([]))
    }

    static func snapshot(_ title: String) -> ProjectSnapshot {
        ProjectSnapshot(id: UUID(), title: title, patternTitle: "p", percent: 0, lastWorked: nil, isFinished: false)
    }

    @Test func theQuestionNamesTheBlankets() {
        let two = [Self.snapshot("Craigh na Dun"), Self.snapshot("Baby Blanket")]
        #expect(WorkIntentDialog.questionText(two) == "Which blanket — Craigh na Dun or Baby Blanket?")
        let three = two + [Self.snapshot("Scarf")]
        #expect(WorkIntentDialog.questionText(three) == "Which blanket — Craigh na Dun, Baby Blanket, or Scarf?")
        #expect(WorkIntentDialog.text(for: .ambiguous(two)).full == "Which blanket — Craigh na Dun or Baby Blanket?")
    }
}

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

    // MARK: a pieced project's chart piece (spec 2026-09-25 §6.5)

    func saidOnPiece(_ action: WorkAction, from cursor: Cursor, in seq: WorkSequence) throws -> WorkIntentDialog.Text {
        let s = try #require(WorkEngine.apply(action, to: cursor, in: seq))
        return WorkIntentDialog.text(for: s, in: seq, pieceTitle: "Front panel")
    }

    @Test func aPieceStepNamesThePiece() throws {
        #expect(try saidOnPiece(.advance, from: .start, in: Self.rows) == WorkIntentDialog.Text("Front panel, row 1, run 2 of 3."))
        #expect(try saidOnPiece(.advance, from: Cursor(row: 1, run: 2), in: Self.rows)
                == WorkIntentDialog.Text("Front panel, end of row 1. Turn.", supporting: "Front panel, row 1, turn"))
        #expect(try saidOnPiece(.advance, from: .start, in: Self.fill)
                == WorkIntentDialog.Text("Front panel, row 1, run 1, ten left in it.", supporting: "Front panel, row 1, run 1"))
    }

    @Test func aPiecesLastStepFinishesThePieceNotTheBlanket() throws {
        #expect(try saidOnPiece(.advance, from: Cursor(row: 2, run: 2), in: Self.rows).full == "That's the last row of Front panel.")
    }

    /// The outcome carries the piece title through the landing; nil keeps single-chart wording.
    @Test func theLandingCarriesThePieceTitle() throws {
        let chart = try Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
        let sequence = try WorkSequence(chart: chart)
        let step = try #require(WorkEngine.apply(.advance, to: .start, in: sequence))
        let single = WorkIntentLanding(step: step, sequence: sequence, chart: chart, countStep: .default, perRepetition: true)
        let pieced = WorkIntentLanding(step: step, sequence: sequence, chart: chart, countStep: .default, perRepetition: true,
                                       pieceTitle: "Front panel")
        #expect(WorkIntentDialog.plain(.moved(single)) == WorkIntentDialog.text(for: step, in: sequence).full)
        #expect(WorkIntentDialog.plain(.moved(pieced)).hasPrefix("Front panel, row 1, "))
    }

    static func snapshot(_ title: String, pattern: String = "p") -> ProjectSnapshot {
        ProjectSnapshot(id: UUID(), title: title, patternTitle: pattern, percent: 0, lastWorked: nil, isFinished: false, detail: nil)
    }

    @Test func aWrittenStepSaysThePieceAndRow() {
        #expect(WorkIntentDialog.plain(.movedWritten(title: "Strip", row: 2, total: 5, finished: false)) == "Strip, row 2 of 5.")
        #expect(WorkIntentDialog.plain(.movedWritten(title: "Strap", row: 58, total: nil, finished: false)) == "Strap, row 58.")
        #expect(WorkIntentDialog.plain(.movedWritten(title: "Strip", row: 5, total: 5, finished: true)) == "That's the last row of Strip.")
    }

    @Test func aRepeatedTitleIsToldApartByItsPattern() {
        let twins = [Self.snapshot("Blanket", pattern: "Craigh na Dun"), Self.snapshot("Blanket", pattern: "Baby Blanket"), Self.snapshot("Scarf")]
        #expect(WorkIntentDialog.questionText(twins) == "Which blanket — Blanket (Craigh na Dun), Blanket (Baby Blanket), or Scarf?")
    }

    @Test func theQuestionNamesTheBlankets() {
        let two = [Self.snapshot("Craigh na Dun"), Self.snapshot("Baby Blanket")]
        #expect(WorkIntentDialog.questionText(two) == "Which blanket — Craigh na Dun or Baby Blanket?")
        let three = two + [Self.snapshot("Scarf")]
        #expect(WorkIntentDialog.questionText(three) == "Which blanket — Craigh na Dun, Baby Blanket, or Scarf?")
        #expect(WorkIntentDialog.text(for: .ambiguous(two)).full == "Which blanket — Craigh na Dun or Baby Blanket?")
    }
}

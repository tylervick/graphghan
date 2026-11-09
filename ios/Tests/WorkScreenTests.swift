import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct WorkScreenTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let phone = CGSize(width: 390, height: 844)
    static let turn = Cursor(row: 42, run: seq.pass(at: 42)!.runs.count)
    static let end = Cursor(row: seq.passes.count, run: seq.passes.last!.runs.count)
    static let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))

    private func screen(_ cursor: Cursor, step: CountStep = .ten, style: BandStyle = .fabric, stretches: [Stretch] = []) -> some View {
        WorkScreen(chart: Self.chart, sequence: Self.seq, cursor: cursor, step: step, perRepetition: true,
                   onDone: {}, onBack: {}, onClose: {}, onJump: {}, onJumpWithinRow: { _, _ in }, onSetStep: { _ in }, onSetPerRepetition: { _ in },
                   bandStyle: style, stretches: stretches)
    }

    @Test func plainRun() throws { #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 8)), named: "work-run", size: Self.phone)) }
    @Test func braid() throws { #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 2)), named: "work-braid", size: Self.phone)) }
    @Test func repeatBand() throws { #expect(try Snapshots.assert(screen(Cursor(row: 179, run: 8)), named: "work-repeat", size: Self.phone)) }
    @Test func fill() throws { #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 10, stitch: 40)), named: "work-fill", size: Self.phone)) }
    @Test func turn() throws { #expect(try Snapshots.assert(screen(Self.turn), named: "work-turn", size: Self.phone)) }
    /// #87: the same repeat row with the band reading one way; the panel and bar are untouched.
    @Test func ribbon() throws { #expect(try Snapshots.assert(screen(Cursor(row: 179, run: 8), style: .ribbon), named: "work-ribbon", size: Self.phone)) }
    /// Finished: the whole chart with ticks only -- no current stretch, no bracket, no labels, no pill, no button.
    @Test func finished() throws { #expect(try Snapshots.assert(screen(Self.end, stretches: Self.stretches), named: "work-finished", size: Self.phone)) }

    /// At the largest accessibility size the count may cap and the landmark pill may drop; nothing clips.
    @Test func accessibilitySize() throws {
        let view = screen(Cursor(row: 42, run: 10, stitch: 40), stretches: Self.stretches).environment(\.dynamicTypeSize, .accessibility5)
        #expect(try Snapshots.assert(view, named: "work-fill-ax5", size: Self.phone))
    }

    /// A shaped chart (#37): the header adds the row's stitches and its shaping, and the pattern's
    /// own row text sits under the panel.
    @Test func shaped() throws {
        let chart = try Chart.load(TestFixtures.data("shaped-basic.chart.json"))
        let seq = try WorkSequence(chart: chart)
        let view = WorkScreen(chart: chart, sequence: seq, cursor: Cursor(row: 4, run: 0), step: .ten, perRepetition: true,
                              onDone: {}, onBack: {}, onClose: {}, onJump: {}, onJumpWithinRow: { _, _ in }, onSetStep: { _ in }, onSetPerRepetition: { _ in })
        #expect(try Snapshots.assert(view, named: "work-shaped", size: Self.phone))
    }

    /// #245: the look-ahead line under the side line, and the button that opens the whole view.
    @Test func lookAheadLine() throws {
        #expect(try Snapshots.assert(screen(Cursor(row: 5, run: 3), stretches: Self.stretches), named: "work-look-ahead-line", size: Self.phone))
    }
    @Test func lookAheadLastRow() throws {
        #expect(try Snapshots.assert(screen(Cursor(row: 14, run: 3), stretches: Self.stretches), named: "work-look-ahead-last", size: Self.phone))
    }
    @Test func theHeaderSpeaksTheLine() {
        #expect(WorkScreen.headerValue(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 5, run: 3), stretches: Self.stretches)
                == "Right side, read right to left. 9 more rows like this, then plain rows for 2 rows")
        #expect(WorkScreen.headerValue(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 5, run: 3), stretches: []) == "Right side, read right to left")
        #expect(WorkScreen.headerValue(chart: Self.chart, sequence: Self.seq, cursor: Self.end, stretches: Self.stretches) == "Every row worked")
    }

    @Test func actionLabelsSpellOutTheStitch() {
        let run = Self.seq.pass(at: 42)!.runs[8]
        let name = Self.chart.palette[Self.chart.colorIndex(of: run.code)!].name
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 42, run: 8), step: .ten) == "Done with \(run.count) single crochet in \(name)")
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 42, run: 10, stitch: 40), step: .ten) == "40 of 117 single crochet in Cream, next ten")
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Self.turn, step: .ten).hasPrefix("Ch 1 in Gold, turn"))
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Self.end, step: .ten) == "Close")
        // a repeat's tap walks the unit, so the spoken action names the repetition (#81)
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 179, run: 8), step: .ten) == "Done with repetition 3 of 22: 5 Gold, 2 Deep Green")
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 179, run: 8), step: .ten, perRepetition: false) == "Done with 5 single crochet in Gold")
    }
}

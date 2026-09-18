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

    private func screen(_ cursor: Cursor, step: CountStep = .ten) -> some View {
        WorkScreen(chart: Self.chart, sequence: Self.seq, cursor: cursor, step: step, perRepetition: true,
                   onDone: {}, onBack: {}, onClose: {}, onJump: {}, onJumpWithinRow: { _, _ in }, onSetStep: { _ in }, onSetPerRepetition: { _ in })
    }

    @Test func plainRun() throws { #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 8)), named: "work-run", size: Self.phone)) }
    @Test func braid() throws { #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 2)), named: "work-braid", size: Self.phone)) }
    @Test func repeatBand() throws { #expect(try Snapshots.assert(screen(Cursor(row: 179, run: 8)), named: "work-repeat", size: Self.phone)) }
    @Test func fill() throws { #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 10, stitch: 40)), named: "work-fill", size: Self.phone)) }
    @Test func turn() throws { #expect(try Snapshots.assert(screen(Self.turn), named: "work-turn", size: Self.phone)) }
    @Test func finished() throws { #expect(try Snapshots.assert(screen(Self.end), named: "work-finished", size: Self.phone)) }

    /// At the largest accessibility size the count may cap and the landmark pill may drop; nothing clips.
    @Test func accessibilitySize() throws {
        let view = screen(Cursor(row: 42, run: 10, stitch: 40)).environment(\.dynamicTypeSize, .accessibility5)
        #expect(try Snapshots.assert(view, named: "work-fill-ax5", size: Self.phone))
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

import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct WorkScreenTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let phone = CGSize(width: 390, height: 844)

    private func screen(_ cursor: Cursor) -> some View {
        WorkScreen(chart: Self.chart, sequence: Self.seq, cursor: cursor, onDone: {}, onBack: {}, onClose: {}, onJump: {}, onSelectRun: { _ in })
    }

    @Test func midRow() throws {
        #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 8)), named: "work-mid-row", size: Self.phone))
    }

    @Test func lastRunInRow() throws {
        let runs = Self.seq.pass(at: 42)!.runs.count
        #expect(try Snapshots.assert(screen(Cursor(row: 42, run: runs - 1)), named: "work-last-in-row", size: Self.phone))
    }

    @Test func finished() throws {
        let end = Cursor(row: Self.seq.passes.count, run: Self.seq.passes.last!.runs.count)
        #expect(try Snapshots.assert(screen(end), named: "work-finished", size: Self.phone))
    }

    /// At the largest accessibility size the count may cap; nothing may clip or overlap the Done field.
    @Test func accessibilitySize() throws {
        let view = screen(Cursor(row: 42, run: 8)).environment(\.dynamicTypeSize, .accessibility5)
        #expect(try Snapshots.assert(view, named: "work-mid-row-ax5", size: Self.phone))
    }

    @Test func doneLabelSpellsOutTheStitch() {
        // Craigh na Dun: gauge.stitch = sc, terms = US
        let label = WorkScreen.doneLabel(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 42, run: 8))
        let run = Self.seq.pass(at: 42)!.runs[8]
        let name = Self.chart.palette[Self.chart.colorIndex(of: run.code)!].name
        #expect(label == "Done with \(run.count) single crochet in \(name)")
        // two-letter-codes: gauge.stitch = sc with no terms → US → still named; palette names are "Color <code>"
        let plainChart = try! Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
        let plainSeq = try! WorkSequence(chart: plainChart)
        #expect(WorkScreen.doneLabel(chart: plainChart, sequence: plainSeq, cursor: .start) == "Done with 3 single crochet in Color Kb")
        // a chart with no gauge.stitch keeps today's label
        let end = Cursor(row: Self.seq.passes.count, run: Self.seq.passes.last!.runs.count)
        #expect(WorkScreen.doneLabel(chart: Self.chart, sequence: Self.seq, cursor: end) == "Close")
    }
}

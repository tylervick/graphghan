import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct ChartBandTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let size = CGSize(width: 366, height: 420)

    private func band(_ cursor: Cursor, label: String? = nil, mode: ChartBand.Mode = .band, style: BandStyle = .fabric) -> some View {
        ChartBand(chart: Self.chart, sequence: Self.seq, cursor: cursor, segmentLabel: label, mode: mode, style: style, onAdvance: {}, onJump: { _, _ in }, onToggleMode: {})
            .background(Color.ground)
    }

    /// #74: at 40 of 117 the hook is a quarter in from the left with its tick labelled 40, and the
    /// ring is the 77 stitches left; at 110 the end is pinned and the landmark's Purple is in frame.
    @Test func fillFollowsTheHook() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: 10, stitch: 40)), named: "band-fill", size: Self.size))
    }
    @Test func fillNearItsEndPinsTheEnd() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: 10, stitch: 110)), named: "band-fill-end", size: Self.size))
    }
    @Test func braidBracket() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: 2), label: "border braid"), named: "band-braid", size: Self.size))
    }
    @Test func repeatBracket() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 179, run: 8), label: "×22 · 3 of 22"), named: "band-repeat", size: Self.size))
    }
    @Test func boundary() throws {
        let runs = Self.seq.pass(at: 42)!.runs.count
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: runs)), named: "band-turn", size: Self.size))
    }
    /// #87: the ribbon on right-to-left rows reads left to right, with the fold arcs at either
    /// end. Row 43 mirrors row 42's braid, fill and turn; row 179 is the repeat.
    static let fill43 = seq.pass(at: 43)!.runs.firstIndex { $0.count >= 20 }!
    @Test func ribbonBraid() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 43, run: 2), label: "border braid", style: .ribbon), named: "ribbon-braid", size: Self.size))
    }
    @Test func ribbonFill() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 43, run: Self.fill43, stitch: 40), style: .ribbon), named: "ribbon-fill", size: Self.size))
    }
    @Test func ribbonRepeat() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 179, run: 8), label: "×22 · 3 of 22", style: .ribbon), named: "ribbon-repeat", size: Self.size))
    }
    @Test func ribbonTurn() throws {
        let runs = Self.seq.pass(at: 43)!.runs.count
        #expect(try Snapshots.assert(band(Cursor(row: 43, run: runs), style: .ribbon), named: "ribbon-turn", size: Self.size))
    }
    /// A chart worked in the round has no turn between passes, so the ribbon draws no fold arcs
    /// and no "turn" label (spec §4.4; CodeRabbit on #96).
    @Test func ribbonInTheRoundHasNoFolds() throws {
        let chart = try Chart.load(TestFixtures.data("minimal-rounds.chart.json"))
        let seq = try WorkSequence(chart: chart)
        #expect(!seq.hasBoundaryStep(after: 2))
        let view = ChartBand(chart: chart, sequence: seq, cursor: Cursor(row: 2, run: 0), segmentLabel: nil, mode: .band, style: .ribbon,
                             onAdvance: {}, onJump: { _, _ in }, onToggleMode: {})
            .background(Color.ground)
        #expect(try Snapshots.assert(view, named: "ribbon-rounds", size: Self.size))
    }
    @Test func wholeChart() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: 8), mode: .whole), named: "band-whole", size: Self.size))
    }
}

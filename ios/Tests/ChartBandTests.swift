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

    static let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))
    private func lookAhead(_ cursor: Cursor) -> some View {
        ChartBand(chart: Self.chart, sequence: Self.seq, cursor: cursor, segmentLabel: nil, mode: .whole, style: .fabric,
                  onAdvance: {}, onJump: { _, _ in }, onToggleMode: {}, stretches: Self.stretches, returnLabel: "Back to Row \(cursor.row)")
            .background(Color.ground)
    }
    /// #245: the whole view with the stretches marked, the current one bracketed, and the way back visible.
    @Test func lookAheadAtRowFive() throws {
        #expect(try Snapshots.assert(lookAhead(Cursor(row: 5, run: 3)), named: "band-look-ahead", size: Self.size))
    }
    /// The return pill grows with its label at an accessibility size rather than letting the text spill.
    @Test func lookAheadAtAnAccessibilitySize() throws {
        #expect(try Snapshots.assert(lookAhead(Cursor(row: 5, run: 3)).environment(\.dynamicTypeSize, .accessibility5), named: "band-look-ahead-ax5", size: Self.size))
    }
    /// #250: zoomed in, the view opens on the current row, and the row numbers and labels keep to
    /// the band's edges while the chart runs off them.
    @Test func lookAheadZoomedIn() throws {
        let view = ChartBand(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 60, run: 0), segmentLabel: nil, mode: .whole, style: .fabric,
                             onAdvance: {}, onJump: { _, _ in }, onToggleMode: {}, stretches: Self.stretches, returnLabel: "Back to Row 60",
                             openingZoom: 2.5)
            .background(Color.ground)
        #expect(try Snapshots.assert(view, named: "band-look-ahead-zoomed", size: Self.size))
    }
    @Test func lookAheadLateInTheBlanket() throws {
        #expect(try Snapshots.assert(lookAhead(Cursor(row: 150, run: 0)), named: "band-look-ahead-late", size: Self.size))
    }

    /// A shaped chart (#37): the ground is drawn as the band's own ground, with no yarn and no
    /// hairlines, so the rows follow the piece's silhouette; the whole view does the same.
    @Test func shaped() throws {
        let chart = try Chart.load(TestFixtures.data("shaped-basic.chart.json"))
        let seq = try WorkSequence(chart: chart)
        for (mode, name) in [(ChartBand.Mode.band, "band-shaped"), (.whole, "band-shaped-whole")] {
            let view = ChartBand(chart: chart, sequence: seq, cursor: Cursor(row: 4, run: 1), segmentLabel: nil, mode: mode,
                                 onAdvance: {}, onJump: { _, _ in }, onToggleMode: {}).background(Color.ground)
            #expect(try Snapshots.assert(view, named: name, size: Self.size))
        }
    }

    /// Fix round 1 (#37): in ribbon style, the fold arc anchors to the stitched span's edge, not
    /// the chart's raw edge, so on a shaped row it sits with the boundary marker and the stitches.
    @Test func shapedRibbonFoldSitsWithTheStitches() throws {
        let chart = try Chart.load(TestFixtures.data("shaped-basic.chart.json"))
        let seq = try WorkSequence(chart: chart)
        let view = ChartBand(chart: chart, sequence: seq, cursor: Cursor(row: 1, run: 1), segmentLabel: nil, mode: .band, style: .ribbon,
                             onAdvance: {}, onJump: { _, _ in }, onToggleMode: {}).background(Color.ground)
        #expect(try Snapshots.assert(view, named: "band-shaped-ribbon", size: Self.size))
    }
}

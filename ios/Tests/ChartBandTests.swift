import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct ChartBandTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let size = CGSize(width: 366, height: 420)

    private func band(_ cursor: Cursor, label: String? = nil, mode: ChartBand.Mode = .band) -> some View {
        ChartBand(chart: Self.chart, sequence: Self.seq, cursor: cursor, segmentLabel: label, mode: mode, onAdvance: {}, onJump: { _, _ in }, onToggleMode: {})
            .background(Color.ground)
    }

    @Test func fillKeepsItsEndInView() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: 10, stitch: 40)), named: "band-fill", size: Self.size))
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
    @Test func wholeChart() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: 8), mode: .whole), named: "band-whole", size: Self.size))
    }
}

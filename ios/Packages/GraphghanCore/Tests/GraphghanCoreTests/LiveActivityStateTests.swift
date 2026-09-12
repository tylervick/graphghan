import Foundation
import Testing
@testable import GraphghanCore

@Suite struct LiveActivityStateTests {
    // two-letter-codes: Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3 (24 stitches)
    static let chart = try! Chart.load(Fixtures.data("two-letter-codes.chart.json"))
    static let seq = try! WorkSequence(chart: chart)

    @Test func startOfChart() throws {
        let s = try #require(LiveActivityState.make(cursor: .start, sequence: Self.seq))
        #expect(s.row == 1 && s.rowCount == 2 && s.side == "RS" && s.runIndex == 0)
        #expect(s.currentCode == "Kb" && s.currentCount == 3)
        #expect(s.nextCode == "Gd" && s.nextCount == 7 && !s.isLastInRow)
        #expect(s.percent == 0 && !s.finished && s.message == nil)
    }

    @Test func lastRunInRow() throws {
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 2, run: 2), sequence: Self.seq))
        #expect(s.currentCode == "Y" && s.currentCount == 3)
        #expect(s.nextCode == nil && s.nextCount == nil && s.isLastInRow)
        #expect(s.percent == 87.5)  // 21 of 24
    }

    @Test func finishedCursor() throws {
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 2, run: 3), sequence: Self.seq))
        #expect(s.finished && s.currentCode == nil && s.currentCount == nil && s.percent == 100 && s.isLastInRow)
    }

    @Test func previousRunCrossesRows() throws {
        let start = try #require(LiveActivityState.make(cursor: .start, sequence: Self.seq))
        #expect(start.previousCode == nil && start.previousCount == nil)
        let second = try #require(LiveActivityState.make(cursor: Cursor(row: 1, run: 1), sequence: Self.seq))
        #expect(second.previousCode == "Kb" && second.previousCount == 3)
        let row2 = try #require(LiveActivityState.make(cursor: Cursor(row: 2, run: 0), sequence: Self.seq))
        #expect(row2.previousCode == "G" && row2.previousCount == 2)  // the last run of row 1
    }

    @Test func invalidCursorIsNil() {
        #expect(LiveActivityState.make(cursor: Cursor(row: 9, run: 0), sequence: Self.seq) == nil)
    }

    @Test func infoCarriesPalette() {
        let id = UUID()
        let info = LiveActivityState.info(projectID: id, chart: Self.chart, sequence: Self.seq)
        #expect(info.projectID == id && info.title == "Two-letter codes" && info.totalRows == 2 && info.totalStitches == 24)
        #expect(info.palette.map(\.code) == ["G", "Gd", "Kb", "Y"] && info.swatch(for: "Gd")?.hex == "#D9A21B" && info.swatch(for: "Q") == nil)
    }

    @Test func unavailableState() {
        let s = WorkActivityState.unavailable("This project is no longer available.")
        #expect(s.message == "This project is no longer available." && s.finished && s.currentCode == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 1, run: 1), sequence: Self.seq))
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(WorkActivityState.self, from: data) == s)
    }
}

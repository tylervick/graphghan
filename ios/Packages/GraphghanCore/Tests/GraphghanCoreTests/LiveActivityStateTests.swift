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

    /// Row 179's `5Y 2G` ×22 band (#81): the state names the repetition and Back's colour is the
    /// repetition before, not the run before; with the tap unit off, neither.
    @Test func repetitionOnTheLockScreen() throws {
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("craigh-na-dun.chart.json")))
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 179, run: 8), sequence: seq))
        #expect(s.repetition == 3 && s.repetitions == 22)
        #expect(s.previousCode == "Y" && s.previousCount == 5)   // repetition 2's first run
        let off = try #require(LiveActivityState.make(cursor: Cursor(row: 179, run: 8), sequence: seq, perRepetition: false))
        #expect(off.repetition == nil && off.repetitions == nil)
        #expect(off.previousCode == "G" && off.previousCount == 2)
        let plain = try #require(LiveActivityState.make(cursor: Cursor(row: 42, run: 8), sequence: seq))
        #expect(plain.repetition == nil)
    }

    @Test func invalidCursorIsNil() {
        #expect(LiveActivityState.make(cursor: Cursor(row: 9, run: 0), sequence: Self.seq) == nil)
    }

    @Test func infoCarriesPalette() {
        let id = UUID()
        let info = LiveActivityState.info(projectID: id, chart: Self.chart, sequence: Self.seq)
        #expect(info.projectID == id && info.title == "Two-letter codes" && info.totalRows == 2 && info.totalCells == 24)
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

    @Test func infoCarriesStitchAndTurningChain() throws {
        let craigh = try Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
        let info = LiveActivityState.info(projectID: UUID(), chart: craigh, sequence: try WorkSequence(chart: craigh))
        #expect(info.stitch == "sc" && info.turningChain == 1)
        let plain = LiveActivityState.info(projectID: UUID(), chart: Self.chart, sequence: Self.seq)  // two-letter-codes: no boundary
        #expect(plain.stitch == "sc" && plain.turningChain == nil)
    }

    @Test func turningChainIsNilForOtherBoundaryKinds() throws {
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"ID","width":2,"height":1},
         "palette":[{"code":"A","name":"a","hex":"#000000"}],"rows":["2A"],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"},"stitch":"dc","boundary":{"kind":"join","chain":3}},
         "technique":{"type":"rounds"}}
        """#
        let id = ChartID.compute(codes: ["A"], rows: ["2A"], technique: .object(["type": .string("rounds")]), passes: nil)
        let chart = try Chart.load(Data(json.replacingOccurrences(of: "\"ID\"", with: "\"\(id)\"").utf8))
        let info = LiveActivityState.info(projectID: UUID(), chart: chart, sequence: try WorkSequence(chart: chart))
        #expect(info.stitch == "dc" && info.turningChain == nil)
    }

    @Test func infoRoundTripsThroughCodable() throws {
        let craigh = try Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
        let info = LiveActivityState.info(projectID: UUID(), chart: craigh, sequence: try WorkSequence(chart: craigh))
        let back = try JSONDecoder().decode(WorkActivityInfo.self, from: JSONEncoder().encode(info))
        #expect(back == info)
    }

    @Test func activityInfoStillEncodesTheOldKey() throws {
        let info = WorkActivityInfo(projectID: UUID(), title: "t", totalRows: 2, totalCells: 24, palette: [])
        let json = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(info)) as! [String: Any]
        #expect(json["totalStitches"] as? Int == 24)
        #expect(json["totalCells"] == nil)
    }

    // Craigh na Dun row 42 (ltr): run 10 is 117 C, a fill; 21 runs, then the boundary.
    static let craigh = try! Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
    static let craighSeq = try! WorkSequence(chart: craigh)

    @Test func fillReportsTheCount() throws {
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 42, run: 10, stitch: 40), sequence: Self.craighSeq))
        #expect(s.counting && s.stitch == 40 && s.currentCode == "C" && s.currentCount == 117 && !s.atBoundary)
        let plain = try #require(LiveActivityState.make(cursor: Cursor(row: 42, run: 8), sequence: Self.craighSeq))
        #expect(!plain.counting && plain.stitch == 0)
    }

    @Test func boundaryCarriesTheNextRowsFirstRun() throws {
        let runs = Self.craighSeq.pass(at: 42)!.runs.count
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 42, run: runs), sequence: Self.craighSeq))
        #expect(s.atBoundary && s.isLastInRow && !s.finished && s.currentCode == nil && s.currentCount == nil)
        let first = Self.craighSeq.pass(at: 43)!.runs[0]
        #expect(s.nextCode == first.code && s.nextCount == first.count)
        #expect(s.previousCode == Self.craighSeq.pass(at: 42)!.runs[runs - 1].code)
        #expect(s.percent == LiveActivityState.make(cursor: Cursor(row: 43, run: 0), sequence: Self.craighSeq)!.percent)
    }

    @Test func oldStatePayloadsDecodeWithDefaults() throws {
        let json = #"{"row":1,"rowCount":2,"runIndex":0,"currentCode":"Kb","currentCount":3,"isLastInRow":false,"percent":0,"finished":false}"#
        let s = try JSONDecoder().decode(WorkActivityState.self, from: Data(json.utf8))
        #expect(s.stitch == 0 && !s.counting && !s.atBoundary)
    }
}

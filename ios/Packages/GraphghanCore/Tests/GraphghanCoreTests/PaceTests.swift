import Foundation
import Testing
@testable import GraphghanCore

@Suite struct PaceTests {
    struct ExpectedSession: Decodable { let start: String; let end: String; let cells: Int }
    struct Expected: Decodable {
        let percent: Double; let cellsDone: Int; let totalCells: Int; let sessions: [ExpectedSession]
        let activeSeconds: Int; let stitchesPerHour: Double?
        enum CodingKeys: String, CodingKey {
            case percent, cellsDone = "cells_done", totalCells = "total_cells", sessions
            case activeSeconds = "active_seconds", stitchesPerHour = "stitches_per_hour"
        }
    }

    @Test(arguments: ["progress-basic", "progress-stitch"]) func matchesTheProgressFixture(_ name: String) throws {
        let doc = try ProgressDocument.decode(Fixtures.data("\(name).progress.json"))
        let raw = try Fixtures.json("\(name).progress.json")
        let chartName = try #require(((raw["ext"] as? [String: Any])?["fixture"] as? [String: Any])?["chart"] as? String)
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("\(chartName).chart.json")))
        let expected = try JSONDecoder().decode(Expected.self, from: Fixtures.data("\(name).progress.expected.json"))
        let s = Pace.summarize(events: doc.events, cursor: doc.cursor, sequence: seq)
        #expect(abs(s.percent - expected.percent) < 0.001)
        #expect(s.cellsDone == expected.cellsDone && s.totalCells == expected.totalCells)
        #expect(s.activeSeconds == expected.activeSeconds)
        #expect(s.sessions.map(\.cells) == expected.sessions.map(\.cells))
        #expect(s.sessions.map { ProgressDates.format($0.start) } == expected.sessions.map(\.start))
        #expect(s.sessions.map { ProgressDates.format($0.end) } == expected.sessions.map(\.end))
        let rate = try #require(s.stitchesPerHour)
        #expect(abs(rate - (expected.stitchesPerHour ?? -1)) < 0.001)
    }

    @Test func summaryWithholdsStitchNumbersForANonStitchKind() throws {
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("filet-blocks.chart.json")))
        let s = Pace.summarize(events: [], cursor: .start, sequence: seq)
        #expect(s.totalCells == seq.totalCells)
        #expect(s.totalStitches == nil)
        #expect(s.stitchesDone == nil)
        #expect(s.stitchesPerHour == nil)
    }

    @Test func noEventsAndSingleEvent() throws {
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))
        let empty = Pace.summarize(events: [], cursor: .start, sequence: seq)
        #expect(empty == ProgressSummary(percent: 0, cellsDone: 0, totalCells: 168, sessions: [], activeSeconds: 0,
                                         stitchesDone: 0, totalStitches: 168, stitchesPerHour: nil))
        let t = ProgressDates.parse("2026-09-12T18:00:00Z")!
        let one = Pace.summarize(events: [ProgressEventRecord(t: t, row: 2, run: 0, kind: .advance)], cursor: Cursor(row: 2, run: 0), sequence: seq)
        #expect(one.sessions == [Session(start: t, end: t, cells: 14)] && one.activeSeconds == 0 && one.stitchesPerHour == nil)
    }

    @Test func backwardsSessionClampsToZeroAndEventsAreSorted() throws {
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))
        let t0 = ProgressDates.parse("2026-09-12T18:00:00Z")!
        let events = [
            ProgressEventRecord(t: t0.addingTimeInterval(300), row: 2, run: 0, kind: .back),
            ProgressEventRecord(t: t0, row: 3, run: 2, kind: .jump),
        ]
        let s = Pace.summarize(events: events, cursor: Cursor(row: 2, run: 0), sequence: seq)
        #expect(s.sessions.count == 1 && s.sessions[0].cells == 14)  // from (1,0) to (2,0) net
        let s2 = Pace.summarize(events: [
            ProgressEventRecord(t: t0, row: 3, run: 2, kind: .jump),
            ProgressEventRecord(t: t0.addingTimeInterval(3000), row: 2, run: 0, kind: .back),  // new session, goes backwards
        ], cursor: Cursor(row: 2, run: 0), sequence: seq)
        #expect(s2.sessions.map(\.cells) == [40, 0])
    }

    @Test func estimateNeedsThreeSessionsAndSpreadsOverTheWindow() {
        let now = ProgressDates.parse("2026-09-20T12:00:00Z")!
        let day: TimeInterval = 86400
        let sessions = [
            Session(start: now.addingTimeInterval(-3 * day), end: now.addingTimeInterval(-3 * day + 600), cells: 30),
            Session(start: now.addingTimeInterval(-2 * day), end: now.addingTimeInterval(-2 * day + 240), cells: 10),
            Session(start: now.addingTimeInterval(-1 * day), end: now.addingTimeInterval(-1 * day + 900), cells: 18),
        ]
        #expect(Pace.estimatedFinish(remainingCells: 110, stitchesPerHour: 120, sessions: Array(sessions.prefix(2)), now: now) == nil)
        #expect(Pace.estimatedFinish(remainingCells: 110, stitchesPerHour: nil, sessions: sessions, now: now) == nil)
        let finish = Pace.estimatedFinish(remainingCells: 110, stitchesPerHour: 120, sessions: sessions, now: now)!
        // 110 st / 120 st/h = 0.9167 h; mean active hours per day over 14 days = (1740/3600)/14 = 0.03452 h/day
        // → 26.55 days
        #expect(abs(finish.timeIntervalSince(now) / day - 26.55) < 0.05)
        // sessions older than the window do not count toward the daily mean
        let old = Session(start: now.addingTimeInterval(-30 * day), end: now.addingTimeInterval(-30 * day + 36000), cells: 999)
        let finish2 = Pace.estimatedFinish(remainingCells: 110, stitchesPerHour: 120, sessions: sessions + [old], now: now)!
        #expect(abs(finish2.timeIntervalSince(now) - finish.timeIntervalSince(now)) < 1)
        #expect(Pace.estimatedFinish(remainingCells: 0, stitchesPerHour: 120, sessions: sessions, now: now) == now)
    }
}

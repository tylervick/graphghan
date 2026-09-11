import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct WorkActivityViewsTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let info = LiveActivityState.info(projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, chart: chart, sequence: seq)
    static let midway = LiveActivityState.make(cursor: Cursor(row: 42, run: 3), sequence: seq)!
    static let lastInRow = LiveActivityState.make(cursor: Cursor(row: 1, run: 0), sequence: seq)!
    static let unavailable = WorkActivityState.unavailable("This project is no longer available.")
    /// Past the last run of the last pass: the cursor the Work screen ends on.
    static let finished = LiveActivityState.make(cursor: Cursor(row: seq.passes.count, run: seq.passes.last!.runs.count), sequence: seq)!

    @Test func hexColor() {
        #expect(HexColor.isLight("#F2E8D5") && !HexColor.isLight("#2B2F33"))
    }

    @Test func lockScreenMidway() throws {
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.midway), named: "lock-midway", size: CGSize(width: 360, height: 170)))
    }

    @Test func lockScreenLastInRow() throws {
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.lastInRow), named: "lock-last-in-row", size: CGSize(width: 360, height: 170)))
    }

    @Test func lockScreenUnavailable() throws {
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.unavailable), named: "lock-unavailable", size: CGSize(width: 360, height: 120)))
    }

    @Test func lockScreenFinished() throws {
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.finished), named: "lock-finished", size: CGSize(width: 360, height: 120)))
    }

    @Test func compactAndMinimal() throws {
        #expect(try Snapshots.assert(WorkCompactLeadingView(info: Self.info, state: Self.midway), named: "compact-leading", size: CGSize(width: 64, height: 36)))
        #expect(try Snapshots.assert(WorkCompactTrailingView(state: Self.midway), named: "compact-trailing", size: CGSize(width: 64, height: 36)))
        #expect(try Snapshots.assert(WorkMinimalView(info: Self.info, state: Self.midway), named: "minimal", size: CGSize(width: 44, height: 36)))
    }

    @Test func expanded() throws {
        #expect(try Snapshots.assert(WorkExpandedCenterView(info: Self.info, state: Self.midway), named: "expanded-center", size: CGSize(width: 340, height: 90)))
        #expect(try Snapshots.assert(WorkExpandedBottomView(info: Self.info, state: Self.midway), named: "expanded-bottom", size: CGSize(width: 340, height: 60)))
    }

    @Test func renderModeWritesIntoTheOutputDirectoryWithoutComparing() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)", isDirectory: true)
        let env = ["GRAPHGHAN_SNAPSHOTS": "render", "GRAPHGHAN_SNAPSHOT_OUT": out.path]
        // A view that would fail a pixel comparison against lock-midway: same size, different content.
        let ok = try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.lastInRow), named: "lock-midway",
                                      size: CGSize(width: 360, height: 170), environment: env)
        #expect(ok)
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("lock-midway.png").path))
        try? FileManager.default.removeItem(at: out)
    }

    @Test func renderModeStillCatchesASizeMismatch() throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)", isDirectory: true)
        let env = ["GRAPHGHAN_SNAPSHOTS": "render", "GRAPHGHAN_SNAPSHOT_OUT": out.path]
        // This SDK's `withKnownIssue` does not return the body's value (it returns Void), so the
        // sanctioned fallback drops the value assertion and relies on the known-issue match itself:
        // the test fails if `assert` does NOT record an Issue here.
        withKnownIssue("size mismatch is reported in render mode") {
            _ = try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.midway), named: "lock-midway",
                                     size: CGSize(width: 360, height: 200), environment: env)
        }
        try? FileManager.default.removeItem(at: out)
    }
}

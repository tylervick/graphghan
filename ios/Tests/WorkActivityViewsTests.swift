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
    static let finished = WorkActivityState.unavailable("This project is no longer available.")

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
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.finished), named: "lock-unavailable", size: CGSize(width: 360, height: 120)))
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
}

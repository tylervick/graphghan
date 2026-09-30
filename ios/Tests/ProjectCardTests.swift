import SwiftUI
import Testing
@testable import Graphghan

@MainActor
@Suite struct ProjectCardTests {
    @Test func activeAndFinished() throws {
        let list = VStack(spacing: 12) {
            ProjectCardView(title: "Craigh na Dun Blanket", percent: 23, line: "Row 42 of 184 · 23%",
                            estimate: "Done around Nov 3", lastWorked: "Last worked yesterday", finished: false, preview: nil)
            ProjectCardView(title: "Craigh na Dun Blanket", percent: 100, line: "Finished",
                            estimate: nil, lastWorked: "Last worked Aug 30", finished: true, preview: nil)
        }
        .padding(16)
        .background(Color.ground.weave())
        #expect(try Snapshots.assert(list, named: "project-cards", size: CGSize(width: 390, height: 280)))
    }

    /// A pieced project whose manifest or current piece fails to load says so, as a single-chart
    /// row does, rather than showing a blank line; while loading the line stays empty.
    @Test func aPiecedRowThatCannotLoadSaysSo() {
        #expect(ProjectRow.cardLine(nil, unavailable: true) == "History couldn't be read")
        #expect(ProjectRow.cardLine(nil, unavailable: false) == "")
        #expect(ProjectRow.cardLine("Panel · Row 1 of 5 · 0 of 5 pieces", unavailable: false) == "Panel · Row 1 of 5 · 0 of 5 pieces")
    }
}

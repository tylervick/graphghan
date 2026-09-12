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
}

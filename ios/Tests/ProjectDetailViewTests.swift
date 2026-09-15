import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct ProjectDetailViewTests {
    /// Byte-identical to the pre-#44 text: a stitch chart's Sessions row must not move.
    @Test func sessionValueTextIsByteIdenticalForAStitchChart() {
        #expect(ProjectDetailView.sessionValueText(cells: 18, cellKind: .stitch, seconds: 300) == "18 stitches · 5 min")
    }

    @Test func sessionValueTextNamesTheNounForANonStitchKind() {
        #expect(ProjectDetailView.sessionValueText(cells: 18, cellKind: .block, seconds: 300) == "18 blocks · 5 min")
    }
}

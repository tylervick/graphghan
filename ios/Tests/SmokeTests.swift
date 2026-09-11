import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct SmokeTests {
    @Test func coreIsLinked() {
        #expect(GraphghanCore.formatSchema == 2)
    }
}

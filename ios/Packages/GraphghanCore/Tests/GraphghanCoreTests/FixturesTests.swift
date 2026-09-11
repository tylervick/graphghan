import Testing
@testable import GraphghanCore

@Suite struct FixturesTests {
    @Test func fixtureSetMatchesSpec() {
        #expect(Set(Fixtures.chartNames) == [
            "craigh-na-dun", "explicit-passes", "layers-stitch", "minimal-rounds",
            "minimal-rows", "two-letter-codes", "unknown-technique",
        ])
    }

    @Test func packageConstants() {
        #expect(GraphghanCore.formatSchema == 2)
        #expect(GraphghanCore.progressSchema == 1)
    }
}

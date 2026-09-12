import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct PatternDetailTests {
    @Test func content() throws {
        let manifest = TestManifest.make(chartID: "final-sc")
        let chart = try Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
        let view = PatternDetailContent(manifest: manifest, chart: chart, preview: nil, onStart: {}, onBrowse: { _ in })
            .background(Color.ground.weave())
        #expect(try Snapshots.assert(view, named: "pattern-detail", size: CGSize(width: 390, height: 760)))
    }
}

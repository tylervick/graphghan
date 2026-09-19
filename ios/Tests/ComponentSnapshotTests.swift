import SwiftUI
import GraphghanCore
import Testing
@testable import Graphghan

@MainActor
@Suite struct ComponentSnapshotTests {
    /// The Siri snippet is the Work screen's panel over its band (App Intents spec §4.4).
    @Test func workSnippet() throws {
        let chart = try Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
        let sequence = try WorkSequence(chart: chart)
        let step = try #require(WorkEngine.apply(.advance, to: .start, in: sequence))
        let landing = WorkIntentLanding(step: step, sequence: sequence, chart: chart, countStep: .default, perRepetition: true)
        #expect(try Snapshots.assert(WorkSnippetView(outcome: .moved(landing)), named: "work-snippet", size: CGSize(width: 360, height: 640)))
    }

    @Test func componentsSheet() throws {
        let sheet = VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                Chip(text: "2 G", hex: "#1E4D3A", state: .done)
                Chip(text: "4 Y", hex: "#D9A21B", state: .done)
                Chip(text: "51 C", hex: "#F2E8D5", state: .current)
                Chip(text: "4 K", hex: "#2B2F33", state: .upcoming)
                Chip(text: "P", hex: "#6B2D5C", state: .plain)
            }
            Button("Start project") {}.buttonStyle(.primary)
            Button("Browse chart") {}.buttonStyle(.secondary)
            Banner(text: "Showing saved patterns. The site could not be reached.", kind: .info, action: .init(label: "Retry") {})
            Banner(text: "Couldn't save your progress: disk full.", kind: .failure, action: .init(label: "Dismiss") {})
            Card { Text("Craigh na Dun Blanket").font(Font.Heather.heading) }
        }
        .padding(16)
        .background(Color.ground.weave())
        #expect(try Snapshots.assert(sheet, named: "components", size: CGSize(width: 390, height: 420)))
    }
}

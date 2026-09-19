import SwiftUI
import GraphghanCore

/// What a Done said to a phone in front of you shows (App Intents spec §4.4): the same panel and
/// band the Work screen draws, at the cursor the step landed on. The Work screen's components take
/// values, not screen state, so nothing is forked here; the band's gestures are inert in a snippet.
/// Any other outcome shows its sentence, so the card never comes up blank.
struct WorkSnippetView: View {
    let outcome: WorkIntentOutcome

    var body: some View {
        Group {
            if case .moved(let landing) = outcome {
                self.landing(landing)
            } else {
                Text(WorkIntentDialog.text(for: outcome).full)
                    .font(Font.Heather.body)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            }
        }
        .background(Color.ground)
    }

    private func landing(_ l: WorkIntentLanding) -> some View {
        let cursor = l.step.cursor
        let content = WorkPanelContent.make(chart: l.chart, sequence: l.sequence, cursor: cursor, step: l.countStep, perRepetition: l.perRepetition)
        let finished = WorkEngine.isFinished(cursor, in: l.sequence)
        return VStack(spacing: 12) {
            // The Work screen's own header line: which row, and how many there are.
            Text("Row \(cursor.row) of \(l.sequence.passes.count)").font(Font.Heather.heading).foregroundStyle(Color.ink)
            WorkPanel(content: content)
            ChartBand(chart: l.chart, sequence: l.sequence, cursor: cursor, segmentLabel: content.bandLabel, mode: finished ? .whole : .band,
                      onAdvance: {}, onJump: { _, _ in }, onToggleMode: {})
                .frame(height: 320)
        }
        .padding(12)
    }
}

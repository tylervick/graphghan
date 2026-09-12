import SwiftUI
import GraphghanCore

/// The current run on its yarn color with the next run on deck beneath it (spec §6.1).
struct SwatchStack: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let pass = sequence.pass(at: cursor.row), cursor.run < pass.runs.count {
            let run = pass.runs[cursor.run]
            let entry = chart.palette[chart.colorIndex(of: run.code) ?? 0]
            let onDeck = OnDeckRule.onDeck(cursor: cursor, chart: chart, sequence: sequence)
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(run.count)").font(Font.Heather.count).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        Text(run.code).font(Font.Heather.code).lineLimit(1)
                    }
                    Text(entry.name).font(Font.Heather.heading).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 16)
                .yarnSurface(entry.hex, radius: 16)
                .zIndex(1)
                .id(cursor)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(run.count) \(entry.name)")
                if let onDeck {
                    Text(onDeck.text)
                        .font(Font.Heather.label)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                        .yarnSurface(onDeck.hex, shape: UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous))
                        .padding(.top, -12)
                        .id(onDeck)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .clipped()
        }
    }
}

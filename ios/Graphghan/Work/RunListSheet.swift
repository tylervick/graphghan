import SwiftUI
import GraphghanCore

/// Every run of the current row as a list, for the "Jump within row" VoiceOver action and as the
/// fallback for a long-press that misses (spec §6).
struct RunListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chart: Chart
    let pass: Pass
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(Array(pass.runs.enumerated()), id: \.offset) { i, run in
                let entry = chart.palette[chart.colorIndex(of: run.code) ?? 0]
                Button { onSelect(i); dismiss() } label: {
                    HStack {
                        Chip(text: "\(run.count) \(run.code)", hex: entry.hex, state: i < current ? .done : i == current ? .current : .upcoming)
                        Text(entry.name).font(Font.Heather.body).foregroundStyle(Color.ink)
                        Spacer()
                    }
                }
                .accessibilityLabel("\(run.count) \(entry.name)\(i == current ? ", current" : i < current ? ", done" : "")")
            }
            .scrollContentBackground(.hidden)
            .background(Color.ground.weave().ignoresSafeArea())
            .navigationTitle(pass.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

import SwiftUI
import GraphghanCore

/// The current row's runs in working order: done runs dimmed, current highlighted, tap to jump.
struct RunChipsView: View {
    let chart: Chart
    let pass: Pass
    let cursor: Cursor
    let onSelect: (Int) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chipRow
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    chipRow
                }
                // The current chip's Heather ring sits 3pt outside the pill; without these the
                // scroll view clips it top and bottom on any row long enough to scroll.
                .scrollClipDisabled()
                .onChange(of: cursor, initial: true) { _, new in withAnimation { proxy.scrollTo(min(new.run, max(0, pass.runs.count - 1)), anchor: .center) } }
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(pass.runs.enumerated()), id: \.offset) { i, run in
                let hex = chart.palette[chart.colorIndex(of: run.code) ?? 0].hex
                Button { onSelect(i) } label: {
                    Chip(text: "\(run.count) \(run.code)", hex: hex, state: i < cursor.run ? .done : i == cursor.run ? .current : .upcoming)
                }
                .buttonStyle(.plain)
                .id(i)
                .accessibilityLabel("\(run.count) \(chart.palette[chart.colorIndex(of: run.code) ?? 0].name)\(i == cursor.run ? ", current" : i < cursor.run ? ", done" : "")")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

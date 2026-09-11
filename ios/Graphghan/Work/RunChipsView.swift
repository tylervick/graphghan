import SwiftUI
import GraphghanCore

/// The current row's runs in working order: done runs dimmed, current highlighted, tap to jump.
struct RunChipsView: View {
    let chart: Chart
    let pass: Pass
    let cursor: Cursor
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(pass.runs.enumerated()), id: \.offset) { i, run in
                        let hex = chart.palette[chart.colorIndex(of: run.code) ?? 0].hex
                        Button { onSelect(i) } label: {
                            Text("\(run.count) \(run.code)")
                                .font(.system(.subheadline, design: .monospaced).bold())
                                .foregroundStyle(ChartImage.isLight(hex) ? .black : .white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(ChartImage.color(hex), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == cursor.run ? Color.accentColor : .clear, lineWidth: 3))
                                .opacity(i < cursor.run ? 0.35 : 1)
                        }
                        .buttonStyle(.plain)
                        .id(i)
                        .accessibilityLabel("\(run.count) \(chart.palette[chart.colorIndex(of: run.code) ?? 0].name)\(i == cursor.run ? ", current" : i < cursor.run ? ", done" : "")")
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: cursor, initial: true) { _, new in withAnimation { proxy.scrollTo(min(new.run, max(0, pass.runs.count - 1)), anchor: .center) } }
        }
    }
}

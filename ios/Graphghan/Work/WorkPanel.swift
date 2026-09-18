import SwiftUI
import GraphghanCore

/// The current step on a card in its yarn colour (spec §5.2). Everything it shows comes from
/// `WorkPanelContent`; this file only lays it out.
///
/// Every run-like kind lays out the same slots, filled or blank, so the panel is one height for a
/// run, a braid, a repeat and a fill, and the band's top edge never moves as the row crosses from
/// one segment into the next (#84). The turn and finished panels sit centred in that same frame.
/// Blank slots keep their line's height at opacity 0 and fade in when a kind fills them.
struct WorkPanel: View {
    let content: WorkPanelContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var runLike: Bool { content.kind != .turn && content.kind != .finished }

    var body: some View {
        ZStack {
            runStack.opacity(runLike ? 1 : 0)
            if !runLike { stepStack }
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .yarnSurface(content.hex, radius: 18)
        .animation(.easeInOut(duration: 0.2), value: content.kind)
    }

    /// The boundary and finished surfaces: title, what the next row faces, and its first colour.
    private var stepStack: some View {
        VStack(spacing: 6) {
            Text(content.title ?? "").font(Font.Heather.title).multilineTextAlignment(.center)
            if let subtitle = content.subtitle { Text(subtitle).font(content.kind == .turn ? Font.Heather.heading : Font.Heather.body).multilineTextAlignment(.center) }
            if let detail = content.detail { Text(detail).font(Font.Heather.label).opacity(0.75) }
        }
    }

    /// Count, colour, then the slots a segment may or may not fill: caption, sequence line,
    /// landmark pill, on-deck line.
    private var runStack: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(content.count ?? 0)").font(Font.Heather.count).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                if let total = content.total { Text("of \(total)").font(Font.Heather.heading).monospacedDigit() }
                if let badge = content.badge {
                    Text(badge).font(Font.Heather.label).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(YarnSurface.foreground(content.hex).opacity(0.6), lineWidth: 1.5))
                }
            }
            Text("\(content.code ?? "") · \(content.name ?? "")").font(Font.Heather.heading).lineLimit(1).minimumScaleFactor(0.7)
            slot(content.segmentLabel?.uppercased(), blank: "BORDER BRAID") { Text($0).font(Font.Heather.caption).opacity(0.7).tracking(0.6) }
            if content.parts.isEmpty {
                Text("0 X").font(Font.Heather.label).lineLimit(2).opacity(0)
            } else {
                sequenceLine
            }
            // At an accessibility size the sentence would push the count and the on-deck line
            // off the card, so the pill drops rather than clipping (spec §5.2); its slot goes too.
            if !dynamicTypeSize.isAccessibilitySize {
                slot(content.landmark, blank: "ends where the colour starts below") {
                    Text($0).font(Font.Heather.label).lineLimit(2).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            slot(content.onDeck, blank: "then 11 Purple") { Text($0).font(Font.Heather.label).opacity(0.75).lineLimit(2).multilineTextAlignment(.center) }
        }
    }

    /// A line that keeps its height when it has nothing to say. `blank` is representative text so
    /// the empty slot measures the same as a filled one; it is never visible.
    @ViewBuilder private func slot(_ text: String?, blank: String, @ViewBuilder line: (String) -> some View) -> some View {
        line(text ?? blank).opacity(text == nil ? 0 : 1)
    }

    private var sequenceLine: some View {
        HStack(spacing: 8) {
            ForEach(Array(content.parts.enumerated()), id: \.offset) { _, part in
                Text(part.text).font(Font.Heather.label)
                    .opacity(part.state == .done ? 0.45 : 1)
                    .overlay(alignment: .bottom) {
                        if part.state == .current { Rectangle().fill(Color.heather).frame(height: 3).offset(y: 4) }
                    }
            }
            if let reps = content.repetitions { Text("×\(reps)").font(Font.Heather.label).opacity(0.7) }
        }
        .lineLimit(2)
    }
}

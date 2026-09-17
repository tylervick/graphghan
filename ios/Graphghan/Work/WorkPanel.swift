import SwiftUI
import GraphghanCore

/// The current step on a card in its yarn colour (spec §5.2). Everything it shows comes from
/// `WorkPanelContent`; this file only lays it out.
struct WorkPanel: View {
    let content: WorkPanelContent

    var body: some View {
        VStack(spacing: 6) {
            switch content.kind {
            case .turn, .finished:
                Text(content.title ?? "").font(Font.Heather.title).multilineTextAlignment(.center)
                if let subtitle = content.subtitle { Text(subtitle).font(content.kind == .turn ? Font.Heather.heading : Font.Heather.body).multilineTextAlignment(.center) }
                if let detail = content.detail { Text(detail).font(Font.Heather.label).opacity(0.75) }
            default:
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(content.count ?? 0)").font(Font.Heather.count).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    if let total = content.total { Text("of \(total)").font(Font.Heather.heading).monospacedDigit() }
                    if let badge = content.badge {
                        Text(badge).font(Font.Heather.label).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(YarnSurface.foreground(content.hex).opacity(0.6), lineWidth: 1.5))
                    }
                }
                Text("\(content.code ?? "") · \(content.name ?? "")").font(Font.Heather.heading).lineLimit(1).minimumScaleFactor(0.7)
                if let label = content.segmentLabel {
                    Text(label.uppercased()).font(Font.Heather.caption).opacity(0.7).tracking(0.6)
                }
                if !content.parts.isEmpty { sequenceLine }
                if let landmark = content.landmark {
                    Text(landmark).font(Font.Heather.label).lineLimit(2).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let onDeck = content.onDeck { Text(onDeck).font(Font.Heather.label).opacity(0.75).lineLimit(2).multilineTextAlignment(.center) }
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .yarnSurface(content.hex, radius: 18)
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

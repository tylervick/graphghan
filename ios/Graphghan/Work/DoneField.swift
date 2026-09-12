import SwiftUI

/// Everything below the card: the Back rail on the leading edge, Done (or Close) filling the rest
/// (spec §6.1). The whole field is the tap target; the pill in the middle is the visual, and it
/// takes the current run's yarn color so the button says which color you're confirming.
struct DoneField: View {
    let finished: Bool
    let canGoBack: Bool
    let doneLabel: String
    /// The current run's yarn color, or nil when finished (the pill turns cream and reads Close).
    let doneHex: String?
    let onDone: () -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if !finished {
                Button(action: onBack) {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 26, weight: .semibold))
                        Text("Back").font(Font.Heather.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.bottom, 40)
                    .frame(width: 84)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(Color.cream.opacity(canGoBack ? 0.85 : 0.35))
                    .background(Color.mossDeep, in: UnevenRoundedRectangle(topTrailingRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .accessibilityLabel("Back one run")
            }
            Button(action: onDone) {
                DonePill(title: finished ? "Close" : "Done", hex: doneHex)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doneLabel)
        }
    }
}

/// The Done label on a capsule in the yarn color: Liquid Glass tinted with it on iOS 26, a flat
/// yarn surface before that. Cream with Ink text when there is no run (the finished Close).
private struct DonePill: View {
    let title: String
    let hex: String?

    var body: some View {
        let label = Text(title)
            .font(Font.Heather.done)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(.horizontal, 24)
        if #available(iOS 26, *) {
            label
                .foregroundStyle(foreground)
                .glassEffect(.regular.tint(fill).interactive(), in: Capsule())
        } else if let hex {
            label.yarnSurface(hex, shape: Capsule())
        } else {
            label
                .foregroundStyle(Color.ink)
                .background(Color.cream, in: Capsule())
                .overlay(Capsule().strokeBorder(YarnSurface.hairline, lineWidth: 1))
        }
    }

    private var fill: Color { hex.map(YarnSurface.fill) ?? Color.cream }
    private var foreground: Color { hex.map(YarnSurface.foreground) ?? Color.ink }
}

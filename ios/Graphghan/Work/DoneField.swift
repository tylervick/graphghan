import SwiftUI

/// The controls that float over the chart backdrop at the bottom of the Work screen (spec §6.1):
/// Back as a small moss glass capsule at the leading edge, Done (or Close) as a wide glass capsule
/// in the current run's yarn color, so the button says which color you're confirming. The backdrop
/// itself is the big Done target; these are the visible handles on it.
struct DoneField: View {
    let finished: Bool
    let canGoBack: Bool
    let doneLabel: String
    /// The current run's yarn color, or nil when finished (the pill turns cream and reads Close).
    let doneHex: String?
    let onDone: () -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if !finished {
                Button(action: onBack) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 22, weight: .semibold))
                        Text("Back").font(Font.Heather.label).lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .frame(width: 84, height: 72)
                    .foregroundStyle(Color.cream.opacity(canGoBack ? 1 : 0.4))
                    .glassCapsule(tint: .mossDeep)
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .accessibilityLabel("Back one run")
            }
            Button(action: onDone) {
                Text(finished ? "Close" : "Done")
                    .font(Font.Heather.done)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .padding(.horizontal, 24)
                    .foregroundStyle(doneHex.map(YarnSurface.foreground) ?? Color.ink)
                    .glassCapsule(tint: doneHex.map(YarnSurface.fill) ?? Color.cream)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(doneLabel)
        }
    }
}

private extension View {
    /// Liquid Glass tinted with `tint` on iOS 26; a flat tinted capsule with the yarn hairline before that.
    @ViewBuilder func glassCapsule(tint: Color) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            background(tint, in: Capsule())
                .overlay(Capsule().strokeBorder(YarnSurface.hairline, lineWidth: 1))
        }
    }
}

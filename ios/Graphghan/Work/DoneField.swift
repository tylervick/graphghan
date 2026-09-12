import SwiftUI

/// Everything below the card: the Back rail on the leading edge, Done (or Close) filling the rest (spec §6.1).
struct DoneField: View {
    let finished: Bool
    let canGoBack: Bool
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
                Text(finished ? "Close" : "Done")
                    .font(Font.Heather.done)
                    .foregroundStyle(Color.cream)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

import SwiftUI

/// A run or a palette entry in its yarn color (spec §6.3).
struct Chip: View {
    enum State { case plain, upcoming, current, done }
    let text: String
    let hex: String
    var state: State = .plain

    var body: some View {
        Text(text)
            .font(Font.Heather.label)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: 52, minHeight: 36)
            .yarnSurface(hex, shape: Capsule())
            .background {
                if state == .current { Capsule().stroke(Color.heather, lineWidth: 3).padding(-3) }
            }
            .opacity(state == .done ? 0.35 : 1)
    }
}

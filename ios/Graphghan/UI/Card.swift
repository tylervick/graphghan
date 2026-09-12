import SwiftUI

/// Panel, 14pt radius, one Line hairline, no shadow (spec §6.2).
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
    }
}

extension View {
    /// Grouped lists keep their sections; rows sit on Panel with a Line hairline instead of the system gray.
    func listRowBackgroundPanel() -> some View {
        environment(\.defaultMinListRowHeight, 44)
            .listRowBackground(Color.panel)
            .listSectionSeparatorTint(Color.line)
    }
}

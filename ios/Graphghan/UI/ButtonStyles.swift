import SwiftUI

/// Moss fill, Cream text, pill, 50pt (spec §6.4).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.Heather.label)
            .foregroundStyle(Color.cream)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.moss.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

/// Panel fill, Line border, Moss text.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.Heather.label)
            .foregroundStyle(Color.moss)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.panel.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var secondary: SecondaryButtonStyle { .init() } }

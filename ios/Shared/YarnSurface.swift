import SwiftUI

/// Every surface painted in a yarn color from a chart goes through here (spec §3): the fill, the
/// foreground that reads on it, and the hairline that keeps cream visible on cream.
enum YarnSurface {
    static let hairline = Color.black.opacity(0.14)
    /// A run whose color code isn't in the palette (stale or corrupt chart data): neutral gray
    /// rather than nothing, so the swatch still renders.
    static let unknownHex = "#888888"
    /// Dark ink for light yarn (#2B2723), warm cream for dark yarn (#F4EFE6).
    private static let darkText = Color(red: 0x2B / 255, green: 0x27 / 255, blue: 0x23 / 255)
    private static let lightText = Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255)

    static func fill(_ hex: String) -> Color { HexColor.color(hex) }
    static func foreground(_ hex: String) -> Color { HexColor.isLight(hex) ? darkText : lightText }
}

struct YarnSurfaceModifier<S: InsettableShape>: ViewModifier {
    let hex: String
    let shape: S

    func body(content: Content) -> some View {
        content
            .foregroundStyle(YarnSurface.foreground(hex))
            .background(YarnSurface.fill(hex), in: shape)
            .overlay(shape.strokeBorder(YarnSurface.hairline, lineWidth: 1))
    }
}

extension View {
    func yarnSurface(_ hex: String, radius: CGFloat) -> some View {
        modifier(YarnSurfaceModifier(hex: hex, shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }
    func yarnSurface<S: InsettableShape>(_ hex: String, shape: S) -> some View {
        modifier(YarnSurfaceModifier(hex: hex, shape: shape))
    }
}

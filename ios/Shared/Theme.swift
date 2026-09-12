import SwiftUI

/// The Heather tokens (spec §3). Named sets live in Shared/Tokens.xcassets so the widget gets them too.
extension Color {
    static let ground = Color("Ground")
    static let panel = Color("Panel")
    static let ink = Color("Ink")
    static let ink2 = Color("Ink2")
    static let line = Color("Line")
    static let heather = Color("Heather")
    static let moss = Color("Moss")
    static let mossDeep = Color("MossDeep")
    /// Text on Moss (#F4F5F0). Not a set: it does not change with the theme.
    static let cream = Color(red: 0xF4 / 255, green: 0xF5 / 255, blue: 0xF0 / 255)
    /// The save-failure rule (#9C3B3B).
    static let brick = Color(red: 0x9C / 255, green: 0x3B / 255, blue: 0x3B / 255)
}

/// The tweed weave (spec §4): 1pt hairlines at 135°, 5pt pitch. Painted behind whatever the caller
/// layers on top afterward (it never intercepts hits), but visually on top of `content` itself:
/// `.background` would draw the canvas underneath an opaque fill like `.ground`, which fully hides
/// it, so the texture would never be visible.
struct Weave: ViewModifier {
    var color: Color = .ink
    var opacity: Double = 0.045

    func body(content: Content) -> some View {
        content.overlay {
            Canvas { context, size in
                let step: CGFloat = 5 * 2.0.squareRoot()
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += step
                }
                context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 1)
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func weave(_ color: Color = .ink, opacity: Double = 0.045) -> some View {
        modifier(Weave(color: color, opacity: opacity))
    }
}

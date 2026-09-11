import SwiftUI

/// `#RRGGBB` → Color, plus the same light/dark rule the PWA uses. Shared so the widget needs no app code.
enum HexColor {
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return (0.53, 0.53, 0.53) }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
    static func color(_ hex: String) -> Color { let c = rgb(hex); return Color(red: c.r, green: c.g, blue: c.b) }
    static func isLight(_ hex: String) -> Bool { let c = rgb(hex); return (c.r * 299 + c.g * 587 + c.b * 114) / 1000 * 255 >= 140 }
}

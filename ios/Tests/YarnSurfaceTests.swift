import SwiftUI
import Testing
import UIKit
@testable import Graphghan

@MainActor
@Suite struct YarnSurfaceTests {
    private func luminance(_ color: Color) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Cream yarn gets dark text, charcoal yarn gets light text; the split is the PWA's 140/255 rule.
    @Test func foregroundFollowsLuminance() {
        #expect(luminance(YarnSurface.foreground("#F2E8D5")) < 0.3)
        #expect(luminance(YarnSurface.foreground("#2B2F33")) > 0.8)
        #expect(luminance(YarnSurface.foreground("#D9A21B")) < 0.3)   // gold is light by the rule
        #expect(luminance(YarnSurface.foreground("#1E4D3A")) > 0.8)
    }

    /// The hairline is what keeps cream on cream visible: 14% black.
    @Test func hairlineIsFourteenPercentBlack() {
        var a: CGFloat = 0
        UIColor(YarnSurface.hairline).getRed(nil, green: nil, blue: nil, alpha: &a)
        #expect(abs(a - 0.14) < 0.01)
    }

    /// A cream swatch on the cream ground still shows its edge.
    @Test func creamOnCream() throws {
        let view = Text("51 C").font(Font.Heather.label).padding(12).yarnSurface("#F2E8D5", radius: 18)
            .padding(12).background(Color(red: 0xF2 / 255, green: 0xE8 / 255, blue: 0xD5 / 255))
        #expect(try Snapshots.assert(view, named: "yarn-cream-on-cream", size: CGSize(width: 120, height: 70)))
    }
}

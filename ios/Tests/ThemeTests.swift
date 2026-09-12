import SwiftUI
import Testing
import UIKit
@testable import Graphghan

@MainActor
@Suite struct ThemeTests {
    /// Every token resolves from the shared catalog (a missing set resolves to clear, which is what this catches).
    @Test func tokensResolve() {
        for name in ["Ground", "Panel", "Ink", "Ink2", "Line", "Heather", "Moss", "MossDeep"] {
            #expect(UIColor(named: name) != nil, "missing color set \(name)")
        }
        #expect(UIColor(Color.ground).cgColor.components?.first != nil)
    }

    /// The bundled faces register under the PostScript names Typography.swift uses. If one is nil,
    /// dump `UIFont.familyNames.flatMap(UIFont.fontNames(forFamilyName:))` and fix the name.
    @Test func fontsRegister() {
        for name in ["Literata-SemiBold", "Literata-MediumItalic", "AtkinsonHyperlegible-Regular", "AtkinsonHyperlegible-Bold", "Nunito-Black"] {
            #expect(UIFont(name: name, size: 17) != nil, "font \(name) not registered")
        }
    }

    @Test func weaveRenders() throws {
        #expect(try Snapshots.assert(Color.ground.weave().frame(width: 60, height: 60), named: "weave", size: CGSize(width: 60, height: 60)))
    }
}

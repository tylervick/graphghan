import SwiftUI
import UIKit

extension Font {
    /// The Heather type ramp (spec §5.2). Every style scales with Dynamic Type except `done`.
    enum Heather {
        static let title = Font.custom("Literata-SemiBold", size: 28, relativeTo: .largeTitle)
        static let heading = Font.custom("Literata-SemiBold", size: 22, relativeTo: .title2)
        static let rowNumber = Font.custom("Literata-SemiBold", size: 26, relativeTo: .title)
        static let done = Font.custom("Literata-SemiBold", fixedSize: 48)
        static let quote = Font.custom("Literata-MediumItalic", size: 17, relativeTo: .body)
        static let body = Font.custom("AtkinsonHyperlegible-Regular", size: 17, relativeTo: .body)
        static let label = Font.custom("AtkinsonHyperlegible-Bold", size: 15, relativeTo: .subheadline)
        static let caption = Font.custom("AtkinsonHyperlegible-Regular", size: 13, relativeTo: .footnote)
        static let count = Font.custom("Nunito-Black", size: 84, relativeTo: .largeTitle)
        static let code = Font.custom("AtkinsonHyperlegible-Bold", size: 34, relativeTo: .title)
    }
}

enum Theme {
    /// Navigation and tab bars are UIKit underneath (spec §6.5): Ground behind both, Literata titles, Moss tint.
    @MainActor static func installAppearance() {
        let ground = UIColor(named: "Ground") ?? .systemBackground
        let ink = UIColor(named: "Ink") ?? .label
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = ground
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: ink, .font: UIFont(name: "Literata-SemiBold", size: 17) ?? .preferredFont(forTextStyle: .headline)]
        nav.largeTitleTextAttributes = [.foregroundColor: ink, .font: UIFont(name: "Literata-SemiBold", size: 34) ?? .preferredFont(forTextStyle: .largeTitle)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = ground
        tab.shadowColor = UIColor(named: "Line")
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

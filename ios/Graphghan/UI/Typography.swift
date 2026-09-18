import SwiftUI
import UIKit

extension Font {
    /// The Heather type ramp (spec §5.2). Every style scales with Dynamic Type except `done` and
    /// `annotation`.
    enum Heather {
        static let title = Font.custom("Literata-SemiBold", size: 28, relativeTo: .largeTitle)
        static let heading = Font.custom("Literata-SemiBold", size: 22, relativeTo: .title2)
        static let rowNumber = Font.custom("Literata-SemiBold", size: 26, relativeTo: .title)
        static let done = Font.custom("Literata-SemiBold", fixedSize: 48)
        static let quote = Font.custom("Literata-MediumItalic", size: 17, relativeTo: .body)
        static let body = Font.custom("AtkinsonHyperlegible-Regular", size: 17, relativeTo: .body)
        static let label = Font.custom("AtkinsonHyperlegible-Bold", size: 15, relativeTo: .subheadline)
        static let caption = Font.custom("AtkinsonHyperlegible-Regular", size: 13, relativeTo: .footnote)
        /// Labels drawn inside a chart (the band's ruler): fixed, because they annotate an 8 pt grid
        /// and a scaled label overflows its strip rather than wrapping (#72).
        static let annotation = Font.custom("AtkinsonHyperlegible-Regular", fixedSize: 13)
        static let count = Font.custom("Nunito-Black", size: 84, relativeTo: .largeTitle)
        static let code = Font.custom("AtkinsonHyperlegible-Bold", size: 34, relativeTo: .title)
    }
}

enum Theme {
    /// Navigation and tab bars are UIKit underneath (spec §6.5): Ground behind both, Literata titles, Moss tint.
    @MainActor static func installAppearance() {
        let ground = UIColor(named: "Ground") ?? .systemBackground
        let ink = UIColor(named: "Ink") ?? .label
        // Transparent, not opaque: the screen behind the bar already paints Ground with the weave
        // under the safe area, and an opaque bar hid it (and on iOS 26 fought the system bar's
        // scroll transitions). The bar contributes only its type.
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
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
        let ink2 = UIColor(named: "Ink2")
        let moss = UIColor(named: "Moss")
        let styleItem: (UITabBarItemAppearance) -> Void = { item in
            item.normal.iconColor = ink2
            item.normal.titleTextAttributes = [.foregroundColor: ink2 ?? .secondaryLabel]
            item.selected.iconColor = moss
            item.selected.titleTextAttributes = [.foregroundColor: moss ?? .label]
        }
        styleItem(tab.stackedLayoutAppearance)
        styleItem(tab.inlineLayoutAppearance)
        styleItem(tab.compactInlineLayoutAppearance)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

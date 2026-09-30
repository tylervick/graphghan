import SwiftUI
import GraphghanCore

/// One written row's card (spec §6.4): the pass's label, its text at heading size with no
/// `.lineLimit`, and its count as a badge in the chart screen's `sc`-badge style. One
/// accessibility element, spoken as the row and the row's own words.
///
/// Split out of `WrittenWorkScreen` so it can be snapshotted on its own: `WrittenWorkScreen`
/// scrolls this inside a `ScrollView` (a long row must never push the Back/Done bar off-screen),
/// but `ImageRenderer` cannot flatten a `ScrollView` -- its content renders blank (#67) -- so the
/// full-screen snapshots can't show what's inside the scroll region. This view, rendered
/// unscrolled, is what actually pins the row text down.
struct WrittenRowPanel: View {
    let pass: WrittenPass
    /// The header's row text ("Row 3 of 5"), folded into this view's accessibility label so a
    /// VoiceOver user gets the row and the row's own words from one element.
    let rowText: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(pass.label).font(Font.Heather.label).foregroundStyle(Color.ink2)
                Text(pass.text).font(Font.Heather.heading).foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let count = pass.count {
                    Text("\(count) sts").font(Font.Heather.label).foregroundStyle(Color.ink2)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(Color.ink2.opacity(0.6), lineWidth: 1.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rowText). \(pass.text)")
    }
}

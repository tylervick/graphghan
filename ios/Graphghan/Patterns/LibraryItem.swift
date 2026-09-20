import Foundation
import GraphghanCore

/// A row of the Patterns tab, and what the detail screen needs to know about it: whether this
/// pattern came from the site or from a file someone opened (#16).
///
/// The two behave differently in ways the maker has to be able to see. A site pattern updates
/// when the feed does and can always be downloaded again; a local one never changes, is not on
/// the site, and is the only copy of itself. The tab keeps them in separate sections for that
/// reason, and this is what tells them apart.
struct LibraryItem: Hashable, Identifiable {
    enum Source: Hashable { case site, local }

    let entry: IndexEntry
    let source: Source

    var id: String { "\(source)/\(entry.slug)" }
    var slug: String { entry.slug }
    var isLocal: Bool { source == .local }
}

import AppIntents
import CoreSpotlight
import Foundation

/// A project as Siri and Spotlight see it (App Intents spec §4.1): a projection of the SwiftData
/// store through `AppModel.projectSnapshots`, never a second copy. Every field already exists on
/// `Project` or comes from the chart; no new storage, no network.
///
/// Available on the app's floor rather than gated, because the optional `project` parameter on
/// `MarkDoneIntent` is a stored property and Swift cannot gate one. What the SDK does gate --
/// `IndexedEntity` and the index itself -- sits under `@available(iOS 18, *)` below. There is no
/// `@AppEntity` macro without an app schema in this SDK, and no schema fits a crochet counter, so
/// this is a plain conformance.
struct ProjectEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Project")
    static let defaultQuery = ProjectEntityQuery()

    var id: UUID
    @Property(title: "Title") var title: String
    @Property(title: "Pattern") var patternTitle: String
    @Property(title: "Percent done") var percent: Double
    @Property(title: "Last worked") var lastWorked: Date?
    var isFinished: Bool

    init(_ snapshot: ProjectSnapshot) {
        // Plain stored fields first: assigning a wrapped property goes through its wrapper, which
        // needs `self` whole.
        id = snapshot.id
        isFinished = snapshot.isFinished
        title = snapshot.title
        patternTitle = snapshot.patternTitle
        percent = snapshot.percent
        lastWorked = snapshot.lastWorked
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(Self.percentText(percent)) · \(patternTitle)")
    }

    /// "43%" for a whole number, "43.5%" otherwise: the tenth is real, the trailing zero is noise.
    static func percentText(_ percent: Double) -> String {
        percent == percent.rounded() ? "\(Int(percent))%" : String(format: "%.1f%%", percent)
    }
}

/// Resolution by id, by name, and the list Siri offers (spec §4.2). Reads the app's projection
/// after the registration wait, so a query that launches the app in the background sees the store.
struct ProjectEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProjectEntity] {
        try await snapshots().filter { identifiers.contains($0.id) }.map(ProjectEntity.init)
    }

    /// Unfinished projects, most recently worked first: what "which blanket" should offer.
    func suggestedEntities() async throws -> [ProjectEntity] {
        try await snapshots().filter { !$0.isFinished }
            .sorted { ($0.lastWorked ?? .distantPast) > ($1.lastWorked ?? .distantPast) }
            .map(ProjectEntity.init)
    }

    /// A spoken name matches the project's own title or its pattern's, so "the Craigh na Dun
    /// blanket" finds a project the maker titled "For Meaghan".
    func entities(matching string: String) async throws -> [ProjectEntity] {
        let needle = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return try await snapshots()
            .filter { $0.title.localizedCaseInsensitiveContains(needle) || $0.patternTitle.localizedCaseInsensitiveContains(needle) }
            .map(ProjectEntity.init)
    }

    @MainActor
    private func snapshots() async throws -> [ProjectSnapshot] {
        guard await WorkIntentHandler.shared.awaitRegistration(), let read = WorkIntentHandler.shared.projectSnapshots else {
            throw WorkIntentError.appNotReady
        }
        return await read()
    }
}

@available(iOS 18, *)
extension ProjectEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.contentDescription = "\(Self.percentText(percent)) · \(patternTitle)"
        set.keywords = [patternTitle, "crochet", "graphghan", "blanket"]
        return set
    }
}

/// Keeps Spotlight honest with the store (spec §4.2): every create, finish, chart switch and
/// delete refreshes the whole set, which is tens of projects at most. Spotlight is a cache of the
/// store, so a failed refresh is not an error the maker can act on; the next mutation tries again.
@available(iOS 18, *)
enum ProjectIndexer {
    static func refresh(_ snapshots: [ProjectSnapshot], index: CSSearchableIndex = .default()) async {
        do {
            try await index.deleteAppEntities(ofType: ProjectEntity.self)
            try await index.indexAppEntities(snapshots.map(ProjectEntity.init))
        } catch {
            // see above
        }
    }
}

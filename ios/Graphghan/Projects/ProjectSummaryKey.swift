import Foundation
import GraphghanCore

/// When a project's progress summary is worth recomputing. `summary(for:)` walks every event of
/// the project and re-faults the relationship after each save, which costs tens of milliseconds
/// per call on a phone; a view that is alive under the Work cover must not pay that on every tap.
/// So the key is nil while the project is being worked (the view is hidden and nothing it shows
/// can be seen) and changes once when the cover closes or the project is mutated from the view.
struct ProjectSummaryKey: Hashable {
    let cursor: Cursor
    let lastWorked: Date?
    let finished: Date?

    static func make(for project: Project, working: Project?) -> ProjectSummaryKey? {
        if let working, working.id == project.id { return nil }
        return ProjectSummaryKey(cursor: project.cursor, lastWorked: project.lastWorked, finished: project.finished)
    }
}

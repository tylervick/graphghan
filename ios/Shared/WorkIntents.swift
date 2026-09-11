import AppIntents
import Foundation
import GraphghanCore

/// The app registers this at launch. In the widget process nothing registers it and `perform` is
/// never called there: `LiveActivityIntent`s run in the app.
@MainActor
final class WorkIntentHandler {
    static let shared = WorkIntentHandler()
    var perform: ((WorkAction, UUID) async -> Void)?
}

struct AdvanceRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Done with this run"
    static let description = IntentDescription("Marks the current run done and moves to the next.")
    static let openAppWhenRun = false

    @Parameter(title: "Project") var projectID: String

    init() {}
    init(projectID: UUID) { self.projectID = projectID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: projectID) { await WorkIntentHandler.shared.perform?(.advance, id) }
        return .result()
    }
}

struct BackRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Back one run"
    static let description = IntentDescription("Undoes the last run.")
    static let openAppWhenRun = false

    @Parameter(title: "Project") var projectID: String

    init() {}
    init(projectID: UUID) { self.projectID = projectID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: projectID) { await WorkIntentHandler.shared.perform?(.back, id) }
        return .result()
    }
}

import AppIntents
import Foundation
import GraphghanCore

/// What a Done or Back on the working project came to, for an intent to put into words
/// (App Intents spec §3.4).
enum WorkIntentOutcome: Sendable {
    /// Spec §3.2 found nothing: no live activity, no unfinished project.
    case noProject
    /// The working project's chart file could not be read.
    case chartUnavailable(title: String)
    /// `ProjectService.apply` returned nil: Back at the very start, Done past the end.
    case nowhereToGo(WorkAction)
    case moved(WorkStep, in: WorkSequence)
}

/// The app registers this at launch (`AppModel.live`). In the widget process nothing registers it
/// and `perform` is never called there: `LiveActivityIntent`s run in the app, and the discoverable
/// intents compile into the app target alone.
///
/// A request can launch the app in the background, and nothing promises the intent performs after
/// `AppModel.live` has claimed the handler. `awaitRegistration` is what keeps a Done from vanishing
/// in that window: every intent waits for the app before it looks for its slot.
@MainActor
final class WorkIntentHandler {
    static let shared = WorkIntentHandler()

    /// A step on the project the caller names: the lock-screen and island buttons.
    var perform: ((WorkAction, UUID) async -> Void)?
    /// A step on the project being worked, which the app resolves (spec §3.2): Siri, Shortcuts,
    /// the Action Button.
    var performWorking: ((WorkAction) async -> WorkIntentOutcome)?

    var isRegistered: Bool { perform != nil && performWorking != nil }

    /// True once the app has claimed the handler, waiting up to `timeout` for it. Polling on the
    /// main actor keeps this free of continuations that a registration would have to remember to
    /// resume; a 25 ms tick is nothing next to the request that got here.
    func awaitRegistration(timeout: Duration = .seconds(5)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !isRegistered, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        return isRegistered
    }
}

struct AdvanceRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Done with this run"
    static let description = IntentDescription("Marks the current run done and moves to the next.")
    static let openAppWhenRun = false
    // Lock-screen and island buttons only: the Siri surface is `MarkDoneIntent`, which resolves its
    // own project (spec §3.1). Exposing this one would put a bare UUID field in Shortcuts.
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Project") var projectID: String

    init() {}
    init(projectID: UUID) { self.projectID = projectID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: projectID), await WorkIntentHandler.shared.awaitRegistration() else { return .result() }
        await WorkIntentHandler.shared.perform?(.advance, id)
        return .result()
    }
}

struct BackRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Back one run"
    static let description = IntentDescription("Undoes the last run.")
    static let openAppWhenRun = false
    // Lock-screen and island buttons only: the Siri surface is `UndoDoneIntent` (spec §3.1).
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Project") var projectID: String

    init() {}
    init(projectID: UUID) { self.projectID = projectID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: projectID), await WorkIntentHandler.shared.awaitRegistration() else { return .result() }
        await WorkIntentHandler.shared.perform?(.back, id)
        return .result()
    }
}

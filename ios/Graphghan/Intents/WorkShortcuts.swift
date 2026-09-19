import AppIntents
import GraphghanCore

/// The Siri, Shortcuts and Action Button surface (App Intents spec §3). Two plain `AppIntent`s
/// beside the `LiveActivityIntent`s in `Shared/WorkIntents.swift`, in the app target on purpose:
/// `Shared/` also compiles into the widget extension, and a plain intent an extension declares runs
/// in that extension, where nothing has registered `WorkIntentHandler`. The lock-screen pair is
/// safe there because the system runs a `LiveActivityIntent` in the app.
///
/// Neither intent names a project. Voice acts on the project being worked (spec §3.2), and one
/// spoken Done is one tapped Done: the project's count step, or the rest of the run.
struct MarkDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark the next stitches done"
    // One literal: `IntentDescription` takes a `LocalizedStringResource`, which a concatenation is not.
    static let description = IntentDescription("Counts one Done in the crochet chart you are working — the project's count step, or the rest of the run — and moves the cursor, exactly as the Done button does.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: WorkIntentDialog.dialog(for: try await WorkIntentHandler.shared.stepWorkingProject(.advance)))
    }
}

struct UndoDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo the last done"
    static let description = IntentDescription("Takes back the last Done in the crochet chart you are working and moves the cursor back, exactly as the Back button does.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: WorkIntentDialog.dialog(for: try await WorkIntentHandler.shared.stepWorkingProject(.back)))
    }
}

/// Spec §3.3. Every phrase carries the app name, which App Intents requires and which keeps "done"
/// and "back" -- two of the most contested verbs on the system -- pointed at this app. `shortTitle`
/// and `systemImageName` are what the Action Button picker shows.
struct GraphghanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkDoneIntent(),
            phrases: [
                "Done in \(.applicationName)",
                "Next in \(.applicationName)",
                "Mark a done in \(.applicationName)",
            ],
            shortTitle: "Done",
            systemImageName: "checkmark")
        AppShortcut(
            intent: UndoDoneIntent(),
            phrases: [
                "Back in \(.applicationName)",
                "Undo that in \(.applicationName)",
            ],
            shortTitle: "Back",
            systemImageName: "arrow.uturn.backward")
    }
}

enum WorkIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// The app never registered the handler within the wait: Siri says so instead of confirming a
    /// count that did not happen.
    case appNotReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: return "Graphghan isn't ready yet. Try again in a moment."
        }
    }
}

extension WorkIntentHandler {
    /// The working-project step for a discoverable intent: waits for the app (spec §3.1), then
    /// performs. Throwing, not no-op'ing, is what keeps a dropped Done from being confirmed.
    func stepWorkingProject(_ action: WorkAction, timeout: Duration = .seconds(5)) async throws -> WorkIntentOutcome {
        guard await awaitRegistration(timeout: timeout), let performWorking else { throw WorkIntentError.appNotReady }
        return await performWorking(action)
    }
}

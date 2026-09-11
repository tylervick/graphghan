import Foundation
import Observation
import GraphghanCore

/// Spec §7 lifecycle: one activity at a time, started with the Work screen, ended on close or
/// finish, restarted after the system's 8-hour end, reconciled on launch.
@MainActor
@Observable
final class LiveActivityController {
    static let hintShownKey = "liveActivityHintShown"
    static let unavailableMessage = "This project is no longer available."

    private let backend: ActivityBackend
    private let defaults: UserDefaults
    private(set) var currentID: String?
    private(set) var currentProjectID: UUID?
    /// One-time pointer at Settings when activities are off or cannot start.
    var settingsHint: String?

    init(backend: ActivityBackend, defaults: UserDefaults) {
        self.backend = backend
        self.defaults = defaults
    }

    func dismissHint() { settingsHint = nil }

    func start(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async {
        if let existing = backend.active().first(where: { $0.info.projectID == projectID }) {
            currentID = existing.id
            currentProjectID = projectID
            await backend.update(id: existing.id, state: state)
            return
        }
        for other in backend.active() { await backend.end(id: other.id, state: nil, immediately: true) }
        currentID = nil
        currentProjectID = nil
        guard backend.areActivitiesEnabled else { hintOnce(); return }
        do {
            currentID = try backend.start(info: info, state: state)
            currentProjectID = projectID
        } catch {
            hintOnce()
        }
    }

    func update(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async {
        guard currentProjectID == projectID else { return }
        if state.finished {
            await end(projectID: projectID, finalState: state)
            return
        }
        if let id = currentID, backend.active().contains(where: { $0.id == id }) {
            await backend.update(id: id, state: state)
        } else {
            // The system ended it (8-hour limit): the next advance starts a fresh one.
            currentID = nil
            await start(projectID: projectID, info: info, state: state)
        }
    }

    func end(projectID: UUID, finalState: WorkActivityState?) async {
        guard currentProjectID == projectID, let id = currentID else { return }
        await backend.end(id: id, state: finalState, immediately: true)
        currentID = nil
        currentProjectID = nil
    }

    func endAll() async {
        for a in backend.active() { await backend.end(id: a.id, state: nil, immediately: true) }
        currentID = nil
        currentProjectID = nil
    }

    func endUnavailable(activityID: String, message: String) async {
        await backend.end(id: activityID, state: .unavailable(message), immediately: true)
        if currentID == activityID { currentID = nil; currentProjectID = nil }
    }

    /// On launch: refresh every active activity from the stored cursor, or end the ones whose
    /// project or chart is gone. The stored cursor wins.
    func reconcile(stateFor: (WorkActivityInfo) async -> WorkActivityState?) async {
        for a in backend.active() {
            if let state = await stateFor(a.info) {
                await backend.update(id: a.id, state: state)
                if currentID == nil { currentID = a.id; currentProjectID = a.info.projectID }
            } else {
                await endUnavailable(activityID: a.id, message: Self.unavailableMessage)
            }
        }
    }

    private func hintOnce() {
        guard !defaults.bool(forKey: Self.hintShownKey) else { return }
        defaults.set(true, forKey: Self.hintShownKey)
        settingsHint = "Live Activities are off for Graphghan, so the lock screen won't show your row. Turn them on in Settings › Graphghan."
    }
}

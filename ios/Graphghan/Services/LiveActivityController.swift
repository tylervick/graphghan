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

    // Serializes every mutating entry point so concurrent calls run one at a time, in arrival
    // order. Without this, one call's `await` (e.g. inside its end-others loop) can suspend
    // while another call reads a stale `active()` snapshot or clobbers `currentID`/
    // `currentProjectID`, leaving two activities live. `acquire`/`release` form a simple FIFO
    // async mutex; each public method acquires it, defers the release, then runs the private
    // `_`-prefixed implementation. Methods that call each other internally (`update` → `end`/
    // `start`, `reconcile` → `endUnavailable`) call the private variant directly so they don't
    // try to re-acquire a mutex they're already holding.
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(backend: ActivityBackend, defaults: UserDefaults) {
        self.backend = backend
        self.defaults = defaults
    }

    func dismissHint() { settingsHint = nil }

    func start(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async {
        await acquire()
        defer { release() }
        await _start(projectID: projectID, info: info, state: state)
    }

    func update(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async {
        await acquire()
        defer { release() }
        await _update(projectID: projectID, info: info, state: state)
    }

    func end(projectID: UUID, finalState: WorkActivityState?) async {
        await acquire()
        defer { release() }
        await _end(projectID: projectID, finalState: finalState)
    }

    func endUnavailable(activityID: String, message: String) async {
        await acquire()
        defer { release() }
        await _endUnavailable(activityID: activityID, message: message)
    }

    func reconcile(stateFor: (WorkActivityInfo) async -> WorkActivityState?) async {
        await acquire()
        defer { release() }
        await _reconcile(stateFor: stateFor)
    }

    private func acquire() async {
        if !isBusy { isBusy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { isBusy = false } else { waiters.removeFirst().resume() }
    }

    private func _start(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async {
        if let existing = backend.active().first(where: { $0.info.projectID == projectID }) {
            currentID = existing.id
            currentProjectID = projectID
            await backend.update(id: existing.id, state: state)
            return
        }
        currentID = nil
        currentProjectID = nil
        for other in backend.active() { await backend.end(id: other.id, state: nil, immediately: true) }
        guard backend.areActivitiesEnabled else { hintOnce(); return }
        do {
            currentID = try backend.start(info: info, state: state)
            currentProjectID = projectID
        } catch {
            hintOnce()
        }
    }

    private func _update(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async {
        guard currentProjectID == projectID else { return }
        if state.finished {
            await _end(projectID: projectID, finalState: state)
            return
        }
        if let id = currentID, backend.active().contains(where: { $0.id == id }) {
            await backend.update(id: id, state: state)
        } else {
            // The system ended it (8-hour limit): the next advance starts a fresh one.
            currentID = nil
            await _start(projectID: projectID, info: info, state: state)
        }
    }

    private func _end(projectID: UUID, finalState: WorkActivityState?) async {
        guard currentProjectID == projectID, let id = currentID else { return }
        // A plain close stays immediate; a finished final state uses the default dismissal so
        // the lock screen briefly shows the explanatory final state instead of vanishing at once.
        await backend.end(id: id, state: finalState, immediately: !(finalState?.finished ?? false))
        currentID = nil
        currentProjectID = nil
    }

    private func _endUnavailable(activityID: String, message: String) async {
        await backend.end(id: activityID, state: .unavailable(message), immediately: false)
        if currentID == activityID { currentID = nil; currentProjectID = nil }
    }

    /// On launch: refresh every active activity from the stored cursor, or end the ones whose
    /// project or chart is gone. The stored cursor wins. A refreshed activity that has since
    /// finished is ended (with the default dismissal, showing the final state) rather than
    /// adopted as current.
    private func _reconcile(stateFor: (WorkActivityInfo) async -> WorkActivityState?) async {
        for a in backend.active() {
            if let state = await stateFor(a.info) {
                if state.finished {
                    await backend.end(id: a.id, state: state, immediately: false)
                    if currentID == a.id { currentID = nil; currentProjectID = nil }
                } else {
                    await backend.update(id: a.id, state: state)
                    if currentID == nil { currentID = a.id; currentProjectID = a.info.projectID }
                }
            } else {
                await _endUnavailable(activityID: a.id, message: Self.unavailableMessage)
            }
        }
    }

    private func hintOnce() {
        guard !defaults.bool(forKey: Self.hintShownKey) else { return }
        defaults.set(true, forKey: Self.hintShownKey)
        settingsHint = "Live Activities are off for Graphghan, so the lock screen won't show your row. Turn them on in Settings › Graphghan."
    }
}

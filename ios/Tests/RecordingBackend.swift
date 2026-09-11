import Foundation
import GraphghanCore
@testable import Graphghan

/// ActivityKit stand-in: records every call and keeps the set of "active" activities.
@MainActor
final class RecordingBackend: ActivityBackend {
    enum Call: Equatable {
        case start(UUID)
        case update(String, Int, Int)          // id, row, runIndex
        case end(String, String?, Bool)        // id, message, immediately
    }
    var areActivitiesEnabled = true
    var startError: Error?
    /// Forces a real suspension inside `end`, so a concurrency test can catch the controller
    /// interleaving two calls instead of serializing them.
    var suspendOnEnd = false
    private(set) var calls: [Call] = []
    private var actives: [ActiveActivity] = []
    private var nextID = 1

    func start(info: WorkActivityInfo, state: WorkActivityState) throws -> String {
        if let startError { throw startError }
        let id = "act\(nextID)"; nextID += 1
        actives.append(ActiveActivity(id: id, info: info))
        calls.append(.start(info.projectID))
        return id
    }
    func update(id: String, state: WorkActivityState) async { calls.append(.update(id, state.row, state.runIndex)) }
    func end(id: String, state: WorkActivityState?, immediately: Bool) async {
        if suspendOnEnd { await Task.yield() }
        actives.removeAll { $0.id == id }
        calls.append(.end(id, state?.message, immediately))
    }
    func active() -> [ActiveActivity] { actives }
    /// The system ended it (8-hour limit): it disappears from `active()` without an `end` call.
    func systemEnded(_ id: String) { actives.removeAll { $0.id == id } }
    func reset() { calls = [] }
}

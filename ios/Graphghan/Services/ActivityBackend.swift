// `@preconcurrency`: ActivityKit marks neither `Activity` nor `Activity.activities` Sendable, so
// strict concurrency flags them crossing the awaits in `update`/`end`. This file holds the whole
// ActivityKit seam -- everything else in the app goes through `ActivityBackend` -- so the
// suppression is contained to it.
@preconcurrency import ActivityKit
import Foundation
import GraphghanCore

struct ActiveActivity: Equatable {
    let id: String
    let info: WorkActivityInfo
}

/// The ActivityKit seam. Production uses ActivityKit; tests use a recording fake.
@MainActor
protocol ActivityBackend: AnyObject {
    var areActivitiesEnabled: Bool { get }
    func start(info: WorkActivityInfo, state: WorkActivityState) throws -> String
    func update(id: String, state: WorkActivityState) async
    func end(id: String, state: WorkActivityState?, immediately: Bool) async
    func active() -> [ActiveActivity]
}

@MainActor
final class ActivityKitBackend: ActivityBackend {
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(info: WorkActivityInfo, state: WorkActivityState) throws -> String {
        let activity = try Activity<WorkActivityAttributes>.request(
            attributes: WorkActivityAttributes(info: info),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil)
        return activity.id
    }

    func update(id: String, state: WorkActivityState) async {
        guard let activity = find(id) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end(id: String, state: WorkActivityState?, immediately: Bool) async {
        guard let activity = find(id) else { return }
        await activity.end(state.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: immediately ? .immediate : .default)
    }

    func active() -> [ActiveActivity] {
        Activity<WorkActivityAttributes>.activities
            .filter { $0.activityState == .active }
            .map { ActiveActivity(id: $0.id, info: $0.attributes.info) }
    }

    private func find(_ id: String) -> Activity<WorkActivityAttributes>? {
        Activity<WorkActivityAttributes>.activities.first { $0.id == id }
    }
}

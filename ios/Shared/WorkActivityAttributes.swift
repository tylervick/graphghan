import ActivityKit
import GraphghanCore

/// The one Live Activity type. Compiled into the app and the widget extension; the core types
/// keep the data definition out of both.
struct WorkActivityAttributes: ActivityAttributes {
    typealias ContentState = WorkActivityState
    let info: WorkActivityInfo
}

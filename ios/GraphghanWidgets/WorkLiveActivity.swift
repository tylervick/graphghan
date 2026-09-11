import ActivityKit
import SwiftUI
import WidgetKit
import GraphghanCore

struct WorkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkActivityAttributes.self) { context in
            WorkLockScreenView(info: context.attributes.info, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    WorkExpandedCenterView(info: context.attributes.info, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkExpandedBottomView(info: context.attributes.info, state: context.state)
                }
            } compactLeading: {
                WorkCompactLeadingView(info: context.attributes.info, state: context.state)
            } compactTrailing: {
                WorkCompactTrailingView(state: context.state)
            } minimal: {
                WorkMinimalView(info: context.attributes.info, state: context.state)
            }
        }
    }
}

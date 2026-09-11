import ActivityKit
import SwiftUI
import WidgetKit
import GraphghanCore

struct WorkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkActivityAttributes.self) { context in
            Text("\(context.attributes.info.title) · Row \(context.state.row) of \(context.state.rowCount)")
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Text("Row \(context.state.row)") }
            } compactLeading: {
                Text("\(context.state.currentCount ?? 0)")
            } compactTrailing: {
                Text("\(context.state.row)")
            } minimal: {
                Text("\(context.state.currentCount ?? 0)")
            }
        }
    }
}

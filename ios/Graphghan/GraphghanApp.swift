import SwiftUI
import GraphghanCore

@main
struct GraphghanApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Text("Patterns").tabItem { Label("Patterns", systemImage: "square.grid.3x3") }
                Text("Projects").tabItem { Label("Projects", systemImage: "checklist") }
            }
        }
    }
}

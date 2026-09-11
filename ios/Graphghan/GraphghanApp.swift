import SwiftData
import SwiftUI
import GraphghanCore

@main
struct GraphghanApp: App {
    private let container: ModelContainer
    private let model: AppModel

    init() {
        do {
            container = try Persistence.makeContainer()
        } catch {
            fatalError("Could not open the project store: \(error)")
        }
        model = AppModel.live(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(container)
        }
    }
}

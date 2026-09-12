import SwiftData
import SwiftUI
import GraphghanCore

@main
struct GraphghanApp: App {
    private let container: ModelContainer
    private let model: AppModel

    init() {
        Theme.installAppearance()
        // A store that won't open is a bad session, not a crash: fall back to an in-memory
        // container so the app still browses and works, and say so through the existing banner.
        var storeError: String?
        let container: ModelContainer
        do {
            container = try Persistence.makeContainer()
        } catch {
            do {
                container = try Persistence.makeContainer(inMemory: true)
                storeError = "Couldn't open the project store; progress will not be saved this session."
            } catch {
                fatalError("Could not open the project store: \(error)")
            }
        }
        self.container = container
        let model = AppModel.live(context: container.mainContext)
        model.projects.lastError = storeError
        self.model = model
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(container)
                .task { await model.reconcileActivities() }
        }
    }
}

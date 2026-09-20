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
                .task {
                    await model.reconcileActivities()
                    model.scheduleReindex()  // Spotlight follows the store; a launch is the cheapest place to catch up
                    // Before the Patterns tab is ever opened: a project row started from a local
                    // pattern needs to know its pattern is local to find its preview and title.
                    await model.loadLocalPatterns()
                    if let url = AppModel.launchImportURL(ProcessInfo.processInfo.arguments) {
                        await model.importBundle(at: url)
                    }
                }
                // Files, Mail and AirDrop: with opening-in-place off, the system copies the file
                // into Documents/Inbox and hands over that URL (#16).
                .onOpenURL { url in Task { await model.importBundle(at: url) } }
        }
    }
}

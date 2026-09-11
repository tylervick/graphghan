import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([Project.self, ProgressEvent.self])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        // Spec 6.3: no CloudKit. `.automatic` would opt the store in the moment the app gained the
        // entitlement, so both configurations say `.none` out loud.
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            try FileManager.default.createDirectory(at: AppGroup.supportURL, withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: AppGroup.storeURL, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

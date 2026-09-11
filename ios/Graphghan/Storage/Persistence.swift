import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([Project.self, ProgressEvent.self])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            try FileManager.default.createDirectory(at: AppGroup.supportURL, withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: AppGroup.storeURL)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

/// App Intents spec §4.5: a project resolves by its own title, by its pattern's, and by id, through
/// the projection the app registers. An extension of `WorkIntentTests` for its `.serialized` trait.
extension WorkIntentTests {
    @Test func aProjectResolvesByItsOwnTitleAndItsPatterns() async throws {
        let h = try await make()  // titled "x"; the pattern is two-letter-codes, uncached here so the id stands in
        let named = try await startAnother(h, title: "For Meaghan")
        let query = ProjectEntityQuery()
        #expect(try await query.entities(matching: "meaghan").map(\.id) == [named.id])
        #expect(try await query.entities(matching: "two-letter").map(\.id).sorted(by: { $0.uuidString < $1.uuidString })
                == [h.project.id, named.id].sorted(by: { $0.uuidString < $1.uuidString }))
        #expect(try await query.entities(matching: "   ").isEmpty)
        #expect(try await query.entities(for: [named.id]).map(\.title) == ["For Meaghan"])
    }

    @Test func suggestionsAreUnfinishedMostRecentFirst() async throws {
        let h = try await make()
        let other = try await startAnother(h, title: "other")
        let done = try await startAnother(h, title: "done")
        h.project.lastWorked = Date(timeIntervalSince1970: 1_000)
        other.lastWorked = Date(timeIntervalSince1970: 2_000)
        done.lastWorked = Date(timeIntervalSince1970: 3_000)
        try h.model.projects.markFinished(done)
        #expect(try await ProjectEntityQuery().suggestedEntities().map(\.id) == [other.id, h.project.id])
        // Finished projects still resolve by name: "how far am I on …" has an answer for them.
        #expect(try await ProjectEntityQuery().entities(matching: "done").map(\.id) == [done.id])
    }

    @Test func percentComesFromTheCursor() async throws {
        let h = try await make()
        let seq = try await h.model.projects.sequence(for: h.project)
        _ = h.model.projects.apply(.advance, to: h.project, in: seq)  // 3 of 24 cells
        let snapshot = await h.model.snapshot(for: h.project)
        #expect(snapshot.percent == 12.5)
        #expect(snapshot.patternTitle == "two-letter-codes")
        let entity = ProjectEntity(snapshot)
        #expect(entity.percent == 12.5 && entity.title == "x")
        #expect(ProjectEntity.percentText(12.5) == "12.5%")
        #expect(ProjectEntity.percentText(43) == "43%")
    }

    @Test func aColdQueryWaitsForTheApp() async throws {
        let h = try await make()
        WorkIntentHandler.shared.perform = nil
        WorkIntentHandler.shared.performWorking = nil
        WorkIntentHandler.shared.projectSnapshots = nil
        let querying = Task { try await ProjectEntityQuery().entities(for: [h.project.id]) }
        try await Task.sleep(for: .milliseconds(100))
        h.model.registerIntentHandler()
        #expect(try await querying.value.map(\.id) == [h.project.id])
    }
}

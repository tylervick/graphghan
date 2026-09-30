import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct RowsLibraryTests {
    @Test func storesByIDAndReadsBack() async throws {
        let library = RowsLibrary(directory: try temporaryDirectory())
        let data = try TestFixtures.pieces("pieces/strip.rows.json")
        let stored = try await library.store(data)
        #expect(await library.has(id: stored.id))
        #expect(try await library.document(id: stored.id) == stored)
        #expect(try await library.data(id: stored.id) == data)
    }

    @Test func refusesAnInvalidDocumentAndStoresNothing() async throws {
        let dir = try temporaryDirectory()
        let library = RowsLibrary(directory: dir)
        let bad = try Data(contentsOf: TestFixtures.directory.appendingPathComponent("refused/rows-gap.rows.json"))
        await #expect(throws: RowsError.self) { try await library.store(bad) }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).isEmpty)
    }
}

import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct ChartLibraryTests {
    @Test func storesDecodesAndMemoizes() async throws {
        let dir = try temporaryDirectory()
        let lib = ChartLibrary(directory: dir)
        let data = try TestFixtures.data("two-letter-codes.chart.json")
        let chart = try await lib.store(data)
        #expect(chart.width == 12)
        #expect(await lib.hasChart(id: chart.id))
        let again = try await lib.chart(id: chart.id)
        #expect(again.id == chart.id)
        let fresh = ChartLibrary(directory: dir)  // reads the file back
        #expect(try await fresh.chart(id: chart.id).height == 2)
        try await lib.remove(id: chart.id)
        #expect(await !lib.hasChart(id: chart.id))
    }

    @Test func rejectsBadDataWithoutWriting() async throws {
        let dir = try temporaryDirectory()
        let lib = ChartLibrary(directory: dir)
        await #expect(throws: (any Error).self) { try await lib.store(Data("not json".utf8)) }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty ?? true)
        await #expect(throws: ChartLibrary.LibraryError.missing("sha256:" + String(repeating: "0", count: 64))) {
            try await lib.chart(id: "sha256:" + String(repeating: "0", count: 64))
        }
        await #expect(throws: ChartLibrary.LibraryError.badID("nope")) { try await lib.chart(id: "nope") }
    }
}

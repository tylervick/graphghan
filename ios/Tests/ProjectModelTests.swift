import Foundation
import SwiftData
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct ProjectModelTests {
    @Test func cursorMapsToColumns() throws {
        let container = try makeInMemoryContainer()
        let p = Project(patternID: "x", chartID: "sha256:" + String(repeating: "a", count: 64), chartVariant: "final", chartGaugeKey: "sc", patternVersion: "1", title: "T", started: Date())
        container.mainContext.insert(p)
        p.cursor = Cursor(row: 4, run: 2)
        try container.mainContext.save()
        #expect(p.cursorRow == 4 && p.cursorRun == 2 && p.cursor == Cursor(row: 4, run: 2))
        #expect(!p.isFinished)
    }

    @Test func deletingAProjectCascadesToItsEvents() throws {
        let container = try makeInMemoryContainer()
        let ctx = container.mainContext
        let p = Project(patternID: "x", chartID: "sha256:" + String(repeating: "a", count: 64), chartVariant: "final", chartGaugeKey: "sc", patternVersion: "1", title: "T", started: Date())
        ctx.insert(p)
        for i in 0..<3 {
            let e = ProgressEvent(t: Date().addingTimeInterval(Double(i)), row: 1, run: i, kind: .advance)
            e.project = p
            ctx.insert(e)
        }
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<ProgressEvent>()) == 3)
        #expect(p.eventRecords.map(\.run) == [0, 1, 2])
        ctx.delete(p)
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<ProgressEvent>()) == 0)
    }
}

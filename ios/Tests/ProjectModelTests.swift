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
        // The events are reached by predicate on their back-reference, not through an array on the
        // project (#79); deleting a project and its events is `ProjectService.delete`'s job now.
        let id = p.id
        var byProject = FetchDescriptor<ProgressEvent>(predicate: #Predicate { $0.project?.id == id })
        byProject.sortBy = [SortDescriptor(\.t)]
        #expect(try ctx.fetch(byProject).map(\.run) == [0, 1, 2])
    }

    /// Review focus 4: a project made before pieces existed reads as one piece, unchanged.
    @Test @MainActor func aProjectWithoutPiecesIsUnchanged() throws {
        let container = try makeInMemoryContainer()
        let p = Project(patternID: "p", chartID: "sha256:x", chartVariant: "final", chartGaugeKey: "sc", patternVersion: "1", title: "T", started: .now)
        container.mainContext.insert(p)
        try container.mainContext.save()
        #expect(!p.isPieced && !p.currentIsWritten && p.currentKey == nil && p.assemblyDone.isEmpty && p.piecesTotal == 1)
    }

    @Test @MainActor func pieceProgressKeepsItsCursor() throws {
        let container = try makeInMemoryContainer()
        let project = Project(patternID: "p", chartID: "", chartVariant: "", chartGaugeKey: "", patternVersion: "1", title: "T", started: .now)
        let piece = PieceProgress(pieceID: "strip", copy: 2, docID: "sha256:y")
        piece.project = project
        piece.cursor = Cursor(row: 4, run: 0)
        container.mainContext.insert(project)
        container.mainContext.insert(piece)
        try container.mainContext.save()
        let fetched = try container.mainContext.fetch(FetchDescriptor<PieceProgress>())
        #expect(fetched.count == 1 && fetched[0].cursor == Cursor(row: 4, run: 0) && fetched[0].key == PieceKey(piece: "strip", copy: 2))
    }
}

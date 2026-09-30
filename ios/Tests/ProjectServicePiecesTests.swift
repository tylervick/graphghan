import Foundation
import SwiftData
import Testing
import GraphghanCore
@testable import Graphghan

/// A pieced project through `ProjectService` (spec 2026-09-25 §5.4, §6.1, §6.2, §6.5), on the
/// pieces-basic fixture: a five-row chart panel, a closed five-row strip, a fin made twice and an
/// open-ended strap.
@MainActor
@Suite struct ProjectServicePiecesTests {
    static func make() async throws -> (ProjectService, PatternManifest) {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        let rows = RowsLibrary(directory: try temporaryDirectory())
        _ = try await charts.store(try TestFixtures.pieces("charts/final-sc/chart.json"))
        for name in ["strip", "fin", "strap"] { _ = try await rows.store(try TestFixtures.pieces("pieces/\(name).rows.json")) }
        let service = ProjectService(context: container.mainContext, charts: charts, rows: rows, patterns: patterns)
        let manifest = try JSONDecoder().decode(PatternManifest.self, from: try TestFixtures.pieces("pattern.json"))
        return (service, manifest)
    }

    @Test func startingAPiecedPatternStartsItsFirstPiece() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        #expect(p.isPieced && p.currentKey == PieceKey(piece: "panel", copy: 1))
        #expect(p.chartID == manifest.charts[0].id && !p.currentIsWritten)
        #expect(p.piecesTotal == 5 && p.assemblyTotal == 2 && p.title == "Pieces basic")
        #expect(try service.pieceProgress(for: p).map(\.key) == [PieceKey(piece: "panel", copy: 1)])
    }

    /// Review focus 2.
    @Test func eachPieceKeepsItsOwnCursor() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        var work = try await service.work(for: p)
        service.apply(.advance, to: p, work: work)   // panel row 1 → row 2 (a one-run row)
        service.apply(.advance, to: p, work: work)
        let panelCursor = p.cursor
        try await service.selectPiece(PieceKey(piece: "strip", copy: 1), of: p, manifest: manifest)
        #expect(p.currentIsWritten && p.cursor == Cursor(row: 1, run: 0) && p.chartID == "")
        work = try await service.work(for: p)
        service.apply(.advance, to: p, work: work)
        #expect(p.cursor == Cursor(row: 2, run: 0))
        try await service.selectPiece(PieceKey(piece: "panel", copy: 1), of: p, manifest: manifest)
        #expect(p.cursor == panelCursor && p.chartID == manifest.charts[0].id)
    }

    @Test func eventsRecordTheirPiece() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        try await service.selectPiece(PieceKey(piece: "fin", copy: 2), of: p, manifest: manifest)
        service.apply(.advance, to: p, work: try await service.work(for: p))
        let doc = try service.exportPiecedDocument(for: p)
        #expect(doc.events.last?.key == PieceKey(piece: "fin", copy: 2) && doc.events.last?.run == 0)
        #expect(doc.current == PieceKey(piece: "fin", copy: 2))
    }

    @Test func doneOnTheLastRowFinishesThePieceNotTheProject() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        try await service.selectPiece(PieceKey(piece: "strip", copy: 1), of: p, manifest: manifest)
        let work = try await service.work(for: p)
        for _ in 0..<5 { service.apply(.advance, to: p, work: work) }
        let strip = try service.pieceProgress(for: p).first { $0.key == PieceKey(piece: "strip", copy: 1) }
        #expect(strip?.finished != nil && !p.isFinished)
        #expect(try service.nextUnfinished(after: p, manifest: manifest) == PieceKey(piece: "panel", copy: 1))
    }

    /// Review focus 1.
    @Test func backUnfinishesAPiece() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        try await service.selectPiece(PieceKey(piece: "strip", copy: 1), of: p, manifest: manifest)
        let work = try await service.work(for: p)
        for _ in 0..<5 { service.apply(.advance, to: p, work: work) }
        service.apply(.back, to: p, work: work)
        let strip = try service.pieceProgress(for: p).first { $0.key == PieceKey(piece: "strip", copy: 1) }
        #expect(strip?.finished == nil && p.cursor == Cursor(row: 5, run: 0))
    }

    @Test func theProjectFinishesWithItsLastPieceAndStep() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        for key in [PieceKey(piece: "strip", copy: 1), PieceKey(piece: "fin", copy: 1), PieceKey(piece: "fin", copy: 2)] {
            try await service.selectPiece(key, of: p, manifest: manifest)
            let work = try await service.work(for: p)
            while !(try service.pieceProgress(for: p).first { $0.key == key }?.finished != nil) { service.apply(.advance, to: p, work: work) }
        }
        try await service.selectPiece(PieceKey(piece: "strap", copy: 1), of: p, manifest: manifest)
        try service.finishPiece(p)
        try await service.selectPiece(PieceKey(piece: "panel", copy: 1), of: p, manifest: manifest)
        let panel = try await service.work(for: p)
        while service.apply(.advance, to: p, work: panel)?.finished != true {}
        #expect(!p.isFinished)                       // assembly still open
        try service.setAssemblyStep(0, done: true, for: p)
        try service.setAssemblyStep(1, done: true, for: p)
        #expect(p.isFinished)
        try service.setAssemblyStep(1, done: false, for: p)
        #expect(!p.isFinished)
    }

    /// Review focus 3.
    @Test func progressLineForAnOpenPiece() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        #expect(try service.progressLine(for: p, manifest: manifest, work: try await service.work(for: p)) == "Panel · Row 1 of 5 · 0 of 5 pieces")
        try await service.selectPiece(PieceKey(piece: "strap", copy: 1), of: p, manifest: manifest)
        let work = try await service.work(for: p)
        #expect(try service.progressLine(for: p, manifest: manifest, work: work) == "Strap · Row 1 · 0 of 5 pieces")
        #expect(service.currentPercent(for: p, work: work) == nil)
    }

    @Test func statusesListEveryCopyInOrder() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        let s = await service.statuses(for: p, manifest: manifest)
        #expect(s.map(\.id) == [PieceKey(piece: "panel", copy: 1), PieceKey(piece: "strip", copy: 1), PieceKey(piece: "fin", copy: 1),
                                PieceKey(piece: "fin", copy: 2), PieceKey(piece: "strap", copy: 1)])
        #expect(s.map(\.line) == ["Row 1 of 5", "5 rows", "3 rows", "3 rows", "Open-ended"])
        #expect(s[0].isCurrent && !s[1].isCurrent)
    }

    /// Otherwise `versionNotice`/`switchChart` could act on the chart the project started with,
    /// once a written piece is current and `chartID` is no longer that chart's id.
    @Test func selectingAWrittenPieceClearsTheChartFields() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        try await service.selectPiece(PieceKey(piece: "strip", copy: 1), of: p, manifest: manifest)
        #expect(p.chartVariant == "" && p.chartGaugeKey == "")
    }

    @Test func setAssemblyStepIgnoresAnOutOfRangeIndex() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        try service.setAssemblyStep(7, done: true, for: p)
        #expect(p.assemblyDone.isEmpty)
    }

    /// The project list and Spotlight follow the current piece (spec §4.2's App Intents hook).
    @Test func selectPieceNotifiesProjectsChanged() async throws {
        let (service, manifest) = try await Self.make()
        let p = try await service.startPiecedProject(manifest: manifest, title: "")
        var count = 0
        service.onProjectsChanged = { count += 1 }
        try await service.selectPiece(PieceKey(piece: "strip", copy: 1), of: p, manifest: manifest)
        #expect(count == 1)
    }
}

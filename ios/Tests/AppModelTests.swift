import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct AppModelTests {
    static let index = #"[{"slug":"p","title":"P","version":"1","stitch":"sc","width":2,"height":1,"size_in":[1,1],"dedication":"","colors":1,"preview":"patterns/p/preview.png","manifest":"patterns/p/pattern.json","charts":1}]"#

    func makeModel() async throws -> (AppModel, StubClient) {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        return (AppModel(context: container.mainContext, patterns: patterns, charts: charts,
                         rows: RowsLibrary(directory: try temporaryDirectory()),
                         localPatterns: try makeLocalPatternStore()), client)
    }

    @Test func offlineWithoutCacheShowsAnError() async throws {
        let (model, _) = try await makeModel()
        await model.loadLibrary()
        #expect(model.index.isEmpty && model.libraryError != nil && model.libraryBanner == nil)
    }

    @Test func refreshFailureKeepsTheCacheAndShowsABanner() async throws {
        let (model, client) = try await makeModel()
        await client.respond("/patterns/index.json", body: Self.index, etag: "\"1\"")
        await model.loadLibrary()
        #expect(model.index.count == 1 && model.libraryBanner == nil && model.libraryError == nil)
        await client.fail("/patterns/index.json")
        await model.loadLibrary(force: true)
        #expect(model.index.count == 1 && model.libraryBanner != nil && model.libraryError == nil)
    }

    /// The project screen's piece row tap: `openPiece` must never open the Work screen on a piece
    /// that didn't actually become current (fix round 1, issue 1).
    @Test func openingAnUnknownPieceLeavesWorkingProjectNil() async throws {
        let (model, _) = try await makeModel()
        _ = try await model.charts.store(try TestFixtures.pieces("charts/final-sc/chart.json"))
        for name in ["strip", "fin", "strap"] { _ = try await model.rows.store(try TestFixtures.pieces("pieces/\(name).rows.json")) }
        let manifest = try JSONDecoder().decode(PatternManifest.self, from: try TestFixtures.pieces("pattern.json"))
        try await model.startPiecedProject(manifest: manifest, title: "")
        let project = try #require(try model.projects.projects().first)
        model.workingProject = nil
        let ok = await model.openPiece(PieceKey(piece: "not-a-piece", copy: 1), of: project, manifest: manifest)
        #expect(!ok && model.workingProject == nil)
    }

    @Test func openingAKnownPieceSetsWorkingProject() async throws {
        let (model, _) = try await makeModel()
        _ = try await model.charts.store(try TestFixtures.pieces("charts/final-sc/chart.json"))
        for name in ["strip", "fin", "strap"] { _ = try await model.rows.store(try TestFixtures.pieces("pieces/\(name).rows.json")) }
        let manifest = try JSONDecoder().decode(PatternManifest.self, from: try TestFixtures.pieces("pattern.json"))
        try await model.startPiecedProject(manifest: manifest, title: "")
        let project = try #require(try model.projects.projects().first)
        let ok = await model.openPiece(PieceKey(piece: "strip", copy: 1), of: project, manifest: manifest)
        #expect(ok && model.workingProject?.id == project.id)
    }

    // MARK: pieced projects (spec 2026-09-25 §6.5) -- Task 11

    static func makeBareModel() async throws -> AppModel {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        return AppModel(context: container.mainContext, patterns: patterns, charts: charts,
                        rows: RowsLibrary(directory: try temporaryDirectory()), localPatterns: try makeLocalPatternStore())
    }

    /// The pieces-basic bundle, imported through `BundleImporter` (via `AppModel.importBundle`)
    /// and started, then Done four times: the panel's first two rows are each one run, so that is
    /// run, turn, run, turn -- landing on row 3, run 0.
    static func piecedProject() async throws -> (AppModel, Project) {
        let model = try await makeBareModel()
        let manifest = try #require(await model.importBundle(data: try TestFixtures.bundle("pieces-basic")))
        try await model.startPiecedProject(manifest: manifest, title: "")
        let project = try #require(try model.projects.projects().first)
        for _ in 0..<4 { _ = await model.performIntent(.advance, chosen: project.id) }
        return (model, project)
    }

    /// A plain, single-chart project: `two-letter-codes`, never worked.
    static func singleChartProject() async throws -> (AppModel, Project) {
        let model = try await makeBareModel()
        let data = try TestFixtures.data("two-letter-codes.chart.json")
        _ = try await model.charts.store(data)
        let manifest = TestManifest.make(chartID: try Chart.load(data).id)
        let project = try await model.projects.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        return (model, project)
    }

    @Test @MainActor func aPiecedSnapshotReadsTheCurrentPiece() async throws {
        let (model, project) = try await Self.piecedProject()
        let s = await model.snapshot(for: project)
        #expect(s.detail == "Panel · Row 3 of 5 · 0 of 5 pieces")
        #expect(abs(s.percent - 33.3) < 0.001)   // 8 of 24 cells: rows 1-2 of the panel (3 + 5)
    }

    /// Review focus 4.
    @Test @MainActor func snapshotOfASingleChartProjectIsUnchanged() async throws {
        let (model, project) = try await Self.singleChartProject()
        #expect(await model.snapshot(for: project).detail == nil)
    }

    @Test @MainActor func aShortcutsDoneOnAWrittenPieceMovesOneRow() async throws {
        let (model, project) = try await Self.piecedProject()
        let manifest = try await model.manifest(for: project.patternID, path: nil)
        try await model.projects.selectPiece(PieceKey(piece: "strip", copy: 1), of: project, manifest: manifest)
        let outcome = await model.performIntent(.advance, chosen: project.id)
        guard case .movedWritten(let title, let row, let total, let finished) = outcome else {
            Issue.record("expected .movedWritten, got \(outcome)")
            return
        }
        #expect(title == "Strip" && row == 2 && total == 5 && !finished)
    }

    /// Spec §6.5: Siri names the chart piece it moved on.
    @Test @MainActor func aShortcutsDoneOnAChartPieceNamesThePiece() async throws {
        let (model, project) = try await Self.piecedProject()
        let outcome = await model.performIntent(.advance, chosen: project.id)
        guard case .moved(let landing) = outcome else { Issue.record("expected .moved, got \(outcome)"); return }
        #expect(landing.pieceTitle == "Panel")
        #expect(WorkIntentDialog.plain(outcome).hasPrefix("Panel, row 3, "))
    }

    @Test @MainActor func aShortcutsDoneOnASingleChartNamesNoPiece() async throws {
        let (model, project) = try await Self.singleChartProject()
        let outcome = await model.performIntent(.advance, chosen: project.id)
        guard case .moved(let landing) = outcome else { Issue.record("expected .moved, got \(outcome)"); return }
        #expect(landing.pieceTitle == nil)
    }
}

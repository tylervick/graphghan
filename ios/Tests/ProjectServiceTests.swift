import Foundation
import SwiftData
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct ProjectServiceTests {
    struct Harness {
        let service: ProjectService
        let client: StubClient
        let context: ModelContext
        let chartData: Data
        let chartID: String
    }

    func makeHarness() async throws -> Harness {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        let service = ProjectService(context: container.mainContext, charts: charts, patterns: patterns)
        let data = try TestFixtures.data("two-letter-codes.chart.json")
        let id = try Chart.load(data).id
        await client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: data)
        return Harness(service: service, client: client, context: container.mainContext, chartData: data, chartID: id)
    }

    @Test func startPinsChartAndVersion() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID, version: "1.2.0")
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "Mine")
        #expect(p.chartID == h.chartID && p.patternVersion == "1.2.0" && p.patternID == "two-letter-codes")
        #expect(p.chartVariant == "final" && p.chartGaugeKey == "sc" && p.title == "Mine" && p.cursor == .start)
        #expect(try h.service.projects().count == 1)
        #expect(try await h.service.sequence(for: p).passes.count == 2)
        // a second, more recently worked project sorts first
        let p2 = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "Second")
        let seq2 = try await h.service.sequence(for: p2)
        h.service.now = { Date(timeIntervalSince1970: 1_800_000_100) }
        _ = h.service.apply(.advance, to: p2, in: seq2)
        #expect(try h.service.projects().first?.id == p2.id)
    }

    @Test func failedDownloadOrDecodeLeavesNoProject() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        await h.client.fail("/patterns/two-letter-codes/charts/final-sc/chart.json")
        await #expect(throws: (any Error).self) { _ = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x") }
        #expect(try h.service.projects().isEmpty)
        await h.client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", body: "{\"schema\":2}")
        await #expect(throws: (any Error).self) { _ = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x") }
        #expect(try h.service.projects().isEmpty)
        // a manifest whose id disagrees with the downloaded chart is refused too
        let wrong = TestManifest.make(chartID: "sha256:" + String(repeating: "0", count: 64))
        await h.client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: h.chartData)
        await #expect(throws: ProjectService.ServiceError.chartMismatch(expected: wrong.charts[0].id, got: h.chartID)) {
            _ = try await h.service.startProject(manifest: wrong, chart: wrong.charts[0], title: "x")
        }
        #expect(try h.service.projects().isEmpty)
    }

    @Test func applyWritesCursorAndEventTogether() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        h.service.now = { t }
        let step = h.service.apply(.advance, to: p, in: seq)
        #expect(step?.cursor == Cursor(row: 1, run: 1))
        #expect(p.cursor == Cursor(row: 1, run: 1) && p.lastWorked == t)
        #expect(p.eventRecords == [ProgressEventRecord(t: t, row: 1, run: 1, kind: .advance)])
        #expect(try h.context.fetchCount(FetchDescriptor<ProgressEvent>()) == 1)
        #expect(h.service.apply(.back, to: p, in: seq)?.cursor == .start)
        #expect(h.service.apply(.back, to: p, in: seq) == nil)   // no-op at the start writes nothing
        #expect(try h.context.fetchCount(FetchDescriptor<ProgressEvent>()) == 2)
        // finishing the last run marks the project finished
        _ = h.service.apply(.jump(row: 2), to: p, in: seq)
        for _ in 0..<3 { _ = h.service.apply(.advance, to: p, in: seq) }
        #expect(p.isFinished && h.service.summary(for: p, sequence: seq).percent == 100)
    }

    @Test func summaryAndExport() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        h.service.now = { Date(timeIntervalSince1970: 1_800_000_000) }
        _ = h.service.apply(.advance, to: p, in: seq)  // Kb 3 stitches done
        let s = h.service.summary(for: p, sequence: seq)
        #expect(s.stitchesDone == 3 && s.totalStitches == 24 && s.sessions.count == 1)
        #expect(h.service.estimatedFinish(for: p, sequence: seq) == nil)  // fewer than 3 sessions
        let doc = h.service.exportDocument(for: p)
        #expect(doc.patternID == "two-letter-codes" && doc.chartID == h.chartID && doc.cursor == Cursor(row: 1, run: 1) && doc.events.count == 1)
    }

    @Test func deleteCascadesAndNotesAndFinish() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        _ = h.service.apply(.advance, to: p, in: seq)
        try h.service.setNotes("bobbin the gold", for: p)
        #expect(p.notes == "bobbin the gold")
        try h.service.markFinished(p)
        #expect(p.isFinished)
        try h.service.delete(p)
        #expect(try h.service.projects().isEmpty)
        #expect(try h.context.fetchCount(FetchDescriptor<ProgressEvent>()) == 0)
    }

    @Test func workingBackwardsReopensAFinishedProject() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        while h.service.apply(.advance, to: p, in: seq) != nil {}  // advance returns nil once finished
        #expect(p.isFinished)
        _ = h.service.apply(.back, to: p, in: seq)
        #expect(!p.isFinished)  // undoing the last stitch un-finishes it, so Work is offered again
        while h.service.apply(.advance, to: p, in: seq) != nil {}
        #expect(p.isFinished)
        _ = h.service.apply(.jump(row: 1), to: p, in: seq)
        #expect(!p.isFinished)
        // and the explicit toggle both ways
        try h.service.markFinished(p)
        #expect(p.isFinished)
        try h.service.markUnfinished(p)
        #expect(!p.isFinished && p.finished == nil)
    }

    @Test func versionNoticeOnlyWhenTheChartChanged() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID, version: "1.0.0")
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        #expect(h.service.versionNotice(for: p, manifest: TestManifest.make(chartID: h.chartID, version: "1.1.0")) == nil)
        let changed = TestManifest.make(chartID: "sha256:" + String(repeating: "b", count: 64), version: "2.0.0")
        #expect(h.service.versionNotice(for: p, manifest: changed) == .chartChanged(newChart: changed.charts[0], newVersion: "2.0.0", canSwitch: true))
        let seq = try await h.service.sequence(for: p)
        _ = h.service.apply(.advance, to: p, in: seq)
        #expect(h.service.versionNotice(for: p, manifest: changed) == .chartChanged(newChart: changed.charts[0], newVersion: "2.0.0", canSwitch: false))
        await #expect(throws: ProjectService.ServiceError.cursorNotAtStart) { try await h.service.switchChart(p, to: changed.charts[0], manifest: changed) }
        #expect(h.service.versionNotice(for: p, manifest: TestManifest.make(chartID: h.chartID, gaugeKey: "hdc")) == nil)  // no matching chart in the manifest: nothing to say
    }

    @Test func switchChartAtTheStart() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        // publish a "new" chart at the same variant/gauge: the minimal-rows fixture stands in for it
        let newData = try TestFixtures.data("minimal-rows.chart.json")
        let newID = try Chart.load(newData).id
        let changed = TestManifest.make(chartID: newID, version: "2.0.0", path: "charts/final-sc/chart.json")
        await h.client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: newData)
        try await h.service.switchChart(p, to: changed.charts[0], manifest: changed)
        #expect(p.chartID == newID && p.patternVersion == "2.0.0")
        #expect(try await h.service.sequence(for: p).passes.count == 12)
    }

    @Test func switchChartMismatchLeavesNothingWritten() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let newData = try TestFixtures.data("minimal-rows.chart.json")
        let minimalID = try Chart.load(newData).id
        let wrongID = "sha256:" + String(repeating: "0", count: 64)
        let changed = TestManifest.make(chartID: wrongID, version: "2.0.0", path: "charts/final-sc/chart.json")
        await h.client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: newData)
        await #expect(throws: ProjectService.ServiceError.chartMismatch(expected: wrongID, got: minimalID)) {
            try await h.service.switchChart(p, to: changed.charts[0], manifest: changed)
        }
        #expect(p.chartID == h.chartID)
        #expect(await h.service.charts.hasChart(id: minimalID) == false)
    }

    @Test func chartUnavailableAfterRemoval() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        try await h.service.charts.remove(id: p.chartID)
        await #expect(throws: ProjectService.ServiceError.chartUnavailable(p.chartID)) { _ = try await h.service.sequence(for: p) }
    }

    @Test func saveFailureSetsLastErrorButNeverBlocksAdvancing() async throws {
        // `isStoredInMemoryOnly: true, allowsSave: false` fails to even *load* the container on this
        // SDK (it backs the in-memory store with a read-only handle on /dev/null, which the store
        // can't open at all -- confirmed empirically, see task-10-fix-report.md). So: persist a project
        // to a real file with a writable container first, then reopen that same file read-only. The
        // reopened context can fetch the already-persisted project fine and fails only on `save()`,
        // which is the failure this test needs.
        let dir = try temporaryDirectory()
        let url = dir.appendingPathComponent("readonly.store")
        let data = try TestFixtures.data("two-letter-codes.chart.json")
        let chart = try Chart.load(data)
        do {
            let writable = try ModelContainer(for: Persistence.schema, configurations: [ModelConfiguration(schema: Persistence.schema, url: url)])
            let p = Project(patternID: "two-letter-codes", chartID: chart.id, chartVariant: "final", chartGaugeKey: "sc", patternVersion: "1.0.0", title: "x", started: Date())
            writable.mainContext.insert(p)
            try writable.mainContext.save()
        }
        let readOnly = try ModelContainer(for: Persistence.schema, configurations: [ModelConfiguration(schema: Persistence.schema, url: url, allowsSave: false)])
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        let service = ProjectService(context: readOnly.mainContext, charts: charts, patterns: patterns)
        let p = try #require(try service.projects().first)
        #expect(p.cursor == .start)
        let seq = try WorkSequence(chart: chart)
        // Spec 6.6: a storage failure never blocks advancing -- the cursor still moves in memory
        // and `apply` still returns the step, even though the save behind it fails.
        let step = service.apply(.advance, to: p, in: seq)
        #expect(step?.cursor == Cursor(row: 1, run: 1))
        #expect(p.cursor == Cursor(row: 1, run: 1))
        #expect(service.lastError != nil)
        // advancing again keeps working from the in-memory cursor, still unblocked by the failing store
        let step2 = service.apply(.advance, to: p, in: seq)
        #expect(step2?.cursor == Cursor(row: 1, run: 2))
        #expect(p.cursor == Cursor(row: 1, run: 2))
    }

    @Test func applyInvokesTheHookAndProjectLookup() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        var seen: [Cursor] = []
        h.service.onApply = { project, _, step in seen.append(step.cursor); #expect(project.id == p.id) }
        _ = h.service.apply(.advance, to: p, in: seq)
        #expect(seen == [Cursor(row: 1, run: 1)])
        #expect(try h.service.project(id: p.id)?.id == p.id)
        #expect(try h.service.project(id: UUID()) == nil)
    }

    @Test func applyCountsAFillWithTheProjectsStepAndRecordsStitch() async throws {
        let h = try await makeHarness()
        let craigh = try TestFixtures.data("craigh-na-dun.chart.json")
        let craighID = try Chart.load(craigh).id
        await h.client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: craigh)
        let manifest = TestManifest.make(chartID: craighID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        #expect(p.step == .ten && p.cursorStitch == 0)
        _ = h.service.apply(.jump(row: 42, run: 10), to: p, in: seq)   // the 117 C fill
        _ = h.service.apply(.advance, to: p, in: seq)
        #expect(p.cursor == Cursor(row: 42, run: 10, stitch: 10) && p.cursorStitch == 10)
        #expect(p.eventRecords.last == ProgressEventRecord(t: p.eventRecords.last!.t, row: 42, run: 10, stitch: 10, kind: .advance))
        try h.service.setCountStep(.twenty, for: p)
        #expect(p.step == .twenty && p.countStep == 20)
        _ = h.service.apply(.advance, to: p, in: seq)
        #expect(p.cursor.stitch == 30)
        let doc = h.service.exportDocument(for: p)
        #expect(doc.cursor.stitch == 30 && doc.events.last?.stitch == 30)
    }

    @Test func aTurnIsAnEventAndBackUndoesIt() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        for _ in 0..<3 { _ = h.service.apply(.advance, to: p, in: seq) }   // three runs of row 1
        #expect(p.cursor == Cursor(row: 1, run: 3) && !p.isFinished)          // the boundary, not row 2
        #expect(h.service.apply(.advance, to: p, in: seq)?.cursor == Cursor(row: 2, run: 0))
        #expect(h.service.apply(.back, to: p, in: seq)?.cursor == Cursor(row: 1, run: 3))
        #expect(try h.context.fetchCount(FetchDescriptor<ProgressEvent>()) == 5)
    }
}

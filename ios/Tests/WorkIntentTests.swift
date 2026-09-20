import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
// Serialized: these cases share `WorkIntentHandler.shared`, which each `make()` claims for its own model.
@Suite(.serialized) struct WorkIntentTests {
    struct Harness { let model: AppModel; let backend: RecordingBackend; let project: Project }

    func make() async throws -> Harness {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        let backend = RecordingBackend()
        let model = AppModel(context: container.mainContext, patterns: patterns, charts: charts,
                             localPatterns: try makeLocalPatternStore(), activityBackend: backend,
                             defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        model.registerIntentHandler()
        let data = try TestFixtures.data("two-letter-codes.chart.json")
        let id = try Chart.load(data).id
        await client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: data)
        let manifest = TestManifest.make(chartID: id)
        let project = try await model.projects.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        return Harness(model: model, backend: backend, project: project)
    }

    @Test func advanceIntentAppliesThroughTheService() async throws {
        let h = try await make()
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        await h.model.liveActivity.start(projectID: h.project.id, info: info, state: state)
        _ = try await AdvanceRunIntent(projectID: h.project.id).perform()
        #expect(h.project.cursor == Cursor(row: 1, run: 1))
        let events = try h.model.projects.events(for: h.project)
        #expect(events.count == 1 && events[0].kind == .advance)
        #expect(h.backend.calls.last == .update("act1", 1, 1))
        _ = try await BackRunIntent(projectID: h.project.id).perform()
        #expect(h.project.cursor == .start && h.backend.calls.last == .update("act1", 1, 0))
    }

    @Test func staleProjectEndsTheActivity() async throws {
        let h = try await make()
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        await h.model.liveActivity.start(projectID: h.project.id, info: info, state: state)
        try h.model.projects.delete(h.project)
        _ = try await AdvanceRunIntent(projectID: h.project.id).perform()
        #expect(h.backend.calls.last == .end("act1", message: LiveActivityController.unavailableMessage, finished: true, immediately: false))
        #expect(h.backend.active().isEmpty)
    }

    @Test func missingChartEndsTheActivity() async throws {
        let h = try await make()
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        await h.model.liveActivity.start(projectID: h.project.id, info: info, state: state)
        try await h.model.charts.remove(id: h.project.chartID)
        _ = try await AdvanceRunIntent(projectID: h.project.id).perform()
        #expect(h.backend.calls.last == .end("act1", message: LiveActivityController.unavailableMessage, finished: true, immediately: false))
    }

    @Test func unparseableIDIsIgnored() async throws {
        let h = try await make()
        // `let`, not `var`: @Parameter's wrappedValue setter is nonmutating (the value lives in the
        // wrapper), so assigning through it doesn't mutate the intent struct itself.
        let intent = AdvanceRunIntent()
        intent.projectID = "not-a-uuid"
        _ = try await intent.perform()
        #expect(h.project.cursor == .start)
        #expect(h.backend.calls.isEmpty)
    }

    /// The system can launch the app in the background for the tap, so nothing has told the controller
    /// which activity is live: it has to adopt the running one instead of dropping the refresh.
    @Test func coldLaunchIntentRefreshesTheActivity() async throws {
        let h = try await make()
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        _ = try h.backend.start(info: info, state: state)  // live on the lock screen, unknown to the controller
        _ = try await AdvanceRunIntent(projectID: h.project.id).perform()
        #expect(h.project.cursor == Cursor(row: 1, run: 1))
        #expect(h.backend.calls.last == .update("act1", 1, 1))
        #expect(h.backend.active().count == 1)
    }

    /// Spec §3.1: a Siri request or a lock-screen tap can launch the app in the background, and
    /// nothing promises the intent performs after `AppModel.live` has claimed the handler. A Done
    /// that lands in that window must wait for the registration, not vanish.
    @Test func coldHandlerStillAppliesTheDone() async throws {
        let h = try await make()
        WorkIntentHandler.shared.perform = nil
        WorkIntentHandler.shared.performWorking = nil
        let intent = AdvanceRunIntent(projectID: h.project.id)
        let performing = Task { @MainActor in _ = try await intent.perform() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.project.cursor == .start)  // nothing registered yet, nothing moved
        h.model.registerIntentHandler()
        try await performing.value
        #expect(h.project.cursor == Cursor(row: 1, run: 1))
        let events = try h.model.projects.events(for: h.project)
        #expect(events.map(\.kind) == [.advance])
    }

    /// The wait has an end: a process where nothing ever registers (a test host without a model)
    /// gives up, and the intent leaves the store as it found it.
    @Test func unregisteredHandlerGivesUp() async throws {
        let h = try await make()
        WorkIntentHandler.shared.perform = nil
        WorkIntentHandler.shared.performWorking = nil
        let registered = await WorkIntentHandler.shared.awaitRegistration(timeout: .milliseconds(50))
        #expect(registered == false)
        #expect(try h.model.projects.events(for: h.project).isEmpty)
        h.model.registerIntentHandler()  // leave the shared handler as the other cases expect it
    }

    /// A cancelled intent must not sit on the main actor until the deadline: that is the actor the
    /// registration it waits for needs.
    @Test func aCancelledWaitGivesUpAtOnce() async throws {
        let h = try await make()
        WorkIntentHandler.shared.perform = nil
        WorkIntentHandler.shared.performWorking = nil
        let clock = ContinuousClock()
        let started = clock.now
        let waiting = Task { @MainActor in await WorkIntentHandler.shared.awaitRegistration(timeout: .seconds(5)) }
        waiting.cancel()
        let registered = await waiting.value
        #expect(registered == false)
        #expect(clock.now - started < .seconds(1))
        h.model.registerIntentHandler()
    }

    @Test func reconcileOnLaunch() async throws {
        let h = try await make()
        let (info, _) = try #require(await h.model.activityState(for: h.project))
        _ = try h.backend.start(info: info, state: LiveActivityState.make(cursor: .start, sequence: try await h.model.projects.sequence(for: h.project))!)
        let seq = try await h.model.projects.sequence(for: h.project)
        _ = h.model.projects.apply(.jump(row: 2), to: h.project, in: seq)  // stored cursor moved while the activity showed row 1
        h.backend.reset()
        await h.model.reconcileActivities()
        #expect(h.backend.calls.last == .update("act1", 2, 0))
    }
}

import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct LiveActivityControllerTests {
    static let seq = try! WorkSequence(chart: Chart.load(TestFixtures.data("two-letter-codes.chart.json")))
    static let chart = try! Chart.load(TestFixtures.data("two-letter-codes.chart.json"))

    struct Harness {
        let backend: RecordingBackend
        let controller: LiveActivityController
        let defaults: UserDefaults
    }
    func make() -> Harness {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let backend = RecordingBackend()
        return Harness(backend: backend, controller: LiveActivityController(backend: backend, defaults: defaults), defaults: defaults)
    }
    func info(_ id: UUID) -> WorkActivityInfo { LiveActivityState.info(projectID: id, chart: Self.chart, sequence: Self.seq) }
    func state(_ cursor: Cursor) -> WorkActivityState { LiveActivityState.make(cursor: cursor, sequence: Self.seq)! }

    @Test func startsOneAndAdoptsTheSameProject() async {
        let h = make(); let p = UUID()
        await h.controller.start(projectID: p, info: info(p), state: state(.start))
        #expect(h.controller.currentID == "act1" && h.controller.currentProjectID == p)
        await h.controller.start(projectID: p, info: info(p), state: state(Cursor(row: 1, run: 1)))
        #expect(h.controller.currentID == "act1")
        #expect(h.backend.calls == [.start(p), .update("act1", 1, 1)])
    }

    @Test func startingAnotherProjectEndsTheFirst() async {
        let h = make(); let a = UUID(), b = UUID()
        await h.controller.start(projectID: a, info: info(a), state: state(.start))
        await h.controller.start(projectID: b, info: info(b), state: state(.start))
        #expect(h.backend.calls == [.start(a), .end("act1", message: nil, finished: nil, immediately: true), .start(b)])
        #expect(h.controller.currentID == "act2" && h.backend.active().map(\.id) == ["act2"])
    }

    @Test func disabledActivitiesSetTheHintOnce() async {
        let h = make(); let p = UUID()
        h.backend.areActivitiesEnabled = false
        await h.controller.start(projectID: p, info: info(p), state: state(.start))
        #expect(h.controller.currentID == nil && h.controller.settingsHint != nil)
        #expect(h.defaults.bool(forKey: LiveActivityController.hintShownKey))
        h.controller.dismissHint()
        await h.controller.start(projectID: p, info: info(p), state: state(.start))
        #expect(h.controller.settingsHint == nil)  // shown once, persisted
    }

    @Test func startFailureAlsoHints() async {
        let h = make(); let p = UUID()
        h.backend.startError = NSError(domain: "test", code: 1)
        await h.controller.start(projectID: p, info: info(p), state: state(.start))
        #expect(h.controller.currentID == nil && h.controller.settingsHint != nil)
    }

    @Test func updateRefreshesRestartsAfterSystemEndAndEndsOnFinish() async {
        let h = make(); let p = UUID()
        await h.controller.start(projectID: p, info: info(p), state: state(.start))
        await h.controller.update(projectID: p, info: info(p), state: state(Cursor(row: 1, run: 1)))
        #expect(h.backend.calls.last == .update("act1", 1, 1))
        h.backend.systemEnded("act1")
        await h.controller.update(projectID: p, info: info(p), state: state(Cursor(row: 1, run: 2)))
        #expect(h.backend.calls.last == .start(p) && h.controller.currentID == "act2")
        await h.controller.update(projectID: p, info: info(p), state: state(Cursor(row: 2, run: 3)))  // finished
        #expect(h.backend.calls.last == .end("act2", message: nil, finished: true, immediately: false) && h.controller.currentID == nil)
    }

    @Test func updateForAnotherProjectIsIgnored() async {
        let h = make(); let a = UUID(), b = UUID()
        await h.controller.start(projectID: a, info: info(a), state: state(.start))
        h.backend.reset()
        await h.controller.update(projectID: b, info: info(b), state: state(.start))
        #expect(h.backend.calls.isEmpty)
    }

    @Test func endClearsCurrent() async {
        let h = make(); let p = UUID()
        await h.controller.start(projectID: p, info: info(p), state: state(.start))
        await h.controller.end(projectID: p, finalState: state(Cursor(row: 1, run: 1)))
        #expect(h.backend.calls.last == .end("act1", message: nil, finished: false, immediately: true) && h.controller.currentID == nil && h.backend.active().isEmpty)
    }

    @Test func reconcileRefreshesOrEnds() async {
        let h = make(); let live = UUID(), gone = UUID()
        _ = try? h.backend.start(info: info(live), state: state(.start))
        _ = try? h.backend.start(info: info(gone), state: state(.start))
        h.backend.reset()
        await h.controller.reconcile { info in info.projectID == live ? self.state(Cursor(row: 2, run: 0)) : nil }
        #expect(h.backend.calls == [.update("act1", 2, 0), .end("act2", message: "This project is no longer available.", finished: true, immediately: false)])
        #expect(h.controller.currentID == "act1" && h.controller.currentProjectID == live)
    }

    @Test func reconcileEndsAFinishedProject() async {
        let h = make(); let p = UUID()
        _ = try? h.backend.start(info: info(p), state: state(.start))
        h.backend.reset()
        await h.controller.reconcile { _ in self.state(Cursor(row: 2, run: 3)) }  // finished
        #expect(h.backend.calls == [.end("act1", message: nil, finished: true, immediately: false)])
        #expect(h.controller.currentID == nil)
    }

    @Test func endUnavailable() async {
        let h = make(); let p = UUID()
        await h.controller.start(projectID: p, info: info(p), state: state(.start))
        await h.controller.endUnavailable(activityID: "act1", message: "Chart missing.")
        #expect(h.backend.calls.last == .end("act1", message: "Chart missing.", finished: true, immediately: false) && h.controller.currentID == nil)
    }

    @Test func concurrentStartsForDifferentProjectsAreSerialized() async {
        let h = make(); let existing = UUID(), a = UUID(), b = UUID()
        // A pre-existing activity gives each concurrent `start` a real suspension point (ending
        // it) to interleave on; two starts on an empty backend never suspend at all, so they
        // can't race no matter how `start` is written.
        _ = try? h.backend.start(info: info(existing), state: state(.start))
        h.backend.reset()
        h.backend.suspendOnEnd = true
        let infoA = info(a), infoB = info(b), start = state(.start)
        let first = Task { @MainActor in await h.controller.start(projectID: a, info: infoA, state: start) }
        let second = Task { @MainActor in await h.controller.start(projectID: b, info: infoB, state: start) }
        _ = await (first.value, second.value)
        #expect(h.backend.active().count == 1)
        #expect(h.controller.currentID == h.backend.active().first?.id)
        #expect(h.controller.currentProjectID == h.backend.active().first?.info.projectID)
    }
}

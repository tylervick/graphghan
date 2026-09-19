import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

/// App Intents spec §3.5: the discoverable intents, through the event log. An extension of
/// `WorkIntentTests` so these share its `.serialized` trait -- every case claims
/// `WorkIntentHandler.shared` for its own model.
extension WorkIntentTests {
    func startAnother(_ h: Harness, title: String) async throws -> Project {
        let manifest = TestManifest.make(chartID: h.project.chartID)
        return try await h.model.projects.startProject(manifest: manifest, chart: manifest.charts[0], title: title)
    }

    func kinds(_ h: Harness, _ project: Project) throws -> [EventKind] {
        try h.model.projects.events(for: project).map(\.kind)
    }

    @Test func markDoneAppliesThroughTheService() async throws {
        let h = try await make()
        _ = try await MarkDoneIntent().perform()
        #expect(h.project.cursor == Cursor(row: 1, run: 1))
        #expect(try kinds(h, h.project) == [.advance])
        // Voice never starts a Live Activity; the Work screen owns that lifecycle.
        #expect(h.backend.calls.isEmpty)
    }

    @Test func doneThenBackReturnsToTheStart() async throws {
        let h = try await make()
        _ = try await MarkDoneIntent().perform()
        _ = try await UndoDoneIntent().perform()
        #expect(h.project.cursor == .start)
        #expect(try kinds(h, h.project) == [.advance, .back])
    }

    // MARK: spec §3.2, which project

    @Test func liveActivityProjectWins() async throws {
        let h = try await make()
        let other = try await startAnother(h, title: "other")
        other.lastWorked = Date()  // more recent than h.project, which was never worked
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        await h.model.liveActivity.start(projectID: h.project.id, info: info, state: state)
        _ = try await MarkDoneIntent().perform()
        #expect(try kinds(h, h.project) == [.advance])
        #expect(try kinds(h, other).isEmpty)
        #expect(h.backend.calls.last == .update("act1", 1, 1))
    }

    @Test func mostRecentlyWorkedProjectWins() async throws {
        let h = try await make()
        let other = try await startAnother(h, title: "other")
        h.project.lastWorked = Date(timeIntervalSince1970: 1_000)
        other.lastWorked = Date(timeIntervalSince1970: 2_000)
        _ = try await MarkDoneIntent().perform()
        #expect(try kinds(h, other) == [.advance])
        #expect(try kinds(h, h.project).isEmpty)
    }

    @Test func aProjectNeverWorkedCountsFromItsStart() async throws {
        let h = try await make()  // started now, never worked
        let other = try await startAnother(h, title: "other")
        other.started = Date(timeIntervalSince1970: 1_000)
        other.lastWorked = Date(timeIntervalSince1970: 2_000)  // long ago; h.project was started after
        _ = try await MarkDoneIntent().perform()
        #expect(try kinds(h, h.project) == [.advance])
        #expect(try kinds(h, other).isEmpty)
    }

    @Test func finishedProjectsAreNeverTargets() async throws {
        let h = try await make()
        let other = try await startAnother(h, title: "other")
        h.project.lastWorked = Date(timeIntervalSince1970: 1_000)
        other.lastWorked = Date(timeIntervalSince1970: 2_000)
        try h.model.projects.markFinished(other)
        _ = try await MarkDoneIntent().perform()
        #expect(try kinds(h, h.project) == [.advance])
        #expect(try kinds(h, other).isEmpty)
        try h.model.projects.markFinished(h.project)
        let outcome = await h.model.performIntent(.advance)
        #expect(WorkIntentDialog.text(for: outcome).full == "You don't have a project going.")
        #expect(try kinds(h, h.project) == [.advance])
    }

    @Test func noProjectSaysSoAndChangesNothing() async throws {
        let h = try await make()
        try h.model.projects.delete(h.project)
        let outcome = await h.model.performIntent(.advance)
        guard case .noProject = outcome else { Issue.record("expected .noProject"); return }
        _ = try await MarkDoneIntent().perform()  // and the intent itself does not throw
        #expect(try h.model.projects.projects().isEmpty)
    }

    @Test func aMissingChartIsSaidNotCounted() async throws {
        let h = try await make()
        try await h.model.charts.remove(id: h.project.chartID)
        let outcome = await h.model.performIntent(.advance)
        #expect(WorkIntentDialog.text(for: outcome).full == "Couldn't open the chart for x.")
        #expect(try kinds(h, h.project).isEmpty)
    }

    // MARK: an activity the system ended

    /// After the system's 8-hour end the controller still remembers its project, but that activity
    /// is not running, so spec §3.2's rule 1 does not apply: rule 2 chooses.
    @Test func aSystemEndedActivityIsNotRuleOne() async throws {
        let h = try await make()
        let other = try await startAnother(h, title: "other")
        h.project.lastWorked = Date(timeIntervalSince1970: 1_000)
        other.lastWorked = Date(timeIntervalSince1970: 10_000)
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        await h.model.liveActivity.start(projectID: h.project.id, info: info, state: state)
        h.backend.systemEnded("act1")
        #expect(h.model.liveActivity.liveProjectID == nil)
        _ = try await MarkDoneIntent().perform()
        #expect(try kinds(h, other) == [.advance])
        #expect(try kinds(h, h.project).isEmpty)
    }

    /// The Work screen restarts an activity the system ended on the next tap; a Done said while
    /// that screen is still open does the same through the one `onApply` path. Nothing else
    /// starts one.
    @Test func aDoneWithTheWorkScreenOpenRestartsASystemEndedActivity() async throws {
        let h = try await make()
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        await h.model.liveActivity.start(projectID: h.project.id, info: info, state: state)
        h.backend.systemEnded("act1")
        h.backend.reset()
        _ = try await MarkDoneIntent().perform()
        #expect(try kinds(h, h.project) == [.advance])
        #expect(h.backend.calls == [.start(h.project.id)])
        #expect(h.backend.active().count == 1)
    }

    // MARK: spec §3.4, nowhere to go

    @Test func backAtTheStartIsNowhereToGo() async throws {
        let h = try await make()
        let outcome = await h.model.performIntent(.back)
        #expect(WorkIntentDialog.text(for: outcome).full == "You're at the beginning.")
        #expect(try kinds(h, h.project).isEmpty)
        #expect(h.project.cursor == .start)
    }

    /// The last Done marks the project finished, and spec §3.2 never targets a finished project:
    /// one more Done is told there is no project going. "You've already finished this one" is
    /// reachable only for a project un-finished by hand with its cursor still at the end.
    @Test func donePastTheEndIsNowhereToGo() async throws {
        let h = try await make()
        let seq = try await h.model.projects.sequence(for: h.project)
        while h.model.projects.apply(.advance, to: h.project, in: seq) != nil {}
        let before = try kinds(h, h.project)
        #expect(h.project.isFinished)
        var outcome = await h.model.performIntent(.advance)
        #expect(WorkIntentDialog.text(for: outcome).full == "You don't have a project going.")
        try h.model.projects.markUnfinished(h.project)
        outcome = await h.model.performIntent(.advance)
        #expect(WorkIntentDialog.text(for: outcome).full == "You've already finished this one.")
        #expect(try kinds(h, h.project) == before)
    }

    // MARK: the cold cases

    /// Said to Siri with the app not running: the system still shows an activity the controller
    /// has never heard of. The Done refreshes it and starts no second one.
    @Test func coldLaunchDoneRefreshesTheActivityTheSystemShows() async throws {
        let h = try await make()
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        _ = try h.backend.start(info: info, state: state)
        _ = try await MarkDoneIntent().perform()
        #expect(try kinds(h, h.project) == [.advance])
        #expect(h.backend.calls.last == .update("act1", 1, 1))
        #expect(h.backend.active().count == 1)
    }

    /// Spec §3.1 through the Siri surface: an intent that performs before `AppModel.live` has
    /// claimed the handler waits for it rather than confirming a count that never happened.
    @Test func coldHandlerStillAppliesMarkDone() async throws {
        let h = try await make()
        WorkIntentHandler.shared.perform = nil
        WorkIntentHandler.shared.performWorking = nil
        let performing = Task { @MainActor in _ = try await MarkDoneIntent().perform() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(try kinds(h, h.project).isEmpty)
        h.model.registerIntentHandler()
        try await performing.value
        #expect(try kinds(h, h.project) == [.advance])
    }

    @Test func aHandlerThatNeverRegistersThrowsRatherThanConfirming() async throws {
        let h = try await make()
        WorkIntentHandler.shared.perform = nil
        WorkIntentHandler.shared.performWorking = nil
        await #expect(throws: WorkIntentError.self) {
            _ = try await WorkIntentHandler.shared.stepWorkingProject(.advance, timeout: .milliseconds(50))
        }
        #expect(try kinds(h, h.project).isEmpty)
        h.model.registerIntentHandler()  // leave the shared handler as the other cases expect it
    }
}

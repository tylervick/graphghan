# Live Activity and Intents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A lock-screen and Dynamic Island Live Activity for the project being worked, with Done and Back buttons that advance the same store the Work screen uses, started and ended with the Work screen and reconciled on launch.

**Architecture:** The core package gains a pure builder that turns a cursor and sequence into the activity's content state, tested against the fixtures. The app gains a `LiveActivityController` over a small `ActivityBackend` protocol (ActivityKit in production, a recording fake in tests) that enforces one activity at a time, adopts an existing activity for the same project, restarts after the system's 8-hour end, ends on close or finish, and reconciles on launch. `AdvanceRunIntent` and `BackRunIntent` are `LiveActivityIntent`s compiled into both the app and a new `GraphghanWidgets` extension; they delegate to a handler the app registers at launch, which calls `ProjectService.apply`, so the Work screen and the lock screen mutate the same way. The activity's views live in a `Shared/` folder compiled into both targets so the app's unit tests can snapshot them with `ImageRenderer`.

**Tech Stack:** Swift 6.2, iOS 17.0, ActivityKit, WidgetKit, AppIntents, SwiftUI `ImageRenderer` for snapshots, Swift Testing, xcodegen.

**Spec:** `docs/superpowers/specs/2026-09-10-graphghan-ios-app-design.md` (section 7; §6.6 for the Settings hint; §9 for tests). This plan is "Plan 3: Live Activity and intents" from section 10. Plan 2's code is on `main` under `ios/`.

## Global Constraints

- Work on branch `feat/live-activity` in a worktree; never commit directly to `main`.
- iOS 17.0 deployment target (interactive Live Activity buttons and `LiveActivityIntent` need it). Bundle ids `com.tylervick.graphghan` (app) and `com.tylervick.graphghan.widgets` (extension); App Group `group.com.tylervick.graphghan`; team `352UZEKYPP`; Swift 6 language mode, strict concurrency.
- One activity at a time. It starts when the Work screen opens; it ends when the screen closes, when the project is finished, or when the system ends it (then the next advance restarts it). On launch the app reconciles: the stored cursor wins; a stale activity is refreshed or ended.
- Attributes: project id, pattern title, total rows, total stitches, palette as code, name, hex. State: row, side, run index, current run (code, count), next run or `isLastInRow`, percent. The state is built by a pure function in the core package.
- Lock screen: title and "Row 42 of 184"; the current run large as a swatch with the count and the name beside it; next run small; Back and Done buttons, Done primary and larger. Dynamic Island: compact leading swatch with count, trailing row number; minimal swatch with count; expanded as the lock screen.
- Intents take a project id, run in the app process, apply through `ProjectService.apply` (the single mutation path), and update the activity. No haptics from the intent. A missing project or chart ends the activity with an explanatory final state. Updates are local only; no push. `AppShortcutsProvider` is NOT registered.
- The core package imports Foundation and CryptoKit only. Every new Swift test uses Swift Testing.
- `git commit` signs inside the sandbox (repo-local key). Commit messages end with:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_016acqd28TPss8NPKVWwzMxK`
- Commands from `ios/`: `mise run generate`, `mise run core-test`, `mise run test`. If a code block does not compile under Swift 6.2 / the iOS 17 SDK, make the smallest change that preserves the stated behaviour and record it; do not rename anything in an **Interfaces** block without saying so.

---

## File structure

| path | responsibility |
|---|---|
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/LiveActivityState.swift` | `WorkActivityInfo`, `WorkActivityState`, `ActivitySwatch`, and the pure builder |
| `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/LiveActivityStateTests.swift` | builder tests against fixtures |
| `ios/project.yml` | new `GraphghanWidgets` extension target; `Shared/` in both targets; `NSSupportsLiveActivities` |
| `ios/Shared/WorkActivityAttributes.swift` | `ActivityAttributes` wrapper around the core types |
| `ios/Shared/WorkIntents.swift` | `AdvanceRunIntent`, `BackRunIntent`, `WorkIntentHandler` |
| `ios/Shared/HexColor.swift` | hex → `Color`, light/dark text choice (no app dependency) |
| `ios/Shared/WorkActivityViews.swift` | lock screen, expanded, compact, minimal views |
| `ios/GraphghanWidgets/GraphghanWidgetsBundle.swift`, `WorkLiveActivity.swift` | the extension entry point and `ActivityConfiguration` |
| `ios/Graphghan/Services/ActivityBackend.swift` | `ActivityBackend` protocol + `ActivityKitBackend` |
| `ios/Graphghan/Services/LiveActivityController.swift` | lifecycle rules |
| `ios/Graphghan/Services/ProjectService.swift` | `project(id:)`, `onApply` hook |
| `ios/Graphghan/AppModel.swift` | owns the controller, registers the intent handler, reconciles on launch |
| `ios/Graphghan/Work/WorkView.swift` | start/end the activity, Settings hint |
| `ios/Tests/RecordingBackend.swift`, `LiveActivityControllerTests.swift`, `WorkIntentTests.swift`, `Snapshots.swift`, `WorkActivityViewsTests.swift`, `__Snapshots__/*.png` | app tests |
| `ios/docs/qa.md` | manual checks for the activity |

---

### Task 0: Branch and worktree

- [ ] **Step 1: Create the worktree**

From the repo root:
```bash
git worktree add .worktrees/live-activity -b feat/live-activity main
cd .worktrees/live-activity && mise trust -q && mise install -q && mise run setup
cd ios && mise install -q && mise run core-test && mise run test
```
Expected: 50 package tests and 31 app tests green. All later commands run inside `.worktrees/live-activity`.

---

### Task 1: Core activity state builder

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/LiveActivityState.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/LiveActivityStateTests.swift`

**Interfaces:**
- Produces:
  - `public struct ActivitySwatch: Codable, Hashable, Sendable { code, name, hex: String }`
  - `public struct WorkActivityInfo: Codable, Hashable, Sendable { projectID: UUID; title: String; totalRows: Int; totalStitches: Int; palette: [ActivitySwatch]; func swatch(for code: String) -> ActivitySwatch? }`
  - `public struct WorkActivityState: Codable, Hashable, Sendable { row: Int; rowCount: Int; side: String?; runIndex: Int; currentCode: String?; currentCount: Int?; nextCode: String?; nextCount: Int?; isLastInRow: Bool; percent: Double; finished: Bool; message: String? }` with `static func unavailable(_ message: String) -> WorkActivityState`.
  - `public enum LiveActivityState { static func make(cursor: Cursor, sequence: WorkSequence) -> WorkActivityState?; static func info(projectID: UUID, chart: Chart, sequence: WorkSequence) -> WorkActivityInfo }`.

Semantics: `row`/`rowCount` are 1-based pass index and pass count; `side` is the pass's side raw value; `currentCode/Count` are the run at the cursor (nil when finished); `nextCode/Count` is the following run in the same pass, else nil with `isLastInRow` true; `percent` is `Pace`-style one-decimal percent of stitches before the cursor; `finished` is `WorkEngine.isFinished`; `message` is only set for the explanatory final state. Invalid cursor → nil.

- [ ] **Step 1: Failing tests**

`LiveActivityStateTests.swift`:
```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct LiveActivityStateTests {
    // two-letter-codes: Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3 (24 stitches)
    static let chart = try! Chart.load(Fixtures.data("two-letter-codes.chart.json"))
    static let seq = try! WorkSequence(chart: chart)

    @Test func startOfChart() throws {
        let s = try #require(LiveActivityState.make(cursor: .start, sequence: Self.seq))
        #expect(s.row == 1 && s.rowCount == 2 && s.side == "RS" && s.runIndex == 0)
        #expect(s.currentCode == "Kb" && s.currentCount == 3)
        #expect(s.nextCode == "Gd" && s.nextCount == 7 && !s.isLastInRow)
        #expect(s.percent == 0 && !s.finished && s.message == nil)
    }

    @Test func lastRunInRow() throws {
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 2, run: 2), sequence: Self.seq))
        #expect(s.currentCode == "Y" && s.currentCount == 3)
        #expect(s.nextCode == nil && s.nextCount == nil && s.isLastInRow)
        #expect(s.percent == 87.5)  // 21 of 24
    }

    @Test func finishedCursor() throws {
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 2, run: 3), sequence: Self.seq))
        #expect(s.finished && s.currentCode == nil && s.currentCount == nil && s.percent == 100 && s.isLastInRow)
    }

    @Test func invalidCursorIsNil() {
        #expect(LiveActivityState.make(cursor: Cursor(row: 9, run: 0), sequence: Self.seq) == nil)
    }

    @Test func infoCarriesPalette() {
        let id = UUID()
        let info = LiveActivityState.info(projectID: id, chart: Self.chart, sequence: Self.seq)
        #expect(info.projectID == id && info.title == "Two-letter codes" && info.totalRows == 2 && info.totalStitches == 24)
        #expect(info.palette.map(\.code) == ["G", "Gd", "Kb", "Y"] && info.swatch(for: "Gd")?.hex == "#D9A21B" && info.swatch(for: "Q") == nil)
    }

    @Test func unavailableState() {
        let s = WorkActivityState.unavailable("This project is no longer available.")
        #expect(s.message == "This project is no longer available." && s.finished && s.currentCode == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 1, run: 1), sequence: Self.seq))
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(WorkActivityState.self, from: data) == s)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ios && mise run core-test` → compile errors for the new types.

- [ ] **Step 3: Implement**

`LiveActivityState.swift`:
```swift
import Foundation

/// A palette entry as the Live Activity draws it.
public struct ActivitySwatch: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let hex: String
    public init(code: String, name: String, hex: String) { self.code = code; self.name = name; self.hex = hex }
}

/// Static attributes of one project's activity (spec §7).
public struct WorkActivityInfo: Codable, Hashable, Sendable {
    public let projectID: UUID
    public let title: String
    public let totalRows: Int
    public let totalStitches: Int
    public let palette: [ActivitySwatch]
    public init(projectID: UUID, title: String, totalRows: Int, totalStitches: Int, palette: [ActivitySwatch]) {
        self.projectID = projectID; self.title = title; self.totalRows = totalRows; self.totalStitches = totalStitches; self.palette = palette
    }
    public func swatch(for code: String) -> ActivitySwatch? { palette.first { $0.code == code } }
}

/// Dynamic state of the activity: what the crocheter is on right now.
public struct WorkActivityState: Codable, Hashable, Sendable {
    public var row: Int
    public var rowCount: Int
    public var side: String?
    public var runIndex: Int
    public var currentCode: String?
    public var currentCount: Int?
    public var nextCode: String?
    public var nextCount: Int?
    public var isLastInRow: Bool
    public var percent: Double
    public var finished: Bool
    /// Only set for the explanatory final state (project or chart gone).
    public var message: String?

    public init(row: Int, rowCount: Int, side: String?, runIndex: Int, currentCode: String?, currentCount: Int?, nextCode: String?, nextCount: Int?,
                isLastInRow: Bool, percent: Double, finished: Bool, message: String? = nil) {
        self.row = row; self.rowCount = rowCount; self.side = side; self.runIndex = runIndex
        self.currentCode = currentCode; self.currentCount = currentCount; self.nextCode = nextCode; self.nextCount = nextCount
        self.isLastInRow = isLastInRow; self.percent = percent; self.finished = finished; self.message = message
    }

    public static func unavailable(_ message: String) -> WorkActivityState {
        WorkActivityState(row: 0, rowCount: 0, side: nil, runIndex: 0, currentCode: nil, currentCount: nil, nextCode: nil, nextCount: nil,
                          isLastInRow: true, percent: 0, finished: true, message: message)
    }
}

/// Pure builders: no ActivityKit here, so the app and its tests share one definition of "what the lock screen shows".
public enum LiveActivityState {
    public static func make(cursor: Cursor, sequence: WorkSequence) -> WorkActivityState? {
        guard let pass = sequence.pass(at: cursor.row), let done = sequence.stitchesBefore(cursor) else { return nil }
        let finished = WorkEngine.isFinished(cursor, in: sequence)
        let current: Run? = cursor.run < pass.runs.count ? pass.runs[cursor.run] : nil
        let next: Run? = cursor.run + 1 < pass.runs.count ? pass.runs[cursor.run + 1] : nil
        let total = sequence.totalStitches
        let percent = total > 0 ? (100 * Double(done) / Double(total) * 10).rounded(.toNearestOrEven) / 10 : 0
        return WorkActivityState(
            row: cursor.row, rowCount: sequence.passes.count, side: pass.side?.rawValue, runIndex: cursor.run,
            currentCode: current?.code, currentCount: current?.count, nextCode: next?.code, nextCount: next?.count,
            isLastInRow: next == nil, percent: percent, finished: finished, message: nil)
    }

    public static func info(projectID: UUID, chart: Chart, sequence: WorkSequence) -> WorkActivityInfo {
        WorkActivityInfo(projectID: projectID, title: chart.title, totalRows: sequence.passes.count, totalStitches: sequence.totalStitches,
                         palette: chart.palette.map { ActivitySwatch(code: $0.code, name: $0.name, hex: $0.hex) })
    }
}
```

- [ ] **Step 4: Run the tests** → `mise run core-test` green (57 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "feat(core): Live Activity info and state built from cursor and sequence"
```

---

### Task 2: Widget extension target and shared attributes

**Files:**
- Modify: `ios/project.yml`, `.gitignore`
- Create: `ios/Shared/WorkActivityAttributes.swift`, `ios/GraphghanWidgets/GraphghanWidgetsBundle.swift`, `ios/GraphghanWidgets/WorkLiveActivity.swift` (placeholder view; Task 6 fills it), `ios/GraphghanWidgets/Assets.xcassets/Contents.json`

**Interfaces:**
- Produces: `struct WorkActivityAttributes: ActivityAttributes { let info: WorkActivityInfo; typealias ContentState = WorkActivityState }`; xcodegen targets `GraphghanWidgets` (app-extension, bundle id `com.tylervick.graphghan.widgets`, sources `GraphghanWidgets` + `Shared`, package dependency `GraphghanCore`, App Group entitlement) embedded in `Graphghan`; the app's Info.plist has `NSSupportsLiveActivities: true` and the app target compiles `Shared/`.

- [ ] **Step 1: project.yml**

Change the `Graphghan` target's `sources` to:
```yaml
    sources:
      - path: Graphghan
      - path: Shared
      - path: Assets.xcassets
```
its `dependencies` to:
```yaml
    dependencies:
      - package: GraphghanCore
      - target: GraphghanWidgets
```
and add `NSSupportsLiveActivities: true` to its `info.properties`. Add the extension target after `GraphghanTests`:
```yaml
  GraphghanWidgets:
    type: app-extension
    platform: iOS
    sources:
      - path: GraphghanWidgets
      - path: Shared
    dependencies:
      - package: GraphghanCore
    entitlements:
      path: GraphghanWidgets/GraphghanWidgets.entitlements
      properties:
        com.apple.security.application-groups: [group.com.tylervick.graphghan]
    info:
      path: GraphghanWidgets/Info.plist
      properties:
        CFBundleDisplayName: Graphghan
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tylervick.graphghan.widgets
        CURRENT_PROJECT_VERSION: 1
        MARKETING_VERSION: "0.1"
        SKIP_INSTALL: YES
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
```
Add `GraphghanWidgets: all` under the scheme's `build.targets`. Append to the repo-root `.gitignore`:
```
ios/GraphghanWidgets/Info.plist
ios/GraphghanWidgets/GraphghanWidgets.entitlements
```
Create `ios/GraphghanWidgets/Assets.xcassets/Contents.json` as `{ "info": { "author": "xcode", "version": 1 } }` and add `- path: Assets.xcassets` under the extension's `sources` only if xcodegen complains about the accent colour; otherwise leave the catalog out (the extension inherits nothing from the app's catalog; the accent setting is harmless if absent).

- [ ] **Step 2: Shared attributes and the extension entry point**

`ios/Shared/WorkActivityAttributes.swift`:
```swift
import ActivityKit
import GraphghanCore

/// The one Live Activity type. Compiled into the app and the widget extension; the core types
/// keep the data definition out of both.
struct WorkActivityAttributes: ActivityAttributes {
    typealias ContentState = WorkActivityState
    let info: WorkActivityInfo
}
```
`ios/GraphghanWidgets/GraphghanWidgetsBundle.swift`:
```swift
import SwiftUI
import WidgetKit

@main
struct GraphghanWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkLiveActivity()
    }
}
```
`ios/GraphghanWidgets/WorkLiveActivity.swift` (placeholder; Task 6 replaces it):
```swift
import ActivityKit
import SwiftUI
import WidgetKit
import GraphghanCore

struct WorkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkActivityAttributes.self) { context in
            Text("\(context.attributes.info.title) · Row \(context.state.row) of \(context.state.rowCount)")
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { Text("Row \(context.state.row)") }
            } compactLeading: {
                Text("\(context.state.currentCount ?? 0)")
            } compactTrailing: {
                Text("\(context.state.row)")
            } minimal: {
                Text("\(context.state.currentCount ?? 0)")
            }
        }
    }
}
```

- [ ] **Step 3: Generate, build, test**

Run: `cd ios && mise run generate && mise run test`
Expected: the project generates with three targets, the app embeds the extension, and `** TEST SUCCEEDED **` (31 tests). If xcodegen rejects `type: app-extension` for a WidgetKit extension, use `type: app-extension` with `settings.base.PRODUCT_BUNDLE_IDENTIFIER` as above and add `platform: iOS` (already present); if Xcode complains that the extension needs `@main` in a file named after the product, that is not a real requirement — check the error text and report.

- [ ] **Step 4: Commit**

```bash
git add .gitignore ios/project.yml ios/Shared ios/GraphghanWidgets
git commit -m "feat(ios): GraphghanWidgets extension target and shared Live Activity attributes"
```

---

### Task 3: Activity backend and lifecycle controller

**Files:**
- Create: `ios/Graphghan/Services/ActivityBackend.swift`, `ios/Graphghan/Services/LiveActivityController.swift`
- Test: `ios/Tests/RecordingBackend.swift`, `ios/Tests/LiveActivityControllerTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor protocol ActivityBackend: AnyObject { var areActivitiesEnabled: Bool { get }; func start(info: WorkActivityInfo, state: WorkActivityState) throws -> String; func update(id: String, state: WorkActivityState) async; func end(id: String, state: WorkActivityState?, immediately: Bool) async; func active() -> [ActiveActivity] }` with `struct ActiveActivity: Equatable { id: String; info: WorkActivityInfo }`.
  - `@MainActor final class ActivityKitBackend: ActivityBackend`.
  - `@MainActor @Observable final class LiveActivityController { init(backend: ActivityBackend, defaults: UserDefaults); private(set) var currentID: String?; private(set) var currentProjectID: UUID?; var settingsHint: String?; func dismissHint(); func start(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async; func update(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async; func end(projectID: UUID, finalState: WorkActivityState?) async; func endAll() async; func endUnavailable(activityID: String, message: String) async; func reconcile(stateFor: (WorkActivityInfo) async -> WorkActivityState?) async }`.
  - `static let hintShownKey = "liveActivityHintShown"`.

Rules the tests pin: `start` adopts an existing active activity for the same project (updates it, does not start a second); otherwise ends every other active activity, then starts one; when activities are disabled or `start` throws, no activity and the Settings hint is set once (persisted in `defaults`). `update` for the current project updates it; if the backend no longer lists it as active (system ended it), it restarts; if `state.finished`, it ends the activity with that final state. `end` ends the current project's activity with the final state (immediately) and clears the current ids. `endUnavailable` ends a given activity with `WorkActivityState.unavailable(message)`. `reconcile` calls `stateFor` for each active activity; a non-nil state refreshes it, nil ends it with the unavailable message "This project is no longer available."; a refreshed activity becomes current only if none is current.

- [ ] **Step 1: Failing tests**

`ios/Tests/RecordingBackend.swift`:
```swift
import Foundation
import GraphghanCore
@testable import Graphghan

/// ActivityKit stand-in: records every call and keeps the set of "active" activities.
@MainActor
final class RecordingBackend: ActivityBackend {
    enum Call: Equatable {
        case start(UUID)
        case update(String, Int, Int)          // id, row, runIndex
        case end(String, String?, Bool)        // id, message, immediately
    }
    var areActivitiesEnabled = true
    var startError: Error?
    private(set) var calls: [Call] = []
    private var actives: [ActiveActivity] = []
    private var nextID = 1

    func start(info: WorkActivityInfo, state: WorkActivityState) throws -> String {
        if let startError { throw startError }
        let id = "act\(nextID)"; nextID += 1
        actives.append(ActiveActivity(id: id, info: info))
        calls.append(.start(info.projectID))
        return id
    }
    func update(id: String, state: WorkActivityState) async { calls.append(.update(id, state.row, state.runIndex)) }
    func end(id: String, state: WorkActivityState?, immediately: Bool) async {
        actives.removeAll { $0.id == id }
        calls.append(.end(id, state?.message, immediately))
    }
    func active() -> [ActiveActivity] { actives }
    /// The system ended it (8-hour limit): it disappears from `active()` without an `end` call.
    func systemEnded(_ id: String) { actives.removeAll { $0.id == id } }
    func reset() { calls = [] }
}
```
`ios/Tests/LiveActivityControllerTests.swift`:
```swift
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
        #expect(h.backend.calls == [.start(a), .end("act1", nil, true), .start(b)])
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
        #expect(h.backend.calls.last == .end("act2", nil, true) && h.controller.currentID == nil)
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
        #expect(h.backend.calls.last == .end("act1", nil, true) && h.controller.currentID == nil && h.backend.active().isEmpty)
    }

    @Test func reconcileRefreshesOrEnds() async {
        let h = make(); let live = UUID(), gone = UUID()
        _ = try? h.backend.start(info: info(live), state: state(.start))
        _ = try? h.backend.start(info: info(gone), state: state(.start))
        h.backend.reset()
        await h.controller.reconcile { info in info.projectID == live ? self.state(Cursor(row: 2, run: 0)) : nil }
        #expect(h.backend.calls == [.update("act1", 2, 0), .end("act2", "This project is no longer available.", true)])
        #expect(h.controller.currentID == "act1" && h.controller.currentProjectID == live)
    }

    @Test func endUnavailable() async {
        let h = make(); let p = UUID()
        await h.controller.start(projectID: p, info: info(p), state: state(.start))
        await h.controller.endUnavailable(activityID: "act1", message: "Chart missing.")
        #expect(h.backend.calls.last == .end("act1", "Chart missing.", true) && h.controller.currentID == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** → `cd ios && mise run test` compile errors.

- [ ] **Step 3: Implement**

`ios/Graphghan/Services/ActivityBackend.swift`:
```swift
import ActivityKit
import Foundation
import GraphghanCore

struct ActiveActivity: Equatable {
    let id: String
    let info: WorkActivityInfo
}

/// The ActivityKit seam. Production uses ActivityKit; tests use a recording fake.
@MainActor
protocol ActivityBackend: AnyObject {
    var areActivitiesEnabled: Bool { get }
    func start(info: WorkActivityInfo, state: WorkActivityState) throws -> String
    func update(id: String, state: WorkActivityState) async
    func end(id: String, state: WorkActivityState?, immediately: Bool) async
    func active() -> [ActiveActivity]
}

@MainActor
final class ActivityKitBackend: ActivityBackend {
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(info: WorkActivityInfo, state: WorkActivityState) throws -> String {
        let activity = try Activity<WorkActivityAttributes>.request(
            attributes: WorkActivityAttributes(info: info),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil)
        return activity.id
    }

    func update(id: String, state: WorkActivityState) async {
        guard let activity = find(id) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end(id: String, state: WorkActivityState?, immediately: Bool) async {
        guard let activity = find(id) else { return }
        await activity.end(state.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: immediately ? .immediate : .default)
    }

    func active() -> [ActiveActivity] {
        Activity<WorkActivityAttributes>.activities
            .filter { $0.activityState == .active }
            .map { ActiveActivity(id: $0.id, info: $0.attributes.info) }
    }

    private func find(_ id: String) -> Activity<WorkActivityAttributes>? {
        Activity<WorkActivityAttributes>.activities.first { $0.id == id }
    }
}
```
`ios/Graphghan/Services/LiveActivityController.swift`:
```swift
import Foundation
import Observation
import GraphghanCore

/// Spec §7 lifecycle: one activity at a time, started with the Work screen, ended on close or
/// finish, restarted after the system's 8-hour end, reconciled on launch.
@MainActor
@Observable
final class LiveActivityController {
    static let hintShownKey = "liveActivityHintShown"
    static let unavailableMessage = "This project is no longer available."

    private let backend: ActivityBackend
    private let defaults: UserDefaults
    private(set) var currentID: String?
    private(set) var currentProjectID: UUID?
    /// One-time pointer at Settings when activities are off or cannot start.
    var settingsHint: String?

    init(backend: ActivityBackend, defaults: UserDefaults) {
        self.backend = backend
        self.defaults = defaults
    }

    func dismissHint() { settingsHint = nil }

    func start(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async {
        if let existing = backend.active().first(where: { $0.info.projectID == projectID }) {
            currentID = existing.id
            currentProjectID = projectID
            await backend.update(id: existing.id, state: state)
            return
        }
        for other in backend.active() { await backend.end(id: other.id, state: nil, immediately: true) }
        currentID = nil
        currentProjectID = nil
        guard backend.areActivitiesEnabled else { hintOnce(); return }
        do {
            currentID = try backend.start(info: info, state: state)
            currentProjectID = projectID
        } catch {
            hintOnce()
        }
    }

    func update(projectID: UUID, info: WorkActivityInfo, state: WorkActivityState) async {
        guard currentProjectID == projectID else { return }
        if state.finished {
            await end(projectID: projectID, finalState: state)
            return
        }
        if let id = currentID, backend.active().contains(where: { $0.id == id }) {
            await backend.update(id: id, state: state)
        } else {
            // The system ended it (8-hour limit): the next advance starts a fresh one.
            currentID = nil
            await start(projectID: projectID, info: info, state: state)
        }
    }

    func end(projectID: UUID, finalState: WorkActivityState?) async {
        guard currentProjectID == projectID, let id = currentID else { return }
        await backend.end(id: id, state: finalState, immediately: true)
        currentID = nil
        currentProjectID = nil
    }

    func endAll() async {
        for a in backend.active() { await backend.end(id: a.id, state: nil, immediately: true) }
        currentID = nil
        currentProjectID = nil
    }

    func endUnavailable(activityID: String, message: String) async {
        await backend.end(id: activityID, state: .unavailable(message), immediately: true)
        if currentID == activityID { currentID = nil; currentProjectID = nil }
    }

    /// On launch: refresh every active activity from the stored cursor, or end the ones whose
    /// project or chart is gone. The stored cursor wins.
    func reconcile(stateFor: (WorkActivityInfo) async -> WorkActivityState?) async {
        for a in backend.active() {
            if let state = await stateFor(a.info) {
                await backend.update(id: a.id, state: state)
                if currentID == nil { currentID = a.id; currentProjectID = a.info.projectID }
            } else {
                await endUnavailable(activityID: a.id, message: Self.unavailableMessage)
            }
        }
    }

    private func hintOnce() {
        guard !defaults.bool(forKey: Self.hintShownKey) else { return }
        defaults.set(true, forKey: Self.hintShownKey)
        settingsHint = "Live Activities are off for Graphghan, so the lock screen won't show your row. Turn them on in Settings › Graphghan."
    }
}
```

- [ ] **Step 4: Run the tests** → `mise run test` green (40 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Services ios/Tests
git commit -m "feat(ios): Live Activity controller with a testable ActivityKit backend"
```

---

### Task 4: Intents, handler, and app wiring

**Files:**
- Create: `ios/Shared/WorkIntents.swift`
- Modify: `ios/Graphghan/Services/ProjectService.swift` (`project(id:)`, `onApply`), `ios/Graphghan/AppModel.swift` (controller, handler registration, `performIntent`, `reconcileActivities`), `ios/Graphghan/GraphghanApp.swift` (reconcile on launch)
- Test: `ios/Tests/WorkIntentTests.swift`, extend `ios/Tests/ProjectServiceTests.swift`

**Interfaces:**
- Produces:
  - `struct AdvanceRunIntent: LiveActivityIntent { @Parameter var projectID: String; init(); init(projectID: UUID) }`, `struct BackRunIntent: LiveActivityIntent` likewise; both `perform()` call `WorkIntentHandler.shared.perform?(action, uuid)` and return `.result()`.
  - `@MainActor final class WorkIntentHandler { static let shared; var perform: ((WorkAction, UUID) async -> Void)? }`.
  - `ProjectService.project(id: UUID) throws -> Project?`; `ProjectService.onApply: ((Project, WorkSequence, WorkStep) -> Void)?` invoked at the end of `apply` (after the save attempt, before returning).
  - `AppModel.liveActivity: LiveActivityController`; `AppModel.init(context:patterns:charts:activityBackend:defaults:)` with `activityBackend` defaulting to `ActivityKitBackend()` and `defaults` to `UserDefaults(suiteName: AppGroup.identifier) ?? .standard`; `func performIntent(_ action: WorkAction, projectID: UUID) async`; `func reconcileActivities() async`; `func activityState(for project: Project) async -> (WorkActivityInfo, WorkActivityState)?`.

- [ ] **Step 1: Failing tests**

`ios/Tests/WorkIntentTests.swift`:
```swift
import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct WorkIntentTests {
    struct Harness { let model: AppModel; let backend: RecordingBackend; let project: Project }

    func make() async throws -> Harness {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        let backend = RecordingBackend()
        let model = AppModel(context: container.mainContext, patterns: patterns, charts: charts, activityBackend: backend,
                             defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
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
        try await AdvanceRunIntent(projectID: h.project.id).perform()
        #expect(h.project.cursor == Cursor(row: 1, run: 1))
        #expect(h.project.eventRecords.count == 1 && h.project.eventRecords[0].kind == .advance)
        #expect(h.backend.calls.last == .update("act1", 1, 1))
        try await BackRunIntent(projectID: h.project.id).perform()
        #expect(h.project.cursor == .start && h.backend.calls.last == .update("act1", 1, 0))
    }

    @Test func staleProjectEndsTheActivity() async throws {
        let h = try await make()
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        await h.model.liveActivity.start(projectID: h.project.id, info: info, state: state)
        try h.model.projects.delete(h.project)
        try await AdvanceRunIntent(projectID: h.project.id).perform()
        #expect(h.backend.calls.last == .end("act1", LiveActivityController.unavailableMessage, true))
        #expect(h.backend.active().isEmpty)
    }

    @Test func missingChartEndsTheActivity() async throws {
        let h = try await make()
        let (info, state) = try #require(await h.model.activityState(for: h.project))
        await h.model.liveActivity.start(projectID: h.project.id, info: info, state: state)
        try await h.model.charts.remove(id: h.project.chartID)
        try await AdvanceRunIntent(projectID: h.project.id).perform()
        #expect(h.backend.calls.last == .end("act1", LiveActivityController.unavailableMessage, true))
    }

    @Test func unparseableIDIsIgnored() async throws {
        let h = try await make()
        let intent = AdvanceRunIntent()
        intent.projectID = "not-a-uuid"
        try await intent.perform()
        #expect(h.project.cursor == .start)
    }

    @Test func reconcileOnLaunch() async throws {
        let h = try await make()
        let (info, _) = try #require(await h.model.activityState(for: h.project))
        _ = try h.backend.start(info: info, state: LiveActivityState.make(cursor: .start, sequence: try await h.model.projects.sequence(for: h.project))!)
        let seq = try await h.model.projects.sequence(for: h.project)
        _ = h.model.projects.apply(.jump(row: 2), to: h.project, in: seq)  // stored cursor moved while the activity showed row 1
        h.backend.reset()
        await h.model.reconcileActivities()
        #expect(h.backend.calls == [.update("act1", 2, 0)])
    }
}
```
Append to `ios/Tests/ProjectServiceTests.swift`:
```swift
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
```

- [ ] **Step 2: Run to verify failure** → compile errors.

- [ ] **Step 3: Implement**

`ios/Shared/WorkIntents.swift`:
```swift
import AppIntents
import Foundation
import GraphghanCore

/// The app registers this at launch. In the widget process nothing registers it and `perform` is
/// never called there: `LiveActivityIntent`s run in the app.
@MainActor
final class WorkIntentHandler {
    static let shared = WorkIntentHandler()
    var perform: ((WorkAction, UUID) async -> Void)?
}

struct AdvanceRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Done with this run"
    static let description = IntentDescription("Marks the current run done and moves to the next.")
    static let openAppWhenRun = false

    @Parameter(title: "Project") var projectID: String

    init() {}
    init(projectID: UUID) { self.projectID = projectID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: projectID) { await WorkIntentHandler.shared.perform?(.advance, id) }
        return .result()
    }
}

struct BackRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Back one run"
    static let description = IntentDescription("Undoes the last run.")
    static let openAppWhenRun = false

    @Parameter(title: "Project") var projectID: String

    init() {}
    init(projectID: UUID) { self.projectID = projectID.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: projectID) { await WorkIntentHandler.shared.perform?(.back, id) }
        return .result()
    }
}
```
In `ProjectService.swift`: add after `var lastError: String?`:
```swift
    /// Called after every successful step (whether or not the save succeeded): the Live Activity updates from here.
    var onApply: ((Project, WorkSequence, WorkStep) -> Void)?
```
add the method:
```swift
    func project(id: UUID) throws -> Project? {
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
```
and in `apply`, replace `return step` with:
```swift
        onApply?(project, sequence, step)
        return step
```
In `AppModel.swift`: change the stored properties and initializer to:
```swift
    let patterns: PatternStore
    let charts: ChartLibrary
    let projects: ProjectService
    let liveActivity: LiveActivityController

    init(context: ModelContext, patterns: PatternStore, charts: ChartLibrary,
         activityBackend: ActivityBackend = ActivityKitBackend(),
         defaults: UserDefaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard) {
        self.patterns = patterns
        self.charts = charts
        self.projects = ProjectService(context: context, charts: charts, patterns: patterns)
        self.liveActivity = LiveActivityController(backend: activityBackend, defaults: defaults)
        projects.onApply = { [weak self] project, sequence, step in
            guard let self, let chart = self.chartCache[project.chartID] ?? nil else { return }
            let info = LiveActivityState.info(projectID: project.id, chart: chart, sequence: sequence)
            guard let state = LiveActivityState.make(cursor: step.cursor, sequence: sequence) else { return }
            Task { await self.liveActivity.update(projectID: project.id, info: info, state: state) }
        }
        WorkIntentHandler.shared.perform = { [weak self] action, id in await self?.performIntent(action, projectID: id) }
    }

    /// Charts seen this launch, so the synchronous `onApply` hook can build activity info without an await.
    private var chartCache: [String: Chart?] = [:]
```
and add these methods (the `// MARK: live activity` section):
```swift
    // MARK: live activity

    /// The attributes and current state for a project, or nil when its chart cannot be read.
    func activityState(for project: Project) async -> (WorkActivityInfo, WorkActivityState)? {
        guard let chart = try? await projects.chart(for: project), let sequence = try? WorkSequence(chart: chart),
              let state = LiveActivityState.make(cursor: project.cursor, sequence: sequence) else { return nil }
        chartCache[project.chartID] = chart
        return (LiveActivityState.info(projectID: project.id, chart: chart, sequence: sequence), state)
    }

    /// A lock-screen button: same mutation path as the Work screen, then the activity updates via `onApply`.
    func performIntent(_ action: WorkAction, projectID: UUID) async {
        guard let project = try? projects.project(id: projectID) else {
            await endActivityUnavailable(projectID: projectID)
            return
        }
        guard let chart = try? await projects.chart(for: project), let sequence = try? WorkSequence(chart: chart) else {
            await endActivityUnavailable(projectID: projectID)
            return
        }
        chartCache[project.chartID] = chart
        _ = projects.apply(action, to: project, in: sequence)
    }

    private func endActivityUnavailable(projectID: UUID) async {
        await liveActivity.reconcile { [weak self] info in
            guard info.projectID == projectID else {
                // untouched: another project's activity keeps its current state
                guard let self, let p = try? self.projects.project(id: info.projectID) else { return nil }
                return await self.activityState(for: p)?.1
            }
            return nil
        }
    }

    /// Launch-time reconciliation (spec §7): the stored cursor wins; stale activities end.
    func reconcileActivities() async {
        await liveActivity.reconcile { [weak self] info in
            guard let self, let project = try? self.projects.project(id: info.projectID) else { return nil }
            return await self.activityState(for: project)?.1
        }
    }
```
Note `chartCache` is declared as `[String: Chart?]` so `?? nil` flattens the lookup; simpler is `[String: Chart]` with `self.chartCache[project.chartID]` — use the simpler form and adjust the hook to `guard let self, let chart = self.chartCache[project.chartID] else { return }`.

In `GraphghanApp.swift`, add to the `RootView()` modifiers:
```swift
                .task { await model.reconcileActivities() }
```

- [ ] **Step 4: Run the tests** → `mise run test` green (46 tests). If `#Predicate { $0.id == id }` fails to compile against a `UUID` on this SDK, fetch all and filter (`try context.fetch(FetchDescriptor<Project>()).first { $0.id == id }`) and note it.

- [ ] **Step 5: Commit**

```bash
git add ios/Shared/WorkIntents.swift ios/Graphghan ios/Tests
git commit -m "feat(ios): Advance and Back Live Activity intents wired through ProjectService"
```

---

### Task 5: Work screen integration and the Settings hint

**Files:**
- Modify: `ios/Graphghan/Work/WorkView.swift`

**Interfaces:**
- Consumes: `AppModel.liveActivity`, `AppModel.activityState(for:)`, `LiveActivityController.start/end/settingsHint/dismissHint`.
- Behaviour: when the Work screen has loaded chart and sequence, it starts (or adopts) the activity; when it disappears, it ends the activity with the current state; the finished state ends it through `update` (already in the controller). If `settingsHint` is set, a banner shows once with "Open Settings" (via `UIApplication.openSettingsURLString`) and "Dismiss".

- [ ] **Step 1: Implement**

In `WorkView.swift`:
- In the `.task` after `Haptics.prepare()` add:
```swift
                if let (info, state) = await model.activityState(for: project) {
                    await model.liveActivity.start(projectID: project.id, info: info, state: state)
                }
```
- Change `.onDisappear` to:
```swift
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Task {
                let final = sequence.flatMap { LiveActivityState.make(cursor: project.cursor, sequence: $0) }
                await model.liveActivity.end(projectID: project.id, finalState: final)
            }
        }
```
- In `content(...)`, directly under the save-error banner block, add:
```swift
            if let hint = model.liveActivity.settingsHint {
                HStack(spacing: 8) {
                    Text(hint).font(.footnote)
                    Spacer()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url).font(.footnote.bold())
                    }
                    Button("Dismiss") { model.liveActivity.dismissHint() }.font(.footnote)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.blue.opacity(0.15))
            }
```
Because `onApply` updates the activity after every `apply`, `perform` needs no change.

- [ ] **Step 2: Build, test, and check on the simulator**

Run: `cd ios && mise run test` → green (no new tests; the controller and intent tests cover the logic). Then build, install, and launch on the iPhone 17 simulator (`xcrun simctl boot "iPhone 17"; xcodebuild … -destination 'platform=iOS Simulator,name=iPhone 17' build; xcrun simctl install …; xcrun simctl launch …`). If a project exists, open it, tap Work, then lock the simulator (Device › Lock, or `xcrun simctl io "iPhone 17" screenshot` after pressing Cmd-L in the Simulator app): the Live Activity should appear on the lock screen with the placeholder text from Task 2. Screenshot to `ios/build/activity-placeholder.png` if you can; otherwise state that interaction was not possible.

- [ ] **Step 3: Commit**

```bash
git add ios/Graphghan/Work/WorkView.swift
git commit -m "feat(ios): Work screen starts and ends the Live Activity; Settings hint"
```

---

### Task 6: Activity views, widget configuration, and snapshot tests

**Files:**
- Create: `ios/Shared/HexColor.swift`, `ios/Shared/WorkActivityViews.swift`
- Replace: `ios/GraphghanWidgets/WorkLiveActivity.swift`
- Test: `ios/Tests/Snapshots.swift`, `ios/Tests/WorkActivityViewsTests.swift`, recorded references under `ios/Tests/__Snapshots__/`

**Interfaces:**
- Produces: `enum HexColor { static func color(_ hex: String) -> Color; static func isLight(_ hex: String) -> Bool }`; views `WorkLockScreenView(info:state:)`, `WorkCompactLeadingView(info:state:)`, `WorkCompactTrailingView(state:)`, `WorkMinimalView(info:state:)`, `WorkExpandedCenterView(info:state:)`, `WorkExpandedBottomView(info:state:)`; `RunSwatch(info:code:count:size:)`; test helper `Snapshots.assert(_ view: some View, named: String, size: CGSize) throws -> Bool`.

- [ ] **Step 1: Failing tests**

`ios/Tests/Snapshots.swift`:
```swift
import CoreGraphics
import SwiftUI
import Testing
import UIKit

/// Minimal snapshot testing: render with ImageRenderer at 2x, compare to a PNG under
/// Tests/__Snapshots__. A missing reference is recorded and the test fails once, so the file gets
/// committed and reviewed. Rendering is deterministic on one simulator model and OS.
@MainActor
enum Snapshots {
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        return url.appendingPathComponent("__Snapshots__", isDirectory: true)
    }()

    /// Returns true when the rendering matches the reference; records and returns false when no reference exists.
    static func assert(_ view: some View, named name: String, size: CGSize, tolerance: Double = 0.005) throws -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.uiImage, let png = image.pngData() else { throw SnapshotError.renderFailed(name) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let reference = directory.appendingPathComponent("\(name).png")
        guard FileManager.default.fileExists(atPath: reference.path) else {
            try png.write(to: reference)
            Issue.record("Recorded new snapshot \(name).png; re-run to compare.")
            return false
        }
        guard let expected = UIImage(data: try Data(contentsOf: reference))?.cgImage, let actual = image.cgImage else { throw SnapshotError.renderFailed(name) }
        guard expected.width == actual.width, expected.height == actual.height else {
            try png.write(to: directory.appendingPathComponent("\(name).actual.png"))
            Issue.record("\(name): size \(actual.width)x\(actual.height) != \(expected.width)x\(expected.height)")
            return false
        }
        let diff = differingFraction(expected, actual)
        if diff > tolerance {
            try png.write(to: directory.appendingPathComponent("\(name).actual.png"))
            Issue.record("\(name): \(Int(diff * 1000)) per mille of pixels differ (see \(name).actual.png)")
            return false
        }
        return true
    }

    private static func pixels(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private static func differingFraction(_ a: CGImage, _ b: CGImage) -> Double {
        guard let pa = pixels(a), let pb = pixels(b), pa.count == pb.count else { return 1 }
        var differing = 0
        let count = pa.count / 4
        for i in 0..<count {
            let o = i * 4
            if abs(Int(pa[o]) - Int(pb[o])) > 8 || abs(Int(pa[o + 1]) - Int(pb[o + 1])) > 8 || abs(Int(pa[o + 2]) - Int(pb[o + 2])) > 8 { differing += 1 }
        }
        return Double(differing) / Double(max(1, count))
    }

    enum SnapshotError: Error { case renderFailed(String) }
}
```
`ios/Tests/WorkActivityViewsTests.swift`:
```swift
import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct WorkActivityViewsTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let info = LiveActivityState.info(projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, chart: chart, sequence: seq)
    static let midway = LiveActivityState.make(cursor: Cursor(row: 42, run: 3), sequence: seq)!
    static let lastInRow = LiveActivityState.make(cursor: Cursor(row: 1, run: 0), sequence: seq)!
    static let finished = WorkActivityState.unavailable("This project is no longer available.")

    @Test func hexColor() {
        #expect(HexColor.isLight("#F2E8D5") && !HexColor.isLight("#2B2F33"))
    }

    @Test func lockScreenMidway() throws {
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.midway), named: "lock-midway", size: CGSize(width: 360, height: 170)))
    }

    @Test func lockScreenLastInRow() throws {
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.lastInRow), named: "lock-last-in-row", size: CGSize(width: 360, height: 170)))
    }

    @Test func lockScreenUnavailable() throws {
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.finished), named: "lock-unavailable", size: CGSize(width: 360, height: 120)))
    }

    @Test func compactAndMinimal() throws {
        #expect(try Snapshots.assert(WorkCompactLeadingView(info: Self.info, state: Self.midway), named: "compact-leading", size: CGSize(width: 64, height: 36)))
        #expect(try Snapshots.assert(WorkCompactTrailingView(state: Self.midway), named: "compact-trailing", size: CGSize(width: 64, height: 36)))
        #expect(try Snapshots.assert(WorkMinimalView(info: Self.info, state: Self.midway), named: "minimal", size: CGSize(width: 44, height: 36)))
    }

    @Test func expanded() throws {
        #expect(try Snapshots.assert(WorkExpandedCenterView(info: Self.info, state: Self.midway), named: "expanded-center", size: CGSize(width: 340, height: 90)))
        #expect(try Snapshots.assert(WorkExpandedBottomView(info: Self.info, state: Self.midway), named: "expanded-bottom", size: CGSize(width: 340, height: 60)))
    }
}
```

- [ ] **Step 2: Run to verify failure** → compile errors.

- [ ] **Step 3: Implement**

`ios/Shared/HexColor.swift`:
```swift
import SwiftUI

/// `#RRGGBB` → Color, plus the same light/dark rule the PWA uses. Shared so the widget needs no app code.
enum HexColor {
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return (0.53, 0.53, 0.53) }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
    static func color(_ hex: String) -> Color { let c = rgb(hex); return Color(red: c.r, green: c.g, blue: c.b) }
    static func isLight(_ hex: String) -> Bool { let c = rgb(hex); return (c.r * 299 + c.g * 587 + c.b * 114) / 1000 * 255 >= 140 }
}
```
`ios/Shared/WorkActivityViews.swift`:
```swift
import SwiftUI
import GraphghanCore

/// A run as a coloured swatch with its count. `size` is the swatch height.
struct RunSwatch: View {
    let info: WorkActivityInfo
    let code: String
    let count: Int
    var size: CGFloat = 44

    var body: some View {
        let hex = info.swatch(for: code)?.hex ?? "#888888"
        Text("\(count)")
            .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(HexColor.isLight(hex) ? .black : .white)
            .frame(minWidth: size * 1.3, minHeight: size)
            .padding(.horizontal, 6)
            .background(HexColor.color(hex), in: RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityLabel("\(count) \(info.swatch(for: code)?.name ?? code)")
    }
}

/// Lock screen and expanded Dynamic Island content (spec §7).
struct WorkLockScreenView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(info.title).font(.headline).lineLimit(1)
                Spacer()
                if state.message == nil { Text("Row \(state.row) of \(state.rowCount)").font(.subheadline.bold()) }
            }
            if let message = state.message {
                Text(message).font(.subheadline)
            } else if state.finished {
                Text("Finished").font(.title2.bold())
            } else {
                HStack(alignment: .center, spacing: 12) {
                    if let code = state.currentCode, let count = state.currentCount {
                        RunSwatch(info: info, code: code, count: count, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.swatch(for: code)?.name ?? code).font(.title3.bold()).lineLimit(1)
                            Text(nextText).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button(intent: BackRunIntent(projectID: info.projectID)) {
                        Image(systemName: "arrow.uturn.backward").font(.title3).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Back one run")
                    Button(intent: AdvanceRunIntent(projectID: info.projectID)) {
                        Text("Done").font(.title3.bold()).frame(minWidth: 88, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(14)
        .activityBackgroundTint(Color(white: 0.08))
        .foregroundStyle(.white)
    }

    private var nextText: String {
        if let code = state.nextCode, let count = state.nextCount { return "then \(count) \(info.swatch(for: code)?.name ?? code)" }
        return state.isLastInRow ? "last run in this row" : ""
    }
}

struct WorkCompactLeadingView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        if let code = state.currentCode, let count = state.currentCount {
            RunSwatch(info: info, code: code, count: count, size: 24)
        } else {
            Image(systemName: "checkmark.circle.fill")
        }
    }
}

struct WorkCompactTrailingView: View {
    let state: WorkActivityState
    var body: some View {
        Text(state.message == nil ? "R\(state.row)" : "—").font(.caption.bold()).monospacedDigit()
    }
}

struct WorkMinimalView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        if let code = state.currentCode, let count = state.currentCount {
            RunSwatch(info: info, code: code, count: count, size: 22)
        } else {
            Image(systemName: "checkmark.circle.fill")
        }
    }
}

struct WorkExpandedCenterView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        HStack(spacing: 12) {
            if let code = state.currentCode, let count = state.currentCount {
                RunSwatch(info: info, code: code, count: count, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.swatch(for: code)?.name ?? code).font(.headline).lineLimit(1)
                    Text("Row \(state.row) of \(state.rowCount)").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(state.message ?? "Finished").font(.headline)
            }
            Spacer()
        }
    }
}

struct WorkExpandedBottomView: View {
    let info: WorkActivityInfo
    let state: WorkActivityState
    var body: some View {
        if state.message == nil, !state.finished {
            HStack(spacing: 10) {
                Button(intent: BackRunIntent(projectID: info.projectID)) {
                    Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 40)
                }
                .buttonStyle(.bordered)
                Button(intent: AdvanceRunIntent(projectID: info.projectID)) {
                    Text("Done").bold().frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
```
`ios/GraphghanWidgets/WorkLiveActivity.swift` (replace the placeholder):
```swift
import ActivityKit
import SwiftUI
import WidgetKit
import GraphghanCore

struct WorkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkActivityAttributes.self) { context in
            WorkLockScreenView(info: context.attributes.info, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    WorkExpandedCenterView(info: context.attributes.info, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WorkExpandedBottomView(info: context.attributes.info, state: context.state)
                }
            } compactLeading: {
                WorkCompactLeadingView(info: context.attributes.info, state: context.state)
            } compactTrailing: {
                WorkCompactTrailingView(state: context.state)
            } minimal: {
                WorkMinimalView(info: context.attributes.info, state: context.state)
            }
        }
    }
}
```

- [ ] **Step 4: Record the snapshots, then run green**

Run: `cd ios && mise run test` once — the eight snapshot assertions fail with "Recorded new snapshot". Open each PNG under `ios/Tests/__Snapshots__/` (the Read tool shows images) and check: the lock screen shows the title, "Row 42 of 184", a gold or green swatch with the count, the colour name, the "then N <name>" line, and Back plus a larger Done; the last-in-row variant says "last run in this row"; the unavailable variant shows the message and no buttons; compact leading is a small swatch with a count, trailing "R42", minimal a swatch. Run `mise run test` again → all green (55 tests). Commit the PNGs. If `Button(intent:)` refuses to render under `ImageRenderer`, wrap the two buttons in `if !ProcessInfo.processInfo.isSnapshotting` — do NOT do this; instead report it, since the buttons are part of what the snapshot must show.

- [ ] **Step 5: See it live**

Build to the simulator and, with a project open on the Work screen, lock the simulator: the lock screen shows the activity; tapping Done there advances the row when the simulator is unlocked and the Work screen refreshes (the screen mirrors `project.cursor` only on `.task`, so also verify the next tap on the Work screen continues from the new cursor — if the on-screen cursor does not follow the lock-screen tap, add `.onChange(of: project.cursorRow) { _, _ in cursor = project.cursor }` and the same for `cursorRun` in `WorkView`, and record it). On the Dynamic Island simulator (iPhone 17 has one) check compact and expanded. Screenshot to `ios/build/activity-lock.png` and `ios/build/activity-island.png` if you can drive it; otherwise state that.

- [ ] **Step 6: Commit**

```bash
git add ios/Shared ios/GraphghanWidgets ios/Tests
git commit -m "feat(ios): Live Activity lock screen and Dynamic Island views with snapshot tests"
```

---

### Task 7: Docs and QA checklist

**Files:**
- Create: `ios/docs/qa.md`
- Modify: `ios/README.md`, `README.md`

- [ ] **Step 1: QA checklist**

`ios/docs/qa.md`:
```markdown
# Manual QA before a TestFlight build

Run on a real iPhone (Live Activities need the lock screen and Dynamic Island).

## Work screen
- [ ] Open a project, tap Work, complete a full row with Done; the strip moves and the chips reset.
- [ ] Swipe right on the Done area, then on the chips: both step back exactly once.
- [ ] Long-press the row title and jump to row 40.
- [ ] Rotate mid-row; the layout survives and Done stays reachable.

## Live Activity
- [ ] With the Work screen open, lock the phone: the activity shows title, row of total, the current swatch, count, colour name, next run, Back and Done.
- [ ] Tap Done on the lock screen twice, then unlock: the Work screen shows the advanced cursor and the event log has two entries.
- [ ] Tap Back on the lock screen: the cursor steps back.
- [ ] Dynamic Island: compact shows swatch + count and R<row>; long-press shows the expanded card with buttons.
- [ ] Close the Work screen: the activity ends.
- [ ] Finish the last run from the lock screen: the activity ends with "Finished".
- [ ] Kill the app while the activity is showing, then relaunch: the activity is refreshed to the stored cursor (or ended if the project was deleted).
- [ ] Settings › Graphghan › Live Activities off, open Work: the one-time hint appears with Open Settings.

## Offline
- [ ] Airplane mode on the library (cached list + banner) and on a project (works normally).
```

- [ ] **Step 2: README notes**

In `ios/README.md` add a "Live Activity" section: the extension target `GraphghanWidgets`, `Shared/` compiled into both targets, intents run in the app via `WorkIntentHandler`, snapshots under `Tests/__Snapshots__` (delete a PNG to re-record it), and that `NSSupportsLiveActivities` is set in the app's Info.plist by `project.yml`. In the root `README.md` "iOS app" paragraph append one sentence: "The Work screen also drives a Live Activity on the lock screen and Dynamic Island with Done and Back buttons."

- [ ] **Step 3: Final checks and commit**

Run from `ios/`: `mise run core-test && mise run test`; from the repo root: `mise run check`.
```bash
git add ios/docs/qa.md ios/README.md README.md
git commit -m "docs: Live Activity notes and the manual QA checklist"
```

- [ ] **Step 4: Finish the branch**

Push `feat/live-activity` and open a pull request against `main` titled "Live Activity with Done and Back on the lock screen", summarizing Tasks 1–7, noting that CI still does not build iOS (Plan 4), and that device provisioning for the extension needs the App Group on `com.tylervick.graphghan.widgets` (automatic signing adds it on the first device build).

---

## Self-review notes

Spec §7 coverage: iOS 17 minimum (Global Constraints, Task 2 target); one activity at a time, start with Work screen, end on close/finish/system end with restart on next advance, launch reconciliation with stored cursor winning (Task 3 rules + Task 4 `reconcileActivities` + Task 5 hooks); attributes and state fields (Task 1, pure and tested); lock screen and Dynamic Island layouts (Task 6); intents as `LiveActivityIntent` taking a project id, applying through `ProjectService.apply` in the app process, updating via the `onApply` hook, no haptics, missing project or chart → explanatory final state (Task 4); local-only updates, no `AppShortcutsProvider` (nowhere registered). §6.6 hint (Tasks 3, 5). §9: state-builder unit tests (Task 1), controller rules (Task 3), intents called directly incl. stale id (Task 4), snapshots of lock screen, compact, minimal (Task 6), manual checks (Task 7).

Type consistency: `LiveActivityController.start/update/end/reconcile` signatures are used identically in Tasks 4, 5, and the tests; `ActiveActivity` is produced by both backends; `WorkActivityAttributes.info` is read by the widget; `WorkIntentHandler.shared.perform` is set in `AppModel.init` and read by both intents; `AppModel.init`'s two new parameters have defaults so Plan 2 call sites (`AppModel.live`, `AppModelTests`) compile unchanged.

Known simplification: `chartCache` in `AppModel` exists only so the synchronous `onApply` hook can build activity info without awaiting the chart actor; it is populated by `activityState(for:)` (Work screen open) and `performIntent`, which are the only two paths that lead to `apply` while an activity is live.

# App Intents Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Done and Back by voice and by the Action Button on every device the app supports: two discoverable `AppIntent`s that resolve the project being worked, one `AppShortcutsProvider`, and a spoken reply that says where the cursor landed. Both routes into `WorkIntentHandler` survive a background launch.

**Architecture:** Three layers. First the gate: `WorkIntentHandler` learns to wait for the app's registration instead of no-op'ing when it is nil, pinned by a test that performs an intent against a cold model. Then the app side: `AppModel` resolves the working project by spec §3.2 and applies through `ProjectService.apply` exactly as the lock-screen button does, returning a `WorkIntentOutcome`. Last the surface: `MarkDoneIntent`, `UndoDoneIntent`, `GraphghanShortcuts` and a pure `WorkIntentDialog` that turns an outcome into words. No intent touches a cursor; `WorkEngine` stays the one place cursor movement is defined.

**Tech Stack:** Swift 6, strict concurrency, App Intents on the iOS 17.0 floor (nothing `@available`-gated in this phase), Swift Testing with the in-memory SwiftData harness and `RecordingBackend`. The SDK ships no `AppIntentsTesting` framework; intents are tested by calling `perform()` directly, as `WorkIntentTests` already does.

**Spec:** `docs/superpowers/specs/2026-09-18-ios-app-intents-design.md` §3 (phase 1). Issue #8.

## Global Constraints

- Deployment target stays iOS 17.0 (`project.yml`). Nothing in this phase needs a newer symbol.
- `AdvanceRunIntent` and `BackRunIntent` keep `isDiscoverable = false` and their `String` project parameter (spec §3.1). Their only change is to wait for registration like the new pair.
- The new intents and the provider compile into the app target only (`Graphghan/Intents/`), not `Shared/`. `Shared/` also compiles into the widget extension, and a plain `AppIntent` declared in an extension's metadata runs in that extension, where nothing is registered. `LiveActivityIntent`s are pinned to the app by the system; plain intents are not. The spec says "beside the existing pair in `Shared/WorkIntents.swift`"; the handler and the outcome type do live there, the intents move one directory over, and §3.1 gets a sentence saying why.
- One spoken Done is one tapped Done: `ProjectService.apply(.advance, ...)` with the project's own `step` and `tapPerRepetition`, the same call `WorkView.perform` makes.
- Cursor movement is asserted through the `ProgressEvent` log (`ProjectService.events(for:)`), never through an intent's return value.
- Every phrase carries `\(.applicationName)`.
- Heather tokens and `DesignRulesTests` are untouched: this phase draws nothing.
- Conventional-commit subjects in the repo's style (`intents:`, `docs:`), one commit per task, the session's `Co-Authored-By` trailer on each.
- Baseline before starting: `cd ios && mise run core-test && mise run test` green on a clean checkout.

## File map

| file | responsibility |
|---|---|
| `ios/Shared/WorkIntents.swift` | `WorkIntentHandler` gains a second registration slot and `awaitRegistration(timeout:)`; `WorkIntentOutcome`; the two Live Activity intents wait instead of no-op |
| `ios/Graphghan/Intents/WorkShortcuts.swift` (new) | `MarkDoneIntent`, `UndoDoneIntent`, `GraphghanShortcuts` |
| `ios/Graphghan/Intents/WorkIntentDialog.swift` (new) | pure outcome → words (spec §3.4) |
| `ios/Graphghan/AppModel.swift` | `workingProjectForIntent()` (spec §3.2), `performIntent(_:)` on the working project, shared step path with the lock-screen button; `registerIntentHandler` registers both slots |
| `ios/Graphghan/Services/LiveActivityController.swift` | `liveProjectID`: the current activity's project, falling back to what the system still shows after a background launch |
| `ios/Tests/WorkIntentTests.swift` | the cold-registration pin |
| `ios/Tests/WorkShortcutsTests.swift` (new) | spec §3.5: event-log movement, the three target rules, Done then Back |
| `ios/Tests/WorkIntentDialogTests.swift` (new) | every dialog case, including inside a fill |
| `ios/README.md`, `ios/docs/qa.md` | the App Intents surface described the way the Live Activity is; a manual Siri check |
| `docs/superpowers/specs/2026-09-18-ios-app-intents-design.md` | §3.1 file placement note; §3.4 the turn wording against the boundary step |

---

## Part A: the gate (spec §3.1, do first)

### Task 1: pin the cold-registration case

- [ ] In `WorkIntentTests`, add `coldHandlerStillAppliesTheDone`: clear both slots on `WorkIntentHandler.shared`, start `AdvanceRunIntent(projectID:).perform()` in a `Task`, register the model after a short sleep, await the task, assert one `.advance` event.
- [ ] Add `unregisteredHandlerGivesUp`: with both slots nil and a short timeout, `awaitRegistration` returns false and the intent leaves the log empty rather than hanging.
- [ ] Run `mise run test`: the first test fails against today's `perform?` no-op.

### Task 2: the handler waits

- [ ] `WorkIntentHandler`: `perform` and `performOnWorkingProject` slots; `isRegistered`; `awaitRegistration(timeout: Duration = .seconds(5)) async -> Bool` polls every 25 ms on the main actor until registered or the deadline.
- [ ] `AdvanceRunIntent`/`BackRunIntent` call `awaitRegistration()` before the slot. Nothing else about them changes.
- [ ] Tests green. Commit `intents: wait for the app's registration instead of dropping a cold-launch tap`.

## Part B: the app side (spec §3.2)

### Task 3: which project

- [ ] `LiveActivityController.liveProjectID: UUID?` = `currentProjectID ?? backend.active().first?.info.projectID`.
- [ ] `AppModel.workingProjectForIntent() throws -> Project?`: rule 1 the live activity's project if it exists and is unfinished; rule 2 the unfinished project with the greatest `lastWorked ?? started`; rule 3 nil.
- [ ] `WorkIntentOutcome` in `Shared/WorkIntents.swift`: `.noProject`, `.chartUnavailable(title:)`, `.nowhereToGo(WorkAction)`, `.moved(WorkStep, in: WorkSequence)`.
- [ ] `AppModel.performIntent(_ action: WorkAction) async -> WorkIntentOutcome` resolves, adopts a live activity the controller does not know (same as the button path), applies, awaits the activity refresh. Factor the adopt-and-apply tail out of the existing `performIntent(_:projectID:)` so both share it.
- [ ] `registerIntentHandler` sets both slots.
- [ ] Tests in `WorkShortcutsTests` for the three rules, through `AppModel.performIntent(_:)` and the event log. Commit `intents: the working project, resolved the way the spec says`.

## Part C: the surface (spec §3.3, §3.4)

### Task 4: the dialog

- [ ] `WorkIntentDialog.text(for:) -> Text(full:supporting:)` and `dialog(for:) -> IntentDialog`. Cases: no project; chart unavailable; nowhere to go for Done and for Back; finished; boundary ("End of row 47. Turn."); inside a fill ("Row 47, run 3, eight left in it." / "Row 47, run 3"); a new run or row ("Row 47, run 4 of 9."). Runs are 1-based in words. Counts to twenty are spelled out.
- [ ] `WorkIntentDialogTests` build passes by hand (a twenty-cell fill needs no fixture). Commit `intents: what Siri says back`.

### Task 5: the intents and the provider

- [ ] `MarkDoneIntent` and `UndoDoneIntent`: plain `AppIntent`, `openAppWhenRun = false`, spec §3.1 title and description, `@MainActor perform()` → `awaitRegistration`, the slot, `WorkIntentDialog.dialog(for:)`. On a registration timeout, throw `WorkIntentError.appNotReady`, a `CustomLocalizedStringResourceConvertible`.
- [ ] `GraphghanShortcuts: AppShortcutsProvider` with the §3.3 phrases, `shortTitle` "Done" / "Back", `systemImageName` `checkmark` / `arrow.uturn.backward`.
- [ ] `WorkShortcutsTests`: `MarkDoneIntent().perform()` writes one `.advance` event; Done then Back returns to `.start` with `[.advance, .back]` in the log; the no-project dialog leaves the store untouched; the cold case through `MarkDoneIntent`.
- [ ] Commit `intents: Done and Back for Siri, Shortcuts and the Action Button (#8)`.

## Part D: docs and ship

### Task 6: docs

- [ ] `ios/README.md`: an "App Intents" section after Live Activity: the two discoverable intents, the phrases, where resolution and the reply live, that the provider is app-target-only and why.
- [ ] `ios/docs/qa.md`: a "Siri and the Action Button" section: with the app killed, "Done in Graphghan" advances the project with the live activity; with no activity, the most recently worked one; Action Button bound to Done counts one step.
- [ ] Spec §3.1 and §3.4 amendments (see Global Constraints and Task 4).
- [ ] `cd ios && mise run core-test && mise run test`; `cd .. && mise run check`. Commit `docs: the App Intents surface in the README and QA (#8)`.
- [ ] PR: "Part of #8", says what Task 1 found, lists the two spec amendments as questions for review.

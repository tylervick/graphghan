# App Intents Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A project modelled as an `AppEntity` and indexed for Spotlight, so Siri can answer "how far am I on the Craigh na Dun blanket" with the app closed; an optional project parameter on Done and Back that asks which blanket when the working project is ambiguous; and a snippet that shows the band a Done landed on.

**Architecture:** `ProjectEntity` is a projection: `AppModel.projectSnapshots()` reads every project through `ProjectService`, computes percent from the cursor the way the Live Activity does (no event walk, so #79's assertion never trips), and the entity, its query and the Spotlight indexer all read that one list through a third `WorkIntentHandler` slot. The phase 1 outcome grows a landing (step, sequence, chart, count step, tap unit) so one value feeds both the sentence and the snippet, and an `ambiguous` case that the intent answers with `requestDisambiguation`. The snippet is `WorkPanel` over `ChartBand`, the Work screen's own components, with inert callbacks. Index refresh hangs off a `ProjectService.onProjectsChanged` hook that every create, finish, unfinish, chart switch and delete fires.

**Tech Stack:** Swift 6, App Intents, CoreSpotlight, SwiftUI; Swift Testing with the in-memory SwiftData harness and the phase 1 intent suite; the snapshot harness for the snippet.

**Spec:** `docs/superpowers/specs/2026-09-18-ios-app-intents-design.md` §4. Builds on the phase 1 plan and PR #102. Closes #8.

## Global Constraints

- Deployment target stays iOS 17.0.
- **Availability is set by the SDK, not by the doc's "iOS 27" heading.** In the iOS 27 SDK: `AppEntity`, `EntityStringQuery`, `requestDisambiguation` and `ShowsSnippetView` are iOS 16; `IndexedEntity` and `CSSearchableIndex.indexAppEntities` are iOS 18; only `IndexedEntityQuery` is iOS 27, and it is not needed. Swift forbids `@available` on a stored property, so the optional `@Parameter var project: ProjectEntity?` on the phase 1 intents cannot be gated at all, which pins `ProjectEntity` itself to the floor. So: the entity, the parameter, the question and the snippet are ungated; the `IndexedEntity` conformance and the indexer are `@available(iOS 18, *)`. Nothing that needs iOS 27 is left ungated (decision 7 holds); §4 of the spec is amended to say where the gates sit and why, and the PR flags it as a decision for review. Raising the Spotlight gate to 27 is a one-token change.
- There is no `@AppEntity` macro without a schema in this SDK; the entity is a plain conformance.
- `RunChipsView`/`RowStripView` (spec §4.4) were deleted by the Work-on-the-chart plan; the Work screen's components are `WorkPanel` and `ChartBand`, and the snippet reuses those.
- No new storage, no network. The entity carries what `Project` and the chart already know; the pattern title comes from the cached manifest, else the pattern id.
- Every mutation and every index refresh goes through `ProjectService`; the app has no rename path today, so "rename" in §4.2 has nothing to hook until one exists.
- The phase 1 tests run unchanged.
- DesignRulesTests: the snippet view uses only Heather tokens and `YarnSurface`.
- Commit subjects `intents:`, `docs:`; the session's `Co-Authored-By` trailer.

## File map

| file | responsibility |
|---|---|
| `ios/Shared/WorkIntents.swift` | `ProjectSnapshot`; `WorkIntentLanding`; `WorkIntentOutcome.ambiguous`; `performWorking` takes a chosen id; `projectSnapshots` slot |
| `ios/Graphghan/Intents/ProjectEntity.swift` (new) | `ProjectEntity: AppEntity`, `ProjectEntityQuery: EntityStringQuery`, `@available(iOS 18) extension ProjectEntity: IndexedEntity`, `ProjectIndexer` |
| `ios/Graphghan/Intents/WorkSnippetView.swift` (new) | panel over band for a landing |
| `ios/Graphghan/Intents/WorkShortcuts.swift` | the optional parameter; the question; `.result(dialog:view:)` |
| `ios/Graphghan/Intents/WorkIntentDialog.swift` | the ambiguous case; the question's wording |
| `ios/Graphghan/AppModel.swift` | `performIntent(_:chosen:)`, ambiguity in resolution, `projectSnapshots()`, index refresh scheduling with a test seam |
| `ios/Graphghan/Services/ProjectService.swift` | `onProjectsChanged` fired by start, finish, unfinish, switch, delete |
| `ios/Graphghan/GraphghanApp.swift` | reindex at launch |
| `ios/Tests/WorkShortcutsTests.swift`, `ProjectEntityTests.swift` (new), `WorkIntentDialogTests.swift`, `ComponentSnapshotTests.swift` | §4.5 |
| `ios/README.md`, `ios/docs/qa.md`, the spec | docs; the §4.5 phrase-competition QA step |

---

## Part A: the projection

### Task 1: snapshots and the landing

- [ ] `ProjectSnapshot: Sendable, Equatable` (id, title, patternTitle, percent, lastWorked, isFinished) and `WorkIntentLanding` in `Shared/WorkIntents.swift`; `.moved(WorkIntentLanding)`, `.ambiguous([ProjectSnapshot])`; `performWorking: ((WorkAction, UUID?) async -> WorkIntentOutcome)?`; `projectSnapshots: (() async -> [ProjectSnapshot])?`; `isRegistered` covers all three.
- [ ] `AppModel.projectSnapshots()`: every project, percent from `sequence.cellsBefore(cursor)` over `totalCells` rounded to a tenth, pattern title from `patterns.cachedManifest(for:)`.
- [ ] `AppModel.performIntent(_:chosen:)`: a chosen id wins; else §3.2, and when rule 2's top two unfinished projects were worked within an hour of each other, `.ambiguous` with every project inside that hour, most recent first.
- [ ] Dialog and phase 1 tests updated for the landing. Commit `intents: a project as data -- snapshots, and the working project can be ambiguous`.

## Part B: the entity

### Task 2: `ProjectEntity` and its query

- [ ] `ProjectEntity` (id, title, patternTitle, percent, lastWorked as `@Property`), `typeDisplayRepresentation` "Project", `displayRepresentation` title with "43% · Craigh na Dun Blanket" subtitle, `init(_ snapshot:)`.
- [ ] `ProjectEntityQuery: EntityStringQuery`: `entities(for:)`, `suggestedEntities()` (unfinished, most recent first), `entities(matching:)` case-insensitive on title or pattern title; all after `awaitRegistration`.
- [ ] `@available(iOS 18, *) extension ProjectEntity: IndexedEntity` with an `attributeSet` naming the pattern; `ProjectIndexer.refresh(_:)` deletes every `ProjectEntity` then indexes the list.
- [ ] `ProjectEntityTests`: resolution by title, by a title that differs from the pattern's, by id; suggested order; finished projects still resolve by name. Commit `intents: ProjectEntity, resolved by title and indexed for Spotlight`.

### Task 3: refresh

- [ ] `ProjectService.onProjectsChanged: (() -> Void)?` fired at the end of `startProject`, `markFinished`, `markUnfinished`, `switchChart`, `delete`.
- [ ] `AppModel.reindex: (([ProjectSnapshot]) async -> Void)` defaulting to `ProjectIndexer.refresh` under `#available(iOS 18, *)`; `scheduleReindex()` stores its `Task` (`indexUpdate`) so tests await it; `GraphghanApp` schedules one at launch.
- [ ] Tests: create, finish and delete each cause one reindex with the right ids; a tap does not. Commit `intents: the Spotlight index follows every project mutation`.

## Part C: the intents

### Task 4: the parameter and the question

- [ ] `@Parameter(title: "Project") var project: ProjectEntity?` on both intents; `perform` passes `project?.id`; on `.ambiguous`, `project = try await $project.requestDisambiguation(among:dialog:)` with "Which blanket — Craigh na Dun or Baby Blanket?", then performs again with the answer.
- [ ] Tests: two same-hour projects → `.ambiguous` naming both, most recent first; one project → no question; a live activity → no question even with two same-hour projects; a chosen id wins over rule 1. Commit `intents: Done and Back take an optional project, and ask when the working one is ambiguous`.

### Task 5: the snippet

- [ ] `WorkSnippetView(landing:)`: `WorkPanel(content:)` from `WorkPanelContent.make`, `ChartBand` below at a fixed height with inert callbacks; `.result(dialog:view:)` from both intents on `.moved`; dialog-only otherwise.
- [ ] A snapshot `work-snippet` in `ComponentSnapshotTests`. Commit `intents: the snippet shows the band the Done landed on`.

## Part D: docs and ship

### Task 6: docs

- [ ] README "App Intents": the entity, Spotlight, the question, the snippet, where the gates sit.
- [ ] `ios/docs/qa.md`: §4.5's phrase competition (a timer running; "done", "next row", "undo"; "how far am I on …"; Spotlight search for a project; the question with two fresh projects; the snippet on a phone) -- on device, flagged for Tyler.
- [ ] Spec §4: availability floors, the macro, the view names, the disambiguation call, the rename note.
- [ ] `cd ios && mise run core-test && mise run test`; `mise run check`. Commit `docs: the Siri AI layer in the README, QA and the spec (#8)`.
- [ ] PR on top of the phase 1 branch: "Closes #8", the gate decision up top, what is unverified.

# Graphghan for iOS: App Intents, Siri, and the Action Button

Date: 2026-09-18
Status: draft (spec for #8)
Builds on: `2026-09-10-graphghan-ios-app-design.md` §3 — this is the follow-on it named
Evidence: WWDC26 [session 240](https://developer.apple.com/videos/play/wwdc2026/240/) (App Schemas),
[session 343](https://developer.apple.com/videos/play/wwdc2026/343/) (advanced App Intents);
[Apple, 2026-09-14](https://www.apple.com/newsroom/2026/09/siri-ai-a-profoundly-more-capable-and-personal-assistant-is-here/)
Closes the design step for: #8

## 1. Purpose

Both hands are holding yarn. That is the whole argument for this feature, and it is a better
argument than most apps have for voice: the phone is propped against the couch, the maker is mid
colour change, and the one thing they need is to say "done" and have the cursor move.

Two App Intents already exist. `Shared/WorkIntents.swift` defines `AdvanceRunIntent` and
`BackRunIntent` as `LiveActivityIntent`s, both with `isDiscoverable = false`, both routed through
`WorkIntentHandler.shared.perform` (registered in `AppModel.live`, `AppModel.swift:58`) into
`ProjectService.apply`, which is the only path that moves a cursor (`WorkEngine` — "the one place
cursor movement is defined"). They are deliberately walled off to the lock screen and the Dynamic
Island, because the Shortcuts surface was left unbuilt. #8 asks for the wall to come down.

What changed since #8 was written is that the wall is no longer the only thing in the way. iOS 27
made App Intents the sole route to Siri, and gave Siri three capabilities that a bare
`AppShortcutsProvider` does not reach: reading app content modelled as `AppEntity`, choosing an
intent agentically from its own metadata rather than from a fixed phrase, and resolving onscreen
references. So this doc does what #8 asked for and then says, separately and behind an availability
gate, what the iOS 27 layer on top of it is.

The split matters because the two halves have very different reach. Phase 1 runs on every device
the app supports (iOS 17.0). Phase 2 needs Apple Intelligence: iPhone 15 Pro or later, English
only, and not in the EU at launch. Building phase 2 first would ship a feature most of the app's
users cannot run.

## 2. Decisions

1. **The Live Activity intents stay as they are.** `AdvanceRunIntent` and `BackRunIntent` keep
   their `String` project parameter, keep `isDiscoverable = false`, and keep serving the lock-screen
   and island buttons. They are not the Siri surface (§3.1).
2. **The Siri surface is two new plain `AppIntent`s**, `MarkDoneIntent` and `UndoDoneIntent`,
   discoverable, with no required parameter in phase 1.
3. **Both routes funnel into `WorkIntentHandler`**, and therefore into `ProjectService.apply` and
   `WorkEngine`. No intent gets its own cursor arithmetic.
4. **One spoken Done is one tapped Done**, which is `Project.step` (a `CountStep`, ten cells by
   default) or the rest of the run when the project is set to `wholeRun` — not one run and not one
   stitch. Voice must not quietly mean something different from the button.
5. **Voice acts on the project you are working**, resolved by the rule in §3.2, not on a project
   named in the phrase. Naming a blanket out loud is the friction this feature exists to remove.
6. **Done and Back take no confirmation.** Both are cheap and each undoes the other. Anything
   lossy — finishing a project, jumping the cursor — stays out (§6).
7. **Everything iOS 27 gates behind `@available`,** and the app's deployment target stays 17.0.
   A device without Apple Intelligence loses phase 2 and keeps a working phase 1.

## 3. Phase 1: Done and Back by voice and by button (normative)

Runs on iOS 17.0+. No Apple Intelligence.

### 3.1 Why new intent types rather than flipping the flag

Flipping `isDiscoverable` on the existing types would put them in Shortcuts and Spotlight with
their `projectID` parameter exposed as a bare UUID string — a field no person can fill in. The
parameter exists because a Live Activity button knows its project and a widget process cannot
query for one.

The two audiences want opposite parameters: the button knows the project and needs no resolution,
the voice request knows no project and must resolve one. One type cannot be both without carrying a
parameter that is wrong for whichever caller it is not serving. Two types, one handler.

`MarkDoneIntent` and `UndoDoneIntent` are therefore plain `AppIntent`s with
`openAppWhenRun = false`. They share `WorkIntentHandler` with the existing pair but compile into the
app target only (`Graphghan/Intents/`), not `Shared/`: `Shared/` also builds into the widget
extension, and a plain intent an extension declares runs in that extension, where nothing has
registered the handler. The lock-screen pair is safe in `Shared/` because the system runs a
`LiveActivityIntent` in the app.

```swift
struct MarkDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark the next stitches done"
    static let description = IntentDescription(
        "Counts one Done in the crochet chart you are working — the project's count step, or the "
        + "rest of the run — and moves the cursor, exactly as the Done button does.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog { … }
}
```

The title and description are not decoration. Under iOS 27 Siri chooses an intent from its
metadata, and "done" and "back" are two of the most contested verbs on the system — timers, alarms
and reminders all want them. Specific, crochet-shaped wording is the only lever we have in that
contest, and §4.5 tests it rather than assuming it.

**Implementation risk to resolve first:** `WorkIntentHandler.shared.perform` is registered by
`AppModel.live` at app launch. A Siri invocation with the app not running launches the app process
in the background, and the intent must not `perform` before that registration has happened. The
existing lock-screen path has the same shape and works, but it works from a state where the app was
recently foregrounded. Phase 1 starts by pinning this with a test that performs the intent against
a cold model, and if the ordering is not already guaranteed, the fix is for the intent to await the
handler rather than to no-op when it is nil (today's code silently does nothing on `perform?`).

### 3.2 Which project

In order:

1. The project whose Live Activity is currently running, if one is (`LiveActivityController` keeps
   exactly one live at a time).
2. Otherwise the unfinished project with the most recent `lastWorked`.
3. Otherwise none: the intent returns dialog "You don't have a project going" and changes nothing.

Rule 1 is the case that matters — a maker with a Live Activity up is, by definition, working that
blanket right now. Rule 2 covers the maker who never opened the Work screen this session. A
finished project is never a target; `Project.isFinished` excludes it.

### 3.3 Phrases and the Action Button

One `AppShortcutsProvider` with two shortcuts. Every phrase carries `\(.applicationName)`, which
App Intents requires and which also buys us the disambiguation §3.1 worries about:

| Intent | Phrases |
|---|---|
| `MarkDoneIntent` | "Done in \(.applicationName)", "Next in \(.applicationName)", "Mark a done in \(.applicationName)" |
| `UndoDoneIntent` | "Back in \(.applicationName)", "Undo that in \(.applicationName)" |

The phrases say "done" and "back" because that is what the buttons say and what a maker already
thinks; decision 4 is what keeps those words meaning the same thing in both places.

`shortTitle` and `systemImageName` are what the Action Button picker shows, so `MarkDoneIntent`
gets "Done" and a checkmark. Binding the Action Button is the user's job in Settings; the app's
only obligation is to offer a shortcut worth binding, and Done is plainly it. Nothing in the app
needs an Action Button API.

### 3.4 What Siri says back

Both intents return `ProvidesDialog`. The reply names where the cursor landed, because a maker who
cannot see the screen has no other confirmation that the count moved:

- Advanced inside a run: `IntentDialog(full: "Row 47, run 3, eight left in it.", supporting: "Row 47, run 3")`
- Landed on a new run: "Row 47, run 4 of 9."
- The row is worked and the turn is the next step (`WorkStep.atBoundary`): "End of row 47. Turn."
  The turn is said here, not on the row that follows: in flat work the turn is itself a step, so
  by the time `WorkStep.startedNewRow` is true the maker has turned, and a new row reads as a new
  run -- "Row 48, run 1 of 9."
- Finished the chart (`WorkStep.finished`): "That's the last one. The blanket is done."
- Nowhere to go — `ProjectService.apply` returns `nil`, which is how Back at the very start and
  Done past the end both present: "You're at the beginning" / "You've already finished this one."

The stitch component of `Cursor` is why the first two differ: with a count step of ten inside a
twenty-stitch fill, one Done leaves the maker in the middle of a run, and a reply that said "run 3"
twice in a row would read as a Done that did not register.

The `full`/`supporting` split exists so the spoken form can be a sentence while the glanceable form
stays short. Reading out the *next* run's colour and count — "twelve moss, then eight heather" —
is #7 and is not phase 1.

### 3.5 Tests

The existing harness (Swift Testing, in-memory SwiftData, stub HTTP client) covers the service;
what is new is intent-level testing with `AppIntentsTesting`:

- Performing `MarkDoneIntent` moves the cursor through `ProjectService.apply` — asserted by the
  `ProgressEvent` log, not by the intent's return value.
- Target selection: each of §3.2's three rules, including the no-project dialog.
- Done then Back returns to the starting cursor, and the event log shows both.
- The cold-registration case in §3.1.

## 4. Phase 2: the Siri AI layer (`@available`-gated where the SDK gates it)

The Siri that reads app content is iOS 27 and Apple Intelligence hardware, but the API this layer
is built from is older, and the gates sit where the iOS 27 SDK puts them, not at 27 across the
board: `AppEntity`, `EntityStringQuery`, `requestDisambiguation` and `ShowsSnippetView` are iOS 16,
`IndexedEntity` and `CSSearchableIndex.indexAppEntities` are iOS 18, and the only iOS 27 symbol in
the area (`IndexedEntityQuery`) is not needed. Swift also forbids `@available` on a stored property,
so the optional `@Parameter var project: ProjectEntity?` on the phase 1 intents (§4.3) cannot be
gated, which pins `ProjectEntity` itself to the app's floor. Decision 7 still holds -- nothing that
needs iOS 27 is ungated -- and a device without Apple Intelligence keeps Spotlight (iOS 18+), the
question and the snippet, and loses only the Siri that reads.

### 4.1 `ProjectEntity`

```swift
struct ProjectEntity: AppEntity {                 // no `@AppEntity` macro without an app schema
    var id: UUID
    @Property(title: "Title") var title: String
    @Property(title: "Pattern") var patternTitle: String
    @Property(title: "Percent done") var percent: Double
    @Property(title: "Last worked") var lastWorked: Date?
    var displayRepresentation: DisplayRepresentation { … }
}
@available(iOS 18, *) extension ProjectEntity: IndexedEntity { … }
```

Every field already exists. `Project` carries `title`, `patternID`, `cursor`, `lastWorked` and
`finished`; `percent` is computed from the cursor the way the Live Activity computes it
(`WorkSequence.cellsBefore` over `totalCells`), not through `ProjectService.summary(for:sequence:)`,
which walks the event log and may never run for the project being worked (#79). The pattern title
comes from the cached manifest, else the pattern id. No new storage, no network: the entity is a
projection of the SwiftData store (`AppModel.projectSnapshots`), reached through a third
`WorkIntentHandler` slot after the same registration wait as the intents.

No app schema fits. The domains Apple ships are messages, mail, photos, documents, media and the
like; there is no crafts or counter domain, and Apple's guidance is explicit that a plain
`AppIntent` reaches the same Siri and Spotlight surfaces. We adopt `.system.searchInApp` where it
fits (#98) and nothing else.

`OwnershipProvidingEntity` is not adopted. A project is local and private to one person; there is
no sharing for Siri to be careful about until #14 or #15 exists.

### 4.2 Resolution

`IndexedEntity` with `CSSearchableIndex.indexAppEntities`, refreshed when a project is created,
finished or unfinished (by hand or by the last Done), switched to a new chart, or deleted — every one
of those already goes through `ProjectService`, which fires `onProjectsChanged`, so the index has
exactly one place to be kept honest; the app also refreshes once at launch, and a step upserts the
one project that moved, since Spotlight shows its percent. Index work runs in the order it was
asked for, and a full refresh that has been superseded is skipped. The app has no rename
path today; when one exists it goes through the same hook. A project count in the tens makes an
`IntentValueQuery` unnecessary; #98's patterns are the larger set. Resolution by name is an
`EntityStringQuery` matching the project's own title or its pattern's.

This is what makes "how far am I on the Craigh na Dun blanket?" answerable with the app closed,
which is the single most valuable thing phase 2 adds.

### 4.3 The optional parameter, and a question when it is ambiguous

Both phase 1 intents gain, under `@available`, an optional project parameter:

```swift
@Parameter(title: "Project") var project: ProjectEntity?
```

Absent, §3.2 still decides. Present, it wins. When §3.2's rule 2 has to choose between two
unfinished projects worked within the same hour, the intent asks rather than guessing:

```swift
project = try await $project.requestDisambiguation(among: candidates, dialog: "Which blanket — Craigh na Dun or Baby Blanket?")
```

`requestDisambiguation(among:)` rather than `requestValue`, because the app knows exactly which
projects are in question and offers those, most recent first, instead of the whole list.

A wrong guess writes a `ProgressEvent` into the wrong project's history, which is worse than a
question.

### 4.4 A snippet

`ShowsSnippetView` returning the Work screen's own `WorkPanel` over `ChartBand` (the chip and
strip views this section first named were replaced by those in the Work-on-the-chart plan), so a
Done said to a HomePod-shaped surface answers in words and a Done said to a phone in front of you
also shows the band. The snippet is the same view the Work screen draws, with the band's gestures
inert; it needed no new shaping.

### 4.5 Tests

- Entity resolution by title, including a title that differs from the pattern's title.
- The disambiguation question fires for two same-hour projects and not for one.
- Availability: the phase 1 tests run unchanged with the phase 2 symbols compiled out.
- A phrase-competition check — perform the intents through Siri on device against "done", "next
  row", "undo" with a timer running — recorded in `ios/docs/` as a QA step, not as an automated
  test, because the model's choice is not ours to assert.

## 5. Deferred, with issues

Onscreen awareness for "this" (#97). Patterns in Spotlight and `.system.searchInApp` (#98).
Donating milestones (#99). A count parameter — "mark five runs done" — is #23's territory and
should be designed there, with the boundary question (what happens when the count overruns the row)
answered once for both the tap and the voice path. Spoken readout of the next run is #7. Apple
Watch is #9, hardware keys are #10, and #68 is the umbrella the three of them sit under.

## 6. Non-goals

Not in either phase: finishing or deleting a project by voice; jumping the cursor by voice
(`WorkAction.jump` stays a screen gesture, #73); starting a project by voice; voice as the primary
counting path — a Siri round trip per stitch is slower than a tap and this feature is for the
moments when tapping is impossible, not for replacing it; any SiriKit type; any change to the
chart format, the pattern feed, or the Python side; Foundation Models, which fits the app poorly
while the patterns are validated deterministic data — the one plausible use, checking a photo of
the work against a row, belongs with #15 rather than here.

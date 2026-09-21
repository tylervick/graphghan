# Graphghan for iOS

SwiftUI app for working graphghan patterns published at https://graphghan.milo.cat/. The
`Packages/GraphghanCore` package reads the chart format (`../docs/chart-format.md`) and is tested
against `../fixtures/chart-format`.

    cd ios
    mise install            # xcodegen
    mise run generate       # Graphghan.xcodeproj (gitignored)
    mise run core-test      # swift test, macOS host
    mise run test           # app unit tests on the iPhone 17 simulator
    open Graphghan.xcodeproj

Bundle id `com.tylervick.graphghan`, App Group `group.com.tylervick.graphghan`, iOS 17.0+.

## Layout

- `Graphghan/` — the app
  - `Storage/` — App Group paths, the two SwiftData models (`Project`, `ProgressEvent`),
    `ChartLibrary` (the chart files) and `LocalPatternStore` (patterns opened from a file)
  - `Network/` — HTTP client and response handling
  - `Services/` — `ProjectService`, through which every project mutation goes, and
    `BundleImporter`, through which an opened `.graphghan` file goes
  - `Patterns/` — Patterns tab with pattern browser and chart detail
  - `Projects/` — Projects tab with project list and detail
  - `Work/` — full-screen Work screen
  - `UI/` — shared components (card, chip, banner, button styles), the type ramp (`Typography.swift`), preview images
- `Shared/` — compiles into the app and the widget: the color tokens (`Tokens.xcassets`, `Theme.swift`), yarn surfaces, Live Activity views and intents
- `Fonts/` — Literata, Atkinson Hyperlegible, Nunito (all OFL), registered in `project.yml`
- `Scripts/make_icon.py` — the app icon; `mise run icon` regenerates it
- `Packages/GraphghanCore/` — Swift reader for the chart format (JSON decoder, engine) and for
  `.graphghan` bundles (`ZipArchive`, `PatternBundle`)
- `Tests/` — app unit tests (Swift Testing, in-memory SwiftData, stub HTTP client)

## Data

Everything lives in the App Group container (`group.com.tylervick.graphghan`):

- SwiftData store at `Library/Application Support/graphghan.store`, chart files at
  `Library/Application Support/charts/<chart id>.json` (never evicted while a project uses one)
- Pattern cache under `Library/Caches/patterns/<id>/`: the library index, manifests, previews and
  their ETags
- Patterns opened from a file at `Library/Application Support/local-patterns/<id>/`: the manifest
  and previews. Application Support rather than the cache beside the site's, because iOS purges
  Caches under disk pressure — free for a site pattern, data loss for the only copy of one someone
  sent (#16)

## Opening a .graphghan bundle

A `.graphghan` file (the format is `../docs/chart-format.md` §Bundle) opened from Files, Mail or
AirDrop becomes a pattern in the Patterns tab, under **On this iPhone**, with a project startable
from it exactly as from a site pattern. `project.yml` declares the exported type
`com.tylervick.graphghan.pattern-bundle` and the document type that claims it;
`LSSupportsOpeningDocumentsInPlace` is false, so the system hands over a copy in `Documents/Inbox`,
which the importer deletes either way. `plutil -p Graphghan/Info.plist` after `mise run generate`
is how to check the registration landed.

`PatternBundle.read` decodes and validates the whole bundle in memory — every chart through
`Chart.load`, the same as a downloaded one, plus its id against the manifest — before anything is
written, so a broken bundle names what is wrong and leaves the library exactly as it was. Charts
go to `ChartLibrary` by chart id like any other; the manifest and previews go to
`LocalPatternStore`. Opening the same bundle again replaces the pattern rather than adding a
second, and a chart the new version drops stays in the library because a project pinned its id.

A pattern is resolved local-first by its id everywhere — manifest, previews, a project's pattern
title — so a local pattern never reaches for the network and never gets a version notice from the
site. The cost is that a bundle whose id matches a published slug shadows it: #135.

## Opening a pattern PDF

A pattern PDF opens the same way (#112, `docs/superpowers/specs/2026-09-20-phone-pdf-import-design.md`):
`project.yml` claims `com.adobe.pdf` as an Alternate handler, and `AppModel.importFile(at:)` routes a
`.pdf` to `PDFImporter` and the import sheet instead of the bundle importer. One that
`graphghan export --format pdf` wrote is read exactly from its text layer (`OwnPDFReader` in
GraphghanCore) and lands in the library with the same chart id the Mac computed, written by
`ChartWriter`, `ManifestWriter` and `ChartPreview`. A PDF with written rows and no chart goes
to `ProseReaderKit` (`Packages/ProseReader`, the same reader the Mac tool runs) on a device with
Apple Intelligence (iOS 26), row by row behind a progress sheet that names the row count, the
estimate and has Cancel, and is assembled by `RowsChart` in GraphghanCore under the same width and
row-number checks the Python importer applies; the chart records `ext.graphghan.import` (spec §6.3)
and the detail screen says when the gauge was not printed. Without the model the sheet says so and
points at the Mac. A PDF with a picture of the chart goes through `GridReader` in GraphghanCore, a
port of the Python `rasterchart.py` held to its answers on the images under `fixtures/import/grid/`
(`GridReaderTests`, `GridColoursTests`): each page is rendered by `PageRenderer` under the
40-megapixel budget (spec §5.1), the largest grid of at least 8×8 cells becomes the chart at once
(`GridChart`), and the written rows, when the pages have them and the iPhone has the model, are
then read as the check underneath the chart on the sheet, with Skip; "Add to library" before the
check ends saves it as stopped. The outcome is `ext.graphghan.import` on the chart (spec §6.3:
`check`, `rows_checked`, `rows_total`, `rows_disagree`, `problem`) and the detail screen's sentence
(`ImportRecord.sentence`). The real pattern PDFs (`fixtures/import/real/`, on the mini only) read to
the Python's pinned hashes in `PDFImportRealTests`, which skips a file that is absent. The grid
reader walks every pixel, so `Packages/GraphghanCore/Package.swift` optimises the package's debug
builds too (`-O`; forty seconds a page otherwise). A PDF whose pages hold almost no text is named
as a picture of text (#151); one with neither chart nor rows gets "No chart or written rows were
found in this PDF"; one that PDFKit cannot open, or ours with a row the reader cannot parse or a
chart too large to hold, gets its own sentence (`PDFImportError.message`, spec §5.4). The sheet
shows the chart before "Add to library" saves it; a read writes nothing, and Cancel leaves the
library as it was. The model never runs in a test: `PDFImportTests` stand a canned `RowReading` in
for it. `--import <path>.pdf` drives the identical path on the simulator, which has no model.

Driving it without a drag: `xcrun simctl launch <device> com.tylervick.graphghan --import <path>`,
or `xcrun simctl openurl <device> "file://<path>"`, which goes through LaunchServices the way Files
does. AirDrop needs a real device; the type registration is what it depends on. The design is
`../docs/superpowers/specs/2026-09-19-open-graphghan-bundles-design.md`.

## Live Activity

The Work screen runs a Live Activity on the lock screen and in the Dynamic Island, backed by the
`GraphghanWidgets` extension target. `Shared/` compiles into both the app and the extension, but
the Done and Back intents run in the app: the extension has nothing registered, so
`WorkIntentHandler` (set up in `AppModel.live`) is what actually calls `ProjectService.apply`. A
lock-screen tap that launches the app from the background still applies through
`ProjectService.apply`. The controller keeps one activity live at a time, restarts it after the
system's 8-hour limit on the next advance, and reconciles every active activity on launch, with
the stored cursor winning. `project.yml` sets `NSSupportsLiveActivities` in the app's Info.plist.
Snapshots of the lock screen and Dynamic Island layouts live under `Tests/__Snapshots__`; delete a
PNG to re-record it. Those references are tied to the iPhone 17 simulator, so re-record on that
device if they drift after an OS update.

## App Intents

Done and Back can be said to Siri, run from Shortcuts, or bound to the Action Button
(`Graphghan/Intents/`). `MarkDoneIntent` and `UndoDoneIntent` are plain, discoverable `AppIntent`s;
`GraphghanShortcuts` offers "Done in Graphghan" (also "Next", "Mark a done") and "Back in Graphghan"
(also "Undo that"). Neither needs a project named: `AppModel.resolveWorkingProject` picks the one
with the Live Activity, else the unfinished project worked most recently, and when two were worked
within the same hour the intent asks which blanket rather than guessing (a wrong guess writes into
the wrong project's history). A spoken Done is exactly a tapped Done -- the project's count step, or
the rest of the run -- applied through `ProjectService.apply` like every other path. The reply
(`WorkIntentDialog`) says where the cursor landed: the run, what is left in a fill, the turn, or that
the blanket is done; on a phone the snippet (`WorkSnippetView`) shows the Work screen's own panel
and band at that cursor.

A project is also an `AppEntity` (`ProjectEntity`): title, pattern, percent done and last worked,
projected from the store through `AppModel.projectSnapshots` with no storage of its own, so Siri can
answer "how far am I on the Craigh na Dun blanket" with the app closed and resolve a project by its
own title or its pattern's. On iOS 18 and later the entities are indexed for Spotlight
(`ProjectIndexer`), refreshed at launch and whenever `ProjectService` starts, finishes, unfinishes,
switches or deletes a project (`onProjectsChanged`); a step upserts just the project that moved
(`onStep`), so the percent Spotlight shows is current without a full refresh on the tap path. Index
work is queued in order, and a full refresh that is no longer the newest is skipped. The entity
and the optional project parameter are not availability-gated, because Swift cannot gate a stored
`@Parameter`; only the Spotlight conformance and the indexer are `@available(iOS 18, *)`.

The lock-screen pair in `Shared/WorkIntents.swift` stays undiscoverable, because its project
parameter is a bare UUID; the discoverable pair lives in the app target only, because `Shared/`
also compiles into the widget extension and a plain intent declared there would run in the
extension, where nothing is registered. Every intent and entity query waits for `AppModel.live` to
register `WorkIntentHandler` before it acts, so a request that launches the app in the background is
counted rather than dropped. The design is
`../docs/superpowers/specs/2026-09-18-ios-app-intents-design.md`.

## Design language

The spec is `../docs/superpowers/specs/2026-09-11-ios-design-language-design.md` ("Heather"). Colors are the
named sets in `Shared/Tokens.xcassets` and nothing else; fonts are `Font.Heather.*`; every yarn-colored
surface goes through `YarnSurface`. Screen snapshots live under `Tests/__Snapshots__` (delete a PNG to
re-record it on the iPhone 17 simulator). The chip row on the Work screen scrolls and `ImageRenderer`
leaves scrolling content blank, so the Work snapshots do not show the chips; the components sheet
covers their states and the QA checklist covers them in place. Dark values are declared in the catalog
but not yet tuned.

## Device build

Building for a physical iPhone (rather than the simulator) needs Xcode signed in under the team
that owns `com.tylervick.graphghan` and a device registered to it. Open `Graphghan.xcodeproj`,
select the "Graphghan" scheme, pick the device as the run destination, and build; the Debug
configuration uses automatic signing (`project.yml`), so the first successful device build
registers both bundle ids and assigns the App Group capability (`group.com.tylervick.graphghan`)
in the developer portal. Nothing else does that registration.

## CI and releases

`.github/workflows/ci.yml`'s `ios` job runs on a pull request that touches `ios/`, `fixtures/`,
`schema/`, or `ci.yml` itself: `mise run core-test`, `mise run script-test`, then the app's unit
tests on the iPhone 17 simulator with snapshots in `render` mode, uploaded as the `ios-snapshots`
artifact for eyeballing. `mise run ci-test` reproduces that last step locally (without CI's `OS=26.2`
destination pin). To re-record every snapshot reference in one run, run
`TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record mise run test` — plain `GRAPHGHAN_SNAPSHOTS=record` has no
effect, because `mise run test` drives `xcodebuild`, which only forwards `TEST_RUNNER_`-prefixed
variables into the test host. `render` mode itself refuses to run without `GRAPHGHAN_SNAPSHOT_OUT`
set, so it can never overwrite a committed reference by accident.

`mise run script-test` runs the hermetic tests for the shell scripts under `Scripts/`.

The same pull request also gets a `revyl-preview` job: a standalone simulator bundle
(`ENABLE_DEBUG_DYLIB=NO`, so it is a real app bundle rather than the Xcode debug-dylib layout)
uploaded to [Revyl](https://revyl.ai), which runs the app on a cloud device and reviews the change
against it. It is a separate job from `ios` deliberately — a build that fails its suite is often the
one you most want on a device — and it uploads without promoting the build to the app's current
version. `.revyl/config.yaml` holds the recipe, the invariants every review checks, and a prompt
describing this app to the agent driving the device; the repo root `README.md` covers the CLI and
the local setup. Local equivalent, once `mise run revyl-setup` has signed you in:

    mise x -- revyl build --local     # build this recipe here and upload the artifact
    mise x -- revyl build             # or build it on a Revyl cloud runner

Two test definitions live in `.revyl/tests/` and run as the `graphghan-pr-review` workflow:

- `pattern-feed-to-project` — the Patterns tab reaches the live feed, a pattern's manifest loads,
  and `Start project` creates a project. Every step crosses the network, which the unit suite
  cannot: it runs against a stub HTTP client.
- `work-progress-persists` — a row is worked on the Work screen, the app is killed, and the
  position is still there on relaunch. `ios/Tests` drives `ProjectService` against an *in-memory*
  SwiftData store, so it proves the arithmetic and nothing about durability.

Both were walked on a real cloud device before being written. `.revyl/tests/README.md` records what
that walk corrected about the app — `Start project` is two screens below the fold, the Work screen's
advance button reads `+10` but is *labelled* `"… next ten"`, and starting a project switches tabs by
itself — and it lives in a Markdown file rather than in the YAML headers because `revyl test push`
round-trips those files through the backend and strips every comment out of them.

Edit them as YAML and push with `mise x -- revyl test push <name>`; `mise x -- revyl test run <name>`
runs one against the app's current build.


A merge to `main` that changes the app ships a TestFlight build to the internal group; `docs/release.md`
has the details, the group settings that keep external testers out of the automatic path, and the
manual dispatch for dry runs and retries.

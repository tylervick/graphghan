# Graphghan: chart format v2, publishing contract, and native iOS Work app

Date: 2026-09-10
Status: approved design (sections reviewed in conversation), awaiting spec review
Builds on: `2026-09-09-graphghan-design.md` (library, PWA, skill)

## 1. Purpose

Expand graphghan from "a viewer for one pattern" into "a place to work any pattern": a native
iOS app with a Patterns tab (browse what is published, start a project at a chosen gauge and
variant) and a Projects tab (per-instance progress with a full-screen, hands-mostly-free Work
screen and a Live Activity on the lock screen). Authoring stays in Python and the Claude skill.

Because nothing open exists for crochet or knitting charts, the app is built on a chart format
of our own that is small at the core, layered, and explicitly extensible, so it can be published
for others later without a rewrite. The format is the contract between Python, the PWA, and
Swift, and it is tested from all three sides against shared fixtures.

## 2. Decisions already made

| Decision | Choice | Why |
|---|---|---|
| Client | Native SwiftUI iOS app, iOS 17 minimum | Live Activity buttons, App Intents, Watch later. The crocheter is on iPhone. |
| Distribution | TestFlight from GitHub Actions, paid Apple account | Builds go to one external tester; the pipeline copies Waddle's proven manual-signing flow. |
| Progress storage | Local SwiftData on the crocheter's phone, no backend, no CloudKit | Nobody else needs to see it; device backup covers loss. |
| Left tab | Patterns: browse the published library and start projects | Real authoring on mobile needs a Python runtime; deferred. |
| First-build hands-free | Big-tap Done, haptics, interactive Live Activity | Spoken readout, Siri, Action Button, Watch, hardware keys are follow-ons. |
| Format | Own JSON, schema 2, with exporters to PNG, OXS, CSV, PDF | OXS cannot express working order; CSV has no metadata; nothing else exists. |
| Palette codes | 1 to 3 letters, count always required in run strings | Removes the 26-color ceiling while keeping rows human-readable. |
| Working order | `technique` enum derived on the client, optional explicit `passes` override | Small enum for the derivable cases; passes are the escape hatch for anything else. |
| Repo | Monorepo, `ios/` alongside the Python package | Spec, schema, and fixtures change in one commit. |

## 3. Non-goals and follow-ons

Not in this version, listed so nobody builds them by accident:

- Spoken readout of the next run; Siri phrases and the Action Button (the intents exist, the
  `AppShortcutsProvider` does not); Apple Watch; hardware keyboard, page-turner or foot-pedal keys.
- "Where am I" from a stitch count; yarn and bobbin management; photos; sessions across devices.
- Opening `.graphghan` bundles from Files or AirDrop (the bundle is defined; the document type
  registration and importer are not built).
- Importers (PNG, OXS, CSV into a pattern folder). Exporters are in scope.
- Techniques other than `rows` and `rounds` (C2C is a reserved name, see 5.6).
- CloudKit sync, sharing progress with the designer, accounts of any kind.
- The in-app options page. The existing options HTML stays a designer's tool.

## 4. Publishing contract (Python side)

### 4.1 Publish table

`pattern.toml` gains an optional `[publish]` table:

```toml
[publish]
charts = [["final", "sc"], ["final", "hdc"]]
```

Each entry is `[variant, gauge_key]`. The first entry is the default. When the table is absent,
the published set is `[["final", <pattern.stitch>]]`, which is what every pattern publishes
today. `graphghan render` refuses an entry whose variant or gauge does not exist.

### 4.2 dist layout

```
patterns/<slug>/dist/
  chart.json  chart.png  preview.png  preview-grid.png  written-rows.txt   # the default, as today
  charts/<variant>-<gauge>/
    chart.json  chart.png  preview.png  preview-grid.png  written-rows.txt  # one per published entry
```

Every published entry is written under `charts/`; the default entry is also copied to the top
level so the current site, the drift check, and CI keep working unchanged. `graphghan render
<slug> --check` compares every published combination, not only the default. `render --gauge` and
`--variant` still build a single ad-hoc combination to `--out` and never touch `dist/`.

### 4.3 Pattern manifest

The site build writes `patterns/<slug>/pattern.json` (schema 1, distinct from the chart schema):

```json
{
  "schema": 1,
  "id": "craigh-na-dun",
  "title": "Craigh na Dun Blanket",
  "version": "1.0.0",
  "dedication": "For Meaghan",
  "quote": "...",
  "author": "Tyler Vick",
  "license": "CC-BY-NC-SA-4.0",
  "preview": "preview.png",
  "palette": [{ "code": "Y", "name": "Gold", "hex": "#D9A21B" }],
  "charts": [
    { "id": "sha256:...", "variant": "final", "gauge_key": "sc", "default": true,
      "path": "charts/final-sc/chart.json", "preview": "charts/final-sc/preview.png",
      "width": 189, "height": 184, "size": { "width": 54.0, "height": 46.0, "unit": "in" },
      "stitch": "sc", "colors": 5, "stitches": 34776,
      "changes_per_row": { "mean": 6.1, "max": 23 }, "yards_est": 3200 }
  ],
  "updated": "2026-09-10T20:00:00Z"
}
```

Paths are relative to the pattern directory on the site. `updated` is the build time. The app
reads the manifest to render a pattern's detail screen without opening any chart.

### 4.4 Site index

`patterns/index.json` keeps its current keys and adds `manifest` (path to `pattern.json`),
`charts` (count of published charts), and `version`. The library screen is one fetch.

### 4.5 Versioning

`pattern.version` is the designer's semver. `chart.id` is a content hash (5.2). A project pins
both at start. The app compares the published manifest against the pinned values: same chart id
means nothing changed regardless of version; a different chart id means the grid, palette codes,
or technique changed.

### 4.6 Tests

Site build tests: manifest exists per pattern, every `charts[].path` and `preview` resolves,
exactly one `default`, the default entry's id equals the top-level `chart.json` id, and the
index's `charts` count matches. CLI tests: the publish table validates, `render` writes every
combination, `render --check` reports drift in a non-default combination.

## 5. Chart format, schema 2

Lives at `docs/chart-format.md` with `schema/chart.schema.json` (JSON Schema 2020-12) and
`schema/progress.schema.json`. This section is the normative summary; the doc restates it with
examples. Readers MUST ignore unknown keys at every level.

### 5.1 Identity

```json
"schema": 2,
"pattern": { "id": "craigh-na-dun", "title": "Craigh na Dun Blanket", "version": "1.0.0",
             "author": "Tyler Vick", "license": "CC-BY-NC-SA-4.0",
             "dedication": "For Meaghan", "quote": "...", "url": "https://graphghan.milo.cat/patterns/craigh-na-dun/" },
"chart":   { "id": "sha256:4f1c...", "variant": "final", "gauge_key": "sc", "width": 189, "height": 184 },
"generator": { "name": "graphghan", "version": "0.2.0" }
```

Required: `schema`, `pattern.id`, `pattern.title`, `pattern.version`, `chart.id`,
`chart.width`, `chart.height`. `pattern.id` matches `[a-z0-9-]+`.

### 5.2 Chart id

`"sha256:" + hex(sha256(canonical))` where `canonical` is the UTF-8 JSON encoding, keys sorted,
no whitespace, of `{"codes": [palette codes in order], "rows": rows, "technique": technique}`.
`passes`, when present, are included as `"passes"`. Names, hexes, yarn, instructions, and
stats do not affect the id: renaming a color is not a new chart.

### 5.3 Palette and cells

```json
"palette": [
  { "code": "Y", "name": "Gold", "hex": "#D9A21B",
    "yarn": { "brand": "Red Heart", "line": "Super Saver", "colorway": "Gold", "weight": "4", "lot": "", "note": "" },
    "thread": { "system": "DMC", "number": "783" },
    "use": "moon, braided border", "symbol": "*" }
],
"rows": ["189Y", "1Y187G1Y"]
```

- `code` matches `^[A-Za-z]{1,3}$` and is unique within the palette. Two codes that differ
  only by case are valid but the Python validator warns.
- `name` and `hex` (`^#[0-9A-Fa-f]{6}$`) are required. Everything else is optional. `yarn` is
  always an object; the TOML shorthand `yarn = "Aran / off-white"` maps to `{"note": ...}`.
- `rows` has exactly `chart.height` strings, listed top to bottom as displayed. Each matches
  `^(\d+[A-Za-z]{1,3})+$`, every code is in the palette, and the counts sum to `chart.width`.
  A run always starts with digits, so `7YB` is one run of code `YB`.
- `layers` (optional) is a map of name to `{ "legend": { code: label }, "rows": [...] }` using
  the same encoding, for stitch symbols, backstitch, carry-or-bobbin hints, and so on. Readers
  that do not know a layer ignore it.

### 5.4 Gauge

```json
"gauge": { "stitches": 14, "rows": 16, "over": { "value": 4, "unit": "in" },
           "stitch": "sc", "hook": "5 mm (US H-8)", "yarn_weight": "4" }
```

`stitches`, `rows`, `over` are required; `unit` is `in` or `cm`. Cell aspect and finished size
are derived, never stored, except as informational copies in `stats`.

### 5.5 Technique and passes

```json
"technique": { "type": "rows", "start": "bottom", "first_side": "RS", "rs_direction": "rtl", "turn": true }
```

A technique maps the grid to an ordered list of passes; a pass is an ordered list of runs. The
progress cursor is `{ "row": <1-based pass index>, "run": <0-based run index> }` for every
technique, because C2C patterns already call a diagonal a row.

Internal model produced by every loader:

```
Pass { label: String, side: RS|WS|null, direction: rtl|ltr|null, gridRow: Int?, runs: [Run] }
Run  { code: String, count: Int, x0: Int? }
```

- `rows` (implemented): pass k uses grid row `height - k` when `start` is `bottom`, else
  `k - 1`. Sides alternate from `first_side`. RS passes read `rs_direction`; WS passes read the
  opposite. Runs are the RLE of that grid row in reading order; `x0` is the leftmost grid
  column of the run regardless of reading direction. `label` is `Row k`. `turn` is
  informational (true for flat work).
- `rounds` (implemented): as `rows` but every pass is `first_side` and reads `rs_direction`.
- `c2c`: reserved name. A reader treats it as unknown until a later schema revision defines its
  derivation with fixtures.
- `none`: no derivable sequence (cross-stitch and the like); display only unless `passes` given.
- Unknown `type`: display only. The Work screen refuses to start with a clear message.

`passes` (optional) is an explicit list in the internal shape above, serialized as JSON objects
`{ "label", "side", "direction", "grid_row", "runs": [{ "code", "count", "x0" }] }` with
`side`, `direction`, `grid_row`, and `x0` optional. When
present it overrides derivation, whatever `type` says. A file with `passes` and an unknown
`type` is fully workable. The generator emits `passes` only when the design needs them; the
validator checks that every run's code is in the palette and, when `gridRow`/`x0` are given,
that they lie inside the grid and match the cells.

### 5.6 Instructions, stats, extensions

```json
"instructions": [ { "title": "Setup", "text": "Foundation: chain W + 1 in Gold (Y). ..." } ],
"stats": { "...": "optional, derived, recomputable" },
"ext": { "graphghan": { "report": { "panel": [x0, y0, x1, y1], "text": [...] } } }
```

`instructions` replaces the fixed `notes.setup`/`notes.colors`; `pattern.toml` keeps `[notes]`
as a shorthand that maps to two sections titled "Setup" and "Colors", and gains an optional
`[[instructions]]` array for more. `stats` keeps today's content. `ext` is a map of vendor name
to anything; `ext.graphghan.report` is generator-private and the pattern tests keep reading it.

### 5.7 Progress document, schema 1

```json
{ "schema": 1, "pattern_id": "craigh-na-dun", "chart_id": "sha256:4f1c...", "pattern_version": "1.0.0",
  "cursor": { "row": 42, "run": 3 }, "started": "2026-09-12T18:04:00Z", "finished": null,
  "events": [ { "t": "2026-09-12T18:31:12Z", "row": 42, "run": 2, "kind": "advance" } ] }
```

`kind` is `advance`, `back`, or `jump`; each event records the cursor after the action. The
PWA's base64 code `{slug,row,run}` is importable as a cursor-only document with an empty log.

### 5.8 Bundle

A `.graphghan` file is a zip containing `pattern.json` at the root plus the chart files and
previews it references at their relative paths. Defined here so the app and site agree; the
document type registration and Files importer are a follow-on.

### 5.9 Exporters

`graphghan export <slug> --format png|oxs|csv [--chart <variant>-<gauge>] [--out ...]`:

- `png`: 1 pixel per stitch, palette hexes, no grid, no scaling. Round-trips through any pixel
  tool and Stitch Fiddle's picture import.
- `oxs`: `<chart>` with `<properties>` (`chartwidth`, `chartheight`, `stitchesperinch`,
  `stitchesperinch_y` from gauge, `charttitle`, `author`), `<palette>` items (`index`,
  `number` from `thread` when present else the code, `name`, `color`), and one `<stitch>` per
  cell in `<fullstitches>`. Empty `<backstitches>`, as the format requires.
- `csv`: `height` lines of `width` codes, comma-separated, top to bottom.

PDF stays the site's print tiles plus written rows.

### 5.10 Migration and the PWA

Schema 1 to 2 is a re-render; there is one pattern and no compatibility reader. `chart_json`
emits schema 2; `data.js` decodes schema 2 (multi-letter codes, `pattern.*`, `gauge`,
`technique`, `instructions`); the PWA loads the default chart, keeps its progress key, and its
export code is unchanged. The drift baseline is re-committed once. Schema 1 top-level keys
`slug`, `title`, `dedication`, `quote`, `version`, `variant`, `stitch`, `cell_aspect`, `hook`,
`yarn_weight`, `size_in`, `first_row_color`, and `notes` are gone: they live under `pattern`,
`chart`, `gauge`, or `instructions`, or are derived (`first_row_color` is the first run of the
first pass).

### 5.11 Fixtures

`fixtures/chart-format/<name>.chart.json` paired with `<name>.sequence.json` (the passes the
loader must produce) and, where relevant, `<name>.progress.json` paired with
`<name>.progress.expected.json` (cursor, per-session summaries, percent). Initial set:

| name | exercises |
|---|---|
| `minimal-rows` | the existing `tests/fixtures/minimal` pattern at sc, start bottom, RS rtl |
| `minimal-rounds` | same grid, `rounds` |
| `two-letter-codes` | codes `Y`, `Gd`, `Kb`; a `7Gd` run adjacent to `2G` |
| `explicit-passes` | `type: "none"` plus `passes`, workable |
| `unknown-technique` | `type: "tunisian"`, no passes: decodes, does not sequence |
| `craigh-na-dun` | the real chart, sequence checked by hash of the pass list |
| `progress-basic` | 3 sessions, one back, one jump; expected stats |

Fixtures are the schema's conformance suite; a schema change adds or updates fixtures first.

## 6. iOS app

### 6.1 Structure

- `GraphghanCore` (Swift package, Swift 6 language mode, no UI imports): `ChartDocument`
  decoding and validation, `Chart` value type (palette, cells as `[UInt8]`, gauge, technique),
  `WorkSequence` (passes, runs; built from technique or explicit passes), `WorkEngine`,
  `ProgressDocument` encode/decode, pace and estimate math, chart id computation.
- `Graphghan` app target (SwiftUI): stores, SwiftData models, screens, haptics, intents.
- `GraphghanWidgets` extension: Live Activity views only.

### 6.2 Pattern data (immutable, cached)

`PatternStore` (actor) fetches `patterns/index.json` and each `pattern.json` from
`https://graphghan.milo.cat/`, storing bytes, ETag, and fetch time under the App Group
container at `Library/Caches/patterns/<id>/`. Requests send `If-None-Match`. Chart files are
downloaded when a project starts and stored under `Library/Application Support/charts/<chart
id>.json`, never evicted while a project references them. Decoding happens once per launch per
chart and is memoized.

### 6.3 SwiftData models

Store file in the App Group container. No CloudKit.

- `Project`: `id: UUID`, `patternID: String`, `chartID: String`, `patternVersion: String`,
  `title: String`, `started: Date`, `finished: Date?`, `notes: String`, `cursorRow: Int`,
  `cursorRun: Int`, `lastWorked: Date?`, `@Relationship(deleteRule: .cascade) events`.
- `ProgressEvent`: `t: Date`, `row: Int`, `run: Int`, `kind: advance|back|jump`, `project`.

`WorkEngine.apply` returns the new cursor and event; the store writes both in one save. Percent
complete is stitches before the cursor over total stitches.

### 6.4 Pace and estimate

Sessions are runs of events with gaps under 20 minutes. Active time is the sum of session
durations. Stitches per active hour is total stitches advanced over active time. The finish
estimate is remaining stitches divided by that rate, spread over the mean active hours per
calendar day across the last 14 days, and is shown only after 3 sessions. All pure functions in
the core package.

### 6.5 Screens

Tab bar with Patterns and Projects; the Work screen is a full-screen cover.

Patterns:
- Library list: preview, title, dedication, finished size at the default gauge, stitch, color
  count. Pull to refresh. A banner when the fetch fails and cached data is shown; an empty state
  with a retry when offline with no cache.
- Pattern detail: preview, quote, specs, palette with yarn notes, instruction sections, and a
  table of published charts with finished size and row count. "Browse chart" opens a full-screen
  viewer: the chart rendered to a `CGImage` at 1 pixel per cell, scaled nearest-neighbor, pinch
  and pan, row numbers on the edges.
- Start project: pick a published chart (variant and gauge, showing the resulting size), name
  it (defaults to the pattern title), Start. Downloads the chart, creates the project, switches
  to Projects. A download failure leaves no project behind.

Projects:
- Project list: preview, title, percent, row of total, last worked, estimate when available.
- Project detail: progress overview, session history, pace, notes, and actions: Work, browse
  chart at the current row, jump to row, mark finished, delete. Version notice per 4.5: same
  chart id shows nothing; a changed id explains what changed and offers "switch to the new chart"
  only when the cursor is at row 1 run 0.

Work screen:
- Full screen, tab bar hidden, `isIdleTimerDisabled` while shown, portrait and landscape.
- Top: "Row 42 of 184", side, and read direction.
- Strip: the rows around the current one drawn from the grid, current row outlined, a marker on
  the starting edge.
- Chips: the current row's runs, done runs dimmed, current highlighted, tap a chip to jump within
  the row.
- Center: the current run as count, code, and color name on a swatch of that color; beneath it
  the next run smaller, or "last run in this row", or "next row starts in Gold".
- The lower half is one tap target for Done. Swipe right anywhere for Back. Long press the row
  number to jump. A Close button top-left.
- Haptics: light for a run, medium for a row, a double tap when the next run introduces a color
  that the previous row did not use.
- Every Done and Back goes through the store, which writes the event and cursor and updates the
  Live Activity.

### 6.6 Error handling

Storage failures surface once as a banner and never block advancing. A chart that fails to
decode marks the project as needing re-download, with a button, rather than crashing. Site
unreachable is a state everywhere except Start project, where it is an explanation. A Live
Activity request failure shows a one-time hint pointing at Settings.

## 7. Live Activity and intents

- Minimum iOS 17 for interactive buttons and `LiveActivityIntent`.
- One activity at a time. Starts when the Work screen opens; ends when it closes, when the
  project is finished, or when the system 8 hour limit ends it, in which case the next advance
  restarts it. On launch the app reconciles: the stored cursor wins; a stale activity is
  refreshed or ended.
- Attributes: project id, pattern title, total rows, total stitches, palette as code, name, hex.
- State: row, side, run index, current run (code, count), next run or `isLastInRow`, percent.
  Built by a pure function in the core package from cursor and sequence.
- Lock screen: title and "Row 42 of 184"; the current run large as a swatch with the count and
  the name beside it; next run small; Back and Done buttons, Done primary and larger.
- Dynamic Island: compact leading swatch with count, trailing row number; minimal swatch with
  count; expanded as the lock screen.
- `AdvanceRunIntent` and `BackRunIntent` conform to `LiveActivityIntent` and `AppIntent`, take a
  project id, run in the app process, apply `WorkEngine`, save, and update the activity. The
  system provides the button's tap feedback; the intent does not attempt haptics of its own. A
  missing project or chart ends the activity with an explanatory final state.
- Updates are local only; no push, no server. `AppShortcutsProvider` is not registered in this
  version.

## 8. Repository, project setup, CI, TestFlight

### 8.1 Layout

```
fixtures/chart-format/          shared conformance fixtures (5.11)
schema/chart.schema.json  schema/progress.schema.json
docs/chart-format.md
ios/
  project.yml                   xcodegen; Graphghan.xcodeproj is gitignored
  mise.toml                     xcodegen and tool versions
  Graphghan/                    app target
  GraphghanWidgets/             widget extension
  Packages/GraphghanCore/       Swift package with Tests/ reading ../../../fixtures
  ExportOptions.plist           local, automatic signing
  ExportOptions-ci.plist        CI, manual signing, both profiles
  Scripts/archive.sh  upload.sh  whats-to-test.sh
  docs/qa.md                    manual checklist before a TestFlight build
```

### 8.2 Identifiers

Bundle id `com.tylervick.graphghan`, extension `com.tylervick.graphghan.widgets`, App Group
`group.com.tylervick.graphghan`. Xcode 26.2, iOS 17.0 deployment target, Swift 6 language mode.

### 8.3 One-time portal work (by hand)

Two App IDs with the App Group capability; two App Store provisioning profiles (app and
extension); the app record in App Store Connect; an external TestFlight group containing the
crocheter. The first external build goes through Beta App Review.

### 8.4 CI

A new `ios` job in `.github/workflows/ci.yml` on `macos-26`, path-filtered to `ios/**`,
`fixtures/**`, `schema/**`: install tools via mise, run xcodegen, `swift test` in the core
package, then `xcodebuild test` for the app scheme on an iPhone simulator. Xcode pinned to 26.2.
The Python job gains schema validation of every fixture and the sequence conformance test.

### 8.5 TestFlight workflow

`.github/workflows/testflight.yml`, adapted from Waddle: `workflow_dispatch` only, with
`validate_only` and `build_number` inputs; concurrency group `testflight`, no cancel; build
number = offset + run number, validated first; ephemeral keychain with the Distribution p12 and
both profiles installed to both profile directories, codesign partition list set; archive and
export with the App Store Connect API key; upload the IPA as an artifact before uploading to
App Store Connect; tag `ios-build-N`; attach What to Test notes from `git log` since the previous
tag; collect distribution logs on failure with the key id scrubbed; delete the keychain always.
Secrets reused from Waddle: `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`. New: `PROVISIONING_PROFILE_APP_BASE64`,
`PROVISIONING_PROFILE_WIDGETS_BASE64`. Not copied: the nightly gate, engine build, screenshots,
feedback fetching.

## 9. Testing

- Conformance: Python and Swift each walk `fixtures/chart-format/`, validate every chart against
  the schema, derive the sequence, and diff against the expected file; progress fixtures produce
  the expected stats. Adding a technique starts with fixtures.
- Python: publish table, dist tree, manifest, stable chart id across re-renders, drift over every
  combination, exporter round trips (PNG, OXS, CSV back to cells and codes), site manifest and
  index assertions, PWA decoder contract test re-baselined.
- Swift core: decoder edge cases (malformed run string, unknown code, case-only duplicate codes,
  row sum mismatch), `WorkEngine` at every boundary (advance and back across rows, back at start,
  advance at end, jump) and the event each yields, progress document round trip, pace and
  estimate from a known log, chart id equals the Python value for every fixture.
- App: in-memory SwiftData: start pins chart id and version; advance writes cursor and event
  atomically; delete cascades; version notice only on a changed chart id. `PatternStore` with a
  stubbed session: fresh fetch, not-modified, offline with cache, offline without cache, failed
  chart download leaves no project. Intents called directly: same store changes as the screen;
  stale project id.
- Live Activity: state builder unit tests; snapshot tests of the lock screen, compact, and
  minimal views.
- Manual, in `ios/docs/qa.md`, before each build: a full row on the Work screen; lock screen
  Done and Back with the app in the background; app killed with an activity showing, then
  relaunched; airplane mode on the library and on a project; rotating the Work screen mid-row.
- Deliberately absent: UI automation of the Work screen; snapshots of app screens beyond the
  activity.

## 10. Work plan

Four implementation plans, each its own branch and worktree:

1. **Format and publishing (Python + PWA).** Schema 2 emitter and validator, JSON Schemas,
   fixtures and conformance test, publish table and dist tree, manifest and index, exporters,
   PWA decoder update, drift re-baseline, `docs/chart-format.md`. Everything else depends on
   the fixtures from this plan.
2. **iOS core and screens.** xcodegen project, `GraphghanCore` with conformance tests,
   SwiftData models, `PatternStore`, Patterns and Projects tabs, Work screen with haptics.
3. **Live Activity and intents.** Widget extension, attributes and state, intents, lifecycle
   reconciliation, snapshot tests, the Settings hint.
4. **CI and TestFlight.** The `ios` CI job, the TestFlight workflow, portal setup notes,
   `qa.md`, first build to the tester.

Plan 2 can start once plan 1 has committed fixtures; plans 3 and 4 follow plan 2.

## 11. Success criteria

- The crocheter installs a TestFlight build, opens Craigh na Dun, starts a project at the sc
  gauge, and works a row from the Work screen and from the lock screen without unlocking.
- Killing the app mid-row loses nothing; relaunch shows the same cursor and a correct activity.
- `uv run graphghan render craigh-na-dun --check` and `pytest` pass with every published
  combination, and `swift test` passes the same fixtures.
- The format doc and schema are enough for someone else to write a reader that sequences the
  fixtures correctly without asking us.

# Open .graphghan bundles from Files and AirDrop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `graphghan export <slug> --format graphghan` writes a byte-reproducible bundle with a committed fixture and a drift test; iOS registers the document type, reads the zip, validates every chart through `GraphghanCore`, and puts the pattern in the Patterns tab as a local pattern a project can start from. Opening the same bundle twice updates rather than duplicates; a broken one says why and changes nothing.

**Architecture:** Three layers, each testable without the one above it. Python: `graphghan/manifest.py` (the manifest projection, moved out of `site/build.py` so there is one definition) and `graphghan/bundle.py` (`to_bundle(pattern_dir) -> bytes`), with one CLI branch. `GraphghanCore`: `ZipArchive` (read-only, name-addressed, ~250 lines over `Compression`) and `PatternBundle.read(Data)`, which decodes the manifest and loads every chart through the existing `Chart.load`. App: `LocalPatternStore` (an actor over the App Group's Application Support, shaped like `PatternStore`), `BundleImporter`, an `.onOpenURL` handler, and a second section in `LibraryView`.

**Tech Stack:** Python 3.12, `zipfile` (stdlib), pytest; Swift 6, `Compression` (system framework, no new dependency), Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-19-open-graphghan-bundles-design.md`. Closes #16.

## Global Constraints

- The writer emits exactly the files the manifest references — `pattern.json`, `preview.png`, and per chart `chart.json` and `preview.png` — and nothing else. Entries are `ZIP_STORED`, sorted by name, timestamped `(1980, 1, 1, 0, 0, 0)`, mode 0o644. Two calls give identical bytes on any OS.
- A bundle's manifest carries `updated: "1980-01-01T00:00:00Z"`. Everything else in it is what `site/build.py` would write for the same pattern.
- Bundles are built from the **committed** `dist/`, never a fresh render.
- `GraphghanCore` gains no third-party dependency. `ZipArchive` refuses zip64, encryption, data descriptors, multi-disk, methods other than 0 and 8, and every path shape in the spec's §5.1 table, each with its own error case.
- Nothing is written to disk until the whole bundle has validated. A refused bundle leaves `ChartLibrary` and the local store byte-identical.
- `Info.plist` is generated: the document type goes in `ios/project.yml` under `info.properties`, and `plutil -p ios/Graphghan/Info.plist` after `mise run generate` is how it is checked.
- `mise run check` before every commit; in `ios/`, `mise run generate`, `mise run core-test`, `mise run test`. Commit subjects `bundle:`, `export:`, `fixtures:`, `core:`, `ios:`, `docs:`; the session's `Co-Authored-By` trailer. `HK_STASH=none` when unstaged files are around.
- A failing `mise run test` sits ten minutes in `simctl diagnose` afterwards; kill it, the results are already logged.

## File map

| file | change |
|---|---|
| `src/graphghan/manifest.py` | new: `publish_order`, `published_docs`, `manifest`, `CHART_FILES`, moved verbatim from `site/build.py` |
| `site/build.py` | imports them instead of defining them |
| `src/graphghan/bundle.py` | new: `BUNDLE_EPOCH`, `bundle_files(pattern_dir)`, `to_bundle(pattern_dir) -> bytes` |
| `src/graphghan/cli.py` | `--format graphghan` in `choices`, a branch in `cmd_export`, the `--chart` refusal, the `<slug>.graphghan` default name |
| `fixtures/bundle/generate.py`, `README.md`, `craigh-na-dun.graphghan` | new |
| `tests/test_bundle.py`, `tests/test_bundle_fixtures.py` | new |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/ZipArchive.swift` | new |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/PatternBundle.swift` | new: `BundleChart`, `PatternBundle`, `BundleError` and its `message` |
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/SiteModels.swift` | `IndexEntry` memberwise init + `init(manifest:)` |
| `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/{ZipArchiveTests,PatternBundleTests}.swift`, `Fixtures.swift` | new tests; `Fixtures` gains a `bundle` path |
| `ios/project.yml` | `UTExportedTypeDeclarations`, `CFBundleDocumentTypes`, `LSSupportsOpeningDocumentsInPlace` |
| `ios/Graphghan/Storage/AppGroup.swift` | `localPatternsURL` |
| `ios/Graphghan/Storage/LocalPatternStore.swift` | new actor |
| `ios/Graphghan/Storage/ChartLibrary.swift` | `data(id:)` |
| `ios/Graphghan/Services/BundleImporter.swift` | new |
| `ios/Graphghan/Services/ProjectService.swift` | `startProject` prefers the library copy |
| `ios/Graphghan/AppModel.swift` | `localPatterns`, `libraryItems`, local-first `manifest`/`preview`, `importBundle`, `importFailure`, `libraryPath` |
| `ios/Graphghan/GraphghanApp.swift`, `RootView.swift` | `.onOpenURL`, the `--import` launch argument, the failure alert |
| `ios/Graphghan/Patterns/{LibraryView,PatternDetailView}.swift` | `LibraryItem`, two sections, the `Local` chip, path binding |
| `ios/Tests/{BundleImportTests,LocalPatternStoreTests,LibraryItemTests}.swift`, `TestSupport.swift` | new tests; a bundle-fixture path helper |
| `docs/chart-format.md`, `README.md`, `ios/README.md` | §Bundle rewritten, an §Interchange bullet, the quick-start line, the app's layout and data sections |
| `.github/workflows/ci.yml` | `fixtures/bundle/**` is already covered by the `fixtures/` path trigger — verify, change nothing if so |

## Tasks

### Task 1: the manifest projection moves into the package

- [ ] Create `src/graphghan/manifest.py` with `CHART_FILES`, `publish_order`, `published_docs`, `manifest`, moved from `site/build.py` unchanged.
- [ ] `site/build.py` imports them; delete the originals. `index_entry` and `finished_size_in` stay.
- [ ] `uv run pytest tests/test_site.py` (or whatever covers the site build) passes untouched.
- [ ] `mise run check`; commit `refactor(manifest): one home for the pattern manifest projection`.

### Task 2: `bundle.py`

- [ ] `BUNDLE_EPOCH = (1980, 1, 1, 0, 0, 0)` and `BUNDLE_UPDATED = "1980-01-01T00:00:00Z"`.
- [ ] `bundle_files(pattern_dir) -> dict[str, bytes]`: the manifest JSON (built with `manifest(published_docs(d), BUNDLE_UPDATED)`, serialised with the same `json.dumps` call `site/build.py` uses) plus every path it references, read from `dist/`. Raise a clear error naming any referenced file that is not in `dist/`.
- [ ] `to_bundle(pattern_dir) -> bytes`: a `zipfile.ZipFile` over a `BytesIO`, entries in sorted name order, each a `ZipInfo` with `date_time=BUNDLE_EPOCH`, `compress_type=ZIP_STORED`, `external_attr=0o644 << 16`, `create_system=0`.
- [ ] `tests/test_bundle.py`: determinism, entry set, stored + timestamp + sort, each file equal to `dist/`, the manifest equals the site's for the same pattern modulo `updated`, and a missing-`dist/` pattern raises.
- [ ] `mise run check`; commit `bundle: a byte-reproducible .graphghan writer`.

### Task 3: the CLI and the fixture

- [ ] `--format graphghan` in `cmd_export`'s `choices`; refuse `--chart` with the spec's message and exit 2; default out `build/exports/<slug>.graphghan`.
- [ ] `tests/test_cli.py`: the default path, and `--chart` exits 2.
- [ ] `fixtures/bundle/generate.py` (one bundle per pattern folder with a `dist/`), `README.md`, and the generated `craigh-na-dun.graphghan`.
- [ ] `tests/test_bundle_fixtures.py`: committed bytes equal a fresh generation; no fixture outlives its pattern.
- [ ] `mise run check`; commit `export: --format graphghan` and `fixtures: the Craigh na Dun bundle`.

### Task 4: `ZipArchive`

- [ ] Parse the EOCD (scan back over the last 65,557 bytes for `PK\x05\x06`), then the central directory; store name, method, CRC, sizes, local offset, flags per entry.
- [ ] `data(named:)`: read the local header for its name/extra lengths only, slice, inflate when method 8 via `compression_decode_buffer` with `COMPRESSION_ZLIB`, check the output length and CRC-32 against the central directory.
- [ ] A CRC-32 implementation (table-driven, `internal`) — `Compression` does not provide one.
- [ ] Every refusal in spec §5.1, each its own `ZipError` case.
- [ ] `ZipArchiveTests`: a helper that hand-builds archives, plus a generated adversarial set; the deflate/stored equivalence; the caps; the CRC mismatch.
- [ ] `mise run core-test`; commit `core: a read-only zip reader for pattern bundles`.

### Task 5: `PatternBundle`

- [ ] `BundleChart`, `PatternBundle`, `PatternBundle.read`, ordering by the manifest; every referenced path required; `schema == 1`, slug shape, non-empty `charts`, no duplicate paths.
- [ ] `BundleError` with a `message` sentence per case, and a test asserting every case has a non-empty one.
- [ ] `IndexEntry` memberwise `init` and `init(manifest:)` (cm→in like the site), in `SiteModels.swift`.
- [ ] `Fixtures.bundle` path; `PatternBundleTests` over the committed fixture: manifest decodes, both charts load and match their ids, previews are PNG, and the three refusals (missing file, invalid chart, id mismatch) built by rewriting the fixture's bytes.
- [ ] `IndexEntry(manifest:)` matches the site's `index.json` values for Craigh na Dun.
- [ ] `mise run core-test`; commit `core: read a .graphghan bundle into a manifest and validated charts`.

### Task 6: the document type

- [ ] `ios/project.yml`: the exported type `com.tylervick.graphghan.pattern-bundle` conforming to `public.zip-archive` with the `graphghan` extension (no MIME tag), the document type claiming it as Owner/Viewer, `LSSupportsOpeningDocumentsInPlace: false`.
- [ ] `mise run generate`; `plutil -p ios/Graphghan/Info.plist` shows all three. Record the output in the PR body.
- [ ] Commit `ios: register the .graphghan document type`.

### Task 7: storage and the importer

- [ ] `AppGroup.localPatternsURL`; `ChartLibrary.data(id:)`.
- [ ] `LocalPatternStore` actor: `manifests()`, `manifest(for:)`, `preview(for:path:)`, `save(_:)` writing to a temp directory and moving into place; an undecodable directory is skipped, not fatal.
- [ ] `BundleImporter`: read → store charts → save locally, in that order, nothing written before validation completes.
- [ ] `ProjectService.startProject` prefers `ChartLibrary` when it holds the chart id.
- [ ] `LocalPatternStoreTests`, and a `ProjectServiceTests` case starting a project with the stub client answering nothing.
- [ ] `mise run test`; commit `ios: store a local pattern and import a bundle into it`.

### Task 8: the Patterns tab and the open path

- [ ] `LibraryItem`; `AppModel.libraryItems`, `localPatterns`, local-first `manifest(for:)`/`preview(for:)`, `importBundle(data:)`, `importFailure`, `libraryPath`.
- [ ] `LibraryView`: two sections with headers that appear only when local patterns exist, the `Local` chip, the path binding; `PatternDetailView` takes a `LibraryItem`.
- [ ] `.onOpenURL` on `RootView`: security-scoped wrapper, the 64 MB size refusal, import, delete the Inbox copy either way; the alert; the `--import` launch argument in `GraphghanApp`.
- [ ] `BundleImportTests`: import stores both charts and shows the pattern; start a project offline; re-import updates and does not duplicate; a truncated bundle and a bad-chart bundle leave everything untouched and set the sentence; the inbox copy is deleted on both paths.
- [ ] `mise run test`; commit `ios: open a .graphghan bundle from Files, Mail and AirDrop`.

### Task 9: the simulator check

- [ ] `mise run generate`, build, launch with `--import <repo>/fixtures/bundle/craigh-na-dun.graphghan`; screenshot the Patterns tab, the detail screen, and a project started from it.
- [ ] Add the fixture to the simulator's Files and open it with "Open in Graphghan"; screenshot the share sheet entry and the result.
- [ ] Publish one review page with the screenshots side by side. **Check in with Tyler.**

### Task 10: docs and the PR

- [ ] `docs/chart-format.md` §Bundle rewritten (what it holds, stored, the fixed `updated`, the fixture) and an §Interchange bullet.
- [ ] `README.md` quick-start line; `ios/README.md` layout, data and a short section on opening a bundle.
- [ ] Blink review by hand on a scratch branch cut from main with the text-only diff applied (`fixtures/bundle/*.graphghan` excluded).
- [ ] `mise run check`, `mise run core-test`, `mise run test` all green; PR with `Closes #16`. **Check in with Tyler.**

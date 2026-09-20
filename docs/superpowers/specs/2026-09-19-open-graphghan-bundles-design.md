# Opening a .graphghan bundle: the writer, the reader, and a local pattern in the library

Date: 2026-09-19
Status: draft (awaiting review)
Builds on: `2026-09-10-graphghan-ios-app-design.md` §4.3 (the pattern manifest), §5.8 (the bundle,
defined and left unwritten) and §6 (the app's stores and screens); `docs/chart-format.md` §Bundle
and §Pattern manifest; `2026-09-19-pattern-pdf-import-export-design.md` §7.1 (the fixture
generator and drift test this one copies)
Evidence: `site/build.py` (the tree the writer zips and the manifest projection it reuses),
`ios/Graphghan/Storage/ChartLibrary.swift`, `ios/Graphghan/Network/PatternStore.swift` and
`ios/Graphghan/Services/ProjectService.swift` (what a pattern must look like before a project can
start from it), the file sizes measured in §3.2, and `.github/workflows/ci.yml` — pytest on
`ubuntu-latest`, the iOS jobs on `macos-26` — which is what decides §3.2
Closes the design step for: #16

## 1. Purpose

Nothing can reach the app but the site feed. A maker who has a pattern that is not published —
their own work in progress, one sent by a friend, one this repo produced but never pushed — has no
way to work it on the phone. #16 asks for the whole path: a writer that produces a `.graphghan`
file, a registration that makes iOS offer "Open in Graphghan" for it, a reader that gets the
charts in under the same validation a downloaded chart gets, and a place in the Patterns tab for a
pattern that is not on the site.

The format is already decided (`docs/chart-format.md` §Bundle): a zip with `pattern.json` at the
root plus the chart files and previews it references. Nothing here changes that. What is open, and
what this document settles, is four things:

1. How the writer makes the same bytes twice, when the manifest it writes carries a build time and
   the fixture it commits is diffed in CI on a different operating system than it was made on (§3.2).
2. How to read a zip on iOS, where Foundation has no zip reader (§4).
3. Where a local pattern is stored, given that it is the only copy of itself (§6.3).
4. Where a local pattern appears in the Patterns tab, which today knows only the site (§6.4).

#112 (a pattern PDF opened on the phone) waits on this and reuses the document-type registration,
the security-scoped read, and the local-pattern storage, with one more content type in front. It
is not designed for here; the only accommodation is that §6.1 and §6.2 are split at the seam
between "a file arrived" and "this file is a bundle", so a second type is a second reader and
nothing else.

## 2. What a bundle is

Unchanged from §5.8, stated completely so the reader and writer can be checked against one thing:

```
craigh-na-dun.graphghan          (a zip)
  pattern.json                   the manifest, schema 1, exactly as the site serves it
  preview.png                    manifest.preview
  charts/final-sc/chart.json     charts[0].path
  charts/final-sc/preview.png    charts[0].preview
  charts/final-hdc/chart.json    charts[1].path
  charts/final-hdc/preview.png   charts[1].preview
```

The bundle carries **exactly the files the manifest references** and nothing else. The site tree
also holds `chart.png` and `written-rows.txt` per chart; the manifest does not reference them, the
app does not read them, and leaving them out halves the file. The reader is name-addressed — it
looks up the entries the manifest names and never walks the archive — so a bundle from another
tool that does carry extra entries opens fine and the extras are ignored.

Paths are manifest-relative and are the same strings the site uses, so a bundle is literally the
site's `patterns/<slug>/` subtree minus the unreferenced files. That is the property worth keeping:
one manifest shape, one set of relative paths, whether it arrived over HTTPS or over AirDrop.

## 3. The writer

`graphghan export <slug> --format graphghan` writes `<pattern>/build/exports/<slug>.graphghan`.

### 3.1 The manifest comes from the site build, not from a copy of it

`site/build.py` already computes the manifest (`manifest()`), the published chart list in
`[publish]` order (`published_docs()`, `publish_order()`). A second implementation in the exporter
would be a second definition of the manifest, and the whole point of the bundle is that the app
cannot tell where the manifest came from.

So those three functions move to a new `src/graphghan/manifest.py` and `site/build.py` imports
them. The move is mechanical — they take a pattern directory and return data, and depend only on
`chartdoc.finished_size`, `pattern.load_pattern` and `publish.chart_key`, all of which are already
in the package. `index_entry()` stays in `site/build.py`: it shapes the site's listing, which a
bundle has no equivalent of.

`bundle.py` then reads the committed `dist/`, builds the manifest, and zips `pattern.json` plus the
files the manifest names, reading each from `patterns/<slug>/dist/` at the path the manifest gives
(`preview.png` and `charts/<key>/…` are the same relative layout in `dist/` and on the site).

A bundle is built from the **committed** `dist/`, never from a fresh render, for the same reason
`export --format pdf` is: what ships must be what `render --check` guards. A pattern with no
`dist/` gets the existing "run 'graphghan render' first" error.

### 3.2 Byte-reproducibility

Three things in a zip move on their own, and a fourth in the manifest.

**Entry timestamps.** Every entry gets a fixed `date_time` of 1980-01-01 00:00:00, the earliest a
zip can represent, with fixed external attributes (0o644) and a fixed create-system. Entries are
written in sorted name order.

**Compression.** Entries are **stored**, not deflated. This is the one decision here that is about
CI rather than taste: pytest runs on `ubuntu-latest` and the fixture is generated on a Mac, and
zlib's deflate output is deterministic for a given zlib build but not across builds — several
distributions now ship Python against zlib-ng, whose output differs byte for byte at the same
level. A deflated fixture would pass locally and drift in CI, which is the worst possible failure
for a drift test. Stored entries are identical everywhere.

The cost is size, and it is small, because the payload is mostly already-compressed PNG. Measured
on Craigh na Dun's two published charts: `preview.png` 15,065 + `charts/final-sc/preview.png`
15,065 + `charts/final-hdc/preview.png` 12,586 + `charts/final-sc/chart.json` 15,666 +
`charts/final-hdc/chart.json` 10,586 + the manifest ≈ **70 KB stored**, against roughly 55 KB
deflated. Well under the 5 MB the pre-commit large-file check allows, and immaterial over AirDrop.

The iOS reader still implements deflate (§5), because a bundle this repo did not write may well use
it and the cost is twenty lines over the `Compression` framework. The asymmetry is deliberate: be
strict in what you write, liberal in what you read.

**Zip64 and data descriptors.** Neither is used. `zipfile` will not reach for zip64 at these sizes,
and streaming descriptors only appear when writing to a non-seekable file; the writer builds into a
`BytesIO`. The reader refuses both rather than guessing (§5).

**`updated` in the manifest.** The site build stamps `datetime.now()`. A bundle cannot: the same
pattern exported twice must give the same bytes. There is no build time available in a checkout
that is stable across clones — git does not preserve mtimes, and shelling out to `git log` from the
exporter would make the output depend on repository state rather than pattern content. So a
bundle's manifest carries a fixed `updated` of `1980-01-01T00:00:00Z`, the same instant as the zip
entry timestamps, and `docs/chart-format.md` §Bundle says so. Nothing reads the field: the app
decodes it (`PatternManifest.updated`) and displays it nowhere, and version comparison is by
`pattern.version` and `chart.id`, never by date. A bundle is content, not a build.

### 3.3 CLI

`--format graphghan` joins the `choices` list in `cmd_export`. Two differences from the other
formats:

- `--chart` is refused: `a bundle is a whole pattern; drop --chart`, exit 2. Every other format
  exports one chart; a bundle carries the manifest, and a manifest with one of its charts missing
  would be a manifest that lies. (`--out` works as usual.)
- The default output name is the slug, not the chart key: `build/exports/<slug>.graphghan`.

### 3.4 Fixture and drift test

`fixtures/bundle/` mirrors `fixtures/import/`: a `generate.py` that writes one `.graphghan` per
pattern folder with a committed `dist/`, a `README.md` saying what they are for, and
`tests/test_bundle_fixtures.py` asserting the committed bytes equal a fresh generation and that no
stale fixture survives its pattern. One file today: `fixtures/bundle/craigh-na-dun.graphghan`.

It is committed because it is the iOS side's only real input — `GraphghanCore`'s bundle tests and
the app's import tests all open this file, the way the chart-format tests open
`fixtures/chart-format/`. It is also the reason a Blink review of this branch needs the scratch-branch
dance (`README.md`, "Agent code review"): a diff with a binary file in it is refused.

## 4. Reading a zip on iOS

Foundation has no zip reader. The two candidates named in #16:

**ZIPFoundation** (MIT, SwiftPM) is the obvious answer and is rejected, for two reasons.

The first is pinning. `Graphghan.xcodeproj` is generated by XcodeGen and gitignored, and
`Package.resolved` lives inside it — so a SwiftPM dependency added here has no committed lockfile
and no checksum anywhere in the repository. The version would live in `project.yml` alone, and
`exactVersion` pins a tag, not bytes. Every other third-party thing in this repo is pinned
*and* verified: `mise.toml` pins exact versions, `Scripts/update-blink-pin.sh` exists specifically
so a URL and a checksum are never edited by hand, and the README's Revyl section is three
paragraphs about refusing an unpinned install. A Swift dependency resolved fresh on every CI
machine would be the single exception, and it would be the one that parses hostile input.

The second is that the hardening has to be written either way. The input is a file from AirDrop or
a mail attachment: an attacker-shaped zip. Path traversal, absolute paths, entry counts, declared
sizes that do not match, decompression bombs — every one of those checks is ours to write on top of
whatever library reads the container, and ZIPFoundation's convenient API (`unzipItem(at:to:)`) is
the one that does the unsafe thing. Starting from a reader that only ever answers "give me the
bytes of the entry named X, up to N of them" removes the unsafe API instead of documenting it.

**A minimal reader in `GraphghanCore`** is what this builds: `ZipArchive`, read-only,
name-addressed, roughly 250 lines. It is a small, closed format — locate the end-of-central-
directory record, walk the central directory, and for a requested name read its local header and
slice the bytes — and it is exactly testable, because the writer is in this repository and a test
can generate adversarial archives with Python's `zipfile` and assert each is refused. `Compression`
(`COMPRESSION_ZLIB`, which on Apple's platforms is raw DEFLATE) supplies inflate. It lives in
`GraphghanCore` rather than the app target so that `mise run core-test` — a two-second `swift test`
on the macOS host, no simulator — covers the parser and the bundle reader together, which is what
#16's verification list asks for.

The trade is that we now own a zip parser. It is bounded: read-only, no zip64, no encryption, no
multi-disk, no streaming descriptors, and a refusal rather than a guess for each. If a future
bundle needs any of them, that is a fixture and a test, not a rewrite.

## 5. `ZipArchive` and `PatternBundle` in GraphghanCore

### 5.1 `ZipArchive`

```swift
public struct ZipArchive {
    public init(_ data: Data) throws          // parses the central directory only
    public var names: [String] { get }        // central-directory order
    public func contains(_ name: String) -> Bool
    public func data(named name: String) throws -> Data
}
```

Parsing: find the End of Central Directory record by scanning backwards from the end over the last
65,557 bytes for `PK\u{05}\u{06}`, take the entry count and the central-directory offset, then read
each central-directory header (`PK\u{01}\u{02}`): name, compression method, CRC-32, compressed and
uncompressed size, local-header offset, and the general-purpose flags. `data(named:)` reads the
local header (`PK\u{03}\u{04}`) at that offset to find where the data starts — the local header's
name and extra-field lengths are the only fields trusted from it, everything else comes from the
central directory — inflates when the method is 8, and verifies CRC-32 against the central
directory before returning.

Refused, each with its own error case:

| condition | why |
|---|---|
| no EOCD, truncated header, offset past the end | not a zip, or damaged |
| `disk number != 0`, multi-disk EOCD | not supported |
| EOCD64 locator present, or any 0xFFFFFFFF size/offset | zip64, not supported |
| general-purpose bit 0 set | encrypted |
| general-purpose bit 3 set (data descriptor) | sizes not known from the header |
| compression method other than 0 or 8 | not supported |
| name is not valid UTF-8, is absolute, contains `..` as a path component, or contains `\` | path traversal |
| name empty, or ends in `/` and has nonzero size | malformed |
| more than 1,024 entries | absurd for a bundle |
| any entry's uncompressed size above 32 MB, or the sum above 64 MB | decompression bomb |
| inflated bytes ≠ the declared uncompressed size, or CRC-32 mismatch | corrupt |

The size caps are checked against the *declared* sizes at parse time and enforced again against
the actual output of the inflater, so a lying header cannot get past the first check and a bomb
cannot get past the second.

### 5.2 `PatternBundle`

```swift
public struct BundleChart: Sendable {
    public let entry: ManifestChart
    public let chart: Chart
    public let data: Data          // the exact bytes, for ChartLibrary.store
}

public struct PatternBundle: Sendable {
    public let manifest: PatternManifest
    public let charts: [BundleChart]        // in manifest order
    public let previews: [String: Data]     // manifest-relative path -> PNG bytes
    public static func read(_ data: Data) throws -> PatternBundle
}
```

`read` opens the archive, decodes `pattern.json` as `PatternManifest`, then for every entry in
`manifest.charts`, in order: reads `entry.path`, loads it through `Chart.load` (the same decode and
validation a downloaded chart gets), and checks the decoded `chart.id` equals `entry.id`. It then
reads `manifest.preview` and every `entry.preview`. **Every path the manifest references must be
present**; a manifest that names a file the archive does not carry is refused, which is what #16's
verification asks for. Nothing partial is returned: `read` either produces a whole bundle or throws.

Additional refusals beyond `ZipArchive`'s: `manifest.schema != 1`; a manifest `id` that is not a
valid slug (`[a-z0-9-]+`, the same rule `site/build.py` enforces before it makes a directory out
of one — this id becomes a directory name on the phone); an empty `charts` array; two charts with
the same `path`.

`BundleError` is a flat `Error, Equatable` enum with a case per condition and a `message: String`
computed property giving the one sentence the app shows. Keeping the sentence in `GraphghanCore`
next to the condition is what makes "a broken bundle reports why" testable without a UI.

## 6. The app

### 6.1 From a tapped file to bytes

`ios/project.yml`, under the app target's `info.properties` (`Info.plist` is generated and
gitignored, so this is the only place it can go):

```yaml
LSSupportsOpeningDocumentsInPlace: false
UTExportedTypeDeclarations:
  - UTTypeIdentifier: com.tylervick.graphghan.pattern-bundle
    UTTypeDescription: Graphghan Pattern
    UTTypeConformsTo: [public.zip-archive]
    UTTypeTagSpecification:
      public.filename-extension: [graphghan]
CFBundleDocumentTypes:
  - CFBundleTypeName: Graphghan Pattern
    CFBundleTypeRole: Viewer
    LSHandlerRank: Owner
    LSItemContentTypes: [com.tylervick.graphghan.pattern-bundle]
```

The identifier is `com.tylervick.graphghan.pattern-bundle`, not the bundle id itself — a UTI equal
to a bundle identifier is a collision waiting to happen, and #112 will want a sibling. The tag
specification declares the filename extension only and **not** a MIME type: claiming
`application/zip` would make this app a candidate handler for every `.zip` anyone receives.
`LSSupportsOpeningDocumentsInPlace: false` is #16's decision and the right one — a bundle is
imported once and then owned by the library; there is nothing to write back.

Delivery is `.onOpenURL` on `RootView`'s scene content. With opening-in-place off, Files, Mail and
AirDrop all copy the file into the app's `Documents/Inbox/` and hand over that URL. The handler:

1. Wraps the read in `startAccessingSecurityScopedResource()` / `stopAccessing…`, balanced with
   `defer`. It is a no-op for an Inbox copy, and it is what #112 will need when a PDF arrives
   in place from a provider that does not copy.
2. Refuses a file above 64 MB by its size attribute before reading a byte.
3. Reads it with `Data(contentsOf:)`, imports (§6.2), and then deletes the Inbox copy — success or
   failure. Nothing else prunes `Documents/Inbox/`, and a maker who opens the same file three times
   should not accumulate three copies.

The split #112 inherits: `onOpenURL` gets bytes and a content type and hands them to an importer
chosen by type. Nothing above that line knows what a bundle is.

### 6.2 The import is atomic

`Services/BundleImporter.swift`, called from `AppModel.importBundle(data:)`:

1. `PatternBundle.read(data)` — every chart decoded, validated and id-checked, every referenced
   file present, all in memory. Anything wrong throws here, before a single byte has been written.
2. `ChartLibrary.store(_:)` for each chart's bytes. Keyed by chart id, so re-importing the same
   bundle rewrites the same files.
3. `LocalPatternStore.save(bundle)` — the manifest and previews, written to a temporary directory
   and moved into place with `replaceItemAt`, so a pattern directory is never half-written.
4. Reload `AppModel.localPatterns`, switch to the Patterns tab, and push the new pattern's detail
   screen.

Step 1 is what gives #16's "a broken bundle reports the reason and leaves the library untouched":
validation is complete before any mutation, rather than interleaved with it.

Re-importing an id that is already local replaces its directory wholesale — update, not duplicate.
Charts it no longer lists stay in `ChartLibrary`; a project started from the previous version pinned
a chart id and must keep opening. Nothing in the app evicts charts today, and this does not start.

### 6.3 Where a local pattern is stored

`AppGroup.supportURL/local-patterns/<id>/`, holding `pattern.json`, `preview.png` and
`charts/<key>/preview.png`. Chart JSON is not here — it goes to `ChartLibrary` under
`charts/<chart id>.json` like every other chart, which is #16's requirement and also gets dedup
with a site copy of the same chart for free.

**Application Support, not the pattern cache.** The obvious alternative — reuse
`Library/Caches/patterns/<id>/`, which already stores manifests and previews, and mark the entry
local — is wrong for one reason that outweighs the reuse: `Library/Caches` is purgeable. iOS
deletes cache directories under disk pressure, and for a site pattern that is free (the next
refresh re-downloads it), while for a local pattern it is data loss — the only copy of a pattern
the maker was given, gone, with a project still pointing at it. Application Support is backed up
and never evicted, which is what "the only copy" requires. The cost is that local patterns are not
subject to the cache's ETag machinery, which they have no use for anyway: there is nothing to
refresh against.

`LocalPatternStore` is an actor mirroring `PatternStore`'s shape, so `AppModel` talks to the two the
same way:

```swift
actor LocalPatternStore {
    init(directory: URL)
    func manifests() -> [PatternManifest]                 // sorted by title
    func manifest(for id: String) -> PatternManifest?
    func preview(for id: String, path: String) -> Data?
    func save(_ bundle: PatternBundle) throws
}
```

A directory whose `pattern.json` does not decode is skipped rather than fatal — the store answers
with what it can read.

**Resolution is local-first.** `AppModel.manifest(for:)` and `preview(for:)` check the local store
before the site store, by pattern id. A project started from a local pattern therefore resolves its
manifest without a network call and never sees a version notice from the site. The cost is that a
bundle whose id matches a published slug shadows the published pattern everywhere; nothing corrupts
(charts are content-hashed and a project opens the chart it pinned), but the site's update notice
goes quiet for it. Giving a local pattern an identity distinct from its slug means recording a
source on `Project`, which is a SwiftData migration and out of scope here: **#135**.

### 6.4 Where a local pattern appears in the Patterns tab

Its own section at the top of the list, headed **On this iPhone**, above the site patterns, which
gain the header **From graphghan.milo.cat**. Neither header appears when there are no local
patterns, so a maker who never opens a file sees exactly today's screen. A local row carries a
`Local` chip next to the title.

Why a section rather than one merged list: the two behave differently in ways a maker has to be able
to see. A site pattern updates when the feed updates and can always be re-downloaded; a local one
never changes, is not on the site, and is the only copy. Sorting them together would make "why
didn't this one update" unanswerable from the screen. Putting local first is because it is the
pattern the maker just added, and because there will rarely be more than a few.

Mechanically: `LibraryView` changes from `List(model.index)` to a `List` with two `Section`s, and
routing changes from `IndexEntry` to

```swift
struct LibraryItem: Hashable, Identifiable {
    enum Source: Hashable { case site, local }
    let entry: IndexEntry
    let source: Source
}
```

so `PatternDetailView` knows which store to ask. `IndexEntry` gains a public memberwise
initialiser and `IndexEntry(manifest:)` in `GraphghanCore` — the same projection `site/build.py`'s
`index_entry` makes, from the manifest and its default chart, with the cm→in conversion the site
does — so a local row is built from the same fields as a site row and renders through the same
`LibraryRow`. Putting that projection in `GraphghanCore` keeps it under `core-test`.

After a successful import the tab switches to Patterns and pushes the new pattern's detail screen,
which needs `LibraryView`'s `NavigationStack` to take a path binding off `AppModel`. Landing on the
pattern you just opened is the whole point of the gesture; a banner saying "added" and leaving the
maker to find the row is worse for two lines less code.

### 6.5 Starting a project from a local pattern

`ProjectService.startProject` fetches the chart with `patterns.chartData(for:path:)` — a network
call, which a local pattern has no answer for. The change is three lines: take the bytes from
`ChartLibrary` when it already holds that chart id, and only fetch otherwise.

```swift
let data = if await charts.hasChart(id: chart.id) { try await charts.data(id: chart.id) }
           else { try await patterns.chartData(for: manifest.id, path: chart.path) }
```

(`ChartLibrary` gains `data(id:)` beside `chart(id:)`.) Everything after that is unchanged,
including the `decoded.id == chart.id` check, which a library copy satisfies by construction since
the file is keyed by its own content hash. The same change makes starting a second project from a
site pattern work offline, which it does not today.

`Chart` browsing already prefers the library (`AppModel.browseChart` checks `hasChart` first), so
the detail screen and chart browser need nothing beyond the manifest and preview lookups in §6.3.

### 6.6 Errors

`AppModel.importFailure: String?`, set to `BundleError.message`, shown as an `alert` from
`RootView` titled "Couldn't open that pattern". The messages are sentences about the file, not
about the parser: "That file isn't a Graphghan pattern." for a non-zip; "This pattern's chart
final-sc is damaged: row 42 doesn't add up to 189 stitches." for a chart that fails validation;
"This pattern is missing the file it lists as charts/final-sc/chart.json." for a missing entry.
`GraphghanCore` owns the sentences (§5.2) and a core test asserts each case has one.

### 6.7 The launch argument

`--import <path>` in `ProcessInfo.processInfo.arguments`, read once in `GraphghanApp`'s scene
`.task`, imports that file as if it had been opened. It exists so the simulator check is a command
rather than a drag, and so an app test can drive the identical path. It does nothing in a release
build beyond what any argument does — it is a debug affordance, not a URL scheme, and cannot be
reached by another app.

## 7. Tests

**Python** (`tests/test_bundle.py`, `tests/test_bundle_fixtures.py`):

- Two calls to `to_bundle` on the same pattern give identical bytes.
- The archive opens with `zipfile`; `pattern.json` decodes and equals the manifest `site/build.py`
  produces for the same pattern with the fixed `updated`; every `charts[].path`, `charts[].preview`
  and `preview` is present and byte-equal to the file in `dist/`; there are no other entries.
- Every entry is `ZIP_STORED` with `date_time == (1980, 1, 1, 0, 0, 0)`; names are sorted.
- `export --format graphghan` writes the default path; `--chart` with it exits 2 with the message.
- The fixture drift test: committed bytes equal a fresh generation, and no fixture outlives its
  pattern.
- `site/build.py` still produces the same tree after the manifest functions move (the existing site
  tests cover this; they must pass unchanged).

**GraphghanCore** (`ZipArchiveTests`, `PatternBundleTests`, run by `mise run core-test`):

- Every refusal in §5.1's table, against archives a small Swift helper builds by hand plus the
  adversarial set generated into the test's temp directory.
- A deflated archive of the same content reads identically to the stored one (the reader's liberal
  half), and a CRC mismatch is refused.
- The committed `fixtures/bundle/craigh-na-dun.graphghan` opens: the manifest decodes, both charts
  load through `Chart.load`, their ids match the manifest, and both previews are non-empty PNG.
- A bundle whose manifest names a missing chart file is refused; a bundle whose chart fails
  validation is refused naming the chart; a bundle whose chart id disagrees with its manifest entry
  is refused.
- `IndexEntry(manifest:)` projects the fixture's manifest to the same values the site's
  `index.json` carries for that pattern.

**App** (`ios/Tests`, Swift Testing, in-memory SwiftData):

- Importing the fixture stores both charts in `ChartLibrary`, writes the local pattern, and the
  library shows it in the local section.
- Starting a project from the imported pattern succeeds with no HTTP client responses configured —
  the stub client records zero requests.
- Importing the same bundle twice leaves one local pattern and one set of chart files, with the
  second import's manifest winning.
- A corrupt bundle (truncated fixture bytes) and a bundle with a bad chart both leave
  `ChartLibrary` and the local store exactly as they were, and set `importFailure` to the sentence.
- The inbox copy is deleted after both a successful and a failed import.

**On the simulator**: `mise run generate`, then `plutil -p ios/Graphghan/Info.plist` shows
`CFBundleDocumentTypes` and the exported type; then the app launched with
`--import <repo>/fixtures/bundle/craigh-na-dun.graphghan`, and separately the file added to the
simulator's Files and opened with "Open in Graphghan". Screenshots of the Patterns tab with the
local section, the pattern detail, and a project started from it go on a review page (#16's second
check-in). AirDrop needs a device and is not part of the check; the type registration in the
generated plist is what it depends on.

## 8. Non-goals and follow-ons

Not in scope: #112 (a PDF as a second openable type), #134 (deleting a local pattern), #135 (a
local pattern whose id matches a site pattern). Exporting a bundle from the app, sharing one out of
the app, and a bundle that carries progress are none of them asked for by anything yet.

## 9. Success criteria

1. `uv run graphghan export craigh-na-dun --format graphghan` writes a file that `zipfile` opens,
   whose `pattern.json` the app decodes, and whose bytes are identical on a second run and in CI.
2. `fixtures/bundle/craigh-na-dun.graphghan` is committed, drift-tested, and is what both Swift
   test suites open.
3. `plutil -p ios/Graphghan/Info.plist` after `mise run generate` shows the exported type and the
   document type, and Files offers "Open in Graphghan" for a `.graphghan` file on the simulator.
4. Opening that file puts the pattern in the Patterns tab under "On this iPhone", with both charts
   in `ChartLibrary`, and a project starts from it with the network unavailable.
5. Opening it again updates the pattern and creates no second row. Opening a damaged one names what
   is wrong and leaves the library exactly as it was.
6. `mise run check`, `mise run core-test` and `mise run test` all pass.

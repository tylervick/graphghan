# Opening a pattern PDF on the phone

Date: 2026-09-20
Status: reviewed 2026-09-20 (Tyler), decisions in §10
Builds on: `2026-09-19-open-graphghan-bundles-design.md` (the file-open path, `LocalPatternStore`,
`ChartLibrary`, the atomic import), `2026-09-19-pattern-pdf-import-export-design.md` (the Python
importer: grid reader, prose contract, cross-check; §9 the on-device reader and its measurements),
`2026-09-10-graphghan-ios-app-design.md` §5 and §6.
Evidence: spec §9.1–§9.2 of the import design (815 of 903 breadth rows, Orca 77 of 77, Craigh na
Dun 177 of 184 on the on-device model); `ios/Packages/ProseReader` (the reader as it stands);
`src/graphghan/rasterchart.py`, `pdfself.py`, `importers.py` (what is to be ported).
Closes the design step for: #112

## 1. Purpose

A maker has a pattern PDF on the phone: bought on Etsy, downloaded from Ravelry, sent by a friend.
Today the only way to work it in the app is to send it to a Mac, run `graphghan import`, and send
the resulting bundle back. Nobody will take that step. This spec makes a PDF opened from Files,
Mail or AirDrop into a chart in the library, with a project startable from it exactly as from a
site pattern or a bundle, and with no Mac in the loop.

The Python importer settled the hard questions: what a chart read from a page must satisfy before
it is written, what the model can and cannot be trusted with, and how written rows and a grid
check each other. The phone does the same work with the same rules, in Swift, against the same
fixtures. What is different on the phone is time: the on-device model reads three to fifteen
seconds a row, so a chart that a page can give in two seconds must come from the page.

## 2. Decisions already made

- Written rows are read by the on-device Foundation Model through `ProseReaderKit`, unchanged in
  what it does: heads, ranges, repeats, run spellings, printed codes, totals, chunks of four, the
  invention filter. It moves into the app as a dependency, gains the iOS platform, and loses
  nothing (spec §9 of the import design; #145–#159).
- Nothing is written unless the whole chart validates through `GraphghanCore` (`Chart.load`), and
  a written row that disagrees with the grid is reported by number and never corrected (import
  design §6.3). The bundle importer's atomic order applies (bundle design §6.2).
- A PDF is registered as an openable type beside `.graphghan`; the security-scoped read, the Inbox
  copy and its removal, the size cap and the launch argument are #16's, reused (bundle design §6.1,
  §6.7).
- Private Cloud Compute stays off. The team lacks the managed entitlement; the reader's `.cloud`
  path exists and stays behind a flag nobody ships (import design §9). The Anthropic model is not
  in this spec.
- Deployment target stays iOS 17. Everything that needs no model (§4.1, §4.2) runs there; the
  model path is gated at run time (§7).

## 3. Non-goals and follow-ons

- #151: written rows printed as pictures (Canva-style PDFs, Outlander) need text recognition
  before any reader sees them. Designed here as a slot (§4.4), built as a follow-on.
- #43, #63, #69 (patterns in rounds): the reader and the grid reader assume rows of colour
  runs, as the Python importer does. Tunisian and mosaic have no chart shape in the format yet.
- The `Evaluations` framework, and the cloud model: after the entitlement, if ever.
- Editing a chart on the phone to fix a disagreeing row: the maker takes the chart as drawn or
  cancels (§5.4). Editing is its own feature.
- Charts from images (PNG, OXS, CSV) on the phone: the Python importer reads them; the phone reads
  PDFs. A PNG of a chart could go through §4.2 unchanged; not in scope.

## 4. Three readers, in order of trust and cost

A PDF is one of three things, decided per document from what its pages contain, and each has a
reader. The order below is the order the app tries them.

### 4.1 Our own PDF: exact, no model

`graphghan export --format pdf` writes a text layer with a fixed grammar: `KEY_ROW`
("{code}  {name}  {hex}  {yarn}"), `CHART_HEADER` ("Chart k of n: columns a-b of W, rows c-d of
H"), `DIRECTION`, and every written row as "Row N (RS): 189 Y (189 sts)" (import design §5, §6.4;
`pdf.py`, `pdfself.py`). `OwnPDFReader` in `GraphghanCore` takes the pages' text (PDFKit extracts
it in the app, §6.1) and rebuilds the chart exactly: the palette from the key, the rows from the
written rows, the dimensions from the chart headers. It is a port of `pdfself.py` (177 lines) and is deterministic:
the same PDF gives the same chart id every time, and that id equals the one the Python side
computed, which the round-trip test on `fixtures/import/craigh-na-dun-final-*.pdf` proves.

This path exists because it is cheap, exact, and the one every published pattern takes when a
maker mails a PDF of it to a friend. It is also the first thing that ships (§8).

### 4.2 A PDF with a chart: the grid first, the rows as the check

Most pattern PDFs carry a grid: a picture of the chart with one coloured cell per stitch. The
Python grid reader (`rasterchart.py`, 637 lines: gradient-run line finding, lattice fitting from
the pitch, cell sampling, palette clustering in Lab, the flat-cell carry, the box-row reader) is
ported to Swift as `GridReader` in `GraphghanCore`, on `vImage` and plain arrays rather than
numpy, with the same constants and the same test images. It reads a page rendered by PDFKit at
the importer's scale and answers what the Python one answers: a `Region` per grid found, and for
the chosen region the cells as palette indexes, the palette as hexes, and a noise figure.

On the phone the grid makes the chart. It takes seconds, and the maker sees a chart at once. The
written rows, when the pages have them, are then read by the model row by row as the check
(import design §6.3, the other way round): each row the model reads is compared with the grid's
row, and a disagreement is reported by row number, never applied. The check runs after the chart
is on screen and can be skipped or stopped; the chart is saved either way, with the check's
result recorded on it (§6.3).

Why the grid first here when the Python importer takes the rows first: time. The Python importer
runs on a Mac where a minute is nothing and the skill reads rows in one pass; on the phone the
rows take a minute per twenty and the grid takes two seconds. The rule that matters is kept: a
disagreement is never resolved by guessing, and the maker is told which rows.

### 4.3 A PDF with written rows and no chart: the rows, with a progress sheet

When no grid is found (Orca's front panel is text only; Outlander's chart is a picture the reader
cannot read), the rows are the only source. `ProseReaderKit.read(pages:)` reads them, the chart
is built from the rows alone (`_rows_alone` in the Python importer: width from the widest row,
height from the highest row number, palette from the key page), and validation is the width
check every row must pass. This takes minutes: Orca's 77 rows took three and a half, Craigh na
Dun's 184 would take forty-six. The sheet says so before it starts, shows the row count climbing,
and can be cancelled at any time with nothing written.

On the phone the reader also has to live within what the system will let an app ask of the model
(#176). Three things follow, and they apply to the check in §4.2 and to the rows-only path alike:
one session answers the whole read rather than one a row, turned over every 16 requests so the
transcript never fills the 4k window and at once if it ever reports that it has; a request the
model refuses as `GenerationError.rateLimited` is waited out and asked again, three attempts and
ten seconds of waiting in all; and once three requests running have been given up on, the waiting
stops, so a phone whose model will not answer costs a 310-row check seconds rather than an hour.
A read whose every lost row was lost to that refusal says so in one sentence rather than in 77
copies of the `GenerationError` text: the check in §4.2 records `the on-device model is busy` as
the record's `problem` (§6.3), whose sentence is "The on-device model is busy; try the check
again in a minute", and the rows-only path in §4.3, which writes no record because it never gets
as far as a chart, fails with that same sentence (`PDFImportError.modelBusy`). The screen is held awake for the length of a check or a
rows-only read. The session reuse is new since the breadth measurement (#146–#150), which was
taken with a session per row: #177 re-measures with it on.

### 4.4 A PDF that is pictures of text: not yet

A page with no text layer where the reader expected rows (page text under 200 characters while
the page holds an image) is reported as "this pattern's rows are printed as a picture; the app
cannot read that yet" and the import stops. #151 puts a text-recognition step in front of §4.3 for
those pages; the slot is `PageText.provider`, a protocol with one implementation today (PDFKit).

## 5. The app

### 5.1 From a tapped file to a reader

`project.yml` adds `com.adobe.pdf` to `CFBundleDocumentTypes` beside the bundle type. Files, Mail
and AirDrop then offer the app for a PDF, and `onOpenURL` receives it as it receives a bundle. The
copy in the Inbox, the size cap (20 MB for a PDF, against the bundle's), the security-scoped read
and the `--import` launch argument are #16's code with one branch on the file's type.

`AppModel.importPDF(data:)` renders nothing itself. It hands the bytes to `PDFImporter`
(`Services/PDFImporter.swift`), which decides the path:

1. If the first page's text matches our cover grammar, §4.1: read, validate, save, done.
2. Render each page and run `GridReader`; if a region of at least 8×8 cells with noise under the
   threshold is found on any page, §4.2. The render is budgeted before it happens: the scale is
   chosen from the page's media box so the bitmap is at most 40 million pixels (`MAX_PIXELS`, the
   Python importer's cap), starting from the importer's usual 4× and halving until it fits, and a
   page that would still exceed the cap at 1× is skipped with "page N is too large to read"
   rather than rendered. Pages are rendered one at a time and released before the next.
3. Else if any page holds row heads (`RowText.blocks` finds two or more), §4.3.
4. Else §4.4, or "no chart or written rows were found in this PDF".

### 5.2 The import sheet

A PDF is not a bundle: a bundle imports in under a second and either works or does not, so the
alert on failure is enough. A PDF has stages and can take minutes, so it gets a sheet, presented
over the Patterns tab the moment the file arrives:

- **Reading the pages**: a determinate bar over page count, a second at most.
- **Chart found** (§4.2): the chart preview, its size and colour count, and the row-check running
  underneath: "Checking written row 34 of 77…", with **Skip the check** and **Cancel**. The
  **Add to library** button is enabled as soon as the chart validates; tapping it before the
  check ends saves the chart with the check marked "not finished".
- **Reading written rows** (§4.3): "This pattern has no chart the app can read, so it is reading
  the 77 written rows. About 4 minutes." A determinate bar over rows, **Cancel**. When it ends:
  the preview, the size, and **Add to library**.
- **Something is wrong**: the sentence, one of the fixed set in §5.4, and **Done**.

The sheet is a `Sheet` route in `RootView` like the start-project sheet; its state is
`PDFImportState`, an `@Observable` the importer drives and tests read.

### 5.3 What is saved

The importer builds a chart document (schema 2) and a manifest (schema 1) in memory, both through
`GraphghanCore`, which gains the writers it lacks: `ChartDocument.encode(...)` producing the
canonical bytes whose `chart.id` `ChartID.compute` hashes (so a chart imported on the phone and
the same one imported on the Mac have the same id), and `PatternManifest.encode(...)` for a local
manifest with `schema: 1`, `id` from the PDF's title slugified (with a numeric suffix if taken),
`version: "0.1.0"`, `author`, `license` and `dedication` empty, `preview` and one `charts` entry.
The preview PNG is drawn from the cells with CoreGraphics at one pixel per cell scaled to 512 on
the long side, the same picture `export.py`'s `preview_png` draws.

Then the bundle importer's order (bundle design §6.2): `Chart.load` over the bytes it will store
(the same validation a downloaded chart gets), `ChartLibrary.store`, `LocalPatternStore.save`
with a `PatternBundle` assembled in memory, reload, switch to the Patterns tab, push the pattern.
The pattern's origin is recorded in the manifest's `dedication` field as "Imported from
<file name> on <date>"; the schema has no better place and the site never sees these.

Gauge: the reader's front-matter read supplies stitches, rows, over and hook when the pages print
a gauge; when they do not, the chart's gauge is the importer's default (14 sc and 16 rows over 4
inches) and the detail screen says "gauge not printed; using 14×16 over 4 in", which the
start-project sheet already lets the maker override.

### 5.4 What can go wrong, and the sentence for each

Each is one fixed sentence, tested, never a raw error:

| condition | sentence |
|---|---|
| file over 20 MB | That file is too big to be a pattern. |
| not a PDF PDFKit can open | That PDF couldn't be opened. |
| no grid, no row heads | No chart or written rows were found in this PDF. |
| rows are pictures (§4.4) | This pattern's rows are printed as a picture; the app can't read that yet. |
| rows only, and no model (§7) | Reading written rows needs Apple Intelligence on this iPhone. Open the PDF on a Mac with graphghan, or send a .graphghan file instead. |
| the chart does not validate | The chart in this PDF isn't one the app can work: <the validator's reason>. |
| some written rows disagree with the grid | Rows 12, 40 and 41 disagree with the chart. The chart is as drawn; check those rows against the PDF. |
| the maker cancelled | (no sentence; the sheet closes, nothing written) |

The disagreement case is not a failure: the chart is saved and the sentence is shown on the
pattern's detail screen under the preview, with the row numbers, until the maker dismisses it.

## 6. The code

### 6.1 Packages

- `ProseReaderKit` gains `.iOS(.v17)` in its platforms with every model-touching symbol already
  behind `@available(macOS 26.0, iOS 26.0, *)`; `RowText` and the document shape are available
  everywhere. The app links the library product; the `prosereader` tool stays a Mac tool.
- `GraphghanCore` gains `OwnPDFReader` (§4.1), `GridReader` (§4.2), `RowsChart` (the rows-alone
  builder and the cross-check, a port of `apply_prose`, `_rows_alone`, `cross_check`), the two
  writers (§5.3), and `PageText` (PDFKit page text with the provider slot). PDFKit is an app
  framework, so page rendering and text extraction live in the app's `PDFImporter` and hand
  `GraphghanCore` images and strings; `GraphghanCore` stays testable on macOS without a PDF.

### 6.2 The grid reader port

`rasterchart.py` is the one piece of real algorithmic work. It is ported function for function,
with the same names, the same constants (`EDGE_THRESHOLD`, `BRIDGE`, `MERGE_PX`, `MAX_SILENT`,
`MAX_NOISE`, `MAX_PIXELS`), and the same behaviour on the same images: each Python unit test
that renders a synthetic grid or reads a fixture page becomes a Swift test over the same PNG,
and the answer (regions, cells, palette, noise) must match the Python answer recorded beside the
image. Where Python uses numpy over the whole image, Swift uses `vImage` for the channel
differences and the box filters and `[UInt8]` loops for the rest; a page is at most 40
million pixels by the render budget in §5.1, and a page reads in under two seconds on an A-series
chip or the reader is not fast enough.

### 6.3 What the cross-check records

The row check's outcome goes into the chart document's `ext` (the format's `ext.graphghan`
namespace): `ext.graphghan.import = { source: "pdf", grid: true|false, check: <status>,
rows_checked: n, rows_disagree: [12, 40, 41] }`, where `check` is one of:

| `check` | meaning | detail-screen sentence |
|---|---|---|
| `finished` | every written row was read and compared | none, or the disagreement sentence (§5.4) |
| `stopped` | the maker tapped Skip the check or Add to library before it ended | "Written rows checked up to row N; N–M not checked." |
| `unavailable` | the device has no model (§7) | "Written rows not checked on this iPhone." |
| `none` | the pages have no written rows to check | none |

PR 3 (2026-09-20) added two fields: `rows_total`, the written rows the pages hold, so the stopped
sentence can say "N+1–M not checked"; and `problem`, present only when the rows could not be
compared at all (they do not assemble, the key pairs two chart colours with one code, or more than
a tenth of the rows disagree so the orientation is wrong), holding the Python importer's sentence;
the detail screen then says "Written rows could not be compared with the chart: <problem>". The
grid path's palette is the grid's own (codes by frequency, names by the nearest named colour); taking
the key's names once the check pairs them is #166.

Skipping and adding-before-the-end are one outcome, `stopped`, because they leave the same state:
rows up to `rows_checked` compared, the rest not. Cancel closes the sheet and writes nothing, so it
has no persisted state. Nothing but the detail screen reads `ext.graphghan.import`, and the chart
id ignores `ext`.

## 7. Gating

- iOS 17 and up: §4.1, §4.2 without the row check, and every failure sentence.
- iOS 26 and up with `SystemLanguageModel.default.availability == .available`: the row check in
  §4.2 and the rows-only path in §4.3. The check is offered, not forced: on a device without the
  model the chart from the grid is saved with `check: unavailable` (§6.3) and the detail screen
  says "Written rows not checked on this iPhone".
- The `#available(iOS 26, *)` guard sits in `PDFImporter`, in one place, around the reader's
  construction; `ProseReaderKit.unavailableReason()` supplies the sentence when the OS is new
  enough and the model is not there.

## 8. Delivery: three PRs, each usable alone

1. **The type and the exact reader.** `com.adobe.pdf` registered; `PDFImporter` with the §4.1
   path and the §5.4 sentences for everything it cannot do yet (a PDF that is not ours reports
   "No chart or written rows were found" until PR 2 and 3 land); the two writers; the preview
   drawer; the sheet with the "Reading the pages" and "Chart found" states; tests against the
   two own-PDF fixtures asserting the chart id equals the fixture's. A maker can open a PDF a
   friend exported. Three days.
2. **Written rows on the phone.** `ProseReaderKit` in the app; the §4.3 path with its progress
   and cancel; `RowsChart`; the §7 gating and its sentences; measured by hand on Orca on a device
   with Apple Intelligence (77 of 77, the same as the Mac tool) since the simulator has no model;
   unit tests for `RowsChart` over the real fixtures' `prose.json` files. Two days.
3. **The grid.** `GridReader` ported with its image tests; the §4.2 path with the check and the
   `ext` record; the detail-screen sentence. CI proves the port on the committed images (§9); the
   cactus, Santa and Orca-chart fixtures under `fixtures/import/real/` are gitignored (copyright),
   so reading them to the hashes pinned in `manifest.toml` is a manual gate run on the mini and
   recorded in this spec's §11 before the PR merges. A week.

## 9. Tests

- `GraphghanCore`: `OwnPDFReaderTests` (text in, chart out, id equal to Python's),
  `GridReaderTests` (image in, regions and cells out, against recorded Python answers, over
  synthetic grids and the two committed own-PDF pages rendered to PNG under `fixtures/import/`),
  `RowsChartTests` (prose.json in, chart out; the cross-check over Craigh's own rows and a
  deliberately wrong row), `ChartDocumentWriterTests` (encode then `Chart.load` then the id).
- App: `PDFImportTests` in the shape of `BundleImportTests`: the sheet's states for each path,
  every §5.4 sentence, cancel leaves the library untouched, and the saved pattern starts a
  project. The model paths are stubbed through a `RowReading` protocol the importer takes, so
  the sheet's row-progress states are tested without a model.
- By hand, on a device: Orca through §4.3 and the cactus blanket through §4.2, recorded in this
  spec's §11 when they run.

## 10. Decisions from review (2026-09-20)

1. Grid first on the phone (§4.2), the reverse of the Python importer's order, for the sake of
   time: agreed. The rule about disagreements is unchanged.
2. The rows-only path (§4.3) ships now, minutes long on-device, with the honest sentence in the
   sheet before it starts and the progress while it runs; the app is in beta and the maker can
   cancel. The cloud model shortens it if the entitlement ever lands.
3. The origin note borrows `dedication` (§5.3) for now; #161 is the manifest field that
   replaces the borrowing.
4. PR order stays as §8: the type and the exact reader, then the rows on the phone, then the grid.

## 11. Success criteria

- A `.pdf` exported by `graphghan export` opens from Files into the library in under two seconds
  with the same chart id the Mac computes. Measured 2026-09-20 on the iPhone 17 simulator: the read and
  save of the 184-row Craigh na Dun PDF take well under a second in `PDFImportTests` (PR 1).
- Orca's PDF opens into a chart of 29×77 with 77 rows read and validated, on a device with Apple
  Intelligence, in under five minutes, with progress shown and cancel working. The grid half was
  measured 2026-09-20 on the mini (iPhone 17 simulator, `PDFImportRealTests`, PR 3): both of page
  9's charts read to 29×77 and to the hashes the Python pinned, in 8.8 and 9.5 s for the whole
  nine-page PDF. The rows half (the check, 310 row heads on those pages) still needs an iPhone
  with Apple Intelligence; the simulator has no model. Not yet run on a device.
- The cactus blanket's PDF opens into the pinned 28×28 chart in under five seconds on iOS 17
  (a manual gate on the mini, §8; the fixture is not in the repository). Measured 2026-09-20 on
  the mini (PR 3): 28×28 from page 2 in 1.6 s, to the Python's hash. Santa's PDF, the other
  gitignored grid fixture: 56×56 in 0.7 s with the Python's eight colours in the same order, but a
  different rows hash, because two cells under the page's watermark that pdfium renders within the
  palette fold-in distance come out of PDFKit a few Lab units farther and stay as single-cell
  colours; the phone's hash is pinned beside the Mac's in `manifest.toml` and the fold-in rule is
  #167.
- Orca's check to completion on an iPhone with Apple Intelligence, 77 of 77 rows, is #176's
  acceptance test. Two device runs so far, neither of them a pass. The first (TestFlight, main at
  829014c) was refused with "Request has been rate limited". The second, 2026-09-21, carried the
  retry, the one reused session and the turnover of §4.3 and was refused again — so a session per
  row was not the cause — while the probe on the same phone answered a bare prompt in 1.9 s, the
  same prompt under the 1308-character instructions in 1.9 s and a structured row in 2.9 s, with
  the app active throughout. The refusal therefore follows the volume of requests rather than any
  one of them, and what the limit actually counts is being measured on the device
  (`LimitReport`) before the reader is paced to it. The time goes here when a run passes.
- Every failure in §5.4 shows its sentence and leaves the library untouched.

# Patterns made of pieces, and shaped rows

Date: 2026-09-25
Status: design agreed in conversation 2026-09-25 (Tyler), section by section; written spec for review
Builds on: `docs/chart-format.md` (chart schema 2, progress schema 1, manifest schema 1),
`2026-09-20-phone-pdf-import-design.md` (the phone importer; §11 the Orca check),
`2026-09-19-open-graphghan-bundles-design.md` (bundles, `LocalPatternStore`),
`2026-09-14-cell-cardinality-design.md` (the withholding rule this spec extends).
Evidence: Orca's PDF (gitignored, `fixtures/import/real/`), both page-9 charts read by
`graphghan.importers.import_file(page=9, region=1|2)`; PR #208 (#205, the no-stitch colour);
PR #209 (#206 small step, what the import left out).
Closes the design step for: #206 (the large step), #37

## 1. Purpose

A maker imports a bag on the phone and gets one flat rectangle labelled as the pattern. Orca, the
worked example, is a crossbody bag:

- a **front and a back panel**, charted side by side on page 9. Each is shaped: 9 stitches at row
  1, 29 at the widest, 3 at row 77, on a 29 × 77 grid whose other cells are a light blue
  (`#a4dade`) that nobody stitches;
- a **side panel** (the gusset), 6 stitches × 104 rows in three colour blocks, written only
  (page 10);
- a **dorsal fin**, two **pectoral fins** (front and back, different rows) and a **tail** made of a
  white and a black half, written only, in sc, dc and tr with extension chains
  (`ch 3, turn, + 2 sc`) (pages 11-12);
- a **strap** written as numbered steps ending "repeat step 3 until … desired length" (page 13);
- **finishing**: D-rings, lining and zipper, and sewing the fins and tail on at named rows
  (pages 13-16), mostly photographs with captions.

Today the phone keeps the front panel as a flat 29 × 77 rectangle, counts the light blue as
stitches, and drops everything else (#209 now says so). This spec says how the format holds shaped
rows and pieces, what a project made of pieces looks like, and how the phone's importer fills it.
The phone importer is the writer this round: the goal is that all of Orca arrives through the app.

## 2. What exists today

Stated plainly, because the design changes each of these:

- **Every row sums to `chart.width`.** `chartdoc.validate_document` (`chartdoc.py:182`) and
  `Chart.init` (`Chart.swift:142-147`) refuse anything else. `sequence()`, `WorkSequence`, the
  strip (`ChartBand.drawRow`), `stats.stitches = w × h` (`export.py:134`), `manifest.py:81`,
  `ManifestWriter` and the PDF writer all assume a full rectangle.
- **A manifest's charts are alternatives.** `charts` lists one pattern at several `variant` and
  `gauge_key` values, exactly one `default`; `StartProjectSheet` picks one; a `Project` works one
  `chartID` with one cursor. Nothing groups charts into parts of one object.
- **The no-stitch colour is a label.** PR #208 marks an imported chart's background
  `use: "no stitch"` (as the Python does from `chart.no_stitch`) and leaves it out of the colour
  count. `RowsChart.noStitch(of:)` decides it: the corner colour, only when every row keeps one
  unbroken run of other cells. The chart id ignores `use`, and nothing downstream reads it: the Work
  screen still walks those cells (#205 stays open for this spec).
- **Only the check knows shapes.** `RowsChart.crossCheck` (#203) lays a narrow written row on the
  cells off the background. That is the only shape-aware code.
- **The importer finds more than it keeps.** `GridReader.findRegions` returns both panels;
  `RowText.sections` finds nine sets of written rows on Orca (#209). `PDFImporter.readGrid` keeps
  the largest region.
- **The source PDF is not kept.** The local pattern holds the chart and the manifest only.
- **Readers refuse an unknown version cleanly.** `Chart.init` throws `unsupportedSchema` for any
  chart schema but 2, and `PatternBundle` says "made by a newer version of Graphghan" for any
  manifest schema but 1. A version bump is therefore a safe way to keep old readers from
  miscounting.

## 3. Decisions made in the conversation

1. **The phone importer is the writer.** The Python validates the new documents and computes their
   progress (it stays the conformance reference) but does not write them (#214).
2. **One project, many pieces.** Starting Orca makes one project holding every piece and the
   assembly; each piece keeps its own cursor; the maker picks which piece to work.
3. **A written-only piece is worked row by row:** the pattern's own text and its `[count]`, ranges
   expanded into rows, an open-ended row that counts up with no total. No cursor inside a row
   (#215).
4. **Progress is pieces done plus the current piece.** No project-wide percent: the strap has no
   total and written rows without counts have no stitch figure, so a whole-bag percent would be
   invented.
5. **The import shows a review list before saving:** rename, remove, reorder, `make × N`. No split,
   merge or add (#212).
6. **Shaped rows keep the rectangle.** The grid stays the picture; a palette colour marked as no
   stitch may only sit at the ends of a row; the chart schema goes to 3 so an old reader refuses
   rather than miscounts. Rejected: rows that sum to their own span with a per-row offset (every
   drawing path would rebuild the margins the picture already had), and inc/dec marks per cell
   (#216).
7. **Pieces live in the manifest**, schema 2. A manifest without `pieces` still means one piece.
8. **The source PDF is kept with the local pattern**, and assembly steps are its pages.

## 4. Non-goals and follow-ons

- #200: whether a server model is needed to name pieces and read assembly. This spec defines the
  interface it would plug into (§7.3) and nothing more.
- #210: a row with a gap (two stitched spans); refused by schema 3.
- #211: pieces written as numbered steps, not row heads (Orca's strap); left out and named.
- #212: split, merge and add in the review list.
- #213: alternative charts per piece.
- #214: the Python writing pieced patterns (import CLI, generator, site).
- #215: a stitch-level cursor for written rows.
- #216: how a shaping step is made, as chart data.
- #207: Python parity for the no-stitch colour count and the corner rule; #202: Python parity for
  the shaped cross-check. Both stand; this spec does not absorb them.
- #43, #63, #69: rounds. A piece worked in rounds is out of scope here, as it is for charts.

## 5. The format

### 5.1 Chart schema 3: shaped rows

A chart document at schema 3 is a schema 2 document with one addition and three rules.

**The no-stitch colour.** A palette entry may carry `"stitch": false` (default `true`). At most one
entry per chart may. The entry stays in the palette so the grid stays the picture; writers also
keep `use: "no stitch"` beside it as the human label (#208's value).

```json
"palette": [
  { "code": "A", "name": "Black", "hex": "#201b18" },
  { "code": "B", "name": "White", "hex": "#ffffff" },
  { "code": "C", "name": "Light blue", "hex": "#a4dade", "stitch": false, "use": "no stitch" },
  { "code": "D", "name": "Gray", "hex": "#737675" }
]
```

**Rules.**

- **One stitched span per row.** In every row of `rows`, no-stitch cells form at most a prefix and
  a suffix. The cells between are one non-empty unbroken span. A no-stitch cell between stitched
  cells, or a row of only no-stitch cells, cannot be worked as written: writers MUST NOT write it,
  readers MUST refuse it (§Design of `chart-format.md`). Both Orca panels satisfy this on every
  row (checked on the importer's output). #210 holds the gap case.
- **Rows still sum to `chart.width`.** `width` × `height` is the bounding box. Layer cells over
  no-stitch cells are not read.
- **Explicit `passes`** on a shaped chart list stitched runs only; a run of the no-stitch code is
  invalid.

**Sequencing** is §Technique and passes unchanged, except that runs of the no-stitch code are
left out. `x0` stays the grid column. Orca's front panel, grid row 76 (`6C9A14C`), becomes
`Row 1: RS, rtl, runs [{A, 9, x0 6}]`; row 2 (`5C9A2B13C`) becomes `WS, ltr, [{A, 9, x0 5},
{B, 2, x0 14}]`.

**Shaping is derived, never stored.** For pass *k* > 1, compare its stitched span with pass
*k − 1*'s, in grid columns, and name each edge in pass *k*'s reading direction: start is the
right edge on an `rtl` pass, the left on `ltr`. The change at each edge is a signed cell count.
Orca row 2 is "+1 at start, +1 at end"; row 7 (`rtl`) "+1 at start". The chart says how many
and where, not how (`1 inc` against `ch 3, turn, + 2 sc`); the pattern's own words for that are
the optional `written` text below, and as chart data they are #216.

**Numbers.** Everything that counted cells of the rectangle counts stitched cells:

| Number | Schema 3 |
|---|---|
| `stats.stitches`, `stats.cells`, `total_cells`, `WorkSequence.totalCells` | stitched cells (the sum of every pass) |
| `stats.counts`, `yards_est`, `skeins_364yd`, the manifest's `colors` and `stitches` | the no-stitch code left out |
| `color_changes_per_row`, `single_stitch_runs` | over stitched runs |
| `stats.size_in`, manifest `size` | the bounding box, as today, under the §Gauge pairing rule |
| foundation rule | `chain ≥ span(pass 1) + first_stitch_in − 1` |

The withholding rule of §Cells still applies on top: a non-`stitch` cell kind withholds the
stitch-named numbers exactly as before.

**Row text.** Optional top-level `written`: an array of strings, one per pass in pass order, the
pattern's own row instruction (Orca: `"R 2 [→]: (Black) ch 1, turn, 1 inc, 7 sc, (White) 1 inc
[11]"`). Readers show it beside the pass; it is not in the chart id, like `instructions`. Its
length MUST equal the pass count when present.

**Chart id.** The canonical object gains `"no_stitch": "<code>"` when the palette has a no-stitch
entry. It changes the sequence, so it changes the id.

**Versioning.** A writer emits schema 3 exactly when the palette has a no-stitch entry, and schema
2 otherwise, so every existing chart, bundle and fixture stays byte-identical. Readers that
implement this spec accept 2 and 3. A schema 2 chart carrying only `use: "no stitch"` (what #208
writes) stays a rectangle: the label is a label. Orca charts already imported on test phones stay
flat until re-imported; converting them in place would make one id mean two sequences.

`schema/chart.schema.json` changes `schema` from `const: 2` to `enum: [2, 3]`, adds
`paletteItem.stitch` and top-level `written`; the span rule is `chartdoc`'s and `Chart.init`'s, as
the row-sum rule is today.

### 5.2 Written-rows document (schema 1)

A piece that is not a grid: `pieces/<piece-id>.rows.json`.

```json
{
  "schema": 1,
  "id": "sha256:…",
  "piece": { "title": "Side panel" },
  "palette": [ { "code": "A", "name": "Black", "hex": "#201b18" },
               { "code": "B", "name": "White", "hex": "#ffffff" } ],
  "rows": [
    { "label": "R 1", "from": 1, "to": 1, "code": "A", "count": 6,
      "text": "(Black) ch 7, from the second stitch from the hook, 6 sc [6]" },
    { "label": "R 2 - R 26", "from": 2, "to": 26, "count": 6, "text": "ch 1, turn, 6 sc [6]" },
    { "label": "R 27 - 86", "from": 27, "to": 86, "code": "B", "count": 6,
      "text": "(White) ch 1, turn, 6 sc [6]. Check the alignment and adjust the work if necessary." },
    { "label": "R 87 - 104", "from": 87, "to": 104, "code": "A", "count": 6,
      "text": "(Black) ch 1, turn, 6 sc [6]. Check the alignment and adjust the work if necessary." }
  ],
  "source": { "pages": [10] },
  "notes": [ { "title": "", "text": "To change the color, finish off the last stitch in R 26 with white …" } ]
}
```

- `rows` entries: `label` (as printed), `from`, `to` (1-based, inclusive), `text` (verbatim),
  optional `count` (the printed stitch count after the row), optional `code` (a palette code, when
  the text names a key colour).
- `from`/`to` tile 1..N in order with no gap and no overlap. A gap is a transcription problem the
  importer reports by row number (§7.2); a document with one is invalid.
- The **last** entry may be open-ended: `"repeat": "until desired length"` (free text, as
  printed) and no `to`. Only the last.
- A pass is one row: an entry from 27 to 86 is 60 passes, each labelled `R 27 - 86 (k of 60)`.
- `id` is `"sha256:" + hex(sha256(canonical))` over `{"rows": [each entry's from, to, text, count,
  code, repeat]}` with the chart id's serialisation rules. Titles, palette names and notes are not
  in it.
- `schema/rows.schema.json` is new.

### 5.3 Manifest schema 2: pieces and assembly

```json
{
  "schema": 2,
  "id": "orca-crossbody-bag", "title": "Orca Crossbody Bag", "version": "0.1.0",
  "palette": [ "…" ],
  "charts": [
    { "id": "sha256:…front", "variant": "front", "gauge_key": "sc", "default": true, "path": "charts/front/chart.json", "…": "…" },
    { "id": "sha256:…back",  "variant": "back",  "gauge_key": "sc", "default": false, "path": "charts/back/chart.json", "…": "…" }
  ],
  "pieces": [
    { "id": "front", "title": "Front panel", "make": 1, "chart": "sha256:…front", "pages": [9, 17, 18] },
    { "id": "back",  "title": "Back panel",  "make": 1, "chart": "sha256:…back",  "pages": [9, 18, 19, 20] },
    { "id": "side",  "title": "Side panel",  "make": 1, "rows": "pieces/side.rows.json", "rows_id": "sha256:…", "pages": [10] }
  ],
  "assembly": [
    { "title": "Pages 13–16", "pages": [13, 14, 15, 16] }
  ]
}
```

- `pieces[]`: `id` (a slug, unique), `title`, `make` (≥ 1, default 1), exactly one of `chart` (a
  `charts[].id`) or `rows` (a path, with its `rows_id`), optional `pages` (pages of the source PDF).
  Order is the pattern's order. `pieces` is non-empty when present.
- In a manifest with `pieces`, `charts` lists the charts the pieces name, each once. They are not
  alternatives; alternatives per piece are #213. When `charts` is non-empty exactly one entry is
  `default`, as in schema 1: the first chart piece's chart, which the library card shows. A
  pattern whose pieces are all written has `charts: []`, no `default`, and the card shows the
  manifest's `preview` (or the title alone when it has none).
- `assembly[]`: `title`, optional `text`, optional `pages`. A step with only pages is a pointer
  into the source PDF (§5.5).
- A manifest without `pieces` is one piece: the default chart. Writers write schema 1 when there
  are no pieces, so every site pattern and committed bundle is unchanged.
- `schema/manifest.schema.json` is new (the manifest has had no schema file; this is the first,
  covering 1 and 2).

### 5.4 Progress schema 2

```json
{
  "schema": 2, "pattern_id": "orca-crossbody-bag", "pattern_version": "0.1.0",
  "pieces": [
    { "piece": "front", "copy": 1, "doc_id": "sha256:…front", "cursor": { "row": 42, "run": 3 }, "finished": null },
    { "piece": "side",  "copy": 1, "doc_id": "sha256:…side",  "cursor": { "row": 1 }, "finished": null }
  ],
  "current": { "piece": "front", "copy": 1 },
  "assembly_done": [],
  "started": "…", "finished": null,
  "events": [ { "t": "…", "piece": "front", "copy": 1, "row": 42, "run": 2, "kind": "advance" } ]
}
```

- One `pieces` entry per piece copy that has been started; `make: 2` gives copies 1 and 2.
- A chart piece's cursor and summary are progress schema 1's, per piece, over §5.1's sequence.
- A written piece's cursor is `{row, run: 0}`: `row` is the 1-based pass and `run` is always 0,
  and `stitch` is never written. The boundary position does not exist for a written piece; Done on
  its last row finishes it. `total_rows` is the last `to`, or
  absent when the last entry is open-ended. `percent` is rows done over `total_rows`, absent when
  open-ended. Stitch figures are emitted only when every entry has a `count` and the piece is
  closed; otherwise the keys are absent, per the §Cells rule.
- Project figures: `pieces_done`, `pieces_total` (the sum of `make`), `assembly_done`,
  `assembly_total`. No project percent (§3.4).
- Events keep schema 1's shape plus `piece` and `copy`: `{t, piece, copy, row, run, stitch?,
  kind}`, recording the cursor after the action. On a written piece `advance` and `back` move one
  row and `jump` any number, always with `run: 0`, so Python's `event["run"]` and Swift's
  `ProgressEvent.run` keep their types. An event without `piece` belongs to the single piece of a
  manifest without `pieces`.
- Sessions are split over all events by time as today. A session's `cells` is the sum, over the
  chart pieces its events touch, of each piece's cells-done difference across the session (the
  cursor before a piece's first event is that piece's cursor before the session, or row 1, run 0).
  Its `rows` is the same sum over written pieces, in rows. `stitches_per_hour` counts chart pieces
  only; written rows get no pace figure.
- Progress schema 1 stays valid for a single-chart project.

### 5.5 Bundle and source PDF

A `.graphghan` bundle of a pieced pattern carries the manifest, every chart and preview it names,
and every `pieces/*.rows.json`. It never carries the source PDF: a bundle carries nothing the
manifest does not name, and the PDF is someone else's. The phone keeps the PDF beside the local
pattern (`LocalPatternStore`, `source.pdf`), deleted with it. Where the PDF is absent (a bundle
opened on another phone), a step's pages read "page 15 of the original PDF".

## 6. The project and the Work screen

### 6.1 Storage

- New SwiftData `@Model PieceProgress`: `pieceID`, `copy`, `docID`, `cursorRow`, `cursorRun`,
  `cursorStitch`, `finished`, and `project`.
- `Project` gains `currentPiece: String?`, `currentCopy: Int` and `assemblyDone: [Int]`, all
  defaulted. `ProgressEvent` gains `piece: String?` and `copy: Int`.
- A single-chart project is unchanged: `currentPiece` nil, its existing cursor fields the only
  piece. Additive models and defaulted fields keep the store's lightweight migration
  (`Persistence.swift` has no `VersionedSchema`).

### 6.2 Starting and the project screen

- Starting a manifest-2 pattern starts the whole pattern; there is no chart picker.
- The project screen lists the pieces in order, then assembly:

  ```
  Front panel      chart   Row 42 of 77
  Back panel       chart   not started
  Side panel       rows    104 rows
  Dorsal fin       rows    Row 9 of 14
  Assembly                 0 of 1 steps
  ```

  A `make: 2` piece shows its copies ("1 of 2 done"); Orca has none, since its two pectoral fins
  and two tail halves are written differently and are separate pieces.
- Tapping a piece opens the Work screen on it and makes it current. Assembly is a checklist; a
  step with pages opens the source PDF at the first page.

### 6.3 Work screen, chart piece

- **Strip.** `ChartBand` draws no-stitch cells as the ground: no yarn colour, no hairlines, so the
  band follows the silhouette. `BandLayout` stays in grid columns, so alignment and mirroring are
  unchanged.
- **Panel and run list** cover stitched runs only, so Done never lands on a light-blue cell.
- **Header**: "Row 2 of 77 · 11 sts". Below it, the shaping line from §5.1 ("+1 at start, +1 at
  end"), hidden when nothing changes.
- **Row text**: when the chart carries `written`, the pass's text sits under the panel.
- `ChartImage` and `ChartPreview` draw no-stitch cells clear, so the card shows the shape.

### 6.4 Work screen, written piece

- No strip. The row's `text` large, its `[count]`, and the label: "R 27 - 86 · 5 of 60".
- Done, Back and Jump move by rows (passes). Header "Row 31 of 104".
- An open-ended row counts up ("Row 57", no total) and offers "Finish piece".

### 6.5 Finishing, progress figures, intents

- Doing the last row finishes a piece; the app offers the next unfinished piece. The project is
  finished when every piece copy and every assembly step is done.
- Projects list, `ProjectEntity`, the snippet and the Live Activity read
  "Front panel · Row 42 of 77 · 3 of 8 pieces". Their `percent` is the current piece's (cells for
  a chart, rows for a closed written piece, none when open-ended).
- `MarkDoneIntent`, `AdvanceRunIntent` and `BackRunIntent` act on the current piece;
  `WorkIntentDialog` says "Front panel, row 42, run 3". `WorkActivityInfo` carries the current
  piece's totals.

## 7. The importer

### 7.1 Find

The same finding #209 counts: every region of at least 8 × 8 that `GridReader.findRegions` finds
on any page is a chart candidate (Orca: 2, both on page 9); every `RowText.sections` run is a rows
candidate (Orca: 9). Each chart region gets its no-stitch colour from `RowsChart.noStitch(of:)`
(#208) and is written at schema 3 when it has one.

### 7.2 Pair, then parse

- **Pairing.** A chart region's own rows are the colour sections as tall as the region.
  Regions are taken in reading order (page, then left to right); height-matched sections in
  document order; the *k*-th region gets the *k*-th section. On Orca the left region (front) gets
  pages 17-18 and the right (back) pages 18-20. Pairing is code and needs no model.
- **A paired section** becomes the chart's `written` text (the row heads and text as `RowText`
  splits them) and its cross-check, run through `RowReading` and `RowsChart.crossCheck` as today,
  once per chart piece, in order, with progress and cancel. Each chart piece gets its own
  `ImportRecord`. A wrong pairing shows as a failed check, which the sheet names by piece; the
  importer does not re-pair.
- **Unpaired sections** become written-piece candidates, parsed by code: row heads and ranges as
  `RowText` splits them (`R 2 - R 26`, `R 27 - 86` → `from`/`to`), a trailing `[n]` →
  `count`, a leading `(Black)` → `code` when the key names that colour. A section whose heads leave
  a gap is reported by row number and offered anyway; the maker may remove it.

### 7.3 Outline, and where #200 plugs in

Steps 7.1-7.2 produce a `PatternOutline`:

```swift
struct PatternOutline {
    var pieces: [PieceOutline]       // title, kind: .chart(regionIndex) | .rows(sectionIndex), make, pages
    var assembly: [AssemblyOutline]  // title, text?, pages
    var leftOut: [String]            // what was found and not offered, for the sheet's sentence
}

protocol PieceReading: Sendable {
    func outline(pages: [String], found: FoundParts) async -> PatternOutline
}
```

`FoundParts` is the regions, sections and pairing from 7.1-7.2. This round's conformer is code
only (`FoundOutline`):

- **Titles**: the label nearest a region (page 9 prints "Front" and "Back" under its charts) or
  the nearest heading-like line to a section; otherwise "Chart 2 (page 9)" or "Rows, page 11,
  R 1–14".
- **Assembly**: pages no piece used, proposed as one step per run of consecutive pages
  ("Pages 13–16").
- **Left out**: anything found that is not a piece, in #209's sentence. Orca's strap is numbered
  steps, which `RowText` does not find (#211); the sheet does not invent it.

A server reader from #200 would conform to `PieceReading` and pre-fill the same list with better
titles, the strap and real step text. Nothing after the outline changes.

### 7.4 Review list

Under the sheet's existing "N × M stitches, K colours" and the check: every piece (title, kind,
pages, rows, check result for charts) and every assembly step. The maker can rename, remove,
reorder and set `make × N`, and then save. A single chart with nothing else found shows no list
and saves exactly as today.

### 7.5 Save

One manifest-2 local pattern: one chart per chart piece (schema 3 when shaped), one
`pieces/<id>.rows.json` per written piece, `assembly`, and `source.pdf` beside it. Every chart and
rows document validates before anything is written; the bundle importer's atomic order applies.
A single found chart saves as manifest 1, as today.

## 8. Delivery: three PRs, each usable alone

1. **Shaped chart pieces.** Schema 3 in `chart-format.md`, `chart.schema.json` and fixtures;
   `chartdoc` validate, sequence and stats; `progress` over stitched cells; `Chart.init`,
   `WorkSequence`, `ChartBand`, `ChartImage`, `ManifestWriter` in Swift; the importer writes
   schema 3 for the one chart it keeps. Orca's front panel imports as 9 → 29 → 3, 3 colours, and
   the Work screen's row 1 is 9 stitches. Waits on #208.
2. **Pieces.** Manifest 2, the rows document and progress 2 (format, schemas, Python validation
   and progress math, fixtures); `PatternBundle` reads manifest 2; `PieceProgress`; the project
   screen, the written-piece Work screen, finishing and intents. Proven with a committed pieced
   fixture bundle; no importer change.
3. **The importer.** Pairing, parsing, `PatternOutline` and `FoundOutline`, the review list,
   keeping the PDF, saving manifest 2. Proven on Orca in `PDFImportRealTests`.

## 9. Tests and fixtures

Changing the format starts with a fixture (`chart-format.md` §Conformance). Orca cannot be
committed, so the fixtures are hand-built in its shape:

- `fixtures/chart-format/shaped-basic/`: a small shaped chart (grows by one at each edge, then
  narrows) with the expected sequence, shaping lines and progress summary.
- Refusal fixtures: a no-stitch cell between stitches (#210's case), a row of only no-stitch, two
  no-stitch codes, a foundation shorter than pass 1's span, `written` of the wrong length.
- `fixtures/chart-format/pieces-basic/`: a manifest 2 with a chart piece, a closed rows piece with
  a range, an open-ended rows piece and `make: 2`; a progress 2 document; the expected summary.
  Refusals: a rows gap, an open-ended entry that is not last, a piece naming a chart not in
  `charts`.
- `fixtures/bundle/`: one pieced bundle, drift-tested like the rest.
- Real: `PDFImportRealTests` pins Orca's outline (2 chart pieces, both schema 3, their spans; the
  written pieces found; the strap in the left-out sentence), skipping when the PDF is absent. The
  Python `test_import_real.py` keeps the flat hashes it pins today (#214).

Python and Swift both run every fixture, as today.

## 10. Success criteria

- Every existing chart, bundle and fixture reads unchanged and hashes the same.
- Orca's PDF, opened on the phone, offers a review list with the front and back panels as shaped
  chart pieces (pass 1 is 9 stitches at `x0` 6, the widest 29, pass 77 is 3; 3 colours each), each
  with its own check, the written pieces `RowText` finds, proposed assembly pages, and the strap
  named as left out. Saved, it starts one project whose Work screen shows row 1 of the front
  panel as 9 stitches with no light blue, and whose Projects row reads "Front panel · Row 1 of 77 ·
  0 of N pieces".
- A written piece can be worked from row 1 to its last, through a range, and an open-ended one
  can be finished by hand.
- The Orca import's total time, both checks included, is recorded in this section on its first
  device run (the phone spec's §11 left its timing open).

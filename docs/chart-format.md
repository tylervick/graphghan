# Graphghan chart format

Version: chart schemas 2 and 3, written-rows schema 1, progress schemas 1 and 2, pattern manifest
schemas 1 and 2. JSON Schemas live in `schema/`; conformance fixtures in `fixtures/chart-format/`.
This document is normative where the schema cannot be (sequencing, ids, progress math).

## Design

A chart document describes one grid at one gauge. It is layered so that a reader that only knows
the palette and cells can still display it, and readers MUST ignore unknown keys at every level.
Nothing in the file is in inches except the gauge block; sizes are derived.

Nobody should be able to work a chart that cannot be crocheted as written. A document that is
*provably* unworkable — rows that do not sum to the width, runs off the grid, a foundation shorter
than the first row — is invalid: writers MUST NOT write it and readers MUST refuse it rather than
warn. Unusual but possible values are not errors.

One cell is one stitch unless the chart says otherwise. That is a real restriction, not a
simplification: the academic survey classifies this object as a "crochet graph" and limits the genre
to patterns "that are flat and whose arrangement of stitches matches a grid" (Seitz et al., Onward!
2022). Genres where a cell is a block, a tile, a motif or a stitch pair say so in `chart.cell`, and a
reader that does not implement the stated kind MUST withhold every stitch-derived number rather than
compute it wrongly. The chart still opens and is still worked: it is the arithmetic that is
withheld, not the pattern.

## Chart document (schemas 2 and 3)

```json
{
  "schema": 2,
  "pattern":  { "id": "craigh-na-dun", "title": "Craigh na Dun Blanket", "version": "1.0.0",
                "author": "Tyler Vick", "license": "CC-BY-NC-SA-4.0", "dedication": "For Meaghan",
                "quote": "...", "url": "https://graphghan.milo.cat/patterns/craigh-na-dun/", "craft": "crochet", "language": "en" },
  "chart":    { "id": "sha256:…", "variant": "final", "gauge_key": "sc", "width": 189, "height": 184 },
  "generator": { "name": "graphghan", "version": "0.2.0" },
  "palette":  [ { "code": "Y", "name": "Gold", "hex": "#D9A21B",
                  "yarn": { "brand": "", "line": "", "colorway": "", "weight": "4", "lot": "", "note": "Gold" },
                  "thread": { "system": "DMC", "number": "783" }, "use": "moon, border", "symbol": "*" } ],
  "rows":     [ "189Y", "1Y187G1Y", "…" ],
  "layers":   { "stitch": { "legend": { "k": "knit", "p": "purl" }, "rows": [ "189k", "…" ] } },
  "gauge":    { "stitches": 14, "rows": 16, "over": { "value": 4, "unit": "in" }, "unit": "stitches",
                "stitch": "sc", "stitch_name": "single crochet", "terms": "US",
                "boundary": { "kind": "turn", "chain": 1, "counts_as_stitch": false, "color": "next" },
                "hook": "5 mm (US H-8)", "yarn_weight": "4" },
  "foundation": { "chain": 190, "first_stitch_in": 2, "note": "in Gold (Y)" },
  "technique": { "type": "rows", "start": "bottom", "first_side": "RS", "rs_direction": "rtl", "turn": true },
  "passes":   [ { "label": "Row 1", "side": "RS", "direction": "rtl", "grid_row": 183,
                  "runs": [ { "code": "Y", "count": 189, "x0": 0 } ] } ],
  "instructions": [ { "title": "Setup", "text": "Foundation: chain W + 1 in Gold (Y).\nCh 1, turn …" } ],
  "stats":    { "…": "derived, optional, recomputable" },
  "ext":      { "graphghan": { "report": { "panel": [ 0, 0, 0, 0 ] } } }
}
```

Required: `schema`, `pattern.id`/`title`/`version`, `chart.id`/`width`/`height`, `palette`, `rows`,
`gauge.stitches`/`rows`/`over`, `technique.type`. `layers`, `passes`, `instructions`, `stats`, `ext`
are optional.

### Palette and cells

- `code` matches `^[A-Za-z]{1,3}$` and is unique. Codes differing only by case are legal but the
  Python validator warns: they are easy to misread at the hook.
- `hex` is `#RRGGBB`. `yarn` is always an object with optional string fields `brand`, `line`,
  `colorway`, `weight`, `lot`, `note`. `thread` is `{system, number}` for floss systems.
- `rows` has exactly `chart.height` run strings, top to bottom as displayed. A run string matches
  `^(\d+[A-Za-z]{1,3})+$`; counts in a row sum to `chart.width`; every code is in the palette.
  Because a run always starts with digits, `7YB` is one run of code `YB`, never two runs (schema 3
  adds a no-stitch colour; see §Shaped rows).
- `layers` are extra grids in the same encoding with their own `legend`; a reader that does not
  know a layer ignores it.
- A layer's legend describes each cell as it looks on the **right side** of the work (the CYC rule
  for crochet and knit chart symbols), so a knit legend of `{"k": "knit", "p": "purl"}` reads
  correctly on a WS pass. Readers do not enforce this yet (#36).

### Cells

`chart.cell` is optional. When present it is an object with `kind` required:

```json
"chart": {
  "id": "sha256:…",
  "width": 60,
  "height": 80,
  "cell": { "kind": "block" }
}
```

`kind` is one of `stitch`, `block`, `tile`, `motif`, `pair` — the five cardinalities the genre
matrix found:

| `kind` | One cell is | Genre | Probe |
|---|---|---|---|
| `stitch` | one stitch | tapestry, intarsia, cross-stitch, stranded knit | `tapestry.md` |
| `block` | a filled or open block, sharing an edge post | filet | `filet.md` |
| `tile` | a `ch 3 + 3 dc` tile | C2C (#18) | `c2c.md` |
| `motif` | a whole worked square | motif-grid blanket | `joined-rounds.md` |
| `pair` | two stitches, one per layer | double knitting | #44 |

Absent means `stitch`. No document written before this key existed carries it, and absent is
always valid.

The enum is closed, matching `gauge.unit` and `boundary.kind`. A value outside it fails schema
validation and the document is refused — which is correct: an unrecognised cardinality is a
document a writer did not produce for this format and a reader cannot reason about at all. The
withholding rule below is for kinds that are *in* the enum and not yet implemented, which today is
every kind but `stitch`.

`schema/chart.schema.json` carries the property under `chart.properties`; `chart`'s `required`
list is unaffected.

What a reader emits is a per-number rule, not a per-document one. A number that counts **cells**
is always honest and is always emitted. A number that counts **stitches** is emitted only when
`kind` is `stitch`; otherwise the key is absent rather than wrong.

| Number | Where | `kind: stitch` | any other kind |
|---|---|---|---|
| `stats.cells` | `export.py` | `w × h` | `w × h` |
| `stats.stitches` | `export.py` | `w × h` | **key absent** |
| `stats.yards_est`, `stats.skeins_364yd` | `export.py` | emitted | **key absent** |
| `stats.counts`, `single_stitch_runs`, `color_changes_per_row` | `export.py` | emitted | emitted (per-cell, honest) |
| `stats.size_in` | `export.py` | follows the gauge/cell pairing in §Gauge — **key absent** when the size does not derive | follows the gauge/cell pairing in §Gauge — **key absent** when the size does not derive |
| `total_stitches` | `progress.py` | emitted | **key absent** |
| `total_cells` | `progress.py` | emitted | emitted |
| `stitches_done` / `cells_done` | `progress.py` | both | `cells_done` only |
| `percent` | `progress.py` | unchanged | unchanged — cells done over cells total is the same arithmetic either way |
| `stitches_per_hour` | `progress.py` | emitted | **key absent** |
| `WorkSequence.totalCells` | `WorkSequence.swift` | emitted | emitted |
| `WorkSequence.totalStitches: Int?` | `WorkSequence.swift` | `totalCells` | **nil** |

`stats.cells` and `total_cells` are emitted for every chart including `stitch` ones, where they
equal the stitch figures: they are the honest name for what the number has always counted.

Because the enum is closed and an out-of-enum kind is refused outright, adding a sixth kind is a
breaking change for every reader already in the field — a document carrying it fails to open at
all, not even degraded. That is the intended trade for refusing an unrecognised cardinality rather
than guessing at it, but it means a new kind is not an additive, optional change the way `cell`
itself was: it belongs with a schema version bump.

### Shaped rows (schema 3)

A shaped piece (a bag panel that grows from 9 stitches to 29 and back to 3) keeps its grid as the
picture: every row still sums to `chart.width`, and `width × height` is the bounding box. One
palette entry may carry `"stitch": false`; its cells are the ground nobody works. Writers keep
`use: "no stitch"` beside it as the human label.

- **At most one** palette entry is `"stitch": false`.
- **One stitched span per row.** No-stitch cells form at most a prefix and a suffix of a row; the
  cells between are one non-empty unbroken span. A no-stitch cell between stitches, or a row of
  only no-stitch cells, cannot be worked as written: writers MUST NOT write it, readers MUST
  refuse it (#210 is the case of a row with a gap).
- **Layer cells over no-stitch cells are not read.**
- **Explicit `passes`** list stitched runs only; a run of the no-stitch code is invalid.
- **Sequencing** leaves the no-stitch runs out; `x0` stays the grid column.
- **Shaping is derived, never stored.** For pass *k* > 1 compare its stitched span with pass
  *k − 1*'s in grid columns; name each edge in pass *k*'s reading direction (start is the right
  edge of an `rtl` pass, the left of an `ltr` one). The change is a signed cell count: "+1 at
  start, +1 at end". How a stitch is added or removed is not in the chart (#216).
- **Numbers** that counted the rectangle count stitched cells: `stats.cells`, `stats.stitches`,
  `total_cells`, `counts`, `yards_est`, `skeins_364yd`, `color_changes_per_row`,
  `single_stitch_runs`, and the manifest's `colors` and `stitches`. `stats.size_in` and the
  manifest `size` stay the bounding box. The foundation rule reads the stitches of pass 1 (the
  first explicit pass when the chart lists passes, else the grid row pass 1 works):
  `chain ≥ stitches(pass 1) + first_stitch_in − 1`.
- **`written`**, optional at either schema: an array of strings, one per pass in pass order, the
  pattern's own row instruction. Readers show it beside the pass; it is not in the chart id. Its
  length MUST equal the pass count.

A writer emits schema 3 exactly when the palette has a no-stitch entry, and schema 2 otherwise,
so a rectangle is byte-identical to what it always was. `"stitch": false` in a schema 2 document
is refused: a schema 2 reader would count those cells. A schema 2 chart whose palette says only
`use: "no stitch"` is a rectangle; the label is a label.

### Gauge

`stitches` and `rows` over `over.value` `over.unit` (`in` or `cm`), the way gauge is stated on a
pattern. Derived values: cell aspect = `stitches / rows`; finished width (when the pairing rule
below allows) = `width / (stitches / over.value)` in `over.unit`, likewise height. `unit` says what
`stitches` and `rows` count —
`stitches` (default), `tiles`, `repeats` or `rounds`. A finished size is derived only when `unit`
and `chart.cell.kind` name the same thing: `stitches` with `stitch`, or `tiles` with `tile`. Both
fields default and their defaults pair, so a chart that states neither is sized as stitches over
stitches, as it always was. Any other combination — a mismatch, or `repeats` (#39) and `rounds`,
whose relationship to a grid cell is not stated — derives no finished size, and readers MUST omit
it rather than compute one. `stats.size_in` follows the same rule.

`stitch` is the abbreviation the chart is worked in; `stitch_name` its spelled-out name, required
when `stitch` is not in the CYC master list and ignored when it is (a chart cannot rename `sc`).
`terms` is `US` or `UK`; absent means `US`. A reader MUST NOT spell out an abbreviation under the
wrong system. `terms_also` names the other system when the written instructions carry both; readers
spell out from `terms` only.

`boundary` is what happens at the end of a pass, authored and never derived:

- `kind` (required): `turn` — turn the work (flat rows); `join` — close the round with a slip
  stitch; `rejoin` — fasten off and start the next pass at the same edge (overlay mosaic,
  one-direction tapestry); `spiral` — continuous rounds, nothing happens; `return` — Tunisian, the
  return pass is the boundary. Readers implement `turn` today and show nothing for the rest.
- `chain` (required): chains made at the boundary; `0` is legal.
- `counts_as_stitch`: default `false`.
- `color`: `next` or `current`. Absent means unstated; a reader says nothing about colour rather
  than guess.

`pattern.craft` (`crochet`, `knit`, `tunisian`, `cross-stitch`) and `pattern.language` (BCP 47)
are optional; absent means unstated.

### Foundation

Top-level, optional: `{ "chain": 190, "first_stitch_in": 2, "note": "in Gold (Y)" }`. `chain` is
the authored foundation chain count and `first_stitch_in` the 1-based chain from the hook where
the first pass's first stitch goes. Both are authored. A foundation with extra chains for an edge
is legitimate; one with fewer than `stitches(pass 1) + first_stitch_in - 1` chains — where
`stitches(pass 1)` is the width, unless the chart is shaped — cannot be worked, and readers MUST
refuse the document (see §Design).

### Chart id

`chart.id` is `"sha256:" + hex(sha256(canonical))` where `canonical` is the UTF-8 JSON of
`{"codes": [palette codes in order], "rows": rows, "technique": technique}` plus `"passes"` when the
document has them and plus `"cell"` when the document has it and it is an object, plus `"no_stitch"`
(the code) when the palette has a `"stitch": false` entry, with keys sorted, no whitespace (`,` and
`:` separators only) and non-ASCII kept as-is. Names, hexes, yarn,
instructions and stats do not affect the id: renaming a color is not a new chart. Readers may verify
the id; writers MUST compute it this way.

### Technique and passes

A technique maps the grid to an ordered list of passes; each pass is an ordered list of runs. The
progress cursor is `{ "row": <1-based pass index>, "run": <0-based run index> }` for every
technique, because C2C patterns already call a diagonal a row.

A cursor may carry `stitch`, the number of cells of run `run` already worked, `0 ≤ stitch <
count`; absent means 0. `run` equal to the pass's run count is the boundary position: every run
worked and the end-of-pass action (the turn) not yet taken, with `stitch` 0. A completed run is
the next run at stitch 0, never `stitch == count`.

Pass shape (explicit `passes` use the same keys; `side`, `direction`, `grid_row`, `x0` optional):

```json
{ "label": "Row 12", "side": "RS", "direction": "rtl", "grid_row": 172,
  "runs": [ { "code": "Y", "count": 7, "x0": 182 } ] }
```

`grid_row` is the 0-based row index into `rows` (top is 0); `x0` is the leftmost grid column of the
run regardless of reading direction.

- `rows`: pass `k` uses grid row `height - k` when `start` is `bottom` (default), else `k - 1`.
  Sides alternate from `first_side` (default `RS`). RS passes read `rs_direction` (default
  `rtl`); WS passes read the opposite. Runs are the run-length encoding of that grid row in
  reading order, so a right-to-left pass lists runs reversed. Label `Row k`. `turn` is
  informational (true for flat work); what to do at the turn — how many chains, whether they
  count — is `gauge.boundary`.
- `rounds`: as `rows` but every pass is `first_side` and reads `rs_direction`. Label `Round k`.
- `c2c`: reserved. Treat as unknown until a later revision defines it with fixtures.
- `none` and any other type: no derivable order. Display only, unless `passes` is present.
- `passes`, when present, override derivation whatever `type` says.

### Instructions, stats, ext

`instructions` is an ordered list of `{title, text}`; `text` is plain text where newlines separate
steps. `stats` is optional and always recomputable. `ext` is a map of vendor name to anything;
`ext.graphghan.report` is generator-private test scaffolding.

## Written-rows document (schema 1)

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
  importer reports by row number (§7.2 of the pieces spec); a document with one is invalid.
- The **last** entry may be open-ended: `"repeat": "until desired length"` (free text, as
  printed) and no `to`. Only the last.
- A pass is one row: an entry from 27 to 86 is 60 passes, each labelled `R 27 - 86 (k of 60)`.
- `id` is `"sha256:" + hex(sha256(canonical))` over `{"rows": [each entry's from, to, text, count,
  code, repeat]}` with the chart id's serialisation rules. Titles, palette names and notes are not
  in it. An absent optional key is left out of its entry, never written as null.
- `schema/rows.schema.json` is the schema.

Derived numbers: `total_rows` is the last entry's `to`, absent when the piece is open-ended.
`total_stitches` is emitted only when the piece is closed (has a `total_rows`) and every entry
carries a `count`; otherwise the key is absent, the same withholding rule as §Cells.

## Progress document (schemas 1 and 2)

### Schema 1

```json
{ "schema": 1, "pattern_id": "craigh-na-dun", "chart_id": "sha256:…", "pattern_version": "1.0.0",
  "cursor": { "row": 42, "run": 3, "stitch": 10 }, "started": "2026-09-12T18:04:00Z", "finished": null,
  "events": [ { "t": "2026-09-12T18:31:12Z", "row": 42, "run": 2, "kind": "advance" } ] }
```

`kind` is `advance`, `back` or `jump`; every event records the cursor **after** the action;
`stitch` is optional on both and absent means 0; writers omit it when 0. `chart_id` may be `null`
for a cursor imported from a source that did not know it. Derived values, as implemented by
`graphghan.progress` and pinned by the `progress-basic` fixture, follow the same split as §Cells:
a number that counts cells is always emitted, and a number that counts stitches is emitted only
when a cell is a stitch (`chart.cell` absent, or `kind: "stitch"`). The `progress-stitch` fixture
pins an offset inside a run, a boundary position, a Back onto that boundary, and a jump into a
run.

- Always emitted: `cells_done` = cells in every earlier pass + runs before `run` in the current
  pass + `stitch`; `total_cells` = cells in every pass; `percent` = 100 × `cells_done` /
  `total_cells`, one decimal — the same arithmetic regardless of kind. Events are sorted by `t`.
  A session is a maximal run of events with gaps ≤ 20 minutes; a session's `cells` is the
  difference in cells-done between the cursor after its last event and the cursor before its
  first event (the cursor before the very first event is row 1, run 0), clamped at 0.
  `active_seconds` is the sum of each session's last − first timestamp.
- Emitted only when a cell is a stitch: `stitches_done` and `total_stitches` (`cells_done` and
  `total_cells` under their stitch names — the same numbers), each session's `stitches` (the same
  number as that session's `cells`), and `stitches_per_hour` — total session stitches over active
  hours, one decimal, or `null` with no active time. For any other kind these four keys are absent
  rather than computed from the wrong cardinality.

### Schema 2 (pieces)

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
- A chart piece's cursor and summary are progress schema 1's, per piece, over the chart's
  sequence.
- A written piece's cursor is `{row, run: 0}`: `row` is the 1-based pass and `run` is always 0,
  and `stitch` is never written. The boundary position does not exist for a written piece; Done on
  its last row finishes it. `total_rows` is the last `to`, or absent when the last entry is
  open-ended. `percent` is rows done over `total_rows`, absent when open-ended. Stitch figures are
  emitted only when every entry has a `count` and the piece is closed; otherwise the keys are
  absent, per the §Cells rule.
- Project figures: `pieces_done`, `pieces_total` (the sum of `make`), `assembly_done`,
  `assembly_total`. No project percent.
- Events keep schema 1's shape plus `piece` and `copy`: `{t, piece, copy, row, run, stitch?,
  kind}`, recording the cursor after the action. On a written piece `advance` and `back` move one
  row and `jump` any number, always with `run: 0`. An event without `piece` belongs to the single
  piece of a manifest without `pieces`.
- Progress schema 1 stays valid for a single-chart project.

Each piece copy carries a running state — its cursor and whether it is finished — that persists
across events and across a session gap. After an event, the copy's `finished` is true exactly when
that event is a **finishing advance** — an `advance` on a written piece that leaves its row
unchanged — and false after any other event (an ordinary advance, a back, or a jump). Un-finishing
and re-finishing a piece across a gap without moving its row adds no rows to either session.

Two rules follow from that state:

- **Rows done** at a written cursor is `row − 1`, or all of the piece's rows once it is finished
  (`row` for an open-ended piece, since it has no total).
- A session's `rows`, for a written piece, is rows done at the copy's state at the end of the
  session minus rows done at its state before the session — the copy's state after its last
  earlier event, or row 1, unfinished, before any — never below 0. A session's `cells` is the same
  difference over chart pieces, in cells. An event naming a piece the manifest does not know is
  skipped outright (it opens no session and updates no running state); an event for a known piece
  with no `pieces[]` summary entry still counts.

`stitches_per_hour` is chart-piece stitches — over every session that touched a chart piece —
divided by those sessions' active seconds; written rows carry no pace figure.

## Pattern manifest (schemas 1 and 2)

### Schema 1

Written by the site build as `patterns/<id>/pattern.json`: identity, `palette` (code, name, hex),
`preview`, `charts` (one per published chart: `id`, `variant`, `gauge_key`, `default`, `path`,
`preview`, `width`, `height`, `size {width, height, unit}`, `stitch`, `colors`, `stitches`,
`changes_per_row {mean, max}`, `yards_est`), and `updated`. Exactly one chart is `default` and it
is the one also served as `chart.json` at the pattern's top level. `size` (and the top-level
index's `size_in`) is governed by `gauge.unit` the same way `stats.size_in` is (#48): key absent,
not a placeholder, when the chart's gauge and cell kind do not pair.

### Schema 2 (pieces and assembly)

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
  `charts[].id`) or `rows` (a path, with its `rows_id`), optional `pages` (pages of the source
  PDF). Order is the pattern's order. `pieces` is non-empty when present.
- In a manifest with `pieces`, `charts` lists the charts the pieces name, each once. They are not
  alternatives; alternatives per piece are a later change. When `charts` is non-empty exactly one
  entry is `default`, as in schema 1: the first chart piece's chart, which the library card shows.
  A pattern whose pieces are all written has `charts: []`, no `default`, and the card shows the
  manifest's `preview` (or the title alone when it has none).
- `assembly[]`: `title`, optional `text`, optional `pages`. A step with only pages is a pointer
  into the source PDF (see §Bundle).
- A manifest without `pieces` is one piece: the default chart. Writers write schema 1 when there
  are no pieces, so every site pattern and committed bundle is unchanged.
- `schema/manifest.schema.json` is the first schema file for the manifest, covering schemas 1
  and 2.

## Bundle

A `.graphghan` file is a zip with `pattern.json` at its root plus the chart files and previews it
references at their relative paths -- the pattern preview, and per published chart its
`chart.json` and `preview.png`. It carries nothing the manifest does not name; readers address
entries by name and ignore any extras, so a bundle from another tool that also packs
`written-rows.txt` opens fine. A pieced bundle also carries every `pieces/*.rows.json` its
manifest names, and never the source PDF.

`graphghan export <slug> --format graphghan` writes one, and `fixtures/bundle/` commits one per
pattern with a drift test. The output is byte-reproducible, which fixes two things a zip would
otherwise let drift:

- Entries are **stored**, not deflated, with a fixed 1980-01-01 timestamp, mode 0o644 and sorted
  names. Stored because zlib's deflate output is deterministic for one zlib build but not across
  builds, and the committed fixture is generated on macOS and diffed by CI on Linux. Readers still
  accept deflate.
- `updated` is fixed at `1980-01-01T00:00:00Z`, the same instant. The site build stamps it with
  the build time; a bundle has no build time that is stable across clones, and nothing reads the
  field. A bundle is content, not a build.

The iOS app registers `com.tylervick.graphghan.pattern-bundle` (conforming to `public.zip-archive`,
extension `graphghan`) and opens one from Files, Mail or AirDrop: `GraphghanCore`'s `PatternBundle`
reads it, validates every chart the same way a downloaded one is validated, and the pattern joins
the Patterns tab as a local pattern. See
`docs/superpowers/specs/2026-09-19-open-graphghan-bundles-design.md`.

## Interchange

- **PNG, one pixel per stitch** (`graphghan export --format png`): palette hexes, no grid. Imports
  1:1 into Stitch Fiddle and any pixel editor. Requires distinct hexes.
- **OXS** (`--format oxs`): Ursa Software's Open Cross Stitch XML. Palette index 0 is the cloth;
  chart colors are 1..n; every cell is a `<stitch x y palindex>` with 0-based coordinates from the
  top-left; `stitchesperinch`/`stitchesperinch_y` come from the gauge. Working order is not
  representable in OXS.
- **CSV** (`--format csv`): `height` lines of `width` comma-separated codes, top to bottom.
- **PDF** (`--format pdf`): a printable pattern (cover, key, the chart tiled across pages at 10 pt
  cells with bold lines every 10, written rows). Real text throughout; the chart page headers, key
  rows and written rows are in grammars fixed in `graphghan/pdf.py` so the importer can read them
  back. Byte-reproducible; `fixtures/import/` commits one per published chart.
- **Bundle** (`--format graphghan`): the whole pattern as one file -- the manifest plus the charts
  and previews it references -- for opening on a phone. See §Bundle above.
- **Import** (`graphghan import <file> --into <slug>`): the reverse of all four. OXS and CSV are
  read as written; a PNG is one pixel per cell unless a grid covers it, in which case it is read
  like a PDF chart page: grid lines found by their edges, cell centres sampled, colours clustered
  or snapped to a `--palette`. A graphghan-made PDF is stitched back from its page headers and key,
  and reads its own written rows. For any other pattern the prose (key, gauge, sizes, written rows)
  arrives as a `prose.json` in the `graphghan-import/1` shape (`schema/import-prose.schema.json`),
  written by the graphghan skill; written rows are the chart when present and the picture is the
  cross-check, and a row that does not sum to the width is reported by number, never fixed.

## Conformance

A reader claims conformance when, for every fixture in `fixtures/chart-format/`, it validates the
chart against `schema/chart.schema.json`, reproduces the expected sequence (or its SHA-256), refuses
to sequence the unknown-technique fixture while still decoding it, reproduces the expected
progress summary, and reproduces `shaped-basic.shaping.json` from the sequence it derives for
`shaped-basic`; reproduces `pieces-basic/progress.expected.json` from `pieces-basic/progress.json`.
Changing the format starts with a fixture.

Every `*.chart.json` document under `fixtures/chart-format/refused/` is otherwise valid — it still
validates against `schema/chart.schema.json` — but a reader MUST refuse it for the one reason
named in its `ext.fixture.refuses`. The same directory also holds five more refusals in the
pieces shape, each otherwise valid against its own schema: a reader MUST refuse
`refused/rows-gap.rows.json` (a gap between two rows entries) and
`refused/rows-open-not-last.rows.json` (an open-ended entry that is not last) against
`schema/rows.schema.json`, and `refused/piece-names-missing-chart.pattern.json` (a piece naming a
chart not in `charts`), `refused/chart-no-piece-names.pattern.json` (a chart no piece names) and
`refused/default-not-first-chart-piece.pattern.json` (a default chart that is not the first chart
piece's) against `schema/manifest.schema.json`.

# Graphghan: what one cell is

Date: 2026-09-14
Status: approved design (reviewed in conversation), awaiting spec review
Builds on: `2026-09-12-pattern-data-model-design.md` (the `boundary` object this copies)
Genre evidence: `docs/research/genres/` — `filet.md`, `c2c.md`, `joined-rounds.md`, `README.md`
Closes the design step for: #44 (part 1)

## 1. Purpose

The format assumes one grid cell is one stitch. That assumption is never written down and never
checked, so a chart from a genre where it is false — filet, C2C, a blanket of motifs — validates
clean and then reports a wrong stitch count, a wrong percentage, a wrong yarn estimate and a wrong
time estimate. Nothing refuses; nothing warns.

`docs/research/genres/README.md` grades every probe as *works*, *refuses*, *silently wrong* or
*partly*, and filet is the single **silently wrong** verdict in the matrix. That grade is the
problem this design removes. The tenet behind #50 — a maker must never be able to work a project
that is not physically viable — has an arithmetic half: a maker must never be handed numbers the
format cannot actually compute. Refusing is acceptable. Lying is not.

Part 1 is this document: declare the cardinality, state the assumption out loud, and stop emitting
the numbers that depend on it. Actually *working* a non-stitch genre is part 2 and stays out
(section 6).

## 2. What is wrong today

Three independent code paths encode cell = stitch, and all three are reached by any chart that
opens:

- `src/graphghan/export.py:112` — `"stitches": int(w * h)`. Chart-level stats. `yards_est` and
  `skeins_364yd` below it scale from `cell_sqin`, so they inherit it.
- `src/graphghan/progress.py:18` — `total_stitches` sums `run["count"]` over every pass. Run
  counts are cells, so the progress document's `total_stitches`, `stitches_done`, `percent` and
  `stitches_per_hour` are all cell counts wearing a stitch name.
- `ios/.../WorkSequence.swift:40,61` — `Pass.stitches` reduces run counts and `totalStitches` sums
  them. `Pace.swift:31` and `LiveActivityState.swift:71` read that total, so the Work screen, the
  pace figures and the Live Activity all inherit it.

The site repeats the assumption in prose: `site/src/app/pattern.js:31` labels the grid
`'stitches × rows'` and `:100` asserts `Every row totals ${chart.W} stitches`.

For the corpus as it stands every one of these is correct, because Craigh na Dun is tapestry and
one cell really is one stitch. They are correct by luck, not by construction.

`docs/research/genres/filet.md` works the arithmetic for the counter-case: a filet row of *n*
blocks is `2n + 1` or `3n + 1` posts depending on the variant, plus chains, with adjacent blocks
sharing an edge post. There is no multiplier that makes `w × h` right.

## 3. Decisions

1. **The declaration is `chart.cell`, an object with a required `kind`.** Not the plural `cells`
   the issue proposed: `Chart.cells: [UInt8]` (`ios/.../Chart.swift:41`) is already the decoded
   grid buffer, and `docs/chart-format.md` §"Palette and cells" already uses the plural for the
   rows encoding. The singular also reads as the question it answers — what one cell *is*.
2. **An object, not a bare string**, copying `gauge.boundary` rather than `gauge.unit`. Part 2
   needs per-genre parameters (filet alone wants `stitches_per_filled`, `chains_per_open`,
   `shared_edge`), and they land as siblings of `kind` without a breaking change. `boundary`
   shipped in Phase 1 on exactly this bet.
3. **A reader that does not implement a `kind` still opens the chart.** A filet chart is
   physically workable — "6 blocks" is a real instruction at the hook — so refusing the document
   would be a wider rule than the tenet states. What gets withheld is the arithmetic, not the
   chart. This follows `gauge.unit`, where an unimplemented unit derives no finished size and the
   rest of the gauge still loads.
4. **A number that counts stitches is absent unless `kind` is `stitch`.** Absent, not zero, not
   null, not renamed in place. A missing key cannot be misread; a wrong number can.
5. **`cell` participates in `chart.id` when present**, on the rule `passes` already follows.

## 4. Phase 1 (normative)

### 4.1 Schema

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

Absent means `stitch`. No existing document gains the key, and none needs editing.

The enum is closed, matching `gauge.unit` and `boundary.kind`. A value outside it fails schema
validation and the document is refused — which is correct: an unrecognised cardinality is a
document this repo's writers did not produce and cannot reason about at all. The suppression path
in §4.3 is for kinds that are *in* the enum and not yet implemented, which is every kind but
`stitch`.

`schema/chart.schema.json` gains the property under `chart.properties`. `chart` keeps its existing
`required` list unchanged.

### 4.2 `chart.id`

§Chart id becomes: canonical is the UTF-8 JSON of `{"codes", "rows", "technique"}`, plus
`"passes"` when the document has them **and plus `"cell"` when the document has it and it is an
object** — the same presence-and-type guard `passes` uses on both sides
(`chartdoc.py:36`, `ChartID.swift:16`).

`chart_id()` gains a `cell: dict | None = None` keyword; `ChartID.compute` gains `cell:
JSONValue?`. Every existing id is byte-identical, because no existing document carries the key.
Two charts with the same grid and different cardinalities stop colliding, which is true of the
objects they describe.

### 4.3 Readers: what is withheld

The rule is per-number, not per-document. A number that counts **cells** is always honest and is
always emitted. A number that counts **stitches** is emitted only when `kind` is `stitch`.

| Number | Where | `kind: stitch` | any other kind |
|---|---|---|---|
| `stats.cells` (new) | `export.py` | `w × h` | `w × h` |
| `stats.stitches` | `export.py:112` | `w × h` | **key absent** |
| `stats.yards_est`, `stats.skeins_364yd` | `export.py` | emitted | **key absent** |
| `stats.counts`, `single_stitch_runs`, `color_changes_per_row` | `export.py` | emitted | emitted (per-cell, honest) |
| `stats.size_in` | `export.py` | emitted | emitted — governed by `gauge.unit` (#48), not by this |
| `total_stitches` | `progress.py:18` | emitted | **key absent** |
| `total_cells` (new) | `progress.py` | emitted | emitted |
| `stitches_done` / `cells_done` (new) | `progress.py` | both | `cells_done` only |
| `percent` | `progress.py:61` | unchanged | unchanged — cells done over cells total is the same arithmetic either way |
| `stitches_per_hour` | `progress.py:66` | emitted | **key absent** |
| `WorkSequence.totalCells` (renamed) | `WorkSequence.swift:52` | emitted | emitted |
| `WorkSequence.totalStitches` (now `Int?`) | `WorkSequence.swift:52` | `totalCells` | **nil** |

`stats.cells` and `total_cells` are emitted for every chart including `stitch` ones, where they
equal the stitch figures. They are the honest name for what the number has always counted.

The progress *summary* is not schema-governed: `schema/progress.schema.json` covers the persisted
event log (`schema`, `pattern_id`, `chart_id`, `cursor`, `events`) and says nothing about the
derived summary. That shape is pinned by `fixtures/chart-format/progress-basic.progress.expected.json`
and by the Swift `ProgressSummary` decoder, and both move together. No schema file changes for
progress, and no progress version number is in question.

On the Swift side the arithmetic is untouched — it is the cursor's denominator and the Work screen
cannot function without it — but the name moves to what it counts. `WorkSequence.totalStitches`
becomes `totalCells`, with `Chart.cellKind: CellKind` (defaulting to `.stitch`) decoded from
`chart.cell.kind` and a computed `totalStitches: Int?` that returns `totalCells` for `.stitch` and
nil otherwise. `Pace.ProgressSummary` takes the same pair and omits `stitchesPerHour` for a
non-stitch kind.

Two constraints on that rename, both load-bearing:

- **`WorkActivityInfo` keeps the wire key `totalStitches`.** It is `Codable` and crosses a process
  boundary into the Live Activity extension, where an activity started before an app upgrade is
  still running and will decode with the old key. The Swift property is renamed to `totalCells`;
  `CodingKeys` pins the encoded name to `totalStitches`. The wire format does not move.
- **`ProgressSummary` is the cross-language conformance surface** for the progress document — it
  decodes `total_stitches` and `stitches_done` directly (`PaceTests.swift:11`). Those become
  optional on both sides together, and the fixture expectations move with them.

No new screen and no new UI surface. Two existing labels read their noun from the kind instead of
hard-coding "stitches": `ProjectDetailView.swift:26` ("Stitches, 3 of 24" → "Blocks, 3 of 24") and
the Work screen's on-deck line, which today says "then 6 O" for six *what* — the run count is
blocks and the worker makes posts (`docs/research/genres/filet.md`).

### 4.4 Generator and validation

`validate_document` gains a check in the §50 family: if `chart.cell` is present it must be an
object with a `kind` in the enum, reported by field and type when it is not — the `else:` branch
shape that #55 is about, applied correctly from the start.

`write_dist` refuses to emit a `stats` block containing a withheld key, so the generator cannot
write a document that contradicts §4.3.

`pattern.toml` gains no surface in Phase 1. Nothing in the corpus authors a non-stitch chart, and
inventing the authoring path before a real pattern needs it is how the `gauge.unit` field ended up
with no author (`docs/chart-format.md` §Gauge, "nothing authors one").

### 4.5 Documentation

`docs/chart-format.md`:

- §Design states the assumption in the same breath as the workability rule: the format describes a
  grid whose cells are worked in order, one cell is one stitch unless the chart says otherwise,
  and a reader that does not implement a stated cardinality withholds every stitch-derived number
  rather than computing it wrongly. Seitz et al. (Onward! 2022) classify this object as a "crochet
  graph" limited to patterns "that are flat and whose arrangement of stitches matches a grid";
  §Design says so and cites it, so the niche is stated rather than implied.
- A new §Cells subsection under Chart document carries the table from §4.1 and the withholding
  rule from §4.3.
- §Chart id takes the normative edit from §4.2.

### 4.6 Fixtures and tests

- `fixtures/chart-format/filet-blocks.chart.json` — the Bella Coco pattern hand-encoded in
  `docs/research/genres/filet.md`, `cell.kind: "block"`, with its `.sequence.json`. It sequences
  fine; the point of the fixture is that it opens and that the stitch-derived keys are absent.
- `fixtures/chart-format/filet-blocks.stats.expected.json` — the withheld-key set, asserted by
  key absence rather than by value.
- A Python test that `chart_id` is unchanged for every existing fixture, pinning §4.2's
  compatibility claim rather than asserting it in prose.
- A Swift conformance test over the new fixture, and the existing cross-language id test extended
  to a document carrying `cell`.
- `docs/research/genres/README.md` moves filet from **silently wrong** to **refuses** with this
  document cited, which is the state change the matrix asks every probe to force.

### 4.7 Compatibility

No existing document changes. No existing id changes. `schema/chart.schema.json` takes one
additive, optional property, so chart schema 2 does not move; `schema/progress.schema.json` is not
touched at all (§4.3). A reader built against
today's format that meets a `cell`-carrying document ignores the key — which is the documented
"readers MUST ignore unknown keys" rule — and computes the wrong numbers, exactly as it does
today. That is not a regression this change can prevent; it is the reason the change is worth
making now, while the only writer and the only two readers are in this repo.

## 5. Deferred, with issues

Filet's real arithmetic — `stitches_per_filled`, `chains_per_open`, `shared_edge`, and a turning
chain keyed on the first cell of the *next* row rather than on the stitch (#44 part 2, with #18
for C2C tiles and #37 for shaped rows). Gauge stated in tiles or repeats rather than stitches
(#48) — related, and deliberately not solved here: `cell` says what a cell is, `gauge.unit` says
what the gauge counts, and a chart can need both. Per-cell stitch through `layers.stitch` (#36).
Border and edging stitch multiples (#38, #39). An authoring path in `pattern.toml` for a
non-stitch chart, which waits on a real pattern that needs one.

## 6. Non-goals

Not in part 1, and not implied by it: working a non-stitch genre; any multiplier from cells to
stitches for any kind; deriving written rows for a non-stitch chart; any change to `Run`, `Pass`,
`WorkSequence`'s pass order or the cursor; any new UI surface in the app; refusing a document
whose only sin is a cardinality we have not implemented.

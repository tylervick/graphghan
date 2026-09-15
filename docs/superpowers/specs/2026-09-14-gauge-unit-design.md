# Graphghan: what the gauge counts

Date: 2026-09-14
Status: approved design (reviewed in conversation), awaiting spec review
Builds on: `2026-09-14-cell-cardinality-design.md` — `chart.cell` is half of this rule
Evidence: `docs/research/claims.md` claim 14; `docs/research/genres/c2c.md`, `joined-rounds.md`
Closes the design step for: #48

## 1. Purpose

`gauge.unit` already exists. It is in the schema as a closed enum (`stitches`, `tiles`, `repeats`,
`rounds`), `docs/chart-format.md` §Gauge already states its rule normatively — "a reader that does
not understand the unit derives no finished size" — `pattern.toml` can already author it
(`pattern.py:94-97` validates `[stitch.<key>].unit`, `export.py:197` writes it through), and Swift
already decodes it (`ChartDocument.swift:116`).

No reader enforces it. All three derive a finished size by dividing the grid by the gauge as though
both counted stitches:

- `src/graphghan/chartdoc.py:122` — `width / (gauge.stitches / per)`
- `ios/.../Chart.swift:70-74` — the same arithmetic, ignoring the `unit` it decoded eight lines up
- `site/src/app/data.js:64` — the same again

So a C2C chart stating "5.5 tiles = 4 in" is sized as though 5.5 *stitches* were 4 inches, and the
number is wrong by whatever a tile is. Crochetpop reports the same 50×50 grid as 12.5 × 10 in worked
in sc and 40 × 40 in worked C2C; we report one of those for both. This is the same defect class
#44 removed from stitch counts — a declared field that readers ignore, producing a confident wrong
number — and it is the last one the corpus evidence names.

## 2. Decisions

1. **Derivation requires the gauge's counting unit and the chart's cell cardinality to name the
   same thing.** `gauge.unit` says what `gauge.stitches` and `gauge.rows` count; `chart.cell.kind`
   (#44) says what a grid cell is. The division is valid exactly when they agree. This makes #48
   the field that *enables* a correct C2C size rather than merely suppressing a wrong one.
2. **Two pairs derive in this phase**: `stitches` ↔ `stitch` and `tiles` ↔ `tile`. Everything else
   withholds (§4.2).
3. **A withheld size is absent**, never zero and never a placeholder — the rule #44 established.
4. **A mismatch withholds; it does not refuse the document.** The chart is still workable.
5. **No new authoring surface.** `pattern.toml` already carries `unit`; this phase adds readers.

## 3. Phase 1 (normative)

### 3.1 The rule

| `gauge.unit` | `chart.cell.kind` | finished size |
|---|---|---|
| `stitches` or absent | `stitch` or absent | derived |
| `tiles` | `tile` | derived |
| `repeats` | any | withheld (#39) |
| `rounds` | any | withheld (§5) |
| any value | any non-matching kind | withheld |

Both fields default, and **their defaults pair**: absent `unit` means `stitches`, absent `cell`
means `stitch`, and that combination derives. Every document in the repo carries neither field, so
every finished size in the repo is unchanged by this phase. That is the compatibility claim, and
§3.5 pins it with a test rather than asserting it.

The pairing is a correspondence between two vocabularies, not string equality — `unit` is plural
(`tiles`) and `kind` is singular (`tile`). One table owns the mapping in each language.

### 3.2 What is withheld

| Value | Where | derivable | not derivable |
|---|---|---|---|
| `finished_size(doc)` | `chartdoc.py:121` | `(w, h, unit)` | **`None`** |
| `stats.size_in` | `export.py` | emitted | **key absent** |
| `Chart.finishedSize` | `Chart.swift:70` | `FinishedSize` | **`nil`** |
| `finishedSize(doc)` | `data.js:63` | `{w, h, unit}` | **`null`** |
| the app's and site's Finished row | | shown | **row omitted** |
| `cell_aspect` | `chartdoc.py:117` | unchanged | unchanged — it is `stitches / rows`, a ratio of two numbers in the same unit, so the unit cancels |

Omitting the row rather than rendering a placeholder follows #44's precedent, where the Pace row
disappears entirely when `stitchesPerHour` is nil.

`stats.size_in` becoming conditional answers the question this repo left open on #48 when the filet
fixture briefly stripped it (final review of `2026-09-14-cell-cardinality.md`, Important 1). Note
where it actually comes from: `export.stats` computes it as `w * gr.SW` by `h * gr.SH`, the active
gauge's **per-stitch** dimensions set by `gr.set_gauge(gauge_key)` — not from the document's `gauge`
block at all. That is precisely why a tiles chart's `size_in` is wrong today, and it means `stats()`
must learn whether the pair derives rather than reading the unit itself. One derived boolean threaded
in, not two fields.

This also revises the `stats.size_in` row that #44 wrote into `docs/chart-format.md` §Cells, which
currently reads "emitted | emitted — governed by `gauge.unit` (#48), not by this". It is now
conditional, and this phase is the "#48" that row was deferring to.

### 3.3 Consumers that must handle absence

- `src/graphghan/cli.py:188` unpacks the tuple (`w_in, h_in, _unit = finished_size(doc)`) and will
  raise on `None`. It must print nothing for the size instead.
- `site/src/app/pattern.js:26,31` puts the result in the specs array; the Finished entry is dropped
  when the size is null.
- Swift's `Chart.finishedSize` has no app call site today — only `ChartTests.swift:48` — so making
  it optional has no UI blast radius in this phase. The app reads the manifest's `size` instead,
  which is #61's territory and explicitly out of scope here.

### 3.4 Validation

`validate_document` gains nothing. A unit/kind mismatch is not a workability failure: the maker can
work the chart, and the format simply cannot relate the gauge to the grid. Refusing would widen the
#50 tenet past where #44 set it — refuse what cannot be worked, withhold what cannot be computed.

The schema is unchanged: `gauge.unit`'s enum already exists and already refuses an unknown value.

### 3.5 Fixtures and tests

- `fixtures/chart-format/tiles-gauge.chart.json` — `gauge.unit: "tiles"` with `chart.cell.kind:
  "tile"`, a C2C-shaped grid, pinning that the pair derives and that both languages agree on the
  number.
- A mismatch case (`unit: "tiles"` with the cell declaration absent, i.e. `stitch`) asserting the
  size is withheld — the direction that absence alone cannot prove.
- A test that every existing fixture's finished size is unchanged, pinning §3.1's compatibility
  claim.
- A cross-language parity test for the derived number, extending the harness
  `tests/test_js_parity.py` already uses for `sequence` and `cellNoun`.

## 4. Deferred, with issues

`repeats` withholds until #39 gives the format cells-per-repeat; a repeat is a multiple of cells and
the multiplier is unexpressible today. `rounds` withholds: "Rnds 1–9 = 4 in" measures a motif
radially, and its relationship to a grid cell is unstated. The motif-grid case (Divine Debris
*Glenda Ghost*, 380 squares on a 19×20 graph — `docs/research/genres/joined-rounds.md`) would derive
correctly if the gauge's round span were known to equal one cell, but that is an assumption, and
inferring it silently is the failure mode this whole line of work exists to remove. Both get issues.

The site manifest's `size {width, height, unit}` and the app labels that read it are #61.

## 5. Non-goals

Not in this phase: any change to `gauge.stitches`/`rows`/`over`; any new authoring surface; a
per-axis derivation where width and height resolve independently; deriving a size for `repeats` or
`rounds`; refusing any document; any change to `chart.id` (`gauge` has never been hashed and is not
hashed now).

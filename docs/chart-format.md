# Graphghan chart format

Version: chart schema 2, progress schema 1, pattern manifest schema 1. JSON Schemas live in
`schema/`; conformance fixtures in `fixtures/chart-format/`. This document is normative where the
schema cannot be (sequencing, ids, progress math).

## Design

A chart document describes one grid at one gauge. It is layered so that a reader that only knows
the palette and cells can still display it, and readers MUST ignore unknown keys at every level.
Nothing in the file is in inches except the gauge block; sizes are derived.

Nobody should be able to work a chart that cannot be crocheted as written. A document that is
*provably* unworkable — rows that do not sum to the width, runs off the grid, a foundation shorter
than the first row — is invalid: writers MUST NOT write it and readers MUST refuse it rather than
warn. Unusual but possible values are not errors.

## Chart document (schema 2)

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
  Because a run always starts with digits, `7YB` is one run of code `YB`, never two runs.
- `layers` are extra grids in the same encoding with their own `legend`; a reader that does not
  know a layer ignores it.
- A layer's legend describes each cell as it looks on the **right side** of the work (the CYC rule
  for crochet and knit chart symbols), so a knit legend of `{"k": "knit", "p": "purl"}` reads
  correctly on a WS pass. Readers do not enforce this yet (#36).

### Gauge

`stitches` and `rows` over `over.value` `over.unit` (`in` or `cm`), the way gauge is stated on a
pattern. Derived values: cell aspect = `stitches / rows`; finished width = `width / (stitches /
over.value)` in `over.unit`, likewise height. `unit` says what `stitches` and `rows` count —
`stitches` (default), `tiles`, `repeats` or `rounds`; a reader that does not understand the unit
derives no finished size (#48; neither reader in this repo checks the unit yet, and nothing
authors one).

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
is legitimate; one with fewer than `width + first_stitch_in - 1` cannot be worked, and readers
MUST refuse the document (see §Design).

### Chart id

`chart.id` is `"sha256:" + hex(sha256(canonical))` where `canonical` is the UTF-8 JSON of
`{"codes": [palette codes in order], "rows": rows, "technique": technique}` plus `"passes"` when
the document has them, with keys sorted, no whitespace (`,` and `:` separators only) and non-ASCII
kept as-is. Names, hexes, yarn, instructions and stats do not affect the id: renaming a color is
not a new chart. Readers may verify the id; writers MUST compute it this way.

### Technique and passes

A technique maps the grid to an ordered list of passes; each pass is an ordered list of runs. The
progress cursor is `{ "row": <1-based pass index>, "run": <0-based run index> }` for every
technique, because C2C patterns already call a diagonal a row.

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

## Progress document (schema 1)

```json
{ "schema": 1, "pattern_id": "craigh-na-dun", "chart_id": "sha256:…", "pattern_version": "1.0.0",
  "cursor": { "row": 42, "run": 3 }, "started": "2026-09-12T18:04:00Z", "finished": null,
  "events": [ { "t": "2026-09-12T18:31:12Z", "row": 42, "run": 2, "kind": "advance" } ] }
```

`kind` is `advance`, `back` or `jump`; every event records the cursor **after** the action.
`chart_id` may be `null` for a cursor imported from a source that did not know it. Derived values,
as implemented by `graphghan.progress` and pinned by the `progress-basic` fixture:

- stitches before a cursor = stitches in every earlier pass + runs before `run` in the current pass;
  percent = 100 × that / total stitches, one decimal.
- Events are sorted by `t`. A session is a maximal run of events with gaps ≤ 20 minutes. A session's
  stitches are the difference in stitches-before between the cursor after its last event and the
  cursor before its first event (the cursor before the very first event is row 1, run 0), clamped at
  0. Active seconds is the sum of each session's last − first timestamp. Stitches per hour is total
  session stitches over active hours, one decimal, or `null` with no active time.

## Pattern manifest (schema 1)

Written by the site build as `patterns/<id>/pattern.json`: identity, `palette` (code, name, hex),
`preview`, `charts` (one per published chart: `id`, `variant`, `gauge_key`, `default`, `path`,
`preview`, `width`, `height`, `size {width, height, unit}`, `stitch`, `colors`, `stitches`,
`changes_per_row {mean, max}`, `yards_est`), and `updated`. Exactly one chart is `default` and it
is the one also served as `chart.json` at the pattern's top level.

## Bundle

A `.graphghan` file is a zip with `pattern.json` at its root plus the chart files and previews it
references at their relative paths. Defined so tools agree; no tool in this repo writes one yet.

## Interchange

- **PNG, one pixel per stitch** (`graphghan export --format png`): palette hexes, no grid. Imports
  1:1 into Stitch Fiddle and any pixel editor. Requires distinct hexes.
- **OXS** (`--format oxs`): Ursa Software's Open Cross Stitch XML. Palette index 0 is the cloth;
  chart colors are 1..n; every cell is a `<stitch x y palindex>` with 0-based coordinates from the
  top-left; `stitchesperinch`/`stitchesperinch_y` come from the gauge. Working order is not
  representable in OXS.
- **CSV** (`--format csv`): `height` lines of `width` comma-separated codes, top to bottom.

## Conformance

A reader claims conformance when, for every fixture in `fixtures/chart-format/`, it validates the
chart against `schema/chart.schema.json`, reproduces the expected sequence (or its SHA-256), refuses
to sequence the unknown-technique fixture while still decoding it, and reproduces the expected
progress summary. Changing the format starts with a fixture.

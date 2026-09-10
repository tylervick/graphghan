# Workflow: brief to shipped pattern

## 1. Brief (ask only what changes the work)
- The quote or text, exactly as it should read; line breaks are yours to choose.
- Motifs and the world they come from (a show, a place, a flower): the specific detail is what
  makes the design theirs. Ask for one or two "must haves" and one "must not".
- Who it is for and where it lives: couch throw ≈ 50–56 × 44–50 in; bed sizes are a different project.
- Caps: rows and columns (people say "under 200"), color count (usually 5–7), stitch (sc, hdc, dc).
- Who crochets it and where they read the chart (phone at the couch → the viewer's working mode).

## 2. Gauge and grid
- Pick the stitch, then the gauge from references/crochet.md, then W = cols(width_in), H = rows(height_in).
- Present the grid as "W × H, ≈ w × h in at gauge"; if a cap is exceeded, either shrink the size,
  simplify the border, or move to hdc. Say which lever you pulled.

## 3. Palette
- Order the palette in pattern.toml; index order is the cell value. Put the background first.
- Contrast on yarn beats fidelity to a muted reference. Name a real colorway for each color.
- The first row color is the outer edge color; note it in pattern.toml `first_row_color`.

## 4. Scaffold
    uv run graphghan new <slug> --title "<Title>"
Edit pattern.toml (dedication, quote, size, colors, notes) and design.py (QUOTE, SIZE_IN, VARIANTS, build()).
`VARIANTS` must keep a `"final"` key: `graphghan check`, `render`'s default `--variant`, and the
scaffolded test all build `"final"`.

## 5. Compose (inches, then cells)
- `build()` must start with `gr.set_gauge(gauge_key)`: every `cols/rows`/inch-mask call reads global
  gauge state; skip it and every gauge renders as sc (the options page would show two identical charts).
- Frame first: `twist_frame` or `link_frame` (both return the panel rect). There is no `plaid_frame`;
  a plaid ground is drawn with `motifs.plaid.plaid` plus a twist strip by hand (see
  `examples/outlander_studies.py` on the library branch after merge).
- Vertical budget inside the panel: scene ∥ lettering (lines × pitch) ∥ foot motifs, with gaps; clamp the
  scene, never the lettering.
- Motifs take explicit palette indices; sizes in inches; use gr.cols()/gr.rows() for placement.
- Return a report dict: `report["panel"]` (`(x0, y0, x1, y1)`) and `report["text"]` (a list of per-line
  `(x0, y0, x1, y1)` boxes) are required — the scaffolded test asserts both. Other keys (scene, thistles,
  dragonfly…) are optional, used only by that pattern's own tests.

## 6. Options page
    uv run graphghan options <slug>
- Two to three variants that differ in one thing each (corners, foot, border style); both gauges.
- Show: stitches × rows, finished size, colors, changes/row mean, busiest-row change count, rough hours.
  The options page shows only the max change count; find the row itself in `dist/chart.json` →
  `stats.color_changes_per_row.per_row` after `render`.
- Send the preview PNGs too; people decide from the picture.

## 7. Iterate
- Change one variable per round. Re-render both gauges. Re-run the numbers.
- Keep a `"final"` key in `VARIANTS` even while iterating: `graphghan check`, `render`'s default
  `--variant`, and the scaffolded test all build `"final"`.
- When asked "are the borders symmetric / equal", measure from the chart (period, crossing spacing,
  span, margins) and answer with the numbers; see design-rules.md for what can and cannot be symmetric.

## 8. Final
    uv run graphghan render <slug> && uv run graphghan check <slug>
- The scaffold's tests build every variant at the default stitch and `final` at every gauge; add tests
  for what makes this design correct on top of that.
- Add pattern tests for what makes this design correct (text lines clear, motifs present, mirrors).
- Bump `version` in pattern.toml and write the CHANGELOG entry.

## 9. Ship
- Commit dist/, `uv run graphghan site build`, deploy (CI on main), tag `<slug>/v<version>`.
- Hand over: viewer link, chart.png for Stitch Fiddle, written-rows.txt, yardage table.

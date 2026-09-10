---
name: graphghan
description: Design and validate pixel-chart craft patterns (graphghan/C2C crochet, colorwork, cross-stitch) from a brief — quote, motifs, size, stitch, color cap — using the graphghan CLI. Use when asked for a crochet/knit chart, a blanket pattern from an image or quote, or to convert a design into stitches.
---

# Graphghan

Turn a brief into a chart you can trust: drawn in inches, rasterized to the crocheter's gauge,
validated row by row, delivered as an offline viewer page and a Stitch Fiddle import file.

## When to use
- "Make me a crochet/knit chart or blanket pattern" from a quote, image, mockup, or list of motifs.
- "Convert this design to stitches", "how many colors/rows will this take", "fix this chart".
- Any pixel-chart craft: graphghan (sc/hdc rows), C2C, colorwork, cross-stitch (square cells).

## The workflow (details: references/workflow.md)
1. Brief: quote, motifs, who it is for, couch/bed size, row and column caps, color cap, stitch preference.
2. Decide gauge from the stitch (references/crochet.md) and the finished size; everything is designed in inches.
3. Palette: 5–7 colors, high contrast on yarn even if the reference looks muted; index order = pattern.toml order.
4. `uv run graphghan new <slug> --title "<Title>"` then edit `patterns/<slug>/pattern.toml` and `design.py`.
5. Compose: frame (braid, links, plaid), scene, lettering (17 rows/line at sc), motifs clear of the words.
6. `uv run graphghan options <slug>` → open `patterns/<slug>/build/options/options.html`; show every variant at sc and hdc with stitches × rows, size, colors, changes/row, busiest row, hours.
7. The person picks; iterate variants (corners, foot motif, border) rather than re-drawing everything.
8. `uv run graphghan render <slug>` → `dist/`; `uv run graphghan check <slug>` must pass.
9. Ship: commit `dist/`, `uv run graphghan site build`, publish or deploy; hand over chart.png for Stitch Fiddle (references/stitchfiddle.md).

## Rules that are not optional (why: references/design-rules.md)
- No run shorter than 2 stitches anywhere in plaid or bands.
- Lettering needs ≥ 11 rows per line to read; 17 at sc, 12 at hdc for a quote; use the aspect-aware text renderer.
- Keep words clear: nothing beside a text line, nothing overlapping the panel behind the letters.
- Count color changes per row, not just stitches; report mean and busiest row for every option.
- An interlace has handedness: mirror the frame, never expect one strip to mirror itself; anchor crossings to the corners with an odd number of half-periods.
- Moons, suns, and other discs stay clear of silhouettes (test it).
- Render every option at both sc and hdc before presenting; hdc trades curve fidelity for 60% of the rows.

## CLI
| command | use |
|---|---|
| `graphghan new <slug> --title T` | scaffold a pattern from the template |
| `graphghan options <slug> [--gauges sc,hdc]` | comparison page for the pick |
| `graphghan render <slug> [--gauge] [--variant] [--check]` | write or verify `dist/` |
| `graphghan check <slug>` | invariants + the pattern's tests |
| `graphghan catalog` | refresh motif thumbnails in this skill's `assets/` |
| `graphghan site build\|serve` | the viewer |

## Review checklist before presenting anything
- [ ] Both gauges rendered; stats table filled; previews at true stitch proportions.
- [ ] `check` passes; the report boxes (panel, text, motifs) are in the design's return value.
- [ ] Palette ≤ the cap; every color has a yarn suggestion.
- [ ] Busiest row named and explained (border, lettering, or motif).
- [ ] One sentence per option on what it is, not how it was made.

## References
- references/workflow.md · references/design-rules.md · references/motifs.md · references/crochet.md · references/stitchfiddle.md

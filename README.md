# graphghan

Charts for pixel-chart crafts (graphghan/afghan crochet, C2C, colorwork, cross-stitch), grown out
of a one-off Outlander-quote blanket generator into a reusable toolkit. One repo, three
deliverables:

1. **`graphghan` Python package + CLI** — compose charts from motifs defined in inches, validate
   them (row totals, palette closure, min run length, mirror symmetry), and export chart data,
   PNGs, and written-row instructions.
2. **A static, installable viewer (PWA)** on GitHub Pages — follow a pattern row by row on a
   phone or tablet, mostly offline, with per-row progress saved on the device.
3. **A Claude skill** (`graphghan`) — the design workflow and rules as a Claude Code skill, so a
   brief ("a blanket with this quote and these motifs") turns into an options page and a
   finished, validated pattern.

Live site: **https://graphghan.milo.cat/**

The first pattern is **Craigh na Dun Blanket** (for Meaghan): 189x184 sc, 5 colors, standing
stones, thistles, a dragonfly, and a braided gold twist border.

## Quick start

```bash
uv sync
uv run graphghan new <slug> --title "<Title>"    # scaffold patterns/<slug>/
uv run graphghan options <slug>                  # compare variants/gauges, writes an HTML page
uv run graphghan render <slug>                   # write dist/chart.json, chart.png, etc.
uv run graphghan check <slug>                    # generic invariants + the pattern's own tests
uv run graphghan site serve                      # build and serve the viewer at :8765
```

Existing patterns work the same way, e.g. `uv run graphghan render craigh-na-dun --check` diffs a
fresh build against the committed `dist/` and fails on drift. Run `uv run graphghan --help` (or
`<command> --help`) for every flag.

## Pattern folder contract

A pattern is a folder under `patterns/<slug>/` with a `pattern.toml` (metadata: title, dedication,
gauges, palette, notes) and a `design.py` that exposes a `VARIANTS` dict and a
`build(gauge_key, variant) -> (Grid, report)` function, where `report` is a dict of named boxes
(at least `panel` and `text`) used by the pattern's own tests. Every pattern commits its default-
gauge render under `dist/` (`chart.json`, `chart.png`, `preview.png`, `preview-grid.png`,
`written-rows.txt`); the site and CI build from those committed files, and
`graphghan render <slug> --check` (run in CI) fails if a fresh render drifts from what's
committed. See `docs/superpowers/specs/2026-09-09-graphghan-design.md` for the full contract.

## The skill

`.claude/skills/graphghan/` packages the design workflow (gauge selection, composition, the
validation rules, options review) as a Claude Code skill, so it's available from any project once
symlinked:

```bash
ln -sfn "$(pwd)/.claude/skills/graphghan" ~/.claude/skills/graphghan   # run from the repo root
```

Then from Claude Code, a brief like "a blanket with this quote and these motifs" drives
`graphghan new`, `options`, and `render`/`check` to a finished pattern.

## Licensing

- Code (`src/`, `site/`, tooling): MIT — see `LICENSE`.
- Pattern designs (`patterns/`): CC BY-NC-SA 4.0 — see `PATTERNS-LICENSE.md`.
- Fonts (`fonts/`, `site/src/fonts/`): SIL Open Font License.

The lettering face used throughout is [Metamorphous](https://fonts.google.com/specimen/Metamorphous)
by Sorkin Type Co, licensed under the OFL.

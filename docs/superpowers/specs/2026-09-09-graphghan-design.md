# Graphghan: reusable chart generator, viewer PWA, and Claude skill

Date: 2026-09-09
Status: approved design (sections reviewed in conversation), awaiting spec review

## 1. Purpose

Turn the one-off Outlander blanket generator (`~/Projects/outlander-blanket`) into a reusable
toolkit for pixel-chart crafts, with three deliverables in one public repository:

1. **`graphghan` Python package + CLI** that renders crochet/colorwork charts from
   compositions defined in inches, validates them, and exports data for humans and tools.
2. **A static, installable viewer (PWA)** on GitHub Pages that a crocheter uses on a phone or
   tablet, mostly offline, to follow a pattern row by row and run by run.
3. **A Claude skill** (`graphghan`) that encodes the design workflow and the rules learned, so a
   future brief ("a blanket with this quote and these motifs") produces an options page and a
   finished pattern with the same quality without re-deriving anything.

The first pattern in the repo is **Craigh na Dun Blanket** (for Meaghan), exactly the finalized
design: 189 x 184 sc, 5 colors, standing stones, Metamorphous lettering, thistles, dragonfly,
braided gold twist border with nailhead corners.

## 2. Non-goals

- No backend, accounts, or cross-device sync. Progress lives on the device; a text export/import
  moves it between devices.
- No in-browser chart editing. Designs are code.
- No Stitch Fiddle automation. The repo produces a 1-px-per-stitch PNG that imports 1:1.
- No knitting- or cross-stitch-specific exports yet. The gauge model already supports square and
  non-square cells; craft-specific instruction formats can come later.
- No browser-automation tests in CI at first.

## 3. Repository

`github.com/tylervick/graphghan`, public. Code under MIT; pattern designs under CC BY-NC-SA 4.0
(change if Tyler prefers). Fonts are OFL and vendored.

```
graphghan/
  README.md  LICENSE  pyproject.toml  uv.lock  .gitignore  .python-version
  src/graphghan/
    __init__.py
    grid.py         Grid, gauge registry + set_gauge, cols()/rows(), inch-space masks
                    (ellipse/circle/square/diamond/stadium rings, ellipse_fill, segment_band,
                    curve_mask_in), dilate, weave, sector_windows
    palette.py      Palette (ordered code -> name/rgb/yarn/use), from_toml, index lookup
    text.py         text_line(): any TTF, size in rows, aspect-corrected, bold/threshold
    motifs/
      __init__.py   registry used by the skill's catalog
      plaid.py      sett-based plaid with priority rule, min run length
      twist.py      twist_strip_in (inch-true two-strand twist, fitted period, corner-anchored)
      knots.py      solomon_knot, corner_block, woven_x_block
      rings.py      interlocked rings
      thistle.py    thistle (large + compact bitmaps), thistle_scaled, bloom_icon
      dragonfly.py  dragonfly, amber_drop
      stones.py     standing_stones (moon placed clear of stones)
      bands.py      stripe_band, link_frame band pieces
    frame.py        twist_frame(corners=solid|dot|cross), link_frame, plaid_frame
    compose.py      text_block, vertical budget helpers, centering helpers
    export.py       rle_rows, chart_png, preview_png, stats, written_rows, chart_json
    validate.py     generic invariants: row sums, palette closure, solid edge, mirror helpers,
                    min-run report, changes-per-row report
    cli.py          `graphghan` entry point (see section 5)
    templates/      design.py template(s) used by `graphghan new`
  patterns/
    craigh-na-dun/
      pattern.toml  design.py  CHANGELOG.md  tests/test_design.py  reference/  dist/
  examples/
    outlander_studies.py  the option studies (dragonfly-in-amber, tartan, link border...)
                          kept as motif-catalog examples; not published to the site
  site/
    src/            index.html, pattern.html (template), app/*.js (ES modules), styles.css,
                    sw.js, manifest.webmanifest, fonts/ (self-hosted OFL), icons/
    build.py        builds site/dist (gitignored)
    tests/          data-contract tests (pytest)
  fonts/            lettering fonts used by the generator (Metamorphous, Georgia fallback note)
  .claude/skills/graphghan/
    SKILL.md  references/{workflow,design-rules,motifs,crochet,stitchfiddle}.md  assets/
  tests/            library tests
  docs/superpowers/{specs,plans}/
  .github/workflows/ci.yml
```

### 3.1 Versioning

- Library: semver in `pyproject.toml`. Not published to PyPI; installed from the repo with uv.
- Pattern: `version` in `pattern.toml`, entries in its `CHANGELOG.md`. A release is an annotated
  git tag `"<slug>/v<version>"` (e.g. `craigh-na-dun/v1.0.0`). `chart.json` carries the version
  and the viewer displays it.
- `patterns/<slug>/dist/` is **committed** for the pattern's default stitch: `chart.json`,
  `chart.png`, `preview.png`, `preview-grid.png`, `written-rows.txt`. The site builds from these
  files only. CI re-renders and fails if committed `dist/` differs from the code (drift check).
- Alternate-gauge renders and option studies go to `patterns/<slug>/build/` (gitignored).

## 4. Pattern contract

### 4.1 `pattern.toml`

```toml
[pattern]
slug = "craigh-na-dun"
title = "Craigh na Dun Blanket"
dedication = "For Meaghan"
quote = "Lord, you gave me a rare woman, and God! I loved her well."
version = "1.0.0"
stitch = "sc"                 # default gauge key
size_in = [54.0, 46.0]
hook = "5 mm (US H-8)"
yarn_weight = "worsted (#4)"
first_row_color = "Y"

[gauge]                       # stitches per inch, rows per inch
sc  = [3.5, 4.0]
hdc = [3.25, 2.5]

[[colors]]                    # order = cell index
code = "C"
name = "Cream"
hex = "#F2E8D5"
yarn = "Aran / off-white"
use = "sky, quote panel"
# ... one table per color

[notes]
setup = ["Foundation: chain W + 1 in Gold ...", "..."]
colors = ["Braid rows alternate gold and green ...", "..."]
```

### 4.2 `design.py`

```python
from graphghan import Grid, gauge, motifs, frame, compose, palette

PAL = palette.load(__file__)          # reads pattern.toml next to this file
VARIANTS = {"final": {"corners": "dot", "foot": "dragonfly"},
            "plain-foot": {"corners": "dot", "foot": "plain"}}

def build(gauge_key: str = "sc", variant: str = "final") -> tuple[Grid, dict]:
    """Return the grid and a report of named boxes (panel, text lines, motifs) for tests."""
```

`build` must be deterministic for a given (gauge, variant) and must not read anything but
`pattern.toml`, the package, and vendored fonts.

### 4.3 `chart.json` (schema 1)

```json
{
  "schema": 1,
  "slug": "craigh-na-dun", "title": "...", "dedication": "For Meaghan", "quote": "...",
  "version": "1.0.0",
  "stitch": "sc", "gauge": {"st_per_in": 3.5, "rows_per_in": 4.0}, "cell_aspect": 0.875,
  "hook": "5 mm (US H-8)", "yarn_weight": "worsted (#4)",
  "width": 189, "height": 184, "size_in": [54.0, 46.0],
  "palette": [{"code": "C", "name": "Cream", "hex": "#f2e8d5", "yarn": "...", "use": "..."}],
  "rows": ["2Y7B..."],
  "stats": {"stitches": 34776, "counts": {"C": 19079}, "single_stitch_runs": {},
            "color_changes_per_row": {"mean": 28.9, "max": 94, "per_row": [..]},
            "yards_est": {}, "skeins_364yd": {}},
  "notes": {"setup": [], "colors": []},
  "report": {"panel": [x0, y0, x1, y1], "text": [[...]], "...": "..."}
}
```

`rows` are listed top to bottom as drawn; pattern row 1 is the last entry. Row order for
working (RS right-to-left on odd rows) is derived by consumers, not stored.

## 5. CLI

`graphghan` (console script, `uv run graphghan ...`):

| command | does |
|---|---|
| `new <slug> --title T [--template craigh-na-dun]` | scaffold `patterns/<slug>/` with pattern.toml, design.py from a template, tests, empty reference/ |
| `options <slug> [--gauges sc,hdc]` | render every variant at each gauge into `build/options/`, write `build/options/options.html` (the comparison page: true-proportion previews, stats table, gauge toggle) |
| `render <slug> [--gauge K] [--variant V] [--out DIR]` | write dist files; `--check` re-renders and diffs against committed dist (exit 1 on drift) |
| `check <slug>` | generic invariants (validate.py) + `pytest patterns/<slug>/tests` |
| `site build [--out site/dist]` | build the viewer from all patterns with committed dist |
| `site serve [--port]` | local static server for the built site |
| `catalog` | render motif thumbnails to `.claude/skills/graphghan/assets/` (used by the skill) |

Exit codes: 0 ok, 1 validation/drift failure, 2 usage error. All paths relative to the repo root,
found by walking up from cwd for `pyproject.toml`.

## 6. Viewer / PWA

### 6.1 Pages
- `index.html`: library. One card per pattern: title, dedication, size, colors, version, and
  this device's progress percent. Cards link to `patterns/<slug>/`.
- `patterns/<slug>/index.html`: generated from `pattern.html` at build time (title, meta, and the
  data URL injected). Loads `patterns/<slug>/chart.json`.

### 6.2 Viewer features
- Chart canvas: zoom, grid (fine + bold every 10), letters, true proportions (cell aspect from
  the data), dim other rows, click a cell to locate; row/column labels from the bottom-left.
- Row panel: current row, RS/WS and reading direction, runs as chips, stitch/change counts,
  prev/next, arrow keys.
- **Working mode** (full-screen, phone-first): the current row's strip of the chart on top; the
  row's runs as large chips with running totals; tapping a chip or the big "done" button advances
  one run; a back control reverts; finishing the last run advances the row; a screen wake lock
  is requested while working (where supported); large type; nothing else on screen.
- Progress: `localStorage["graphghan:<slug>:progress"] = {row, run, updatedAt, patternVersion}`,
  wrapped in try/catch. Export/import as a short base64 text blob (copy/paste), no backend.
- Print tiles (existing behaviour) and a real download link for `chart.png` plus the written rows.
- Theme: existing light/dark token system; fonts self-hosted for offline use.

### 6.3 PWA
- `manifest.webmanifest`: name, short name, start_url `./`, `display: standalone`, theme and
  background colors, icons 192/512 (static, drawn by build.py from a fixed icon design).
- `sw.js`: precache list generated by `build.py` (every file with a content hash); cache name
  includes the build hash; install caches everything; fetch is cache-first for precached URLs and
  network-first with cache fallback otherwise; activate deletes old caches; the page shows a
  small "new version, reload" notice when a new worker is waiting.
- After one online visit, library and all patterns work offline and install to the home screen.

### 6.4 Build and deploy
- `site/build.py`: copies `site/src`, generates per-pattern pages, writes `patterns/index.json`,
  copies each pattern's `dist/`, computes hashes, writes the precache manifest into `sw.js`.
- GitHub Actions deploys `site/dist` with `actions/deploy-pages` on push to `main`.

## 7. Skill

`.claude/skills/graphghan/` authored with the `skill-creator` plugin and superpowers'
`writing-skills`, symlinked to `~/.claude/skills/graphghan` for use outside the repo.

- `SKILL.md`: triggers (pixel-chart crafts: graphghan, C2C, colorwork, cross-stitch; any "make me
  a chart/pattern from this image, quote, motifs"), the workflow summary, the CLI, where the
  references are, and the review checklist (render both gauges, count color changes, check
  lettering legibility, present options before finalizing).
- `references/workflow.md`: brief -> constraints (size, stitch, color cap, row/column caps) ->
  palette -> composition in inches -> options page -> pick -> final -> check -> site.
- `references/design-rules.md`: no runs under 2 stitches; lettering needs >= 11 rows per line
  (17 at sc for a quote); aspect-aware text rendering; interlace has handedness (mirror the
  frame, don't expect one strip to mirror itself); anchor crossings to corners with an odd
  half-period count; keep words clear of motifs; count changes per row not just stitches;
  place moons and the like clear of silhouettes; prefer straight-edged motifs at hdc.
- `references/motifs.md`: catalog with parameters and thumbnails (from `graphghan catalog`).
- `references/crochet.md`: gauge tables, RS/WS order, color-change technique, yardage and time
  estimates, when hdc/dc make sense.
- `references/stitchfiddle.md`: import steps, free-tier limits, gauge proportions.

The skill's acceptance test: in a fresh session, a brief with a quote and three motifs leads the
skill to scaffold a pattern, produce an options page, and, after a pick, a passing `check`.

## 8. Testing and CI

- Library tests (`tests/`): grid/gauge math, masks, weave, text rendering (glyph rows/cols,
  aspect), export round-trip (rows -> chart_json -> decode), validate helpers.
- Pattern tests (`patterns/<slug>/tests/`): the invariants from today's `test_final.py`, using
  the report boxes.
- Drift test: `graphghan render <slug> --check` for every pattern.
- Site tests: chart.json schema, index.json, precache list covers every emitted file.
- Lint: ruff.
- CI (`ci.yml`): on push/PR: `uv sync`, ruff, pytest (library + patterns + site), drift check,
  site build. On `main`: deploy Pages.

## 9. Work plan (parallel)

1. **Foundation (sequential, main):** create the repo, move code into `src/graphghan` with the
   module split above, write `patterns/craigh-na-dun` (pattern.toml with the dedication, design.py
   from `designs.final`, tests, dist), CLI skeleton with `render`/`check`, contracts committed.
2. **Parallel streams in git worktrees, one subagent each:**
   - `feat/library`: package refactor completion, `new`/`options`/`catalog`, validate.py, library
     tests, drift check, templates, examples.
   - `feat/site`: viewer, working mode, progress, PWA, build.py, site tests.
   - `feat/skill`: SKILL.md and references via skill-creator, thumbnails from the catalog, symlink.
   Streams depend only on the contracts (sections 4, 5) and must not edit each other's trees.
3. **Integration (sequential):** merge, CI + Pages, tag `craigh-na-dun/v1.0.0`, phone check,
   README, memory notes.

## 10. Success criteria

- `uv run graphghan check craigh-na-dun` passes and `render --check` reports no drift.
- The site is live on GitHub Pages, installs on a phone, and works offline with run-level
  progress tracking.
- In a fresh Claude session the skill triggers on a brief and reaches an options page end to end.
- The published Craigh na Dun chart is byte-identical (rows) to the finalized design.

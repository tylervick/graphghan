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

Tooling is managed by [mise](https://mise.jdx.dev) (uv, hk, and the linters) and
[hk](https://hk.jdx.dev) (git hooks). One-time, in a fresh checkout:

```bash
mise trust && mise install    # uv, hk, actionlint, gitleaks, zizmor
mise run setup                # uv sync --all-groups, then install the git hooks
```

That gives you a pre-commit hook (ruff, formatting, file hygiene) and a pre-push hook
(the above plus pytest and the workflow/secret scans). Day to day:

```bash
mise run check    # lint + test, the same pair CI runs
mise run fix      # apply every fix hk can make
mise run test     # pytest only
```

Orca worktrees run `mise run setup` automatically on creation — see `orca.yaml`.

Then the tool itself:

```bash
uv run graphghan new <slug> --title "<Title>"    # scaffold patterns/<slug>/
uv run graphghan options <slug>                  # compare variants/gauges, writes an HTML page
uv run graphghan render <slug>                   # publish every [publish] chart to dist/
uv run graphghan check <slug>                    # generic invariants + the pattern's own tests
uv run graphghan export <slug> --format oxs        # also png (1 px/stitch) and csv; --chart final-hdc picks a chart
uv run graphghan site serve                      # build and serve the viewer at :8765
```

Existing patterns work the same way, e.g. `uv run graphghan render craigh-na-dun --check` diffs a
fresh build against the committed `dist/` and fails on drift. Run `uv run graphghan --help` (or
`<command> --help`) for every flag.

## Pattern folder contract

A pattern is a folder under `patterns/<slug>/` with a `pattern.toml` (metadata: title, dedication,
gauges, palette, notes) and a `design.py` that exposes a `VARIANTS` dict and a
`build(gauge_key, variant) -> (Grid, report)` function, where `report` is a dict of named boxes
(at least `panel` and `text`) used by the pattern's own tests. Every pattern commits every published
chart under `dist/charts/<variant>-<gauge>/` (declared in `[publish]` in `pattern.toml`; the first
entry is also copied to `dist/` top level); the site and CI build from those committed files, and
`graphghan render <slug> --check` (run in CI) fails if a fresh render drifts from what's
committed. See `docs/superpowers/specs/2026-09-09-graphghan-design.md` for the full contract.

## Chart format

Charts are JSON documents in the graphghan chart format (schema 2): a palette, run-length rows,
a gauge, and a `technique` that defines working order, with a content-hash id. The format is
documented in `docs/chart-format.md`, has JSON Schemas under `schema/`, and ships conformance
fixtures under `fixtures/chart-format/` that any reader (the PWA, the iOS app, yours) can test
against. `graphghan export` writes 1-px PNG, OXS, and CSV.

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

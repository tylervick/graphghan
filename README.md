# graphghan

Charts for pixel-chart crafts (graphghan/afghan crochet, C2C, colorwork, cross-stitch), grown out
of a one-off Outlander-quote blanket generator into a reusable toolkit. One repo, three
deliverables:

1. **`graphghan` Python package + CLI** — compose charts from motifs defined in inches, validate
   them (row totals, palette closure, min run length, mirror symmetry), and export chart data,
   PNGs, and written-row instructions.
2. **A published pattern feed** on GitHub Pages — every chart as data: a `patterns/index.json`
   listing, a manifest per pattern, the chart files, and the JSON Schemas. The iOS app reads it;
   so can anything else.
3. **A Claude skill** (`graphghan`) — the design workflow and rules as a Claude Code skill, so a
   brief ("a blanket with this quote and these motifs") turns into an options page and a
   finished, validated pattern.

Published at **https://graphghan.milo.cat/** (a landing page over the feed; to work a pattern,
use the iOS app).

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
uv run graphghan export <slug> --format oxs        # also png (1 px/stitch), csv, and pdf (printable); --chart final-hdc picks a chart
uv run graphghan site serve                      # build and serve the pattern feed at :8765
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
fixtures under `fixtures/chart-format/` that any reader (the iOS app, yours) can test
against. `graphghan export` writes 1-px PNG, OXS, CSV, and a printable PDF laid out like a sold pattern
(cover, key, tiled chart, written rows); `fixtures/import/` holds one such PDF per published chart.

## iOS app

`ios/` holds the SwiftUI app for working a published pattern on an iPhone (see `ios/README.md`):
a Patterns tab fed from this site, a Projects tab with per-project progress, and a full-screen
Work screen. `ios/Packages/GraphghanCore` is the Swift reader for the chart format and passes the
same conformance fixtures as the Python package. The Work screen also drives a Live Activity on
the lock screen and Dynamic Island with Done and Back buttons. CI runs the iOS tests on every pull
request that touches `ios/`, and `.github/workflows/testflight.yml` ships a build to TestFlight by
hand (see `ios/docs/release.md`).

## The skill

`.claude/skills/graphghan/` packages the design workflow (gauge selection, composition, the
validation rules, options review) as a Claude Code skill, so it's available from any project once
symlinked:

```bash
ln -sfn "$(pwd)/.claude/skills/graphghan" ~/.claude/skills/graphghan   # run from the repo root
```

Then from Claude Code, a brief like "a blanket with this quote and these motifs" drives
`graphghan new`, `options`, and `render`/`check` to a finished pattern.

## Agent code review (Blink)

[Blink](https://blink.review) reviews each Claude Code turn's diff and feeds the findings back to
the agent before you see them. It is **optional and per-developer** — nothing in CI depends on it,
and both workflows skip the download — but the CLI is pinned in `mise.toml` so everyone who opts in
runs the same build:

```bash
mise install            # includes the pinned blink
mise run blink-setup    # sign in, install the hooks, check they will resolve
```

`blink setup` writes its hooks to your user-level `~/.claude/settings.json`, not into this
repository; `blink setup claude-code --remove` takes them out again. The hooks invoke a bare
`blink`, which for a mise-managed tool resolves only through mise's shims directory — `mise run
blink-setup` verifies that and tells you what to add to your shell profile if it is missing.

Two things to know when reading a review:

- `blink review` diffs against the **local** `main` ref, not `origin/main`. In an Orca worktree
  local `main` is never checked out and so never advances, and a review whose range is forty
  commits wide reports real findings about other people's merged work. `git fetch origin main:main`
  (with the colon) updates both refs; `git diff --name-only main...HEAD` should list only your own
  files before you trust a finding.
- Blink is not in the mise registry and has no release tags, so Renovate cannot bump it. Run
  `Scripts/update-blink-pin.sh` (add `--write` to apply) instead of editing the URLs and checksums
  by hand — and not `blink update`, which drops an unpinned copy in `~/.local/bin` that then
  shadows or diverges from the pinned one depending on your `PATH` order.

## Licensing

- Code (`src/`, `site/`, tooling): MIT — see `LICENSE`.
- Pattern designs (`patterns/`): CC BY-NC-SA 4.0 — see `PATTERNS-LICENSE.md`.
- Fonts (`fonts/`): SIL Open Font License.

The lettering face used throughout is [Metamorphous](https://fonts.google.com/specimen/Metamorphous)
by Sorkin Type Co, licensed under the OFL.

# Graphghan Claude Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Claude skill at `.claude/skills/graphghan/` that turns a brief (quote, motifs, size, stitch, color cap) into an options page and then a finished, validated pattern using the `graphghan` CLI, carrying every rule learned on the first blanket.

**Architecture:** `SKILL.md` (triggers, workflow summary, CLI, checklist) plus five reference files the skill points to only when needed, plus thumbnails rendered by `graphghan catalog`. Authored with the `skill-creator` plugin's process and superpowers' `writing-skills`; symlinked into `~/.claude/skills`.

**Tech Stack:** Markdown, the `graphghan` CLI (library plan), `skill-creator` plugin, `superpowers:writing-skills`.

**Spec:** `docs/superpowers/specs/2026-09-09-graphghan-design.md` (section 7)

## Global Constraints

- Branch `feat/skill` in a worktree of `~/Projects/graphghan`; only write under `.claude/skills/graphghan/`. The CLI you document is the one in the library plan (Task 9): `graphghan new|options|render|check|catalog|site`.
- `SKILL.md` frontmatter: `name: graphghan`, a `description` that states when to use it (the trigger phrases below) in under 300 characters. Keep `SKILL.md` under 250 lines; details go in `references/`.
- Before writing anything, load and follow the `skill-creator` skill (`Skill: skill-creator`) and `superpowers:writing-skills`; where their guidance and this plan differ on structure, theirs wins; the content below is what must be in the files.
- Numbers below are copied from the finalized pattern and must not be "improved" without re-measuring: lettering 17 rows/line at sc, 12 at hdc; min run 2 stitches; gauges sc 3.5×4.0, hdc 3.25×2.5, dc 3.0×1.625 per inch; twist crossings every 2.0 in; Stitch Fiddle free tier 300×300 and 50 colors.
- Commit after every task with the attribution trailer:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01W4MmgYzfdwasS3YkdiwPWe`.

---

## File structure

| path | responsibility |
|---|---|
| `.claude/skills/graphghan/SKILL.md` | triggers, the workflow in 12 lines, CLI cheatsheet, review checklist, pointers |
| `references/workflow.md` | the full brief → ship procedure with what to ask, decide, and show at each step |
| `references/design-rules.md` | the hard-won rules with the reason for each |
| `references/motifs.md` | catalog: every motif function, its parameters, when to use it, thumbnail |
| `references/crochet.md` | gauges, RS/WS, color changes, yardage/time, hdc/dc trade-offs |
| `references/stitchfiddle.md` | import steps and limits |
| `assets/*.png` | thumbnails from `graphghan catalog` |

---

### Task 1: SKILL.md via skill-creator

**Files:**
- Create: `.claude/skills/graphghan/SKILL.md`

**Interfaces:**
- Consumes: CLI commands from the library plan.
- Produces: the skill entry point.

- [ ] **Step 1: Load the authoring skills**

Invoke `skill-creator` and `superpowers:writing-skills`. Note their required frontmatter and any structure rules; apply them to the file below.

- [ ] **Step 2: Write SKILL.md**

```markdown
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
```

- [ ] **Step 3: Validate against skill-creator**

Run whatever validation skill-creator provides (frontmatter check, description length, structure). Fix reported issues.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(skill): graphghan SKILL.md"
```

---

### Task 2: workflow.md and design-rules.md

**Files:**
- Create: `.claude/skills/graphghan/references/workflow.md`, `.claude/skills/graphghan/references/design-rules.md`

- [ ] **Step 1: Write workflow.md**

```markdown
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

## 5. Compose (inches, then cells)
- Frame first (twist_frame / link_frame / plaid + twist), which returns the panel rect.
- Vertical budget inside the panel: scene ∥ lettering (lines × pitch) ∥ foot motifs, with gaps; clamp the
  scene, never the lettering.
- Motifs take explicit palette indices; sizes in inches; use gr.cols()/gr.rows() for placement.
- Return a report dict with every box a test could want: panel, scene, text (list), thistles, dragonfly…

## 6. Options page
    uv run graphghan options <slug>
- Two to three variants that differ in one thing each (corners, foot, border style); both gauges.
- Show: stitches × rows, finished size, colors, changes/row mean, busiest row, rough hours.
- Send the preview PNGs too; people decide from the picture.

## 7. Iterate
- Change one variable per round. Re-render both gauges. Re-run the numbers.
- When asked "are the borders symmetric / equal", measure from the chart (period, crossing spacing,
  span, margins) and answer with the numbers; see design-rules.md for what can and cannot be symmetric.

## 8. Final
    uv run graphghan render <slug> && uv run graphghan check <slug>
- Add pattern tests for what makes this design correct (text lines clear, motifs present, mirrors).
- Bump `version` in pattern.toml and write the CHANGELOG entry.

## 9. Ship
- Commit dist/, `uv run graphghan site build`, deploy (CI on main), tag `<slug>/v<version>`.
- Hand over: viewer link, chart.png for Stitch Fiddle, written-rows.txt, yardage table.
```

- [ ] **Step 2: Write design-rules.md**

```markdown
# Design rules (each with the reason it exists)

1. **No run shorter than 2 stitches** in plaid, bands, or frames. One-stitch runs double the color
   changes and look like noise in yarn. The plaid uses a priority rule (gold > red > blue > green)
   instead of twill hatching for exactly this reason; the sett rounds every stripe up to 2 cells.
2. **Lettering needs at least 11 rows per line**; a four-line quote gets 17 rows at sc and 12 at hdc.
   Below that, serifs and bowls collapse. Use the aspect-aware renderer (`graphghan.text.text_line`):
   it renders at 8× and box-filters to the cell aspect, so letters are not stretched at hdc.
   Metamorphous with `bold=0.035, threshold=0.42` is the proven face; true uncials break up.
3. **Words stay clear.** Nothing flanks a text line (mirrored dragonflies beside "and God!" read as
   mess); test that every text line's band across the panel holds only background and ink.
4. **Count changes per row.** Stitch counts mislead; a 244-wide plaid row at 40 changes is fine, a
   braid row at 120 is not. Report mean and busiest row for every option, and name what causes the peak.
5. **Interlace has handedness.** A two-strand twist is a screw thread: its mirror is the opposite
   twist, so a single strip can never be symmetric about its own middle. Make the *frame* symmetric
   (bottom = mirror of top, right = mirror of left) and say so. Anchor crossings to the corner edges
   with an odd number of half-periods so both ends of a strip look the same.
6. **Cells are not square.** sc cells are 0.29 in wide × 0.25 in tall. Draw in inches (`gr.cols`,
   `gr.rows`, inch-space masks) so circles are round on the blanket. The chart will still look
   slightly squatter along rows than along columns; that is the viewer, not the design.
7. **Discs clear silhouettes.** Place moons/suns relative to the hill top and beyond the last stone
   (`standing_stones` does this); assert `not (dilate(moon) & stones).any()` in the pattern tests.
8. **Prefer straight-edged motifs at hdc.** Knots and rings blur first when rows get tall; stones,
   text, bands, and dragonfly silhouettes survive.
9. **Simplify borders to cut rows, not the scene.** A braid strip is 3.5 in; a linked band is 2.5 in;
   the scene and the words are why the blanket exists.
10. **Hand-draw small things natively.** A thistle scaled down from a big bitmap turns into a cactus;
    draw a compact version at the target size (`thistle_small`).
11. **Show, then ask.** Options page with both gauges and numbers first; questions second. People
    choose from pictures and reject from numbers.
12. **Keep the finished design reproducible.** `render --check` must pass; if a motif changes,
    the pattern's tests and CHANGELOG change with it.
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "docs(skill): workflow and design rules"
```

---

### Task 3: crochet.md and stitchfiddle.md

**Files:**
- Create: `.claude/skills/graphghan/references/crochet.md`, `.claude/skills/graphghan/references/stitchfiddle.md`

- [ ] **Step 1: Write crochet.md**

```markdown
# Crochet reference for charts

## Gauges (worsted #4, 5 mm hook, blocked)
| stitch | st/in | rows/in | cell (in) | aspect h/w | notes |
|---|---|---|---|---|---|
| sc  | 3.5  | 4.0   | 0.286 × 0.250 | 0.875 | the graphghan default; curves survive |
| hdc | 3.25 | 2.5   | 0.308 × 0.400 | 1.30  | 60% of the rows for the same size; knots blur |
| dc  | 3.0  | 1.625 | 0.333 × 0.615 | 1.85  | too coarse for lettering at couch size |
Other yarn: bulky #5 with 6–6.5 mm ≈ 2.75 st × 3 rows per in (sc). Always swatch 20 × 20 and block.

## Reading and working
- Chart row 1 is the bottom row (the foundation row). Odd rows are right-side rows and are read
  right to left; even rows left to right. Written rows are emitted in working order already.
- Foundation: chain W + 1 in the first row color; row 1 starts in the 2nd chain from the hook.
- Ch 1, turn each row; turning chains are not stitches.
- Color change: work the stitch until two loops remain, drop the old color, pull the new one through.
- Carry unused colors under the stitches (tapestry) for ≤ 3 colors per row; bobbins for more or for
  long gaps. Braid rows: tapestry. Lettering rows: carry charcoal under cream between letters.
- Block to the finished size; the braid straightens and the letters square up.

## Estimates
- Yardage: 1.1 yd per square inch of sc in worsted, +20% for tails and carried strands. Skeins of 364 yd.
- Time: ~1,100 sc or ~850 hdc per hour plus 3 s per color change; excludes weaving ends.
- A 189 × 184 sc blanket with ~29 changes per row is about 35 hours of stitching.

## Choosing the stitch
- Caps on rows → hdc. Lettering-heavy or curve-heavy → sc. Big and fast with no lettering → dc.
- Mixed stitches are for texture (a dc ridge, a sewn-on braided cord over a plain band); the chart
  itself stays one stitch because every cell assumes the same height.
```

- [ ] **Step 2: Write stitchfiddle.md**

```markdown
# Stitch Fiddle import

Use when the crocheter wants the chart inside Stitch Fiddle (stitchfiddle.com).

1. Charts → Create new chart → Craft: Crochet → Project: **Crochet colorwork** → pick any yarn list
   (or "My own colors"). Continuing past this step accepts their terms and needs an account; do that
   part yourself, not via automation.
2. **Import picture** → upload `patterns/<slug>/dist/chart.png` (one pixel per stitch, exactly N flat colors).
3. Number of colors = N (the palette length); stitches on the longest side = the chart width (or
   height if taller). With an exact-pixel image the import lands 1:1 with no color guessing.
4. Chart settings → Size → gauge proportions: enter the gauge (e.g. 14 st × 16 rows per 4 in) so the
   preview shows the finished shape.
5. Their "Written instructions" should match `written-rows.txt` row for row; a mismatch means the
   stitch count entered at import was wrong.

Limits: free accounts allow charts up to 300 × 300 stitches and 50 colors; Premium 1,000 × 1,000
and 200 colors. Formats: .png, .jpg, .gif. The importer picks colors automatically, which is why
you never upload a photo: reduce to the palette first.
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "docs(skill): crochet and Stitch Fiddle references"
```

---

### Task 4: Motif catalog with thumbnails

**Files:**
- Create: `.claude/skills/graphghan/references/motifs.md`, `.claude/skills/graphghan/assets/*.png`

**Interfaces:**
- Consumes: `uv run graphghan catalog` (library plan Task 9) writing PNGs named after `motifs.CATALOG` entries: `twist-strip, solomon-knot, woven-x, rings, thistle, thistle-small, bloom-icon, dragonfly, amber-drop, standing-stones, plaid, stripe-band`.

- [ ] **Step 1: Render thumbnails**

Run: `uv run graphghan catalog` → `.claude/skills/graphghan/assets/` holds 12 PNGs.

- [ ] **Step 2: Write motifs.md**

```markdown
# Motif catalog

All functions take explicit palette indices and sizes in inches (cells via `gr.cols/gr.rows`).
Thumbnails are rendered at sc gauge, 10 px per stitch, by `graphghan catalog`.

| motif | call | use it for | notes |
|---|---|---|---|
| ![](../assets/twist-strip.png) twist strip | `motifs.twist.twist_strip_in(length, thick, horizontal, period_in=4.0, amp_in=1.0, radius_in=0.3, bg, fg, fit=True)` | braided border strips | inch-true; crossings every 2 in; fitted so a crossing lands on both corners; use through `frame.twist_frame` |
| ![](../assets/solomon-knot.png) Solomon's knot | `motifs.knots.corner_block(w, h, bg, fg, outline=2)` | corner blocks ≥ 6 in | two interlaced stadium rings; blurs at hdc |
| ![](../assets/woven-x.png) woven X | `motifs.knots.woven_x_block(w, h, bg, fg, outline=2, bar_in=0.6)` | saltire corners | reads at any gauge |
| ![](../assets/rings.png) rings | `motifs.rings.rings(bg, fg, r_in=1.1, r_out=1.75, gap_in=1.9)` | wedding rings on a panel | 2 crossings, left ring over at top |
| ![](../assets/thistle.png) thistle | `motifs.thistle.thistle(bg, head, leaf)` | 8.5 in tall thistle (19 × 34 cells at sc) | hand-drawn; scale only via `thistle_scaled` |
| ![](../assets/thistle-small.png) thistle, compact | `motifs.thistle.thistle_small(bg, head, leaf)` | ≤ 6.5 in thistles | native small drawing; `thistle_scaled` picks it under 7 in |
| ![](../assets/bloom-icon.png) bloom icon | `motifs.thistle.bloom_icon(bg, head, calyx)` | a thistle in each link of a linked band | 4 × 4 cells at sc |
| ![](../assets/dragonfly.png) dragonfly | `motifs.dragonfly.dragonfly(w, h, bg, body, wing_fill, wing_line, span=7.0)` | dragonfly silhouettes/outlines | solid wings (`wing_fill == wing_line`) read best under 6 in |
| ![](../assets/amber-drop.png) amber drop | `motifs.dragonfly.amber_drop(w, h, bg, fill, line, a=4.3, b=4.9, edge=0.42)` | the "dragonfly in amber" emblem | blit the dragonfly onto it with `bg` = the drop's fill |
| ![](../assets/standing-stones.png) standing stones | `motifs.stones.standing_stones(w, h, bg, hill, stone, moon)` | Craigh na Dun scene across a panel | moon placed clear of stones; needs ≥ 9 in height |
| ![](../assets/plaid.png) plaid | `motifs.plaid.plaid(w, h, phase_x, phase_y, colors={"G","B","Y","R"}, sett, priority)` | tartan-colored frames | priority rule, min 2-stitch stripes; busy: ~40 changes per full row |
| ![](../assets/stripe-band.png) stripe band | `motifs.bands.stripe_band(length, thick, seq, horizontal)` | zero-change frame bands | seq = [(color, cells), …] |

Frames (`graphghan.frame`): `twist_frame(g, W, H, bg, fg, edge_in=0.5, strip_in=3.5, corners="dot"|"solid"|"cross", margin_in=0.75)`
and `link_frame(g, W, H, ground, rail, bloom, calyx, edge_color, ...)`; both return the panel rect.
Lettering: `compose.text_block(g, lines, x_center, y_top, size_rows, pitch_rows, font_path, color, bg)`.
```

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "docs(skill): motif catalog with thumbnails"
```

---

### Task 5: Acceptance test in a fresh context

**Files:**
- None new (results go in the PR description); symlink is created in the library plan's Task 12.

- [ ] **Step 1: Dispatch a fresh subagent with only the brief**

Prompt (verbatim):
> You are in `~/Projects/graphghan`. A friend wants a couch-sized crochet blanket for her sister with the quote "Dinna fash, sassenach" and Scottish motifs (thistles, a stag if it can be drawn, a braided border). Under 200 stitches and rows, at most 6 colors, single crochet. Produce an options page with at least two variants and tell me where it is and the numbers for each.

The subagent must, without further instruction: trigger the `graphghan` skill, run `graphghan new`, edit the pattern, run `graphghan options`, and report `patterns/<slug>/build/options/options.html` with stitches × rows, colors, changes/row and busiest row per variant.

- [ ] **Step 2: Record what happened**

If the subagent did not trigger the skill or missed a step, fix `SKILL.md` (description triggers, workflow wording) and rerun once. Remove the throwaway pattern folder afterwards (`git clean -fd patterns/<slug>`).

- [ ] **Step 3: Commit any SKILL.md fixes**

```bash
git add -A && git commit -m "fix(skill): trigger wording from acceptance run"
```

---

## Self-review

- **Spec coverage:** §7 SKILL.md → Task 1; references workflow/design-rules → Task 2; crochet/stitchfiddle → Task 3; motifs.md + thumbnails → Task 4; symlink → library plan Task 12; acceptance test → Task 5.
- **Placeholders:** none; every file's content is given in full.
- **Type consistency:** motif signatures in motifs.md match the library plan Task 5/6 (`twist_strip_in(length, thick, horizontal, period_in, amp_in, radius_in, bg, fg, fit)`, `corner_block(w, h, bg, fg, outline)`, `twist_frame(..., corners, margin_in)`); CLI names match library Task 9.

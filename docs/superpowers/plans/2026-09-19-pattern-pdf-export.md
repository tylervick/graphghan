# Pattern PDF Export Implementation Plan (PR 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `graphghan export <slug> --format pdf` writes a printable pattern laid out the way yarn companies sell them (cover, key, chart tiles, written rows), with every string as real text and byte-reproducible output, and commits one such PDF per published chart under `fixtures/import/` as the importer's ground truth.

**Architecture:** One new module, `graphghan/pdf.py`, exposes `to_pdf(doc) -> bytes` over a schema 2 chart document, the same input the PNG/OXS/CSV exporters take, so the CLI change is one `choices` entry and one branch. Everything is drawn on a reportlab canvas with `invariant=1` (no dates, fixed document id), cells are drawn per run from `export.rle_rows`, the cover photo is `preview_png` rendered into memory, and the title uses the repo's Metamorphous TTF. `fixtures/import/generate.py` mirrors `fixtures/chart-format/generate.py`: a test regenerates and diffs bytes.

**Tech Stack:** Python 3.12, reportlab 5 (BSD), Pillow, numpy; pypdfium2 5 (BSD/Apache) only in tests here, to read the PDF back; pytest.

**Spec:** `docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md` §3, §4, §7.1. Closes #109.

## Global Constraints

- Real text everywhere except the cover preview and the overview image. The importer (PR 2 and 3) reads the chart page headers, the key rows and the written rows from the text layer, in the grammars fixed in §4.2 of the spec; those strings are constants in `pdf.py`, and the tests extract them back with pypdfium2.
- Output is deterministic: `invariant=1`, no version string in the bytes (the package version moves on its own; the pattern version is on the cover). Two calls to `to_pdf` on the same document give identical bytes.
- Every committed fixture stays under the 5 MB pre-commit limit; the target for Craigh na Dun at sc is under 1 MB. Draw runs, not cells.
- The chart format does not change. `to_pdf` reads only keys `docs/chart-format.md` already defines and tolerates the absence of every optional one (`foundation`, `gauge.boundary`, `stats.yards_est`, `instructions`, `pattern.dedication`).
- Numbering follows the working order (spec §4.1): row 1 at the bottom, odd row numbers on the right margin and even on the left, columns numbered with 1 at the right. Cell width 10 pt; cell height `10 × gauge.stitches / gauge.rows` (the fabric proportion `preview_png` uses). Tiles are balanced: the columns per page is `ceil(W / ceil(W / max_cols))` so no page holds a sliver.
- `mise run check` before every commit; commit subjects `export:`, `fixtures:`, `docs:`; the session's `Co-Authored-By` trailer.
- The spec is corrected where this plan found it wrong: sc cells are wider than tall (10 × 8.75 pt, not 11 × 12.6), the header grammar uses an ASCII hyphen, and `Creator` carries no version.

## File map

| file | change |
|---|---|
| `pyproject.toml`, `uv.lock` | `reportlab>=5.0.1`, `pypdfium2>=5.13.0` as ordinary dependencies (done: `uv add`) |
| `src/graphghan/pdf.py` | new: `to_pdf(doc) -> bytes`, the layout, the text grammars as constants |
| `src/graphghan/cli.py` | `--format pdf` in `cmd_export` and its `choices` |
| `fixtures/import/generate.py`, `fixtures/import/README.md`, `fixtures/import/*.pdf` | new: one PDF per published chart of every pattern |
| `tests/test_pdf.py` | new: determinism, page count, text grammars read back, size, cover fields, no-optional-keys document |
| `tests/test_import_fixtures.py` | new: committed fixture bytes equal a fresh generation |
| `tests/test_cli.py` | `export --format pdf` writes the default path |
| `README.md`, `.claude/skills/graphghan/SKILL.md`, `docs/chart-format.md` §Interchange | mention the format |
| `docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md` | the three corrections above |

## Tasks

### Task 1: `pdf.py` skeleton, cover and key

- [x] `to_pdf(doc: dict) -> bytes`: canvas on a `BytesIO`, letter, `invariant=1`, `pageCompression=1`; `setTitle`, `setAuthor`, `setSubject` (the pattern id and chart id), `setCreator("graphghan")`.
- [x] Register `Metamorphous` from `text.FONT_METAMORPHOUS` once (module-level guard); body text Helvetica.
- [x] A small `_Page` cursor: margins, `text(line, font, size)` with `simpleSplit` wrapping, `space(pt)`, `need(pt)` that starts a new page, and a footer with the title and page number on every page.
- [x] Cover: title, dedication, quote, `author · license · version`; the preview via `ImageReader` over a PIL image from `preview_png`'s logic (refactor `export.preview_png` so the image builder is a separate `preview_image(a, rgb, cw, ch, grid)` and `preview_png` saves it); materials block (yarn weight, hook, gauge sentence, terms, finished size or grid size, stitch counts, foundation note); yardage per colour when `stats.yards_est` exists; each `instructions[]` section as a heading and wrapped paragraphs.
- [x] Key page: heading `Key`, then one line per palette entry in the grammar `KEY_ROW = "{code}  {name}  {hex}  {yarn}"` with a filled swatch to the left; `yarn` is `brand line colorway` joined with spaces, or `note`, or empty.
- [x] Test: `to_pdf(craigh)` twice gives equal bytes; page 1 text contains the title and `For Meaghan`; the key page text contains `Y  Gold  #D9A21B`.

### Task 2: chart tiles and the overview

- [x] Geometry: `CELL_W = 10`, `cell_h = CELL_W * gauge.stitches / gauge.rows`; usable area after margins, header, number gutters and the key strip; `cols_per_page`, `rows_per_page`, balanced tile counts.
- [x] Overview page when tiles > 1: the whole chart scaled to fit, runs as rectangles, tile outlines with `Chart k` labels.
- [x] Each tile page: header `CHART_HEADER = "Chart {k} of {n}: columns {a}-{b} of {W}, rows {c}-{d} of {H}"`; on the first tile only, `DIRECTION = "Row 1 starts at the bottom right; odd rows are RS and read right to left."`; run rectangles; thin grey lines every cell, black every 10 counted from column 1 / row 1 (so bold lines land on the same multiples on every page); column numbers top and bottom, row numbers odd on the right and even on the left, 5 pt; the key strip along the bottom (swatch + code + name).
- [x] Test: a 189×184 sc document produces 4 × 3 tiles and 1 overview; the page texts carry every `CHART_HEADER` and the ranges cover 1..W and 1..H exactly once; render one tile page with pypdfium2 and check the grid's bounding box is where the geometry says (a coarse sanity check, not the importer).

### Task 3: written rows and the document without optional keys

- [x] Written rows pages: heading, then `export.written_rows` lines with the boundary from `gauge.boundary`, 8 pt, two columns, wrapped continuation lines indented.
- [x] Test: the written-rows text contains `Row 1 (RS):` and the last row; a document stripped of `foundation`, `gauge.boundary`, `instructions`, `pattern.dedication`, `pattern.quote` and `stats.yards_est` still exports; a `tile` cell-kind document exports without any stitch or yardage line.
- [x] Size: Craigh na Dun sc under 1 MB; assert under 5 MB in the test.

### Task 4: CLI and fixtures

- [x] `cmd_export`: `choices` gains `pdf`; branch writes `to_pdf(doc)` bytes to `--out` or `build/exports/<key>.pdf`.
- [x] `fixtures/import/generate.py`: for every `patterns/*/dist/charts/*/chart.json`, write `fixtures/import/<slug>-<key>.pdf`; `README.md` explains what they are for and that `real/` is the gitignored home of foreign PDFs (added in PR 2).
- [x] `tests/test_import_fixtures.py`: every committed PDF equals a fresh `to_pdf` of its chart, and every published chart has a fixture.
- [x] `tests/test_cli.py`: `export craigh-na-dun --format pdf --out tmp` writes a file starting with `%PDF`.
- [x] Docs: README quick start line, SKILL.md export row, chart-format §Interchange bullet, spec corrections.
- [x] `mise run check`; commit; PR with `Closes #109`, a page-by-page description, the fixture sizes, and the cell-size decision noted for review.

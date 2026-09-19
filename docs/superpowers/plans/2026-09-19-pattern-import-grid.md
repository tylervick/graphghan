# Pattern Import, Grid Half Implementation Plan (PR 2 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `graphghan import <file> --into <slug>` turns a 1-px PNG, an OXS file, a CSV, a picture of a chart, or the chart pages of a PDF into a pattern folder that renders and checks, and every PDF in `fixtures/import/` round-trips through it with zero drift against its committed chart.

**Architecture:** Two new modules. `graphghan/rasterchart.py` is the grid reader: it finds every periodic grid on an image from the long straight edges of its lines (gradient, not darkness), fits the pitch, samples the centre of each cell and clusters the samples to a palette; it has no idea what a PDF is. `graphghan/importers.py` is everything around it: the file-kind front ends (OXS, CSV and 1-px PNG through `exporters.read_*`; images and pypdfium2-rendered PDF pages through the grid reader), stitching our own PDF's tiles back together from the `CHART_HEADER` text, and the assembler that validates and writes the pattern folder from two new templates. The CLI is one `import` subcommand over `importers.import_file`. PR 3 adds the prose half on top of the same `ImportResult`.

**Tech Stack:** Python 3.12, numpy, Pillow, pypdfium2 (already a dependency), pytest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md` §5, §7. Closes #17 and the grid half of #108 (#108 stays open for PR 3).

## Global Constraints

- Nothing is written until the assembled document passes `chartdoc.validate_document` and the row-total, palette-code and palette-closure invariants; the target folder must not exist unless `--force`.
- A pattern folder made from someone else's file is local by design: the report's first line says so, and the real fixtures never enter git (`fixtures/import/real/.gitignore`).
- Zero drift means the imported run strings equal the committed `rows` and the hexes equal `palette[].hex`, string for string, reported with `drift_message`'s "first differing row" wording.
- Numbering on our own PDFs follows spec §4.1: `Chart k of n: columns a-b of W, rows c-d of H` with column 1 at the right and row 1 at the bottom, so tile (a, b, c, d) lands on grid columns `W-b..W-a` and grid rows `H-d..H-c`.
- The grid reader ignores a symbol printed over a colour (median of the central 40 % of the cell) and does not read symbol-only grids; a rotated chart (the argyle diamond) is out of scope and recorded as a negative case.
- `mise run check` before every commit; commit subjects `import:`, `fixtures:`, `docs:`; the session's `Co-Authored-By` trailer.

## File map

| file | change |
|---|---|
| `src/graphghan/rasterchart.py` | new: `find_regions`, `read_region`, `cluster_palette`, `snap_to_palette`, `Region` |
| `src/graphghan/importers.py` | new: `import_file`, `ImportResult`, `stitch_own_pdf`, `write_pattern`, `load_chart_png` |
| `src/graphghan/templates/import-design.py.tmpl`, `import-test_design.py.tmpl` | new pattern templates for imported charts |
| `src/graphghan/cli.py` | `import` subcommand |
| `fixtures/import/real/{.gitignore,README.md,manifest.toml}` | the gitignored home of foreign files and the committed expectations |
| `tests/test_rasterchart.py` | synthetic grids: pitch, bold lines, two grids on one image, symbols over colour, no grid |
| `tests/test_importers.py` | OXS/CSV/PNG into a folder, own-PDF stitching, refusal paths, the written folder renders and checks |
| `tests/test_import_roundtrip.py` | every `fixtures/import/*.pdf` imports to its committed chart with zero drift |
| `tests/test_import_real.py` | manifest-driven, skips absent files |
| `README.md`, `.claude/skills/graphghan/SKILL.md`, `docs/chart-format.md` | the command |

## Tasks

### Task 1: the grid reader on synthetic images

- [x] `find_regions(img) -> list[Region]`: greyscale, horizontal and vertical absolute gradients thresholded to an edge mask; per column and per row the longest run of edge pixels (gaps of 2 px bridged); columns and rows whose run is at least 40 px and a quarter of the longest are line candidates; adjacent candidates merge into one line with its segment extent; lines cluster by gap (a gap over three times the median splits); a column cluster and the row lines whose segments overlap its span form a region when both have at least five lines and consecutive gaps within 25 % of their median; missing lines at a double gap are inserted. `Region` carries bbox, pitch, cols, rows, and the fitted line positions.
- [x] `read_region(img, region, cells=None) -> np.ndarray[h, w, 3]`: median RGB of the central 40 % of each cell; `cells` overrides the counts and raises when the fitted pitch disagrees by more than one cell.
- [x] `snap_to_palette(samples, hexes) -> indexes` in Lab with a ΔE ceiling, naming the offending cell; `cluster_palette(samples) -> (indexes, hexes)` greedy in Lab by frequency, clusters under 0.1 % of cells reported as suspected bleed.
- [x] Tests on images drawn with Pillow: one grid with bold every 10 gives the right counts and colours; two grids side by side give two regions; a cell with a symbol drawn over it still reads its colour; a page of text lines gives no region; a known palette snaps and a foreign colour is refused by cell.

### Task 2: our own PDF round-trips

- [x] `importers.render_pages(pdf_path, scale=4)` and `page_texts`; `stitch_own_pdf(pdf_path)` reads the `CHART_HEADER` grammar off each page, takes that page's largest region, checks its cell counts against the header, and places it; the palette comes from the `KEY_ROW` lines parsed off their hex.
- [x] `tests/test_import_roundtrip.py`: for every `fixtures/import/*.pdf`, the stitched rows equal the committed chart's `rows` and the hexes equal its palette.

### Task 3: the assembler and the pattern folder

- [x] `ImportResult` (grid indexes, palette entries, source, regions found, warnings, meta placeholders) and `write_pattern(result, into, title, force)`: `pattern.toml` (title, `IMPORTED: fill me` placeholders, gauge `sc = [3.5, 4.0]` unless given, `size_in` from the grid, palette with hexes, `first_row_color` = the bottom row's majority code), `chart.png`, `design.py` and `tests/test_design.py` from the templates (row totals, palette closure, pinned sha256 of the rows, `validate_document`), `import-report.md`, `CHANGELOG.md`.
- [x] `load_chart_png(path, palette)` for the template's `design.py`.
- [x] Validation gate before writing; after writing, `render` into the folder's `dist/` and run its tests, reporting the outcome.
- [x] Tests: OXS, CSV and 1-px PNG exports of `two-letter-codes` import to a folder in `tmp_path` that renders and whose tests pass; the folder refuses to overwrite; an unknown CSV code is named.

### Task 4: the CLI

- [x] `graphghan import <file> --into <slug-or-path> [--title T] [--palette pattern.toml] [--cells WxH] [--pixels|--raster] [--page N] [--region K] [--box x0,y0,x1,y1] [--force]`; for a PDF without our `Creator`, every region on every page is listed and the largest imported unless `--page/--region/--box` chooses.
- [x] `tests/test_cli.py`: import a PNG export into `tmp_path` and render it.

### Task 5: real fixtures

- [x] `fixtures/import/real/`: `.gitignore` (`*` except the manifest and README), `README.md` (where the files come from, copyrighted, how the test skips), `manifest.toml` with the three C2C entries (cactus PDF page 2, santa PDF page 1, argyle recorded as `unsupported = "rotated 45 degrees, hatched fills"`), dimensions from the first import, `rows_sha256` blank until Tyler eyeballs the preview.
- [x] `tests/test_import_real.py`: skips with the file name when absent; asserts width, height, colour count, and the sha256 when pinned.
- [x] Render `preview-grid.png` of each real import into the scratchpad for the eyeball check-in.

### Task 6: docs and PR

- [x] README quick start, SKILL.md CLI table, chart-format §Interchange, spec §8 note on the argyle negative case.
- [x] `mise run check`; commit; PR with `Closes #17`, references #108, the round-trip result, the real-fixture previews for eyeballing.

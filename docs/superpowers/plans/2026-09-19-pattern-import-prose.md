# Pattern Import, Prose Half Implementation Plan (PR 3 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `graphghan import <file.pdf> --into <slug>` reads the prose of a pattern through the graphghan skill: the colour key, gauge, hook, yarn, finished size, title and dedication, and the written rows, which become the primary source of the chart with the grid as the cross-check. Every published pattern round-trips PDF export → import through the written rows → diff with zero drift, and the tapestry patterns with written rows import with their real defects reported by row number.

**Architecture:** One JSON document, `prose.json`, is the contract between the model and the code (spec §6.2); `schema/import-prose.schema.json` pins it. `graphghan/prose.py` owns it: a structural check, the written-rows-to-grid mapping (working order and row-1 position to display order), the row-total check that names rows, the cross-check against the grid, and the metadata that flows into `pattern.toml`. `graphghan/pdfself.py` writes `prose.json` from a graphghan-made PDF's own text layer, so CI exercises the whole path without a model. `import` becomes a two-run command: the first run stages pages and a request for the skill under `build/import/<stem>/`, the second consumes `prose.json`. The skill gains a reference that tells Claude what to read and how to write the document.

**Tech Stack:** Python 3.12, pypdfium2 (text extraction), numpy; jsonschema (dev) validates the schema in tests; pytest.

**Spec:** `docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md` §6, §7. Closes #108. Builds on PR #116 and PR #120.

## Global Constraints

- Written rows are the primary source when present and `--rows` is `auto` or `written`; the grid is the cross-check. A row whose runs do not sum to the chart width is reported as `row N: runs sum to X, chart width is W (page P: "<text>")` and the import stops; nothing is corrected. `--rows grid` falls back to the grid with the failing rows kept in the report.
- Missing or duplicated row numbers are errors that name the numbers. More than 10 % of rows disagreeing with the grid is an error that says the row-1 position or direction is probably wrong; fewer are warnings with the row and first differing column.
- `chart.row1` in `prose.json` is one of `bottom-right` (default), `bottom-left`, `top-left`, `top-right`; written runs are in working order as printed and are mapped to display order from it and the default row technique.
- `prose.json` for someone else's pattern is derived from their text and is gitignored with the file it came from; the real-fixture manifest records only counts, hashes, and the expected errors.
- The two-run command writes nothing under `patterns/` on the first run; staging goes under the repo's `build/import/<stem>/`, which is gitignored.
- `mise run check` before every commit; commit subjects `import:`, `skill:`, `fixtures:`, `docs:`; the session's `Co-Authored-By` trailer.

## File map

| file | change |
|---|---|
| `schema/import-prose.schema.json` | new: the `prose.json` contract |
| `src/graphghan/prose.py` | new: `load_prose`, `check_prose`, `written_to_grid`, `row_total_problems`, `cross_check`, `apply_prose` |
| `src/graphghan/pdfself.py` | new: `prose_from_own_pdf(path) -> dict` from the cover, key, chart headers and written-rows pages |
| `src/graphghan/importers.py` | `import_file(..., prose=, rows_source=)`; `stage_request(path, into)` writes `build/import/<stem>/`; `ImportResult.meta` carries the prose metadata; `pattern_toml` writes real gauge, hook, yarn, size, dedication, quote, author, notes |
| `src/graphghan/cli.py` | `--prose <path>`, `--rows auto|written|grid`, `--grid-only`; the first-run stop |
| `.claude/skills/graphghan/references/import.md`, `SKILL.md` | the reading workflow and the contract |
| `.gitignore` | `/build/` |
| `fixtures/import/real/manifest.toml`, `README.md` | the three prose fixtures: `prose` file, `rows_source`, expected errors |
| `tests/test_prose.py` | mapping, totals, cross-check, schema validity of every example |
| `tests/test_pdfself.py` | our PDFs read themselves into a valid `prose.json` |
| `tests/test_import_roundtrip.py` | the written-rows path: zero drift, zero mismatches |
| `tests/test_import_real.py` | prose fixtures and their expected errors |
| `docs/chart-format.md`, `README.md`, spec §6 corrections | the command and the contract |

## Tasks

### Task 1: the contract and the mapping (`prose.py`, schema)

- [x] `schema/import-prose.schema.json`: `schema` const `graphghan-import/1`; optional `pattern`, `gauge`, `finished_size`, `palette[]` (code, name, hex, yarn, key_label), `chart` (pages[], width, height, cell, row1, no_stitch), `written_rows[]` (row, side, page, text, runs [[code, count]...], total), `notes`, `instructions[]`, `uncertain[]`. `additionalProperties` allowed at the top level, so a reader ignores what it does not know.
- [x] `check_prose(doc) -> list[str]`: the structural checks that need words the schema lacks (codes match `CODE_RE`, hexes `#rrggbb`, row numbers positive, runs pairs).
- [x] `written_to_grid(rows, width, height, row1) -> (grid, problems)`: `row_total_problems` first (each names row, sum, width, page and text), then missing/duplicate numbers, then placement: bottom starts put row k on grid row `height-k`, top starts on `k-1`; runs reverse when the row's working direction is right-to-left (odd rows when row 1 starts at the right, even rows otherwise).
- [x] `cross_check(grid_from_rows, grid_from_image) -> (mismatches, error)`: per-row first differing column; the 10 % rule.
- [x] `apply_prose(result, doc)`: palette from `palette[]` (hexes from the key, else from the grid clusters in order), title and friends into `result.meta`, gauge converted to per-inch pairs, `finished_size` to inches.
- [x] Tests: a hand-written 5×4 chart in all four `row1` positions; a bad total names its row and quotes the text; a duplicate row 21 is named; a flipped grid trips the 10 % rule with the hint; every example in the tests validates against the schema (jsonschema).

### Task 2: our own PDFs read themselves (`pdfself.py`)

- [x] Cover: title from the PDF `Title`; dedication, quote, `author - license - version` line, `Yarn:`, `Hook:`, `Gauge: N sts and M rows = V unit (stitch, terms)`, `Finished size:`; `instructions` from the headed sections after Colours. Key page: `KEY_RE`. Chart pages: `HEADER_RE` into `chart.pages`, width and height. Written rows pages: `Row k (RS|WS): [ch n, turn, ]runs (N sts)` into `written_rows` with page numbers; wrapped continuation lines rejoined.
- [x] `tests/test_pdfself.py`: for both fixture PDFs the document validates, has every row, and the gauge, hook, size and palette equal the chart document's.
- [x] `tests/test_import_roundtrip.py`: `import_file(pdf, rows_source="written")` rows equal the committed chart and `cross_check` reports zero mismatches.

### Task 3: the two-run command

- [x] `stage_request(path, stem)`: `build/import/<stem>/pages/pNN.png` and `pNN.txt`, `grid.json` (regions, the chosen grid's run strings and hexes), `request.md` (what to fill, the contract, which pages mention key/gauge/row by keyword), and the exit message.
- [x] `import_file(path, prose=..., rows_source=...)`: a PDF with our `Creator` uses `pdfself` when no prose is given; otherwise the caller's `prose.json`, or the staged `build/import/<stem>/prose.json` when it exists; an image file accepts `--prose` the same way (the blog charts).
- [x] `cmd_import`: `--prose`, `--rows`, `--grid-only`; the first run on a foreign PDF stages and stops with exit 0; the report gains a "Written rows" section with the cross-check result.
- [x] `pattern_toml` from `meta`: real `[gauge]`, `hook`, `yarn_weight`, `size_in`, `dedication`, `quote`, `author`, `[notes]`, `[[instructions]]`, palette names and yarn from the key.
- [x] Tests: the CLI stages on a foreign PDF and writes nothing; with `--prose` it writes; `--rows grid` on a document with a bad row keeps the row in the report.

### Task 4: the skill

- [x] `references/import.md`: run `import` once, read `request.md`, look at the page images it names, write `prose.json` (the contract with one worked example), run `import` again, read `import-report.md`, stop at the first row-total failure and look at the page rather than fix the number; how to transcribe "(agave) x 85" and "8sc in c1" and "Rows 9-10" into runs; state `row1` from the chart's numbering, never assume.
- [x] `SKILL.md`: an "Importing a pattern" section and the CLI row.

### Task 5: the tapestry fixtures

- [x] Treasurie heart: `tr-tapestry-heart.jpg` (17×15 raster, top-numbered chart) plus a `prose.json` written from the page text with `row1 = "top-left"`; expected zero mismatches.
- [x] Spotted Horse blanket: the rows 1–10 Stitch Fiddle strip as the grid plus a `prose.json` of all 98 written rows; expected error `row 21 printed twice`, then with the duplicate removed the totals hold and the cross-check covers rows 1–10.
- [x] Orca front panel: `prose.json` of pages 17–20; expected row-total errors for every shaped row (the report names the first), `--rows grid` imports the panel, and the 29-wide rows cross-check clean.
- [x] Manifest entries with `prose`, `rows_source`, `expect_errors`; `tests/test_import_real.py` asserts them and skips absent files.

### Task 6: docs and PR

- [x] README, chart-format §Interchange, spec §6 corrections, `fixtures/import/README.md`.
- [x] `mise run check`; commit; PR with `Closes #108`, the round-trip result through the written rows, the real-fixture outcomes.

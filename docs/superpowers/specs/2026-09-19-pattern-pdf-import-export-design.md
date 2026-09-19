# Pattern PDFs: export like a sold pattern, import what people already own

Date: 2026-09-19
Status: draft (spec for #109, #17, #108; one doc because the exporter exists to feed the importer)
Builds on: `2026-09-09-graphghan-design.md` (pattern folder contract, `export.py`),
`2026-09-10-graphghan-ios-app-design.md` §3 (importers named as the follow-on),
`docs/chart-format.md` (schema 2: run strings, `chart.cell`, `gauge.unit`)
Evidence: `docs/research/corpus/corpus.csv` (133 coded patterns), the ten on-hand PDFs in
`docs/research/corpus/pdf/`, `docs/research/genres/c2c.md` and `tapestry.md`, the #59 shaping
note on #17, and the two probes recorded in §2.3
Closes the design step for: #109, #17, #108

## 1. Purpose

Three issues, one pipeline. #109 asks for `graphghan export --format pdf` that lays a chart out the
way patterns are sold. #17 asks for `graphghan import` over 1-px PNG, OXS and CSV. #108 asks for
`graphghan import` over a pattern PDF, split so that code reads the grid and a model reads the
prose. The exporter is the ground truth for the importer: every published pattern is exported,
imported, and diffed against its committed chart, and that round trip must show zero drift.

The decisions made in the issues are taken as given and are not reopened here:

- Code reads the grid: render the chart page to an image, find the grid lines, sample each cell,
  cluster to a palette. This is #17's raster importer with a PDF renderer in front; one module.
- A model reads the prose: the colour key, gauge, hook, yarn, finished size, title, dedication,
  and the written rows, returned as structured data shaped like the chart format and
  `pattern.toml`. The first version runs through the `graphghan` Claude Code skill. No Apple API;
  a macOS 27 `apple_fm_sdk` spike is optional and last (§9).
- Written rows are the primary source when present; the grid is the cross-check. Every import
  passes `chartdoc.validate_document` and the pattern's own checks before anything is written. A
  row that fails the row-total check is reported with its row number, never fixed.

The site and the iOS app are out of scope. The chart format is not changed (§8).

## 2. What the inputs actually look like

### 2.1 The corpus

Of 133 coded patterns, 75 carry a chart; 14 are colour grids, 7 symbol grids, 3 both, 17 symbol
diagrams. The yarn-company stratum (Yarnspirations, 36 PDF-backed rows) is the layout makers are
used to: a cover with a photo, materials, gauge as "N sts and M rows = 4 in", abbreviations, then
written rows, then the chart pages with a key. Where the corpus codes a row-1 position it is
bottom-right nine times and bottom-left twice; direction is stated in 12 of 36. Written rows
accompany the chart in 18 of the 36.

The six first targets, from `corpus.csv` and the files:

| id | source | chart | written | what it tests |
|---|---|---|---|---|
| `mdc-c2c-santa-blanket` | blog page, chart is an image | colour grid, cell = tile, row 1 bottom-right, no key | no | raster PNG from a web page; tile cells |
| `ys-bernat-corner-to-corner-crochet-cactus-blanket` | Yarnspirations PDF | colour grid, cell = block, row 1 bottom-left, key | no | PDF page with a key; C2C |
| `ys-caron-argyle-c2c-crochet-baby-blanket` | Yarnspirations PDF | colour grid plus symbol diagram, cell = tile, key | no | two chart kinds on one PDF; pick the colour grid |
| `shd-tapestry-blanket` | blog page, chart is an image | colour grid, one stitch | yes, 104 wide, rows 50/56/62 inconsistent, row 21 duplicated | written rows that fail the row-total check on purpose |
| `tr-tapestry-beginner` | blog page, chart is an image | colour grid | yes, 13-st and 18-st swatches | small charts; written rows give per-colour segments |
| `onhand-en-orcacrossbodybagpdfpattern` | purchased PDF | **vector** grid (2,377 paths per page), two 29×77 panels on one page, a cyan "no stitch" ground | yes, `R 1 [←]: (Black) ch 10, ..., 9 sc [9]`, shaped with `inc`/`dec` | two grids on one page; shaped rows |

Three of the six are web pages, not PDFs, and their charts are images on the page. That is why
the raster reader is one module with two front ends (a PDF page renderer and an image file
loader) rather than a PDF feature.

### 2.2 The on-hand ten

Rendered and probed with pypdfium2 (page sizes, text length, image and path counts per page):

- **Outlander Tapestry** (12 pages): a cover, a "Pattern" page with a colour guide (seven greys
  named Black through White, "72 stitches x 118 rows", hook, yarn), then nine pages that are one
  full-page raster image each, and a FAQ. The raster pages are **not a grid**: they are the
  written rows drawn as coloured boxes with a count in each (`← Row 21 [RS]: 13 4 2 3 12 …`).
  There is no chart at all. This is prose for the model, read from the page image, and the
  highest-value real fixture for the prose half.
- **Orca bag** (20 pages): real text throughout, a Stitch Fiddle vector chart on page 9 (front
  and back panels side by side, row numbers odd on the right and even on the left, column numbers
  29→1 left to right), written rows on pages 17–20 in a fixed grammar, and a materials page with
  gauge in cm. Shaped: rows grow from 9 to 29 stitches by `1 inc` at the ends. The chart is
  rectangular because the cyan cells stand for "no stitch".
- **Nancy Afghan, Chaparral, Northeasterly, the Stitchberry set, the swatching guide**: no colour
  grid (texture, symbol diagrams, or photos). They are the negative cases: `import` must say
  "no grid found on any page" and stop, not invent one.

### 2.3 Two probes that shaped §5

1. A dark-pixel projection on the Orca page (scale 4, 34 px cell pitch) finds the column lines
   only where the cells are light; black cells swamp the line signal. So the line finder works on
   the **gradient** (a line is an edge on both sides of a thin band) and on the **period**
   (autocorrelation of the projected gradient gives the pitch before any single line is trusted),
   not on darkness.
2. The Orca page holds two grids 139 pt apart with the row-number gutters between them. A
   single bounding box would merge them. So the finder returns every periodic region on a page
   and the importer chooses, rather than assuming one chart per page.

## 3. Libraries

| need | choice | licence | why |
|---|---|---|---|
| write PDF | **reportlab** 5 | BSD-3 | real text with embedded TrueType (Metamorphous for the title, the OFL face the repo already ships), vector rectangles and lines for the grid, `invariant=1` for byte-reproducible output so the committed fixture PDFs can be drift-checked like `fixtures/chart-format/`. fpdf2 is LGPL, borb and PyMuPDF are AGPL, Pillow's PDF writer rasterises everything. |
| render and read PDF | **pypdfium2** 5 | BSD-3 / Apache-2.0 | one wheel, no system poppler (the builder has no `pdftotext`), renders a page to a PIL image at any scale, extracts text with character boxes, reads document metadata. Also what the Yarnspirations fetch script should fall back to (#115). |
| images, arrays | Pillow, numpy | already dependencies | |

Both are ordinary dependencies in `pyproject.toml`, not an extra: `graphghan export` and
`graphghan import` are core commands, and an optional extra is the kind of thing that fails on
the one machine that matters.

## 4. The exporter: `graphghan export <slug> --format pdf`

Reuses `export.rle_rows`, `export.written_rows`, `export.preview_png`, `chartdoc.finished_size`,
and the `pattern.toml` metadata already on the chart document. Reads the committed
`dist/.../chart.json` exactly as the PNG/OXS/CSV exporters do, so it needs no design build.

### 4.1 Pages, in the order the yarn-company stratum uses

1. **Cover.** Title (Metamorphous), dedication and quote, author and licence. A materials block:
   yarn weight and hook; the palette as "A Cream — Aran / off-white, about 1,180 yd" using
   `stats.yards_est` when the chart's cell kind is `stitch`; finished size from `finished_size`
   when it derives, else the grid size alone; gauge as "14 sts and 16 rows = 4 in in single
   crochet"; terms. The `preview.png` is embedded as the photo. Every instruction section
   (`instructions[]`) follows as headed paragraphs.
2. **Key.** One row per palette entry: a filled swatch (the hex), the code, the name, the yarn,
   the use. The key is also repeated in a strip on every chart page so a tile is readable alone.
3. **Chart pages.** The grid tiled across letter pages, 0.5 in margins, cells 10 pt wide and
   10 × stitches/rows tall (so an sc chart's cells are 10 × 8.75 pt, wider than tall, the fabric
   proportion `preview_png` uses): up to 49 columns and 74 rows per page, balanced so no page
   holds a sliver, so Craigh na Dun at sc is 4 × 3 = 12 pages. Thin grey lines every cell, black lines every 10, column and row numbers in every
   margin. Numbering follows the working order: **row 1 is at the bottom, odd row numbers on the
   right margin, even on the left, columns numbered 1 at the right**, which is the Stitch Fiddle
   layout, the Orca layout, and the bottom-right convention the corpus codes most often. Each
   page header says which columns and rows it holds ("Columns 1–55 of 189, rows 1–50 of 184")
   and the first chart page states the direction in a sentence ("Row 1 starts at the bottom
   right; odd rows are RS and read right to left"). A 1-page overview (the whole chart at
   1 pt cells with the page tiles outlined) precedes the tiles when there is more than one.
4. **Written rows.** `written-rows.txt` reflowed, one row per line, 9 pt, two columns, with the
   turning chain from `gauge.boundary` as today.

Cells are drawn per run (`rle_rows`), not per cell, so a 189 × 184 chart is a few thousand
rectangles rather than 35 thousand. Every string is real text; the only images are the preview
on the cover and the overview.

### 4.2 Marks the importer relies on

- Document info: `Creator` = `graphghan`. The importer uses it to recognise its own layout
  (§6.4). No version string goes into the bytes: the package version moves on its own and would
  break the byte-for-byte fixture check; the pattern version is on the cover.
- Chart page header text, in a fixed grammar with ASCII hyphens: `Chart <k> of <n>: columns
  <a>-<b> of <W>, rows <c>-<d> of <H>`. This is how tiles are placed when the importer stitches pages back together.
- Key rows in a fixed grammar: `<code>  <name>  <hex>  <yarn>`.

None of these are hidden markers; they are the text a maker reads.

### 4.3 CLI and output

`graphghan export <slug> --format pdf [--chart final-hdc] [--out path]`, default
`patterns/<slug>/build/exports/<key>.pdf`, the same as the other formats. `--format pdf` is added
to the existing `choices`. Output is deterministic (`invariant=1`, no timestamps) and must stay
under the 5 MB pre-commit limit; Craigh na Dun at sc is about 150 KB.

## 5. The importer, grid half: `graphghan import <file> --into <slug>`

### 5.1 One command, four file kinds

| input | how it is read | prose |
|---|---|---|
| `.oxs` | `exporters.read_oxs`: palette names and hexes, grid | none needed; names come from the file |
| `.csv` | `exporters.read_csv` with `--palette <toml>` (codes must match) | none |
| `.png` / `.jpg`, 1 px per cell | `exporters.read_png` with `--palette <toml>`, or cluster to a palette when none is given | none |
| `.png` / `.jpg`, a picture of a chart | the raster grid reader (§5.2) | optional |
| `.pdf` | pypdfium2 renders every page at 4× (≈ 300 dpi); the raster grid reader runs on each; text is extracted per page for the prose half | §6 |

An image is treated as a picture of a chart when `--cells WxH` is given or when the grid reader
finds a periodic region covering most of it; otherwise it is 1 px per cell. `--pixels` and
`--raster` force either reading.

### 5.2 The raster grid reader (`graphghan/rasterchart.py`)

Shared by the PDF and image front ends; pure numpy and Pillow.

1. **Find candidate regions.** Convert to greyscale; compute horizontal and vertical gradient
   magnitude; project each onto its axis. Autocorrelate the projections inside a sliding window
   to find spans with a strong period between 4 and 80 px (at 4× render, that is cells from
   1 pt to 20 pt). Contiguous spans on both axes with a consistent period form a region. Return
   every region as `(page, bbox, pitch_x, pitch_y, cols, rows)`, largest first.
2. **Fit the lines.** Inside a region, lines are the gradient peaks nearest to `origin + k ×
   pitch`; the fit is refined by least squares over all peaks so a bold line every 10 does not
   pull the phase. `cols` and `rows` are the counts of cells between the first and last line.
   `--cells WxH` overrides the counts and is an error if the fitted pitch disagrees by more than
   one cell.
3. **Sample cells.** The median colour of the central 40 % of each cell, which ignores symbols
   printed in the cell and anti-aliased line edges. Cells are read left to right, top to bottom,
   which is the chart format's display order.
4. **Cluster to a palette.** With `--palette <toml>` or a key from the prose half, snap each
   sample to the nearest entry in Lab and refuse any sample farther than a threshold (reported
   with its cell). Without one, greedy clustering in Lab with a fixed radius, ordered by
   frequency, coded `A`, `B`, `C`…, named by the nearest of a short colour-name table, and the
   hexes written to `pattern.toml` for the person to rename. A cluster used by fewer than
   0.1 % of cells is reported as a suspected line or symbol bleed, not silently kept.
5. **Assemble pages.** Our own layout is stitched from the page header grammar (§4.2). A foreign
   multi-page chart is stitched from the prose half's `chart.pages` (§6.2) when present; without
   it, each region is a separate candidate and the largest is taken.

Which region is imported: the largest by cell count unless `--page N`, `--region K` (1-based,
in the order the report lists them) or `--box x0,y0,x1,y1` (page fractions) says otherwise. The
report always lists every region found, so the Orca front and back panels come out as regions 1
and 2 on page 9 and the person picks.

### 5.3 What gets written

`patterns/<slug>/` (or the path given to `--into`), through the existing scaffold:

- `pattern.toml` with the title, author, gauge, hook, yarn weight, finished size and palette
  from the prose half, or placeholders that say `IMPORTED: fill me` when there is no prose. An
  imported C2C grid gets `[stitch.<key>] unit = "tiles"` only when the prose says so; nothing is
  guessed (#18 owns the C2C technique itself).
- `chart.png`, 1 px per cell, the imported grid in the palette's hexes.
- `design.py` from a new template that loads `chart.png` through `exporters.read_png` and
  returns a `Grid` and a report with `panel` = the whole chart and `text` = `[]`.
- `tests/test_design.py` from a new template: row totals, palette closure, the chart's sha256
  against the value pinned at import, and `validate_document` on the rendered document. It does
  not run `validate.run_all`'s edge and mirror checks, which describe a bordered blanket, not a
  chart in general (#114).
- `import-report.md`: the source file, pages, every region found, the cluster table, every
  warning, and the cross-check result (§6.3).
- `CHANGELOG.md` with an "Imported from <file>" entry.

Nothing is written until the assembled document passes `validate_document` and the row-total,
palette-code and palette-closure invariants. After writing, `import` runs the folder's tests and
`render`, and reports either "ready: `graphghan render <slug>`" or the failure. A pattern folder
made from someone else's PDF is local by design; the report's first line says the source is
copyrighted and the folder must not be committed.

## 6. The importer, prose half

### 6.1 Two runs of one command

`graphghan import <file.pdf> --into <slug>`:

1. **First run, nothing to consume yet.** Renders and reads the grid (§5), extracts the text of
   every page to `build/import/<stem>/pages/p<NN>.txt` next to `p<NN>.png`, writes `grid.json`
   (the regions and the sampled grid as run strings) and `request.md`: what the model must fill,
   the JSON contract below, the page list, and which pages look like a key, a materials block or
   written rows (by keyword). It then stops with "waiting for `build/import/<stem>/prose.json`;
   open request.md with the graphghan skill", exit 0. `--grid-only` skips the wait and writes
   the folder with placeholders.
2. **Second run, `prose.json` present** (or `--prose <path>`). Assembles, cross-checks, validates,
   writes (§5.3).

The skill does the reading in between. `.claude/skills/graphghan/references/import.md` documents
the contract; `SKILL.md` gains an "Importing a PDF" section that says: run `import` once, read
`request.md`, look at the page images it names, write `prose.json`, run `import` again, read
`import-report.md`, and stop at the first row-total failure to look at the page rather than
fixing the number.

### 6.2 `prose.json`, the contract

Shaped like the chart document and `pattern.toml` so nothing is translated twice. Every field is
optional except `schema`; absent means "not in the PDF", never "unknown".

```json
{
  "schema": "graphghan-import/1",
  "pattern": {"title": "Orca Bag", "author": "Jin", "dedication": "", "craft": "crochet",
              "terms": "US", "language": "en"},
  "gauge": {"stitches": 20, "rows": 24, "over": {"value": 10, "unit": "cm"},
            "stitch": "sc", "stitch_name": "single crochet", "hook": "2.5 mm",
            "yarn_weight": "sport (#2)",
            "boundary": {"kind": "turn", "chain": 1, "counts_as_stitch": false}},
  "finished_size": {"width": 18, "height": 28, "unit": "cm"},
  "palette": [
    {"code": "A", "name": "Black", "hex": "#000000", "yarn": {"brand": "…"}, "key_label": "Black"},
    {"code": "B", "name": "White", "hex": "#ffffff", "key_label": "White"}
  ],
  "chart": {"pages": [{"page": 9, "region": 1, "cols": [1, 29], "rows": [1, 77]}],
            "width": 29, "height": 77, "cell": {"kind": "stitch"},
            "row1": "bottom-right", "no_stitch": "#a9dde4"},
  "written_rows": [
    {"row": 1, "side": "RS", "page": 17, "text": "R 1 [←]: (Black) ch 10, …, 9 sc [9]",
     "runs": [["A", 9]], "total": 9}
  ],
  "notes": {"setup": ["…"], "colors": ["…"]},
  "instructions": [{"title": "Assembly", "text": "…"}],
  "uncertain": ["row 30 wraps onto a second line; count read as 15"]
}
```

Rules the assembler applies:

- `palette[].hex` from the key when printed; otherwise the model gives `key_label` only and the
  assembler takes the hex from the grid cluster with the matching order or name. Codes are the
  key's letters when it has them, else `A`, `B`, `C`… in key order.
- `written_rows[].runs` are in **working order** as printed. The assembler turns them into grid
  rows using `chart.row1` and the default technique (`rows`, start bottom, first side RS, RS
  right-to-left): row k lands on grid row `H − k`, reversed when its side reads right to left.
  `text` is kept verbatim so a failure can quote the line.
- `gauge.over` in cm is kept in cm; `finished_size` in cm is converted to inches for
  `pattern.toml`'s `size_in` (which is inches by contract) and noted in the report.
- `chart.no_stitch` names a colour that is a background, not a stitch. It stays in the palette
  with `use = "no stitch"` so the grid remains rectangular; shaped rows are #37's problem, and the
  report says so when the written rows and the grid disagree only in those cells.
- `chart.row1` is where **written row 1** sits on the printed chart, not how the picture labels
  its rows: Treasurie's heart numbers the picture 1 at the top while its written rows build up
  from the foundation. The cross-check names the corner to try when the guess is wrong.
- When written rows exist, the key's codes are paired with the picture's colours by which code
  the rows put in those cells, so a key without hexes still pairs; a picture that shows only
  part of the chart (Spotted Horse's rows 1–10 strip) is described in `chart.pages` and only
  those rows are cross-checked.

### 6.3 Written rows first, grid as the cross-check

When `written_rows` is present and `--rows` is `auto` (the default) or `written`:

1. Every written row must have a `runs` list whose counts sum to `chart.width` (or to the row's
   own stated `total` when the pattern prints one, and then that total must equal the width).
   A row that does not is reported as `row 56: runs sum to 102, chart width is 104 (page 3:
   "Row 56: 8 A, 14 B, 80 A")` and the import stops before writing. `--rows grid` lets the
   person fall back to the grid for that import; the failing rows stay in the report.
2. The rows that pass are compared to the grid row by row. A mismatch is a warning with the
   row, the first differing column, and both readings; it does not stop the import, because the
   grid reader is the less trusted source. More than 10 % of rows mismatching is an error,
   because then the row-1 position or the direction is probably wrong, and the report says so.
3. Missing rows (a written row 21 printed twice and no 22, as in `shd-tapestry-blanket`) are an
   error naming the missing and duplicated numbers.

Without written rows the grid is the only source and the checks are the validators alone.

### 6.4 Our own PDFs read themselves

A PDF whose `Creator` is `graphghan` has a text layer in a grammar this repo controls (§4.2), so
`graphghan/pdfself.py` writes `prose.json` from it without a model: the key rows give the
palette, the cover gives the metadata, the written-rows pages give `written_rows`, the chart
headers give `chart.pages`. It produces exactly the §6.2 document and goes through the same
assembler and cross-check, so the round-trip test exercises every line of the prose path except
the model. This is not a second design: it is the model's job done by a regular expression for
the one layout where a regular expression is enough. For any other PDF the model is the reader.

## 7. Fixtures and the round-trip test

### 7.1 Our own PDFs, committed

`fixtures/import/<slug>-<key>.pdf` for every `[publish]` entry of every pattern, generated by
`fixtures/import/generate.py` the way `fixtures/chart-format/generate.py` works, with a README.
`tests/test_import_roundtrip.py` does, for each:

1. `to_pdf(chart.json)` must equal the committed bytes (the exporter is deterministic).
2. Import the PDF with `--rows grid`: rows and palette hexes equal the committed `chart.json`.
3. Import with `--rows written` through `pdfself`: the same, and the cross-check reports zero
   mismatches.
4. The 1-px PNG, OXS and CSV exports of the same chart import to the same rows.

Zero drift means `rows` are string-equal and `palette[].hex` are equal, checked with
`drift_message`'s "first differing row" wording. This is the `render --check` model applied to
the importer.

### 7.2 Real PDFs, never committed

`fixtures/import/real/` is gitignored except `manifest.toml` and `README.md`. The manifest has
one table per fixture:

```toml
[[fixture]]
id = "onhand-en-orcacrossbodybagpdfpattern"
source = "local"                          # or the corpus source_url
file = "EN_OrcaCrossbodyBagPDFPattern.pdf"
page = 9
region = 1
width = 29
height = 77
colors = 4
rows_sha256 = ""                          # pinned after Tyler eyeballs the first import
```

`tests/test_import_real.py` skips with the reason "real fixture <file> is absent; see
fixtures/import/real/README.md" when the file is missing, and otherwise asserts the width,
height, colour count and, once pinned, the sha256 of the imported run strings. Expected values
come from the first import Tyler checks against the PDF, then get pinned; a blank `rows_sha256`
means "dimensions only". The README says where the files come from (the corpus `pdf/` folder,
the fetch script, the on-hand ten) and repeats that they are copyrighted.

Order of work on real inputs: the three C2C colour grids first (grid half only, no prose
needed), then the three tapestry patterns with written rows (prose half), then Outlander as the
stretch case where the "written rows" are a raster image the model reads by eye.

## 8. Non-goals and follow-ons

- #112: the on-phone importer. This doc fixes the grid algorithm and the `prose.json` shape it
  will port; nothing here is designed for iOS.
- #18: a C2C technique in the chart format. Imported C2C grids are `technique: rows` grids of
  tile cells and refuse to sequence, exactly as `c2c.md` describes.
- #37: shaped rows. The Orca panels import as rectangles with a no-stitch colour.
- #114: `run_all`'s edge and mirror checks; imported patterns get their own test template.
- #115: the fetch script's missing-`pdftotext` failure.
- #64: `render --check` compares parsed JSON; the round-trip test compares strings on purpose.
- Symbol-only grids (`symbol-grid`, 7 in the corpus) and symbol diagrams: the sampler ignores a
  symbol over a colour, it does not read one without a colour. That is a later chart.
- Rotated charts. The argyle C2C chart (`ys-caron-argyle-c2c-crochet-baby-blanket`) turned out to
  be a diamond rotated 45° with hatched symbol fills, not the colour grid its corpus row suggests;
  the reader finds no grid on it and the real-fixture manifest records it as `unsupported`.
- The chart format does not change. Nothing here adds a key to `chart.json`.

## 9. Optional last: an on-device reader spike

On macOS 27, `apple_fm_sdk` can do the §6.2 extraction with a `@Generable`-style schema. If it
is tried, it is a `--reader apple` flag that writes the same `prose.json` and is measured against
the six real fixtures with the same manifest. It is not part of the three PRs.

## 10. Questions for review

1. Cell size on the chart pages: 10 pt (12 pages for Craigh na Dun at sc). Yarn-company
   PDFs run smaller and fit more per page; makers complain about both. 10 pt is the proposal.
2. Row-number sides: odd on the right and even on the left, columns 1 at the right (§4.1). This
   follows the working direction rather than the reading direction. Say if the reverse is what
   you want printed.
3. The self-reading path (§6.4) stands in for the model in CI. It exercises the assembler and
   the cross-check but not the model's reading; the real fixtures are the only test of that.
4. `--into` defaults to `patterns/<slug>`, which the site build would pick up if it were ever
   committed. The report's first line warns; is a hard refusal to write under `patterns/` for a
   non-graphghan source wanted instead?

## 11. Delivery

Three PRs, in the order the issues depend on each other, each with `Closes #N`:

1. **#109** the exporter (§4), its fixtures (§7.1 items 1 and 4, since the PNG/OXS/CSV round
   trip needs no importer), the two dependencies.
2. **#17** and the grid half of #108 (§5, §7.1 item 2, the three C2C real fixtures).
3. **#108** the prose half (§6, §7.1 item 3, the three tapestry real fixtures, the skill
   reference, README and manifest updates).

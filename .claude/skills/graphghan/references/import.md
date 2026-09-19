# Importing a pattern someone else wrote

`graphghan import` splits the work by what each side is good at (spec: `docs/superpowers/specs/2026-09-19-pattern-pdf-import-export-design.md` §5–6). Code reads the grid: it finds the chart on the page, samples every cell, clusters the colours. You read the prose: the colour key, the gauge and sizes, the title, and the written rows, and hand them back as one JSON document. Written rows are the primary source when the pattern has them; the grid is the cross-check.

## The two runs

    uv run graphghan import <file.pdf|png|jpg> --into <slug>

1. **First run.** The grid is read and the prose is not. The command writes `build/import/<stem>/`:
   `pages/pNN.png` (every page as an image), `pages/pNN.txt` (its text), `grid.json` (what the
   grid reader found: size, colours, run strings, every grid on every page), and `request.md`
   (what to read, and which pages mention a key, gauge or row 1). It stops with
   `waiting for build/import/<stem>/prose.json`.
2. **You write `prose.json`** (below). Look at the page images `request.md` names; the text files
   are there for copying numbers, not for trusting layout.
3. **Second run.** The same command, unchanged. It picks up the staged `prose.json`, maps the
   written rows onto the grid, checks every row, cross-checks against the grid, and writes the
   pattern folder. Read `patterns/<slug>/import-report.md` before saying anything is done.

`--grid-only` skips the prose (placeholders in `pattern.toml`); `--rows grid` uses the grid even
when written rows exist; `--prose <path>` names a document somewhere else. A chart that is an
image on a web page goes in as the image, with `--prose` written from the page's text.

## `prose.json`

Schema `graphghan-import/1` (`schema/import-prose.schema.json`). Every field but `schema` is
optional; leave out what the pattern does not say. Never invent a hex, a gauge or a row.

```json
{
  "schema": "graphghan-import/1",
  "pattern": {"title": "Orca Bag", "author": "Jin", "terms": "US", "craft": "crochet"},
  "gauge": {"stitches": 20, "rows": 20, "over": {"value": 10, "unit": "cm"},
            "stitch": "sc", "stitch_name": "single crochet", "hook": "3 mm",
            "yarn_weight": "aran", "boundary": {"kind": "turn", "chain": 1}},
  "finished_size": {"width": 40, "height": 16, "unit": "cm"},
  "palette": [
    {"code": "A", "name": "Black", "hex": "#201b18", "key_label": "Black",
     "yarn": {"brand": "Wolle Rödel", "line": "Cotton Universal"}},
    {"code": "B", "name": "White", "hex": "#ffffff", "key_label": "White"}
  ],
  "chart": {"width": 29, "height": 77, "row1": "bottom-right",
            "pages": [{"page": 9, "region": 1}], "no_stitch": "#a4dade"},
  "written_rows": [
    {"row": 1, "side": "RS", "page": 17, "text": "R 1 [←]: (Black) ch 10, from the second stitch from the hook, 9 sc [9]",
     "runs": [["A", 9]], "total": 9},
    {"row": 2, "side": "WS", "page": 17, "text": "R 2 [→]: (Black) ch 1, turn, 1 inc, 7 sc, (White) 1 inc [11]",
     "runs": [["A", 9], ["B", 2]], "total": 11}
  ],
  "notes": {"setup": ["Start from the bottom; odd rows are RS and read right to left."]},
  "uncertain": ["row 30 wraps onto a second line; count read as 15"]
}
```

### The key → `palette`

- `code` is the letter the pattern uses; when it uses names ("agave", "Main Color") give `A`,
  `B`, `C`… in key order and put the name in `key_label`. Codes are 1–3 letters.
- `hex` only when the key prints one or shows a swatch you can read. Without hexes the import
  pairs the key's entries with the chart's colours in order of use and says so.
- A colour on the chart that is background rather than a stitch (the cyan around a shaped
  piece) goes in `chart.no_stitch`, not in the palette.

### Gauge, sizes, title

As printed, in the pattern's own units: `over` may be `4 in` or `10 cm`. `stitch` is the gauge
key (`sc`, `hdc`, `dc`); `stitch_name` the words. `boundary` is the turning chain when the
pattern states one. `finished_size` likewise in the pattern's units.

### The written rows

- One entry per row, `row` as numbered, `runs` in **working order exactly as printed**, `text`
  the line verbatim, `page` where it is, `total` the count the pattern prints for that row if any.
- "(agave) x 85, (terra) x 19" → `[["A", 85], ["B", 19]]`. "8sc in c1, 1sc in c2, 8sc in c1" →
  `[["A", 8], ["B", 1], ["A", 8]]`. "Rows 9–10: 3 c1, 11 c2, 3 c1" → two entries. "sc across in
  color 1" → one run of the row's width. An `inc` is one extra stitch in that colour; a `dec`
  is one fewer; a row whose stitches do not add up to the chart width **stays as printed**: the
  import reports it by number, and that is the point.
- `chart.row1` is where **written row 1** sits on the printed chart, not how the picture labels
  its rows. Row-worked crochet builds up from the foundation, so written row 1 is almost always
  the bottom row of the picture even when the image numbers its rows 1 at the top (Treasurie's
  heart does exactly that). `bottom-right` (row 1 at the bottom, odd rows read right to left) is
  the default and the right answer unless the pattern says otherwise. If you guess wrong the
  cross-check says the grid matches when flipped, and names the corner to try.

### What the report will say

`import-report.md` lists every grid found, the palette with cell counts, the written-rows
cross-check ("98 written rows, 0 disagree with the chart"), and warnings. A row-total failure
stops the import before anything is written and names the row, page and text. When that
happens, look at the page; do not change the number to make it fit. `--rows grid` imports the
grid alone with the failing rows kept in the report, which is the right call for a shaped piece.

## Do not

- Commit the folder, the staged pages, or `prose.json` for a pattern that is not ours. They are
  someone else's work; `build/` and `fixtures/import/real/` are gitignored for that reason.
- Read the chart's cells yourself. The grid reader did; if it read wrong, say so in `uncertain`
  and use `--region`, `--page`, `--box` or `--cells` to point it at the right grid.

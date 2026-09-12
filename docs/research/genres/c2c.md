# Genre probe: corner-to-corner (C2C)

Verdict: **refuses for working order; silently wrong in the site manifest.**

## Source

Bernat Crochet Corner to Corner Afghan (BRC0302-002577M, Yarnspirations), a published
yarn-company pattern. The first rows, verbatim from the PDF:

> With MC, ch 6.
> 1st row: (RS). 1 dc in 4th ch from hook. 1 dc in each of next 2 ch. Turn. 1 block made.
> 2nd row: Ch 6. 1 dc in 4th ch from hook. 1 dc in each of next 2 ch – beg block made. (Sl st.
> Ch 3. 3 dc) in next ch-3 sp - block made. Turn.
> 3rd row: Beg block. (Block in next ch-3 sp) twice. Turn. 3 blocks.
> … increasing 1 block each row until there are 58 blocks. … decreasing each side as follows:
> 1st row: (RS). Sl st in each of first 3 dc and next ch-3 sp. Block in same …

Gauge is stated as "16 sc and 19 rows = 4"" — in *single crochet*, a stitch the pattern never
uses in the body. Make & Do Crew's C2C blanket states gauge as "5.5 tiles = 4"" instead. Two
published C2C patterns, two incompatible gauge conventions.

## What one cell is

A block (tile) is `ch 3 + 3 dc` = 4 operations, 3 of them stitches. The first block of a row is
`ch 6, dc in 4th ch, dc, dc` (the turning chain is folded into the beginning block). Each
subsequent block is `sl st, ch 3, 3 dc` into the previous row's ch-3 space. So per tile: 3 dc
always, plus a ch-3 that *does* function as a stitch-height post (it stands in for the first
dc), plus a joining sl st except on the first tile.

## Encoding attempt

The colour grid itself is expressible: `rows` of run strings, one cell per tile, `chart.width`
= tiles across. `technique.type: "c2c"` is reserved, so `chartdoc.sequence` raises
`UnsupportedTechnique` and the Swift `WorkSequence` throws — the app cannot open it for work.
That is the intended "refuse" outcome.

Where it goes wrong anyway:

- `site/build.py` writes `stitches: width * height` into `pattern.json` for every chart
  regardless of technique. For a 58×58 C2C that reports 3,364 stitches; the real count is
  ~13,456 (4 per tile) or ~10,092 (3 dc per tile), depending on what you count. **Silently
  wrong**, in the published manifest, before the app ever refuses it.
- `export.stats` does the same for `stats.stitches` and derives `yards_est` from it; a C2C
  yarn estimate would be off by 3-4×.
- `gauge` cannot say "tiles". A reader computing `finished_size` from `gauge.stitches` would
  get the wrong size unless the author lies and puts tiles in `stitches`.

## What a C2C pass would need

Two turning chains (row-start ch 5 or ch 6; per-block ch 2 or ch 3 depending on that choice);
a diagonal pass order with increase and decrease phases; a stitch-count per pass that is not
the cell count; and a gauge in tiles. None of this is in Phase 1 and it should not be. It is
#18, sharpened.

## Immediate fix (cheap, worth doing now)

Refuse to derive `stitches`, `yards_est` and `finished_size` when `technique.type` is not
`rows` or `rounds`, in both `export.stats` and `site/build.py`, and say so in
`docs/chart-format.md`. Filed under #44.

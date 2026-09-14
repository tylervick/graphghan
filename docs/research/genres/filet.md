# Genre probe: filet crochet

Verdict: **silently wrong.** A filet chart validates as a colour grid and then every derived
number is false. Highest-value structural gap (#44).

## Source

Bella Coco Crochet, *How To Filet Crochet: FREE Pattern* (UK terms; `tr` below is US `dc`).
Verbatim:

> Foundation: Chain multiples of 12 + 3.
> Row 1: tr in fourth ch from hook (skipped 3-ch counts as tr), tr in next 5 ch, [1 ch, skip next
> ch, tr in next ch] three times, tr in next 6 ch, rep from * across …
> Row 2: 4 ch (counts as tr and 1 ch), [skip ch sp, tr in next st, 1 ch] twice, skip ch sp, tr in
> next 6 sts …
> Row 3: 3 ch (counts as tr here and throughout), *tr in next 6 sts, [1 ch, skip ch sp, tr in
> next st] three times, rep from * across, ending with final tr in third ch … Turn.

Confirmed by Yarnspirations' filet collection and the Crochetpop filet generator: a filled block
is `3 dc` (US), an open block is `dc, ch 1 (or 2), skip, dc`, and adjacent blocks share their
edge post.

## What one cell is

A block is 2 or 3 stitches plus a chain, and its boundary stitch is shared with the neighbour:
a row of *n* blocks has `2n + 1` posts in the one-chain variant or `3n + 1` in the two-chain
variant. The turning chain counts as the first post in every row (`3 ch counts as tr`) and is
`4 ch` when the row starts with an open block (`counts as tr and 1 ch`). So the turning chain
depends on the *first cell of the next row*, not on the stitch — a third turning-chain rule the
corpus had not shown before.

## Encoding attempt

`rows` as a two-code grid (`F` filled, `O` open) with `chart.width` = blocks: **validates**.
`technique: rows` with `start: bottom`, RS right-to-left: **sequences**. The app would open it,
show "Row 1 of N", count stitches, and estimate yarn and time — every number wrong:

- `stats.stitches = w × h` counts blocks; real stitches are `(2n+1)` or `(3n+1)` per row plus
  chains.
- `WorkSequence.totalStitches` and every percentage follow the block count.
- `gauge.stitches` would be stated in blocks by a designer who does not know better, and the
  finished-size derivation would then be right by accident and wrong for any other reader.
- The on-deck line would say "then 6 O" — six *what*? The run count is blocks, the worker
  makes posts.

Nothing refuses. That is the difference from C2C, which at least fails to sequence.

## What a filet pass would need

A declared cell cardinality (`cells: {stitches_per_filled: 3, stitches_per_open: 1,
chains_per_open: 2, shared_edge: true}` or a simpler `cells: "filet-2ch"` enum), a turning-chain
rule keyed on the first cell of the row, and stitch counts per pass computed from cells rather
than equal to them. Written rows would then be derivable ("3 ch, tr in next 6 sts, [1 ch, skip,
tr] ×3 …"), which is what Crochetpop and MakeBead already do.

## Immediate fix

Same as C2C: a `cells` declaration that defaults to `one-stitch`, and readers that refuse to
compute stitch-derived numbers for any other value until they implement it. Filed under #44.

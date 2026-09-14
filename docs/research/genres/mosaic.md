# Genre probe: overlay mosaic crochet

Verdict: **refuses for stitch, wrong for direction.** The colour grid fits; the per-cell stitch
and the one-direction rows do not.

## Source

Jera's Jamboree, *Mosaic Crochet: Free chart* — "The Mosaic crochet chart is written in UK. US
terms are in brackets." Verbatim:

> The chart is read from right to left for each row.
> A blank box indicates you will work a dc (US sc) in blo
> A box marked with X denotes working a drop-down tr (US dc) in flo of the st 2 rows below.
> A box marked with (X) denotes working a drop-down tr (US dc) in flo of the st 2 rows below
> BEHIND the tr (US dc) crochet stitch.
> End each row with a dc (sc), ch1 (to secure) and cut yarn/fasten off.
> Row 1: With A, ch25, work 1 dc in the back leg of 2nd ch from hook and in each ch across …
> Row 2: Join B, ch1, 1dc in first st, 1dc in blo of each st across to last st, 1dc in last st
> Row 3: Join A, ch1, dc in first st, 1 dc in blo of next st, 1 drop down tr in the flo, *1 dc
> in blo of next 5 sts, 1 drop down tr in the flo; rep from * …

Cross-checked with The Loopy Lamb (granny square and cup cozy, US terms, `DDC` = drop-down
double crochet, `BLO sc`) and Juniper & Oakes ("worked in one direction only, fastening off at
the end of each row").

## What one cell is

Exactly one stitch — but *which* stitch is the chart's content, not the colour. Colour
alternates by row (A, B, A, B…) and is redundant with the row number. The cell says: plain
(`sc blo`), drop-down (`dc flo into the stitch two rows below`), or drop-down-behind. The
drop-down reaches into row *r−2*, so a cell's meaning depends on the grid two rows down, and
the fabric's visible colour at that cell is the colour of row *r−2*, not row *r*.

## Encoding attempt

- `rows` as the colour grid: expressible but nearly meaningless (every row is one colour).
- `layers.stitch` with legend `{ "s": "sc blo", "d": "drop-down dc flo 2 rows below", "b":
  "drop-down dc behind" }`: the format allows it; **no reader exposes it** (#36). The Work
  screen would show "24 A" and nothing else.
- Direction: every row is worked RS, right to left, with the yarn cut and re-joined.
  `technique: rows` alternates sides and directions — wrong. `technique: rounds` gives every pass
  the same side and direction — right by accident, and mislabels every pass "Round". Neither
  says "fasten off and rejoin each row", which is what a worker needs to know at each row end
  (it changes the on-deck line from "ch 1, turn" to "sc, ch 1, cut, join B").
- Terms: "written in UK, US in brackets" — `terms: "both"` exists in the codebook; the format's
  `terms` is a single value. A document that carries both should declare its *primary* and
  readers should not spell out from the other. Note for Phase 1: enum stays `US`/`UK`; a
  dual-terms pattern picks one.

## What a mosaic pass would need

Per-cell stitch through `layers.stitch` surfaced on runs (#36); a row-boundary rule that is
"fasten off, join next colour, ch 1" rather than "turn" (#43's row-shaped sibling — the
turning-chain object needs a `turn: false` / `rejoin` variant); a legend convention that a cell
may reference rows below it. Stitch Fiddle treats overlay mosaic as its own chart type for
these reasons.

## Immediate fix

None cheap. The right first step is #36's reader path, since mosaic is the genre that would
actually use it. Recorded on #36.

# Genre probe: motifs worked in joined rounds (granny squares, mosaic squares)

Verdict: **partly.** The grid is the wrong shape for a motif, but the *round boundary* is the
finding, and it is the same finding as the rows case.

## Sources

DROPS 120-3 *Seaside Blues* (30 granny squares, joined rounds, US edition), verbatim:

> ch 4 and form a ring with 1 sl st in first ch.
> ROUND 1: ch 4 (= 1 dc + 1 ch), * 1 dc in ring, ch 1 *, repeat a total of 7 times, finish with
> 1 sl st in 3rd ch from beg of round = 8 dc.
> ROUND 2: ch 3 (= 1 dc), … finish with … 1 sl st in 3rd ch from beg of round … Cut the yarn.
> ROUND 3: Change color. Ch 4, …

The Loopy Lamb *Mosaic Granny Square* (overlay mosaic in joined rounds, US), from the coded
record: "worked from the center-out in joined rounds … Do NOT turn your work at the end of
rounds"; from Rnd 2 the join is a **Reverse Slip Stitch Color Change**: "YO with the new color
and pull through the loop on your hook. YO and CH 1 to secure." Gauge is "Rnds 1–9 = 4 in
square" — measured in rounds, not stitches.

## What the boundary is

Per round: a starting chain that **counts** as the first stitch (`ch 3 (= 1 dc)`, `ch 4 (= 1 dc
+ 1 ch)`), work around, a **join** (`1 sl st in 3rd ch from beg of round`), an optional **cut and
re-join** in the next colour, or — in the mosaic square — a join that *is* the colour change and
ends with the next round's chain in the new colour. That is the rows story again (chain, counts
or not, colour) plus one new verb: *join*. Spiral amigurumi is the same story with the verb
*none*.

## Encoding attempt

- The motif itself is not a grid: round 1 has 8 stitches, round 8 has ~100. Out of genre for
  `rows` (#37), same as amigurumi.
- The *blanket* is a grid of motifs — 5 × 6 squares with a colour combination each — and DROPS
  gives an assembly diagram for exactly that. A chart where one cell is one *motif* is a real
  object (Divine Debris's Glenda Ghost is 380 squares in a 19 × 20 ghost graph) and our format
  could carry it as a colour grid whose cells mean "square of combination k", with `cells`
  declaring that a cell is a motif (#44).
- `technique: rounds` cannot say joined-vs-spiral, whether the starting chain counts, or that a
  round ends with a colour change (#43). The `boundary` proposal covers all three with
  `kind: join`.

## Conclusion

Joined rounds are the strongest case for the boundary vocabulary being one object: everything
the row corpus needed (`chain`, `counts_as_stitch`, `color`) recurs verbatim, plus `kind`.

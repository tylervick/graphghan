# Genre probe: knit texture charts (knit/purl, relief)

Verdict: **partly.** The grid and the direction rules fit; the per-cell stitch is the whole
content and no reader surfaces it (#36).

## Sources

DROPS 159-26 *Waffle Love* and DROPS 221-45 *Clean Start* (knitted cloths, US editions).
Verbatim keys:

> = K from RS, P from WS
> = P from RS, K from WS
> = knit from right side, purl from wrong side
> = knit from wrong side

DROPS 157-21 *A Patch of Comfort*: "Diagram shows all rows seen from RS." Instructions are
written as "work according to A.1 (1st row = RS)" with the chart carrying the pattern; DROPS
0-1644 is the same cloth type fully written out ("ROW 1 (wrong side): 3 garter, * knit 4, purl 2
* …").

## Encoding attempt

- Grid: one cell one stitch, rectangular, rows alternate RS/WS — `technique: rows` with knit
  direction defaults works.
- Colour: single colour; `rows` would be one run per row. The chart's information is entirely
  in `layers.stitch` with a legend of *two* symbols that each mean two things: "K from RS, P
  from WS". The RS-face rule documented in Phase 1 makes that legend well-defined; nothing in
  the readers uses it.
- DROPS puts the RS/WS duality *in the legend text itself* — the symbol is defined as a pair.
  A legend value like `"k/p"` with the documented rule is enough; no per-side legend needed.
- "1 ridge = K 2 rows", "3 ridges" edging, "repeat A.2 until 3 sts remain": repeats and edge
  stitches outside the chart (#39). The written version (0-1644) has none of that ambiguity and
  no chart at all — a reminder that for texture, written rows are the primary artifact for many
  knitters (BANA's transcription rule, claim 8).

## Conclusion

Nothing new structurally: it is #36 with a knit legend, which the fixture already models, plus
#39 for repeats. The one documentation fix (symbols describe the RS face) is in Phase 1.

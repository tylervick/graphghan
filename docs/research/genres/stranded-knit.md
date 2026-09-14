# Genre probe: stranded (fair isle) knitting

Verdict: **works for the colour grid; partly for the working order.** The gaps are chart repeats
and technique prose, not the cell model.

## Sources

Spruce Hill Knits, *Fair Isle Knit Hat*: "The colorwork chart contains 10 stitches that will
repeat 8 times per row. The chart is read from [right to left]." Worked in the round on
circulars, "the colorwork chart is worked a total of three times", gauge "22 stitches x 30 rows"
after blocking, US and metric needle sizes, floats advice.

Tin Can Knits, *Clayoquot*: "start with chart A, and work round one, reading from right to
left … knit 2 sts with MC, then knit one stitch with CC1, then knit one stitch with MC. That's
the 4-stitch repeat"; three colours in one round; floats; yarn dominance ("the yarn that is drawn
up from underneath … creates slightly larger stitches").

## Encoding

- Cell = one stitch, colour = the cell. Exactly our model.
- Worked in the round, every round from the right side, read right to left: `technique:
  rounds` with `first_side: RS`, `rs_direction: rtl`. Fits.
- The chart is a **10-stitch repeat worked 8 times across and 3 times up**, not an 80×N grid.
  Our format has no repeat markers; the writer would have to unroll the chart (#39). Unrolling is
  lossless for working but loses what the designer said, and BANA/CYC both ask for repeats to be
  marked.
- Knit-specific gauge (sts and rows over 4 in) fits `gauge`. Needle sizes are free text under
  `gauge.hook` — wrong word, right slot; #32 should name it `tool` or add `needle`.
- Floats, dominance and "knit inside out" are technique prose; `instructions[]`. The app shows
  none of it (#40).
- Crown decreases ("*K2tog, knit 6* repeat") change the stitch count each round: out of the
  grid, same as shaping (#37). A stranded *blanket* would not have this; a hat does.

## Conclusion

For a rectangular stranded panel the format is right today; Phase 1's `terms`/`stitch` fields
are irrelevant (knit has no turning chain and a fixed vocabulary). The two real gaps are repeats
(#39) and the naming of `hook` for needles (#32).

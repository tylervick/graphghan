# Genre probe: amigurumi (spiral rounds, shaped)

Verdict: **refuses, correctly.** Out of genre on three axes at once; worth recording because it
is the most-published crochet object and the clearest statement of what a grid chart is not.

## Source

Supergurumi, *Amigurumi Crochet Bunny*: "crocheted only with single crochet stitches in spiral
rounds", 2.5 mm hook, stitch marker listed as a notion. Verbatim rounds:

> Round 1: 6 sc into the Magic Ring (6 stitches).
> Round 2: [1 increase] repeat till end of the round (12 stitches).
> Round 3: [1 sc, 1 increase] repeat till end of the round (18 stitches).
> Round 4: 1 sc, 1 increase, [2 sc, 1 increase] repeat 5 times, 1 sc (24 stitches).
> … Round 15: Crochet the complete round into the front loop only. …
> Round 16: Fill the head with polyfill. Crochet 18 sc (18 stitches).
> … Round 21: Crochet the complete round into the back loop only. …

## Why it refuses

1. **Every round has a different stitch count** (6, 12, 18, 24, 30 … 24, 18, 12, 6). Rows must
   sum to `chart.width` (#37).
2. **Spiral rounds with no join and no chain** — `technique: rounds` cannot say this (#43); a
   stitch marker is the only way to find the round boundary, and the pattern lists one as a
   notion for that reason.
3. **Placement modifiers carry structure**: "front loop only" at round 15 and "back loop only" at
   round 21 are where the shape bends; they are per-round instructions, not per-cell colour.
4. **Non-stitch steps inside the sequence**: "Fill the head with polyfill" is a step between
   rounds, with no stitch attached. Our pass list has nowhere for it.

A grid cannot carry this and should not try. The correct behaviour is to refuse at
`technique.type` (say, `spiral-rounds`) with a message, which the current code does for anything
other than `rows`/`rounds`. The failure to guard against is a designer choosing `rounds` and
padding rows to a common width — the format would accept it and the counts would be wrong.

## What it tells the format

- `technique: rounds` needs a join declaration even for objects we *can* represent (#43).
- The `notions` field (#33) matters at the hook, not just in the shop: "stitch marker" is
  load-bearing here.
- Stitch counts per pass (CYC: "after every row/round that contains an increase or decrease")
  are the one thing a sequence needs to carry if it ever leaves the grid (#37).

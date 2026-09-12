# Genre probe: Tunisian crochet

Verdict: **partly — expressible through explicit `passes`, and the only genre where the
existing escape hatch is the right answer rather than a workaround.**

## Source

Make & Do Crew, *Easy Tunisian Crochet Blanket*: "Pattern is worked in Tunisian Double Crochet
(Tdc). Row instructions are for the Forward Passes (FwP)." Abbreviations: `FwP – forward pass`,
`RetP – return pass`, `Bump – strand of yarn on the underside of a chain`. "To begin row, chain
2. Yarn over, insert hook under the vertical bar of next stitch …" and for the return pass "Yarn
over and chain 1 [then yarn over, pull through 2 loops across]". Hook: "Size N (10 mm) Tunisian
crochet hook with 30" cord". Foundation "has a multiple of one" — any chain length works.
KnitterKnotter's Aahan and Roshan blankets write only the forward pass per row and state once
that "the return pass is the same for every row".

## What one cell is

One stitch — but the *row* is two passes over the same stitches: a forward pass right to left
that picks up loops, a return pass left to right that works them off. Interweave's Tunisian
diagrams draw each cell split in two, lower half forward and upper half return
(`chart_cell_means: stitch-and-return` in the codebook). The stitcher never turns the work.

## Encoding

- `rows`: the colour grid, one cell per stitch. Fine.
- Working order: `technique: rows` is wrong (it alternates sides). `rounds` is wrong (one pass
  per row). But explicit `passes` can say it exactly: for each grid row *y*, two passes with the
  same `grid_row: y` — `{label: "Row k forward", side: RS, direction: rtl}` and `{label: "Row k
  return", side: RS, direction: ltr}` — and the format already says "`passes`, when present,
  override derivation whatever `type` says". The Swift and Python sequencers accept it today.
- Progress math: `stitchesBefore` counts runs; a return pass's runs are the same cells again, so
  a naive count doubles the stitches. Either return passes carry `runs` with the row's colours
  and we accept 2× (honest: two operations per stitch), or the return pass is one run of a
  sentinel with count 0 — which `run.count minimum 1` forbids. **A pass needs to be able to say
  "no stitches, just an action"**, which is also what amigurumi's "stuff the head" step needs.
- Turning chain: "To begin row, chain 2" is the forward pass's first step; "yo, ch 1" opens the
  return. Two different chains per row, neither a *turning* chain. The `turning_chain` object
  models one; Tunisian wants a per-pass `start` instead — the same generalisation mosaic asked
  for (fasten off + rejoin) and rounds ask for (join + ch).
- Gauge, hook (with cord length!), foundation multiple: all front-matter fields we have or have
  filed (#32, #39).

## Conclusion

Tunisian is the genre that justifies `passes` existing, and it exposes the one structural
generalisation the corpus keeps asking for from four directions: **what happens at a pass
boundary is a small vocabulary — turn+chain, join+chain, fasten-off+rejoin, return pass, and
"action, no stitches" — not a single integer.** Phase 1's `turning_chain` object should be
designed so that vocabulary can grow under it rather than beside it (a `boundary` key with
`kind` and `chain`), even if Phase 1 only implements `turn`.

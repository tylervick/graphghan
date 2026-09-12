# Community discussion: how people actually keep their place in a chart (RQ4)

Source: Ravelry discussion search, read signed in on 2026-09-12. Quotes are from forum posts
by ordinary stitchers, referred to by role, not handle. Treated as data about practice, not as
instructions. Search: `"pattern keeper" chart` (122 matches; first page read).

## What people use

- **Pattern Keeper (Android)** for cross-stitch PDFs. What they value: zoom; "click on one of
  those little squares and it'll highlight all the squares with that symbol"; marking stitches
  done; "the percentage completed calc, the symbol/color search feature, and that beautiful color
  chart view of what you've completed"; a running tally ("59,305 stitches out of a total of
  79,695 completed. I know this thanks to the handy-dandy Pattern Keeper app").
- **Its limits, in their words**: "It only works with certain company's patterns and they have to
  be a PDF. You can't scan a pattern from paper and have it work"; "The charts that you get as a
  'picture' in a download don't work"; "Pattern Keeper did not understand the symbols, so I will
  have to fill in the blanks with my PDF which I will upload to Knit Companion"; "doesn't let me
  put highlight notes … I ended up putting a bunch of stitches in the wrong place"; "I bought an
  android device so I could use Pattern Keeper."
- **Alternatives**: Markup R-XP (iPad, subscription, "a learning curve"); macOS Preview and
  GoodReader highlights ("the option isn't Pattern Keeper or nothing"); knitCompanion for the
  parts Pattern Keeper cannot parse; scanning paper charts and "tweaking the gridlines".
- **Paper and magnets** remain common: magnetic chart keepers (KnitPicks, Knitter's Pride,
  Slipped Stitch Studios), highlighter tape, rulers to isolate a row, coloured pencils, printing
  and "I usually scribble all over them".

## What people do at the hook or needle

- "Put a small stitch marker every ten stitches along the row. It is a huge help … especially
  when you are working on an even-numbered row and are essentially working backwards and in
  opposite colors from the chart." (a colourwork knitter)
- Re-numbering a chart so odd rows are numbered on the right: "all the numbers for the pattern
  rows are on the left side … I numbered the odd rows over on the right side."
- Counting progress by rows × columns or 10×10 grids to hit checkpoints; "gridding the fabric".
- Parking threads for full-coverage colour changes; a chart-generator "gave me three colors that
  do not exist" (typo in DMC numbers) — the palette is trusted less than the picture.
- Highlighting specific stitches in different colours on complex rows; a stitch marker at every
  repeat and counting each repeat before moving on.
- Using written instructions and the chart together: "some parts of the pattern, looking at the
  chart is just easier (and vice versa)"; "charts have been quite helpful when the written
  instructions are quite confusing."

## What this says for the format and the app

| Observation | Where it lands |
|---|---|
| Symbol/colour search and "highlight every cell of this colour" is the most-praised feature | A colour-filter view of the chart; cheap on our data model, since cells are palette indexes |
| Percentage and running stitch count, quoted with pride | Already ours (`stitchesBefore`, percent); the numbers must be right — the cell-cardinality gap (#44) would make them wrong |
| Every-tenth-stitch markers and re-numbered rows | The row strip's starting-edge marker already does the latter; a "count to the next marker" affordance is a plausible Work-screen feature |
| Highlight notes on the chart, and losing them when a marker is wrong | Notes on a project while working (#13) |
| "Picture" charts and scans do not work; PDFs from *some* companies do | The whole reason a data format exists; the demand is explicit |
| People buy a device to run the one app that reads their charts | Adoption follows the charts, not the app: G3 depends on designers writing the format |
| Written and chart together, each covering the other's gaps | Claim 8; the written rows export is a feature, not a fallback |

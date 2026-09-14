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

## US and UK terms, from the designer and tester side (RQ6, claim 4)

Search: `"US terms" "UK terms" designer` (87 matches; first page read).

- Designers routinely publish two versions and recruit testers per system: "Both US Terms and UK
  Terms available … Testers: 5 (3 for US Terms, 2 for UK Terms)"; "written in both US Terms and
  UK Terms"; "Choice of UK or US terms; please state which you prefer". Errata are tracked per
  version ("Corrections: US Terms … UK Terms Finished Measurements should read …").
- Inference from the designer's country fails: "Just because a designer lives in the UK …
  [doesn't] necessarily mean they will use UK terms (depends on where they learned)"; "I'm UK
  too but learnt US terms as made more sense and 95% patterns are in US terms I've found."
- "Is this pattern UK or US terms?" is a recurring thread type, resolved by forensic reading
  ("if it has a sc … it is in US terms"; "honestly, after looking at the designer's [photos] …
  I do feel this is US terms"). Undeclared terms cost readers a forum thread.
- A designer's own poll: buyers "would buy one written in US terms and 36% would buy one written
  in UK terms … For a designer who wishes to sell their [patterns] …" — a market reason to
  write both, which is why `terms_also` exists in the proposal.
- Some patterns carry "a 'key' for US/UK terms" inline — a conversion table inside the pattern.

Consequence: declared per document, `both` is a real state, and the app must never guess.

## Working a graphghan, in crocheters' own words (RQ1, RQ4)

Search: `graphghan` (570 topics). Threads read: *graphghan tips, tricks, and advice?*, *Carrying
yarn for a graphghan*, *Graphghan Yarn Amount and HELP*.

- **Losing the direction is the failure people guard against.** "I do mine 1 block to 1 sc and
  just when I turn the work start on the next block up … So you will read it from left to right
  then right to left. And a highlighter is great for marking what you have already done. When I
  would stop for the evening I would make sure I was into a row so I would know which way I was
  going or I would mark the end of the row with an arrow telling me which way to start." That is
  the cursor, the direction line and the row strip, described by someone who had none of them.
- **Yarn management is the dominant question**, and it is a per-region decision, not a pattern-
  level one: "for different portions I used different carrying techniques"; "I did NOT carry
  yarns underneath the white parts … you could really see the grey background yarn underneath";
  "large stretches of background color … would be best worked in intarsia rather than stranded";
  "2 bobbins going for each letter … and tapestry-carry the main color"; "I hate weaving [in
  ends] with a passion." Nothing in any format models this; the closest is prose in
  `instructions`, and the app shows none of it (#40).
- **Working every row from the right side** is a real practice for tapestry: "This afghan was
  done all from the right side, I started and ended each row" — the mosaic-style boundary
  (`rejoin`) used on a plain tapestry graphghan by choice; and "you could crochet a row of sc
  backwards" to avoid turning. The boundary vocabulary in the proposal covers both; a fixed
  `turn: true` does not.
- **Charts are placed inside plain fields**: "work as normal until you get to where you want the
  graph to start and then work the graph" — a 20"×20" logo in a 60"×80" blanket. Our chart is the
  whole blanket; an offset-within-margins is a cheap generator feature and a cheap format note.
- **Mirroring by reading direction**: "I followed the pattern right to left for the first
  [dragon], and then left to right for the second one. Not sure I'll do that again – it was
  confusing." A `mirror` flag on a pass is a plausible authored feature; noted, not filed.
- People design their own graphghans in Stitch Fiddle and post the link when asking for help —
  the chart tool is upstream of the forum, and a format they could hand over would be too.

## The chart is technique-agnostic; the gauge decides everything (RQ3, RQ6)

Threads: *Filet crochet graphghan?*, *Graphghan Help for a Novice Crocheter*.

- A novice bought "a graph pattern … 180 squares by 225 squares", planned C2C, and computed
  "about 6 squares over 4 inches, I'll have a 120" x 150"" blanket. The reply: "You really
  should consider working this where 1 SC is 1 square, which is how the pattern is undoubtedly
  meant to be done." **The same graph is worked in sc, hdc, dc, C2C or filet at the maker's
  choice, and the cell size — the gauge — decides the finished object.** Our published sc and hdc
  variants of one chart are exactly this; a `gauge.unit` of tiles would let a C2C variant be
  honest about its size.
- **Cell aspect is a known pain**: "my SC are not square, so my portraits tend to look squashed
  … I put my image thru Paint and stretch the height by 25%"; "you can adjust Excel so that the
  cells (rows and columns) are square"; "substitute a tr for every dc … our tr stitches are
  usually the exact height we need to make our blocks square". Our `cell_aspect` from
  `gauge.stitches / rows` is the modelled answer to a problem makers solve by hand in Paint.
- **Makers design graphghans in cross-stitch software and spreadsheets**: KG-Chart, PCStitch
  Pro, knitPro (microrevolt), Excel with an X per filled block, Photoshop Elements to posterise
  and pixelate. "For me the biggest part of a graphgan has been the creation of a good chart."
  So the cross-stitch interchange formats (OXS, `.pat`) *are* graphghan formats in practice —
  our OXS export and Stitch Fiddle's OXS import are the bridge that already exists.
- **Shadow filet** uses a half-filled block as a third cell value (tr blocks, "guess where to put
  the stitch half way through the block") — filet's cell vocabulary is not binary (#44).
- Filet colourwork exists ("carry your colors up vertically behind the front of your work") and
  one designer "cuts his color changes and does not weave in ends … more suitable for wall
  hangings".

## Cell geometry and sub-cell colour (axis 14)

Threads: *Tapestry crochet charting* (Stitch Fiddle group), *Best tapestry crochet technique for
precise detail?*

- Offset grids are a common request: "chart my tapestry crochet designs where the rows are
  offset. A chart using offset circles is used to design a circle motif such as … the bottom of
  a bag or a mandala". Stitch Fiddle's reply: "your case is a very common case … we will create
  predefined shapes for these particular cases (mochila bags, tapestry, mandala)".
- A 300 × 225 tapestry (30+ colours, "7' x 5.25'", 14 sc × 17 rows = 4 in) fights "the stair-step
  effect because of the shape of the stitches" on diagonals. Remedies offered: finer gauge;
  "half stitches … allows for more detail on diagonal type things (like circle edges)"; a
  "non-decrease double sc" where "you change colour in the middle of the stitch. So one half SC
  is the angled colour and the other half is the next colour"; long sc reaching rows below;
  motifs worked at angles and joined.
- One-direction rows have a cost: "each new row leaned slightly to the right — resulting in
  swatch corners that weren't 90°."
- The maker "made the chart by converting an image to grid in StitchFiddle" — again the chart
  tool is upstream of the forum.

**For the format:** sub-cell colour has a precedent — OXS carries half and quarter stitches for
cross-stitch — so a `cells` declaration (#44) could admit `half` as a value without inventing
anything. Offset/circular grids are a different coordinate system and stay out of genre; the
honest move is to say so in `chart-format.md`.

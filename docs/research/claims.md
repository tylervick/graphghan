# Claim register

Every design claim the chart format rests on, with its evidence and what would flip it. Counts
are recomputed from `corpus/corpus.csv` after every batch (see `README.md`, revision loop).
"Stratum" names the codebook field and values the count is taken over. A claim is **settled**
only when its stopping criterion in README.md is met; until then it is **open** however strong
it looks.

Evidence tiers: **C** = coded corpus count; **S** = a standard says so (CYC, BANA, ISO);
**P** = primary source read in full (a spec, a manual); **T** = tool behaviour observed;
**A** = academic; **U** = user research; **X** = secondary/second-hand.

| # | Claim | Status | Evidence now | Flips if |
|---|---|---|---|---|
| 1 | The turning chain cannot be derived from the row's stitch; it must be authored | **settled: authored** | T: Stitch Fiddle has no turning-chain field anywhere and its written export is colour runs only; Crochetpop's generator keys the filet chain on the next row's first cell (ch 5 = dc + space). C (batches 1-6, 56 row-worked crochet/Tunisian): sc→1 in 12/13 (92%); hdc→1 in 3/4; **dc→3 in 7/12, dc→2 in 5/12 (58%)**; "in pattern" 1 in 7/10; filet keys on the next row's first cell; C2C on the block height. dc cannot reach the 95% bar; stated at all 46/56 (82%). Pre-corpus: Pre-corpus: hdc→ch 1 in 3/3 on-hand; dc→ch 2 in 1/1; two patterns alternate ch 1/ch 2 within one piece; DROPS 203-1 states ch 1 for sc rows and ch 3 for dc rows in the same pattern (P) | ≥95% of ≥30 coded row-worked patterns per stitch agree on one count |
| 2 | Whether the turning chain counts as a stitch is stated by designers and varies | **settled: a field** | T: Crochetpop prints "(counts as dc + first sp)" and teaches a lesson titled "Turning Chain Counts as Stitch". C (n=56): stated 26/56 (46%), yes 16 / no 10. Pre-corpus: stated in 7 patterns, both values present; Red Heart RHC0502 "does not count"; DROPS foundations "(= 2 double crochets)" count | fewer than 20% of coded patterns state it, or all agree |
| 3 | The turning chain's colour at a colour change is ambiguous without a field | open, **genre-bound** | C (n=56): applicable in 32, stated in 13 (all `next`) — 3/32 in plain rows, 13/15 in Yarnspirations mosaic. Optional, never derived, shown when present. Designers do not write this down. Keep the field optional; never derive; do not show it unless stated | corpus shows one convention ≥95% |
| 4 | US/UK terms must be declared per document, never inferred | **settled** | C (n=109): declared 42, inferable-only 55 (yarn-company house style), none 12; US 37 / UK 3 / both 2. Bernat mixes US stitches with the UK verb "miss". P: Ravelry pattern pages carry a **Crochet terminology** field with `US` and `both US and UK` values; catalogue-wide counts: US 456,772 / UK 56,507 / **unknown 157,211** (23%). S: CYC table (`dc`, `tr`, `htr` collide). C: 7/9 on-hand declare. P: DROPS same pattern in both editions; UK edition carries a leftover US "double crochet" | a reliable inference rule is found (there is none: UK `dc` patterns can contain no `sc`) |
| 5 | The stitch vocabulary is open; a closed enum is wrong | **settled** | C (n=109): special stitches defined in 39/109 (36%); placement modifiers in 66/109 (61%). S: CYC "designers may use special abbreviations". C: custom stitches in 6/10 on-hand (puff, hhdc, camel, picot sc, waistcoat, splhdc) | corpus shows <5% custom stitches |
| 6 | Chart-level stitch is the right model for a grid chart; per-cell stitch is the known extension | strong, open | A: Seitz et al. classify grid charts this way. S: BANA "colour strand or type of stitch". T: Stitch Fiddle separates "colorwork" from "overlay mosaic"; X: tapestry sites | a corpus grid chart mixes stitches per cell without being mosaic/filet |
| 7 | One cell is not always one stitch (filet, C2C, mosaic, double knitting, Tunisian) | **settled** | C (64 charted): one-stitch 26, block 7, tile 6, unstated 21 — 30% of the known are not one stitch. T: Stitch Fiddle's chart-type list; Ravelry's gauge has a *repeats* unit. T: Stitch Fiddle lists these as distinct chart types. C: C2C corpus patterns define a tile as ch 3 + 3 dc; filet blocks as 3 dc / dc-ch2-dc | — (structural, proven by construction) |
| 8 | Written instructions must accompany a chart (accessibility) | settled for design | T: Stitch Fiddle's written export is Premium and runs-only; Crochetpop prints full rows with chain, turn, foundation and per-row counts. C (64 charted): 31/64 (48%) ship written rows — the standard is not the practice. P: Ravelry-wide, chart 102,826 vs written 493,847; accessibility-tagged patterns < 0.2%. Ravelry has a "Universal – no written language" class. S: BANA guidelines; Atherley ("charts can be used, but full written instructions must also appear"); T: Stitchmastery and Crochetpop both emit written rows with foundation and turning chain | — |
| 9 | Front-matter fields patterns actually carry | **settled for priority** | C (n=109): hook mm 105 (96%), finished size 96 (88%), hook US 91 (83%), abbreviations 86 (79%), notions 74 (68%), skill 72 (66%; labels vary), yarn weight 67 (61%; 51 number+name), put-up 65 (60%), substitution 24 (22%), fibre 11 (10%), **care 2 (2%)**. P: Ravelry form (`formats/ravelry-form.md`). S: CYC submission checklist; Lion Brand taxonomy (T) | corpus counts per field decide which are ≥50% present |
| 10 | Joined rounds vs spiral must be declared | open | C: pilot (DROPS 120-3 joined with counting starting chain; Yarnspirations amigurumi spiral pending) | corpus shows rounds patterns never vary within an object type |
| 11 | Interop in adjacent crafts happens through PDF conventions or a single vendor's format, never a multi-vendor data format — except WIF | strong | P: WIF spec; T: Pattern Keeper + Ursa export convention; knitCompanion `.kc`; Stitchmastery `.knit`, TXT out; OXS single-vendor | a multi-vendor crochet/knit chart format is found |
| 12 | A published format needs: contents manifest, tiny required core, unknown/obsolete-key rules, namespaced vendor extensions with a registry, versioning reader rule, a second implementer | strong | P: WIF (all of these), knitout (versioning + extensions), OXS (counter-example: single vendor) | — |
| 13 | What a worker needs at the hook that the app does not show | open | U: pending Meaghan session (`users/meaghan-questions.md`) | — |
| 14 | `gauge.stitches / rows / over.value` is the right gauge shape | settled, **needs a unit** (#48) | T: Crochetpop — "50×50 cells finishes about 12.5 × 10 in worked in sc, and 40 × 40 in worked C2C". C (n=109): sts+rows over 4 in 72, over 2 in 6, other 5, **tiles 4, rounds 3, blocks 1**, unstated 17. P: Ravelry models gauge as stitches *or repeats* over 1/2/4 in. Add `gauge.unit` (additive, unhashed). Ravelry `gauge`, `gauge_divisor`, `row_gauge`, `gauge_pattern`; CYC "sts and rows = 4 in"; C: `gauge_form` counts pending | corpus shows a dominant form we cannot express (e.g. tiles for C2C — which we already cannot) |

## How to update

After a batch: run the counts script (to be added as `corpus/counts.py`), paste the numbers into
"Evidence now", change status only when README's criterion is met, and record the delta in
`log.md`.

## New observations awaiting a claim number

- **Row 1 is often a different stitch from the body.** Red Heart RHC0502 works row 1 in hdc into
  the chain and every later row in splhdc; DROPS 0-1396 and the Nancy Afghan open with a plain
  row before the pattern. Chart-level `gauge.stitch` cannot say this. Cheap answer:
  `foundation.note`; structural answer: a per-pass stitch override (#36). Watch `notes` in the
  corpus for how often it recurs. (from `genres/tapestry.md`)
- **Intarsia vs tapestry is a stated technique choice on the same chart** ("Work color changes
  using intarsia technique"). One pattern so far; a field only if publishers state it routinely.
- **C2C gauge has two incompatible conventions**: Bernat states it in sc ("16 sc and 19 rows =
  4""), Make & Do Crew in tiles ("5.5 tiles = 4""). (from `genres/c2c.md`, feeds #18)

- **Foundation `first_stitch_in` tracks the stitch height** (n=109): 2nd chain in 40 (sc/hdc), 4th
  in 21 (dc), 3rd in 6, 6th in 1 — authored per gauge key, as Phase 1 proposes.
- **Chain position**: start of the next row in 29, end of the row in 10 (n=56). Rendering
  choice, not data; start-of-row is the majority and Yarnspirations' house style.
- **Chart row 1 corner is not universal**: bottom-right 5, bottom-left 2 of those that say. The
  direction fields must be written out, never defaulted silently, when we publish. (pilot 1)
- **A third turning-chain rule: keyed on the first cell of the next row.** Filet (Bella Coco):
  "3 ch (counts as tr)" before a row starting with a filled block, "4 ch (counts as tr and 1 ch)"
  before one starting with an open block. Not derivable from the row's stitch *or* from the
  previous row — it depends on the chart cell about to be worked. (from `genres/filet.md`; #44)
- **Dual-terms documents exist**: "written in UK, US terms in brackets" (Jera's Jamboree mosaic).
  `terms` stays a single primary value; a dual document declares its primary. (`genres/mosaic.md`)
- **Overlay mosaic rows end with fasten-off and a re-join, not a turn.** The turning-chain
  object needs a row-boundary variant beyond `count` (claim 10's row-shaped sibling).
- **`craft` is missing from the format** and is the first field every catalogue keys on (Ravelry,
  Lion Brand tags, LoveCrafts). Unhashed, one line, Phase 2. (`formats/ravelry-form.md`)
- **Held-together strands** is a real, small field: CYC's checklist, Ravelry's form and one corpus
  pattern all state it. Belongs with yarn (#34).
- **A boundary can be a stitch instead of a chain.** Little Puffs (Pattern Princess): rows start
  "ch 1 (does not count)" then a *stacked single crochet* that "counts as a dc" — zero-chain
  boundary with a stitch as the post. Divine Debris's Glenda Ghost squares are joined rounds that
  are also *turned* ("ch 1, turn" at round start) — `join` and `turn` are not exclusive. Both
  fit the proposed `boundary` object (`kind`, `chain`, plus a `post` stitch) and neither fits an
  integer. (batch 5)
- **A chart whose cell is a whole motif is a real, published object**: Glenda Ghost's assembly
  graph, "each block in the graph represents a square". `cells` (#44) should allow `motif`.
- **The chart is technique-agnostic and the maker chooses the stitch** (Ravelry threads: a 180×225
  graph bought "shown in crochet", planned in C2C, advised back to sc). Supports publishing one
  grid at several gauge keys, and `gauge.unit` for tile-based variants. Cell aspect is a real
  maker problem ("stretch the height by 25%"); `cell_aspect` from gauge is its modelled answer.
- **Cell geometry beyond aspect — a new axis (14).** Ravelry threads describe tapestry charts
  "where the rows are offset", "Tapestry Crochet paper … slightly staggered effect", and "the
  diagonal lines produced by standard tapestry crochet techniques" on a 300×225 chart. Our cells
  are axis-aligned rectangles with one aspect ratio; a staggered grid or a per-row lean is not
  expressible. Community source, not corpus; the earlier "converged at 13 axes" claim in the
  superseded research doc is amended here. Whether it needs a field or a note depends on whether
  any published chart-driven pattern actually ships an offset grid — none in the corpus does.
  Sub-cell colour (half stitches for diagonals) has an OXS precedent (half/quarter stitches).
- **Publishers rely on house style instead of declaring terms** (batch 6a): Yarnspirations
  declares in 0/15; every one is US by house convention. Independent designers declare far more
  often. A document travelling outside its publisher's site loses the house style, so the field
  must be written, not inferred (claim 4, strengthened).
- **Chain colour is genre-dependent** (batch 6a): stated in 13/15 Yarnspirations mosaic
  patterns (the colour changes at the row start and the chain is in the new colour) versus 3/32
  plain row patterns. Claim 3 stays optional, but "rarely stated" was a rows-only observation.
- **C2C turning chain at a yarn company**: `inc-row=6; dec-row=3` in 4/5 Caron/Red Heart C2C
  patterns and `inc-row=5; dec-row=2` in the hdc one — the row-start chain tracks the block's
  stitch height, and "Ch 2 at beg of row counts as hdc" is stated. Consistent with claim 1's
  filet finding: the chain is keyed on what is about to be worked.
- **Hook size is mm-first at scale** (Ravelry): the five sizes with no US letter (2.5, 3.0, 4.5,
  7.0, 7.5 mm) are used by ≈123k patterns. #32's `{mm, us}` with mm required is confirmed.
- **Difficulty is not a catalogue fact**: 82% of Ravelry crochet patterns are unrated; the three
  scales in use (CYC 1-4, Lion Brand levels, Ravelry 1-10) do not map. `skill_level` (#33) is a
  designer's own label, stored as printed with a CYC mapping where one is claimed.

- **The chart tool has no turning chain; the generator does** (2026-09-14, tools driven). Stitch
  Fiddle — where makers design graphghans and post links from the forums — has no field for the
  turning chain and exports colour runs; Crochetpop, a generator, prints it at the start of every
  row with "counts as" and keys it on the first cell. The number lives in prose or in a generator
  that knows the stitch, never in the chart. Phase 1's `boundary` is the field the chart tool
  lacks, in the format the chart tool already imports (.oxs / 1-px PNG).
- **Stitch Fiddle's "Work" setting has a value we lack**: always one direction (start every row
  at the same edge). That is `boundary.kind: rejoin`; the settled `technique.turn` boolean cannot
  say it.
- **Cursor granularity, from a second tool**: Stitch Fiddle's progress tracker offers full rows ·
  stitch-by-stitch · group of stitches — row, stitch, run. Our Work screen's run cursor is the
  middle option; a stitch-level cursor (#11, #20) is the finer one and it is on offer in the
  free tier.

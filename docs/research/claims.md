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
| 1 | The turning chain cannot be derived from the row's stitch; it must be authored | open, strengthening | C (pilot 1, 16 row-worked crochet): sc→1 in 5/5; hdc→1 in 3/3; **dc→3 in 3/6, dc→2 in 3/6**; stated at all 12/16. Pre-corpus: Pre-corpus: hdc→ch 1 in 3/3 on-hand; dc→ch 2 in 1/1; two patterns alternate ch 1/ch 2 within one piece; DROPS 203-1 states ch 1 for sc rows and ch 3 for dc rows in the same pattern (P) | ≥95% of ≥30 coded row-worked patterns per stitch agree on one count |
| 2 | Whether the turning chain counts as a stitch is stated by designers and varies | open, strengthening | C (pilot 1): stated 8/16, yes 5 / no 3. Pre-corpus: stated in 7 patterns, both values present; Red Heart RHC0502 "does not count"; DROPS foundations "(= 2 double crochets)" count | fewer than 20% of coded patterns state it, or all agree |
| 3 | The turning chain's colour at a colour change is ambiguous without a field | open, **weak** | C (pilot 1): stated in 1/16 (`next`). Designers do not write this down. Keep the field optional; never derive; do not show it unless stated | corpus shows one convention ≥95% |
| 4 | US/UK terms must be declared per document, never inferred | strong, open | C (pilot 1): declared 17/28, inferable-only 10/28, US 15 / UK 2. S: CYC table (`dc`, `tr`, `htr` collide). C: 7/9 on-hand declare. P: DROPS same pattern in both editions; UK edition carries a leftover US "double crochet" | a reliable inference rule is found (there is none: UK `dc` patterns can contain no `sc`) |
| 5 | The stitch vocabulary is open; a closed enum is wrong | strong, open | C (pilot 1): special stitches defined in 13/28; placement modifiers (BLO/FLO/post/ch-sp) in 17/28. S: CYC "designers may use special abbreviations". C: custom stitches in 6/10 on-hand (puff, hhdc, camel, picot sc, waistcoat, splhdc) | corpus shows <5% custom stitches |
| 6 | Chart-level stitch is the right model for a grid chart; per-cell stitch is the known extension | strong, open | A: Seitz et al. classify grid charts this way. S: BANA "colour strand or type of stitch". T: Stitch Fiddle separates "colorwork" from "overlay mosaic"; X: tapestry sites | a corpus grid chart mixes stitches per cell without being mosaic/filet |
| 7 | One cell is not always one stitch (filet, C2C, mosaic, double knitting, Tunisian) | strong | C (pilot 1, 18 charted): one-stitch 10, tile 4, block 1, n/a 2, unstated 1 — 28% not one-stitch. T: Stitch Fiddle lists these as distinct chart types. C: C2C corpus patterns define a tile as ch 3 + 3 dc; filet blocks as 3 dc / dc-ch2-dc | — (structural, proven by construction) |
| 8 | Written instructions must accompany a chart (accessibility) | settled for design | C (pilot 1): only 5/18 charted patterns ship written rows — the standard is not the practice. S: BANA guidelines; Atherley ("charts can be used, but full written instructions must also appear"); T: Stitchmastery and Crochetpop both emit written rows with foundation and turning chain | — |
| 9 | Front-matter fields patterns actually carry | open | C (pilot 1, n=28): hook mm 28, finished size 26, abbreviations 22, hook US 22, notions 17, yarn weight 17 (13 give number+name), skill 15, put-up 12, substitution 8, fibre 3, **care 1**. S: CYC submission checklist; Lion Brand taxonomy (T) | corpus counts per field decide which are ≥50% present |
| 10 | Joined rounds vs spiral must be declared | open | C: pilot (DROPS 120-3 joined with counting starting chain; Yarnspirations amigurumi spiral pending) | corpus shows rounds patterns never vary within an object type |
| 11 | Interop in adjacent crafts happens through PDF conventions or a single vendor's format, never a multi-vendor data format — except WIF | strong | P: WIF spec; T: Pattern Keeper + Ursa export convention; knitCompanion `.kc`; Stitchmastery `.knit`, TXT out; OXS single-vendor | a multi-vendor crochet/knit chart format is found |
| 12 | A published format needs: contents manifest, tiny required core, unknown/obsolete-key rules, namespaced vendor extensions with a registry, versioning reader rule, a second implementer | strong | P: WIF (all of these), knitout (versioning + extensions), OXS (counter-example: single vendor) | — |
| 13 | What a worker needs at the hook that the app does not show | open | U: pending Meaghan session (`users/meaghan-questions.md`) | — |
| 14 | `gauge.stitches / rows / over.value` is the right gauge shape | settled | C (pilot 1): sts+rows over 4 in 17/28, over 2 in 3, other span 2, **tiles 4** (all C2C), unstated 2. Ravelry `gauge`, `gauge_divisor`, `row_gauge`, `gauge_pattern`; CYC "sts and rows = 4 in"; C: `gauge_form` counts pending | corpus shows a dominant form we cannot express (e.g. tiles for C2C — which we already cannot) |

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

- **Foundation `first_stitch_in` tracks the stitch height** (pilot 1): 2nd chain in 8 (sc/hdc), 4th
  chain in 9 (dc), 3rd in 2 — so it is authored per gauge key, as Phase 1 proposes.
- **Chain position is a coin flip**: written at start of the next row in 6, at the end of the row
  in 5. Rendering choice, not data; the on-deck line can say either. (pilot 1)
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

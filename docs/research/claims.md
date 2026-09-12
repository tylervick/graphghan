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
| 1 | The turning chain cannot be derived from the row's stitch; it must be authored | open | C: pilot in progress. Pre-corpus: hdc→ch 1 in 3/3 on-hand; dc→ch 2 in 1/1; two patterns alternate ch 1/ch 2 within one piece; DROPS 203-1 states ch 1 for sc rows and ch 3 for dc rows in the same pattern (P) | ≥95% of ≥30 coded row-worked patterns per stitch agree on one count |
| 2 | Whether the turning chain counts as a stitch is stated by designers and varies | open | C: pilot. Pre-corpus: stated in 7 patterns, both values present; Red Heart RHC0502 "does not count"; DROPS foundations "(= 2 double crochets)" count | fewer than 20% of coded patterns state it, or all agree |
| 3 | The turning chain's colour at a colour change is ambiguous without a field | open | Orca bag chains in next colour; Craigh na Dun in old; corpus field `tc_color` mostly unstated so far | corpus shows one convention ≥95% |
| 4 | US/UK terms must be declared per document, never inferred | strong, open | S: CYC table (`dc`, `tr`, `htr` collide). C: 7/9 on-hand declare. P: DROPS same pattern in both editions; UK edition carries a leftover US "double crochet" | a reliable inference rule is found (there is none: UK `dc` patterns can contain no `sc`) |
| 5 | The stitch vocabulary is open; a closed enum is wrong | strong, open | S: CYC "designers may use special abbreviations". C: custom stitches in 6/10 on-hand (puff, hhdc, camel, picot sc, waistcoat, splhdc) | corpus shows <5% custom stitches |
| 6 | Chart-level stitch is the right model for a grid chart; per-cell stitch is the known extension | strong, open | A: Seitz et al. classify grid charts this way. S: BANA "colour strand or type of stitch". T: Stitch Fiddle separates "colorwork" from "overlay mosaic"; X: tapestry sites | a corpus grid chart mixes stitches per cell without being mosaic/filet |
| 7 | One cell is not always one stitch (filet, C2C, mosaic, double knitting, Tunisian) | strong | T: Stitch Fiddle lists these as distinct chart types. C: C2C corpus patterns define a tile as ch 3 + 3 dc; filet blocks as 3 dc / dc-ch2-dc | — (structural, proven by construction) |
| 8 | Written instructions must accompany a chart (accessibility) | settled for design | S: BANA guidelines; Atherley ("charts can be used, but full written instructions must also appear"); T: Stitchmastery and Crochetpop both emit written rows with foundation and turning chain | — |
| 9 | Front-matter fields patterns actually carry: skill level, notions, put-up, hook mm+US, yarn weight, care | open | C: pilot. S: CYC submission checklist; Lion Brand taxonomy (T) | corpus counts per field decide which are ≥50% present |
| 10 | Joined rounds vs spiral must be declared | open | C: pilot (DROPS 120-3 joined with counting starting chain; Yarnspirations amigurumi spiral pending) | corpus shows rounds patterns never vary within an object type |
| 11 | Interop in adjacent crafts happens through PDF conventions or a single vendor's format, never a multi-vendor data format — except WIF | strong | P: WIF spec; T: Pattern Keeper + Ursa export convention; knitCompanion `.kc`; Stitchmastery `.knit`, TXT out; OXS single-vendor | a multi-vendor crochet/knit chart format is found |
| 12 | A published format needs: contents manifest, tiny required core, unknown/obsolete-key rules, namespaced vendor extensions with a registry, versioning reader rule, a second implementer | strong | P: WIF (all of these), knitout (versioning + extensions), OXS (counter-example: single vendor) | — |
| 13 | What a worker needs at the hook that the app does not show | open | U: pending Meaghan session (`users/meaghan-questions.md`) | — |
| 14 | `gauge.stitches / rows / over.value` is the right gauge shape | settled | Ravelry `gauge`, `gauge_divisor`, `row_gauge`, `gauge_pattern`; CYC "sts and rows = 4 in"; C: `gauge_form` counts pending | corpus shows a dominant form we cannot express (e.g. tiles for C2C — which we already cannot) |

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

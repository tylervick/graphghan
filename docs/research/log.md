# Research log

Dated entries: what landed, what changed in the design as a result, and why. Newest last.

## 2026-09-12 — plan and first batch

**Landed.** Research plan (`README.md`), codebook (~60 fields), Meaghan question set, WIF 1.1
spec read in full, format post-mortems (WIF, knitout, OXS, KnitML), tool teardowns (Stitch
Fiddle genre list, Crochetpop, Stitchmastery, Pattern Keeper + Ursa export convention,
knitCompanion, Lion Brand taxonomy), claim register with 14 claims, corpus tooling
(`fetch-yarnspirations.sh`, `tools/html2txt.py`, `tools/corpus_csv.py`), a 40-file raw corpus
(10 on-hand, 4 Yarnspirations, 1 Lion Brand, 8 DROPS incl. 2 US/UK twins, 16 indie pages,
1 cross-stitch), and a pilot coding run (38 files, every 4th double-coded) launched as a
workflow.

**Access.** Yarnspirations rate-limits the whole domain after ~5 requests (HTTP 429 challenge,
also on `.json`); DROPS is browser-only; Ravelry needs a sign-in in the extension's Chrome
window; Stitch Fiddle and Yarnspirations need the extension's site permission; LoveCrafts'
designer handbook 404/500s.

**Findings that changed the design note** (none applied yet — spec revisions wait for the
pilot counts):

- DROPS states both turning-chain rules in one pattern: ch 1 not counting before a sc-height
  row, ch 3 counting before a dc-height row. Strengthens claims 1 and 2; nothing new to model.
- DROPS' UK edition carries a leftover US "double crochet" in one sentence. Terms must be
  declared, never inferred (claim 4).
- Stitch Fiddle's crochet chart wizard lists C2C, colorwork, filet, overlay mosaic, free form,
  Tunisian colorwork, Tunisian with return pass, symbol chart — an independent statement of the
  axis inventory (claims 6, 7).
- Pattern Keeper and knitCompanion both run on PDFs with hand-drawn grids and counters, and
  Ursa ships a PDF-layout export "for Pattern Keeper". Interop in the working-app layer is a
  layout convention, not data (claim 11). This is the demand signal for G3.
- WIF's mechanisms — contents manifest, tiny required core, skip rule, private-section
  registry, obsolete keys never error, sparse defaults, one revision then frozen — are the G3
  checklist (claim 12). Our format has three of seven.

**Open.** Pilot results and inter-coder disagreements; codebook revision; Yarnspirations batch
through Chrome; Ravelry designer form and forums; Meaghan session; genre probes; cross-stitch
corpus (every free source needs an account or a cart).

## 2026-09-12 — pilot coding results (batch 1, 38 files)

48 agents, 0 errors; 28 usable patterns (10 listings/tutorials at low confidence). Inter-coder
disagreement 28/560 fields (5%), all formatting or n/a-vs-unstated; codebook revised to v2.
Counts in `claims.md`. Headlines: dc turning chain splits 3/3 between ch 2 and ch 3; sc and hdc
consistent at ch 1 (5/5, 3/3); `tc_color` stated in 1/16; written rows accompany only 28% of
charts; care instructions appear in 1/28; `first_stitch_in` follows stitch height (2nd vs 4th).

**Design consequences.** Claim 3 (chain colour) is demoted to optional-never-shown-unless-stated;
Phase 1 keeps the field but the UI must not promote it. Claim 9: `care` (#35) drops to lowest
priority; hook mm, finished size, abbreviations, notions and yarn weight are what publishers
actually write. The design note's section 4 now cites these counts instead of the ten on-hand
patterns.

## 2026-09-12 — batch 2 (13 files: 7 indie tapestry, 6 DROPS)

17 agents, 0 errors; 12 usable. Inter-coder disagreement 7/224 (3%), down from 5% after v2.
Codebook v3 (charts lost by extraction → `unextracted`; `tc_color` n/a; ounces/meters; more
finishing steps; short rows are shaping) and v4 (knit analogues). Corpus at 51 rows, 40 usable.
dc turning chain still 3/3 split; hdc 3/3 at ch 1; "counts as a stitch" stated in 12/24, yes 5 /
no 7. Batch 3 (18 files: mosaic, filet, amigurumi, stranded knit, cross-stitch) launched.

## 2026-09-12 — batch 3 (18 files: mosaic, filet, amigurumi, stranded knit, cross-stitch page)

23 agents, 0 errors; 10 usable (8 of 18 were tutorials/roundups at low confidence — the
technique-specific strata are thinner in complete free patterns than the blanket strata).
Inter-coder disagreement 29/280 (10%), up from 3%: the new strata hit codebook gaps (no
`square`, `inset-mosaic`, `counted`; knit joins; round-end chains in the next colour). Codebook
v5. Corpus at 68 rows, 50 usable. New: The Loopy Lamb's mosaic rounds close with a reverse
slip-stitch colour change whose `ch 1` is in the *next* colour — `tc_color: next` stated in
rounds, where the row corpus almost never states it.

## 2026-09-12 — batch 4, Ravelry, cumulative

Batch 4 (4 Tunisian, 1 cross-stitch PDF): 7 agents, 0 errors, all usable. Corpus: 73 rows, 55
usable; 21 double-coded; cumulative disagreement 73/1288 fields (6%). Ravelry signed in: the
designer "add a pattern" form read in full (`formats/ravelry-form.md`) — gauge has a *repeats*
unit, hook sizes are mm-first, and "Universal – no written language" is a recognised class.
Claims and the design note now cite n=55. Two additions queued for Phase 2 from Ravelry:
`craft` on `pattern`, and `gauge.unit`. Genre probes complete for 7 genres; matrix in
`genres/README.md`; filet remains the only "silently wrong".

## 2026-09-12 — batch 5 (Ravelry-listed indie designers, 9 files)

12 agents, 0 errors; 6 usable. New boundary variants: a stacked sc standing in for the turning
chain (zero chains, counts as a dc); joined rounds that are also turned. A motif-grid chart
(each cell one square). UK-terms stratum attempt via UK designer sites mostly failed (Typepad
and Squarespace pages are JS-only; one non-UTF-8 page crashed html2txt, now fixed). UK docs in
corpus: 5. Yarnspirations fetch running throttled at 20 s; batch 6 will be the whole stratum.

## 2026-09-12 — Ravelry community threads; Stitch Fiddle driven; saturation amended

Ravelry signed in. Forum threads read on chart-keeping apps, graphghan working practice, US/UK
terms from the designer side, filet portraits and technique choice (`users/community-threads.md`).
First-hand statement of the failure the Work screen prevents ("mark the end of the row with an
arrow telling me which way to start"). Stitch Fiddle wizard driven: genre list with definitions,
yarn-line palettes, **.oxs and 1-px PNG import** (our two exports), gauge dialog identical to ours.
Yarnspirations fetch resumed at 20 s cadence after the 429 lifted; batch 6a (15 files) coding.

**Saturation amended**: a fourteenth structural axis — cell geometry (offset rows, stitch slant)
— surfaced from community threads, not from patterns. Recorded in `claims.md`; no corpus
pattern exhibits it yet, so no field is proposed.

## 2026-09-12 — Ravelry population data; Yarnspirations stratum complete

Ravelry advanced-search filters read as population data (`formats/ravelry-form.md`):
terminology US 456,772 / UK 56,507 / unknown 157,211; Pattern Instructions chart 102,826 vs
written 493,847, accessibility tags < 0.2%; Colorwork mosaic 9,796; Crochet Techniques filet
13,884, tapestry 12,526, Tunisian 8,831; Construction in-the-round 173,120 vs flat 109,102;
yarn weight "no weight specified" 68,246; held-together ≈2%. Claims 4, 8, 10 updated with
these. Community threads on chart-keeping apps, graphghan working practice, terms from the
designer side, filet portraits and tapestry charting (`users/community-threads.md`); a
fourteenth axis (cell geometry: offset rows, slant; sub-cell colour with an OXS precedent) is
recorded, amending the earlier "converged at 13".

Yarnspirations: 51/52 fetched after the rate limit lifted; batches 6a (15, C2C + mosaic) coded,
6b (18, filet/Tunisian/stranded/amigurumi) and 6c (13, rows/rounds/dishcloths) running. Corpus
at 97 rows before 6b/6c. Stitch Fiddle wizard driven (imports OXS and 1-px PNG). LoveCrafts
handbook is down server-side. Phase 1 revision proposal written, not applied
(`proposal-phase1-revision.md`).

## 2026-09-12 — corpus pass complete (batches 6b, 6c)

128 coded, 109 usable, 37 double-coded, 5.0% cumulative field disagreement. Final counts in
`corpus/runs/counts-final.txt` and `claims.md`. Claims 1, 2, 4, 5, 7 marked settled; 3 revised
to genre-bound; 9 settled for priority. Design note §4 cites n=109/56. Yarnspirations house
style: US stitches, UK verb "miss" (Bernat). Motif blanket (Caron Spirals) uses unjoined spirals
sewn into panels with joined edging — `round_join: both` widened beyond tutorials.

Open for the next pass: print stratum (book/magazine, ≈17% of Ravelry); Meaghan's session
(RQ1 first-hand evidence still zero); tool teardowns behind logins (Stitch Fiddle editor,
Crochetpop); the Phase 1 revision decision.

## 2026-09-14 — Stitch Fiddle and Crochetpop driven; Phase 1 revision accepted

Tyler created free accounts; both tools driven read-only (one empty test chart left in Stitch
Fiddle). Findings in `tools/README.md`. Headline: the chart tool has no turning-chain field and
exports colour runs; the generator prints the chain at row start with "counts as", keyed on the
first cell, and prints three boundary kinds (turn, join, none). Stitch Fiddle's direction model
has an "always one direction" value we lack — `boundary.kind: rejoin`. Crochetpop's size FAQ
(50×50 = 12.5×10 in sc, 40×40 in C2C) is the `gauge.unit` case in one sentence.

Tyler accepted `proposal-phase1-revision.md`. Design note §5–§7 rewritten: `gauge.boundary
{kind, chain, counts_as_stitch, color}`, `gauge.unit`, `gauge.terms_also`, `pattern.craft`,
`pattern.language`; Phase 1 implements `kind: turn` only. Issues #48 (`gauge.unit`) and #49
(`craft`, `language`, `terms_also`) filed; #43 carries the other kinds.

DMC: `dmc.com` not yet allowed in the Chrome extension; cross-stitch stratum still one chart.

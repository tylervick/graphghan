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

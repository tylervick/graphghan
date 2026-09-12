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

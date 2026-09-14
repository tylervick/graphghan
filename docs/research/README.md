# Research plan: what the chart format has to be, for other tools to adopt it

Date: 2026-09-12
Status: approved approach; executing
Goal: **G3** — the chart format is published for other tools and designers to adopt. This is the
horizon the v2 spec planned for ("so it can be published for others later without a rewrite").
Supersedes the after-the-fact coverage frame in
`../superpowers/specs/2026-09-12-pattern-data-model-research.md`, which stays as the record of
the first pass and its flaws.

## Why the first pass was not enough

It ran ad hoc rounds, then built a verification frame after stopping and declared saturation
against it. The corpus was ten PDFs that happened to be on hand. "Three of three hdc patterns"
is N=3. No user research. The two richest sources — Ravelry and real tools — were skipped because
they needed a login or an install. Every stopping criterion below is set **before** the research
it governs, and every claim carries its evidence count.

## Research questions

| RQ | Question | Done when |
|---|---|---|
| 1 | What must a chart carry so someone works it with no other document? | Meaghan and two other crocheters complete a row sequence from the app alone; every "what do I do now?" is logged and answered by a field or a documented no |
| 2 | What must a pattern carry to be publishable? | Every item on the CYC checklist, BANA's guidelines, and the Ravelry, Etsy and LoveCrafts listing forms has a home in the format or a documented no |
| 3 | Which genres do we represent, refuse, or extend to? | Every genre in the matrix has 2-3 real charts hand-encoded in the format; zero "silently wrong" cells |
| 4 | What do tools store, and what do crocheters actually use while working? | 6+ apps torn down with exported files read; 20+ coded forum threads about working from patterns and apps |
| 5 | What makes a craft interchange format get adopted or die? | WIF spec read in full; KnitML, OXS and knitout adoption histories written up; a governance, versioning and conformance model chosen; at least one other tool author consulted |
| 6 | Which conventions vary by designer (must be authored) vs. are standard (may be assumed)? | A convention is assumable only at >=95% agreement across >=30 coded patterns in the relevant stratum; otherwise it is authored |

RQ5 is what G3 adds over G2. It is also the one where being wrong is most expensive, because a
published format cannot be un-published.

## Method

### Coded corpus (RQ1, RQ2, RQ6)

60-100 patterns, stratified so that each cell of craft x technique x source has at least three:

- **Craft**: crochet, knit, cross-stitch.
- **Technique**: flat rows, joined rounds, spiral rounds, C2C, filet, tapestry/graph, overlay
  mosaic, fair isle / stranded, Tunisian.
- **Source type**: yarn-company free patterns (Yarnspirations, Lion Brand, Red Heart — strictly
  CYC-formatted), European (Drops/Garnstudio — UK/EU terms, deliberately), independent designers
  (Ravelry, Etsy, blogs), magazines/books where obtainable, and the ten already on hand.

Every pattern is coded against `codebook.md` into `corpus.csv`. Coding is done in parallel by a
workflow; a 10% sample is re-coded by a second reader and disagreements resolved by amending the
codebook, not by picking a side. Every claim in the design spec then reads "N of M in stratum S."

### Primary access, not summaries (RQ2, RQ4, RQ5)

- Ravelry forums and pattern pages through Tyler's login in Chrome. Read-only.
- The WIF specification obtained and read in full, not characterised second-hand.
- Tools actually installed: Stitch Fiddle, Crochetpop, Pattern Keeper, knitCompanion, Chart
  Minder, Stitchmastery, CrochetCharts, and the top three row-counter apps. Export files read.

### User research (RQ1, RQ4)

Meaghan, working Craigh na Dun. `meaghan-questions.md` is a fixed question set and an observation
guide; Tyler runs it and relays answers verbatim. Marked first-hand. Two further crocheters
recruited through Ravelry groups, marked as such.

**Deferred 2026-09-14** (Meaghan away; Tyler's call): the session runs retroactively when she is
back. Phase 1 proceeds without it because every Phase 1 field is authored, additive and unhashed —
RQ1's answers can change the Work screen's wording in the design note's §6.4 and nothing else.
Results still land in `users/meaghan-session-1.md`; RQ1's "done when" stays open until then.

### Genre probes (RQ3)

For each technique above, obtain two or three real charts and hand-encode them in the current
format. Record the verdict — works, refuses, silently wrong — and the exact field that fails.
The representability matrix becomes a test log.

### Format post-mortems (RQ5)

Why WIF lived (committee of competing vendors, 1990s, still universal). Why KnitML died. How OXS
got adopted across cross-stitch tools. How knitout is governed. What a conformance suite that
another implementer would actually run looks like — ours has fixtures, but nobody outside the
repo has run them.

## Artifacts

All under `docs/research/`:

- `README.md` — this plan.
- `codebook.md` — the fields and allowed values every pattern is coded against.
- `corpus.csv` — one row per pattern; the evidence.
- `claims.md` — the claim register: every design claim, its current evidence count and stratum,
  confidence, and what would flip it.
- `tools/` — one teardown note per application.
- `genres/` — one probe note per genre with the hand-encoded chart.
- `formats/` — post-mortems for WIF, KnitML, OXS, knitout.
- `users/` — Meaghan's session and the two others.
- `log.md` — dated entries: what was added, what changed in the spec as a result.

## Revision loop

1. A batch lands (corpus rows, a teardown, a probe, a session).
2. `corpus.csv` counts are recomputed; `claims.md` evidence counts update.
3. Any claim whose evidence crossed its threshold — either way — is flagged.
4. Genre probes re-run against the current schema.
5. The design spec is revised; the delta is written to `log.md` with the reason.
6. Each RQ's criterion is checked. Research on an RQ closes when its criterion is met, and
   reopens if a later batch breaks it.

## What reopens a closed RQ

- A new stratum is added to the corpus.
- A genre probe lands "silently wrong."
- A claim's agreement drops below 95% as M grows.
- Another tool author disagrees with a design decision on grounds we had not considered.

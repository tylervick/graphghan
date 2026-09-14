# Research coverage: what a pattern has to say, and how we know when we have looked enough

Date: 2026-09-12
Status: living document — the audit trail behind `2026-09-12-pattern-data-model-design.md`
Companion to: `2026-09-12-pattern-data-model-design.md`

## 1. Why this document exists

The first pass at the design was a targeted sweep: it found real things, but it had no stopping
rule, so "we have researched this" meant "I stopped looking" rather than anything checkable.
This document is the instrument. It says which kinds of source count, what each one yielded,
when the yield stopped, and what would reopen the question.

Three checks, in order of how much they are worth:

1. **Source coverage** (section 3) — have we looked at each *kind* of source, not just more of
   the same kind? Cheap to fake, so it is the weakest check.
2. **Saturation** (section 4) — does a new source still produce a *new structural axis*? This is
   the real test. Counting new facts rewards trivia; counting new axes rewards structure.
3. **Representability** (section 6) — take a real pattern archetype and ask whether our format
   can express it, or refuses it cleanly, or accepts it and is silently wrong. The third outcome
   is the only unacceptable one.

## 2. Scope boundary

The format describes **one flat grid worked in a known order, one cell to one stitch**. The
academic survey of crochet notation has a name for this genre — a "crochet graph" — and its
assessment is the one to design against: charts like these "leave little room for ambiguities"
but are "very limited with regard to the types of patterns that they can represent", being
usable only for patterns "that are flat and whose arrangement of stitches matches a grid"
(Seitz et al., Onward! 2022).

That is our niche stated precisely, and it is a defensible one. What matters is that patterns
outside it are **refused**, not silently mis-measured. See #44.

## 3. Source coverage

| # | Category | Status | Principal sources | Yield |
|---|---|---|---|---|
| 1 | Standards bodies | done | Craft Yarn Council Standards & Guidelines (2018 PDF + site); CGOA Masters | Abbreviations, US/UK/Canada terms, chart symbols, yarn weight 0-7, hook mm↔US, project levels, care categories, submission checklist |
| 2 | Accessibility standards | done | BANA *Guidelines for Transcribing Knit and Crochet Patterns* (2024); Kate Atherley; Accessible Patterns Index | Charts must be accompanied by written instructions; abbreviation expansion; chart direction conventions confirmed independently |
| 3 | Interchange formats | done | OXS; Pattern Maker XSD; WIF (weaving); knitout; KnitML; CROML; PKF/XML crochet symbols (Zaharieva-Stoyanova) | OXS `properties` and per-stitch `marked`; WIF as the 30-year precedent; no crochet instruction standard exists |
| 4 | Catalogue models | done | Ravelry API field list | `gauge` + `gauge_divisor` + `gauge_pattern` + `row_gauge` independently matches our gauge shape |
| 5 | Academic / HCI | done | Seitz et al., *Digital Crochet* (Onward! 2022); AmiGo (SCF 2022); stitch-mesh representations | Insertion points as crochet's irreducible ambiguity; genre classification; per-cell stitch is the known extension of a grid chart |
| 6 | Designer & tech-editor practice | done | Tech-editor checklists; pattern-writing style guides | Required-elements lists agree with CYC; "special stitches" section is where custom stitches are defined |
| 7 | Real patterns (corpus) | done | 10 patterns: 7 written-row crochet, 2 chart-driven, 1 symbol chart | Turning chain variance, counts-as-stitch, chain colour, foundation, notions, skill level |
| 8 | Chart-crochet genres | done | Filet, overlay mosaic, interlocking, C2C, tapestry, Tunisian | The cell-cardinality axis; row-boundary behaviour; two-chart patterns |
| 9 | Knitting chart genres | done | Fair isle, double knitting, brioche, CYC knit symbols | One square = two stitches; two passes per row; RS/WS symbol duality |
| 10 | Commercial tools | partial | Crochetpop, Stitch Fiddle, Stitchmastery, CrochetCharts, crochetpatternmaker.net | Output anatomy and designer-facing settings. **Their file formats are not public**; the academic survey reports they encode only symbol arrangement, not stitch relationships |
| 11 | Community discussion | thin | Blogs, designer posts | Searches surfaced commentary, not primary threads. Ravelry forums need a login; see section 7 |

## 4. Saturation log

A "structural axis" is a dimension along which a pattern can differ that the format must model —
not a field, a *kind* of field. New facts are cheap; new axes are the signal.

| Round | Sources | New axes | Running total |
|---|---|---|---|
| 1 | 10-pattern corpus | Row-boundary behaviour (turning chain: count, counts-as-stitch, colour); terminology system; foundation; open stitch vocabulary; stitch placement (BLO/FLO/post/ch-space) | 5 |
| 2 | CYC standard | Chart symbols describe the RS face; front-matter vocabulary (skill, notions, yarn put-up, hook units, care) | 7 |
| 3 | OXS, WIF, Ravelry, knitout, KnitML, CROML | Progress-inside-the-chart (OXS `marked`) | 8 |
| 4 | Academic (Seitz, AmiGo) | Insertion point as the irreducible ambiguity; the genre boundary itself | 10 |
| 5 | Accessibility (BANA, Atherley) | Written instructions as a required parallel artifact | 11 |
| 6 | Amigurumi / rounds | Round-boundary behaviour (joined vs spiral) — a second instance of axis 1, but a real gap (#43) | 11 |
| 7 | Filet, overlay mosaic, interlocking | Cell-to-stitch cardinality (#44); multiple grids per chart | 13 |
| 8 | Tunisian, double knitting, brioche | **none** — all three are instances of cardinality (axis 12) and passes-per-grid-row, which `passes` already expresses | 13 |

**Verdict: converged on structure.** Round 8 covered three unrelated genres and produced no new
axis. Rounds 6 and 7 produced gaps but they were instances of axes already named. The curve
flattened at 13.

**Not converged on vocabulary.** Front-matter fields (axis 7) are still accumulating one at a
time and probably always will — every designer adds something. That is fine, because vocabulary
gaps are additive and cheap (#32-#35), whereas structural gaps are expensive. The stopping rule
below is deliberately about structure only.

## 5. Axis inventory, mapped to the format

| # | Axis | Format today | Verdict |
|---|---|---|---|
| 1 | Row boundary: turning chain, count, counts-as-stitch, colour | `technique.turn` boolean only | Phase 1 of the design |
| 2 | Round boundary: joined vs spiral | not modelled | #43 |
| 3 | Terminology system (US/UK) | not modelled | Phase 1 |
| 4 | Foundation: chain count, first stitch position | prose only | Phase 1 |
| 5 | Open stitch vocabulary | `gauge.stitch` free string | Phase 1 (`stitch_name`) |
| 6 | Stitch placement (BLO/FLO/post/ch-space) | not modelled | Out of genre — a graph-chart concern (#36 territory) |
| 7 | Front matter (skill, notions, yarn, hook units, care) | partial and untyped | #32, #33, #34, #35 |
| 8 | Chart symbols describe the RS face | unstated | Documented in Phase 1; enforced by #36 |
| 9 | Progress inside the chart (OXS `marked`) | separate progress document | Deliberate: our chart is immutable and hashed |
| 10 | Insertion point ambiguity | fixed by construction — the grid means "the stitch below" | Out of genre, and the reason the genre is unambiguous. Worth stating |
| 11 | Written instructions as a parallel artifact | `written-rows.txt` | Have it; name it as a guarantee (#45) |
| 12 | Cell-to-stitch cardinality | assumed 1 | #44, and #18/#37 are instances |
| 13 | Multiple grids per chart (interlocking front/back) | `layers` | Already expressible; keep `layers` general |

Axes we already satisfy and should not lose: 9, 11, 13, and passes-per-grid-row (Tunisian and
brioche both fit the existing explicit `passes` escape hatch, since a pass carries its own
`grid_row`).

## 6. Representability matrix

The real test. "Refuses" is an acceptable outcome; "silently wrong" is not.

| Archetype | Can we express it? | Notes |
|---|---|---|
| Single-crochet graphghan (ours) | **Yes** | The design target |
| Tapestry crochet panel, flat, rectangular | **Yes** | Outlander Tapestry fits today |
| Tapestry crochet worked in rounds (bags) | **Partly** | `rounds` works; join behaviour unstated (#43) |
| Knit colourwork / fair isle, flat | **Yes** | Same grid, same direction rules |
| Cross-stitch | **Yes** | And exports to OXS |
| Knit/purl texture chart | **Partly** | `layers.stitch` exists but no reader surfaces it (#36) |
| Overlay mosaic | **No** | Per-cell stitch (#36) plus one-direction rows with fasten-off |
| Interlocking / locked filet mesh | **Partly** | Two grids fit `layers`; the technique does not |
| Filet crochet | **No, and silently wrong** | Would validate, then report wrong counts (#44) |
| C2C graphghan | **No** | Reserved; tile cardinality and tile gauge (#18) |
| Tunisian | **Partly** | Two passes per grid row fit explicit `passes`; no fixture proves it |
| Shaped tapestry panel (Orca bag) | **No** | Rows must sum to `chart.width` (#37) |
| Amigurumi | **No** | Spiral rounds, increases, 3D — out of genre |
| Garment with sizes and pieces | **No** | Out of genre |

Two entries are the ones that matter: **filet crochet is the only "silently wrong" cell**, which
is what makes #44 the highest-value structural issue. Everything else either works or refuses.

## 7. Stopping rule

Research on **structure** is closed. It reopens if any of these happen:

- A new genre is proposed for the format and its cell cardinality, row boundary, or grid count
  is not already in section 5.
- A pattern archetype lands in section 6 as "silently wrong".
- Someone publishes an actual crochet *instruction* interchange format. Nothing exists today;
  this is worth re-checking annually rather than continuously.

Research on **vocabulary** is explicitly open-ended and tracked as issues, not as a question to
finish.

Known thin spots, recorded honestly rather than closed:

- **Community discussion (category 11).** Ravelry's forums are behind a login and its API needs
  OAuth, so the richest source of designer complaint about pattern formats was not reached. Worth
  one authenticated pass.
- **Commercial file formats (category 10).** None are public. The academic survey's claim that
  they encode symbol arrangement rather than stitch relationships was taken at second hand.
- **WIF (category 3).** Included as a precedent for a craft interchange format that survived 30
  years by committee consensus across competing applications. The specification itself was not
  read — two source hosts were unreachable. Worth reading before any attempt to publish our
  format for others, which is the moment its lessons would matter.

## 8. Sources

Standards: [Craft Yarn Council](https://www.craftyarncouncil.com/standards) and the
[2018 Standards & Guidelines PDF](https://media.craftyarncouncil.com/sites/default/files/images/standards/CYC_YarnStandards-2018-11-06.pdf);
[BANA Guidelines for Transcribing Knit and Crochet Patterns (2024)](https://brailleauthority.org/sites/default/files/hobbies/Guidelines%20for%20Transcribing%20Knit%20and%20Crochet%20Patterns%202024.pdf);
[CGOA Masters](https://crochet.org/become-a-master/).

Formats: [OXS](https://www.ursasoftware.com/OXSFormat/); [WIF](https://wif-format.org/);
[knitout](https://textiles-lab.github.io/knitout/knitout.html); [KnitML](http://www.k2g2.org/wiki:knitml);
[Ravelry API](https://www.ravelry.com/api).

Academic: Seitz, Rein, Lincke, Hirschfeld, [*Digital Crochet: Toward a Visual Language for Pattern
Description*](https://patrickrein.de/publications/SeitzReinLinckeHirschfeld_2022_DigitalCrochet_preprint.pdf),
Onward! 2022; [AmiGo](https://dl.acm.org/doi/10.1145/3559400.3562005), SCF 2022;
Zaharieva-Stoyanova & Bozov, [XML-based representation of crochet symbols](https://dipp.math.bas.bg/dipp/article/view/dipp.2017.7.16), 2017.

Accessibility: [Kate Atherley on accessibility](https://stitchmastery.com/on-accessibility-guest-post-by-kate-atherley/);
[Accessible Patterns Index](https://accessiblepatternsindex.com/).

Corpus: 10 pattern PDFs held locally, not redistributable. Listed by title and designer in the
design note's section 4 where cited.

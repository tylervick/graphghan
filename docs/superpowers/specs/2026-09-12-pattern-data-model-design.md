# Graphghan: the stitch, the turning chain, and what a pattern has to say

Date: 2026-09-12
Status: approved design (sections reviewed in conversation), awaiting spec review
Builds on: `2026-09-10-graphghan-ios-app-design.md` (chart format v2)
Research coverage and stopping rule: `2026-09-12-pattern-data-model-research.md`
Closes the design step for: #25

## 1. Purpose

The iOS Work screen tells you how many stitches and in which colour. It never tells you **which
stitch** you are working, and it never tells you **how many chains to make when you turn**. Both
are on the chart already or missing from it entirely, and this decides which.

Investigating that turned up a second question worth answering once: the format was written
against one pattern, and it is not obvious what a published pattern is obliged to say. Section 3
answers that from the industry standard and a corpus of real patterns, so the rest of the gaps
are written down with issue numbers instead of being rediscovered one at a time.

Phase 1 (section 6) is normative and is what an implementation plan should follow. Sections 7
and 8 are deferred, each behind an issue.

## 2. What the format knows today

**The stitch is chart-level and uniform.** `gauge.stitch` is the gauge key — `"sc"` or `"hdc"` —
written by `src/graphghan/export.py:187` from the `gauge_key` argument, which comes from
`[publish].charts` in `patterns/craigh-na-dun/pattern.toml:68`. It is genuinely uniform: the
design calls `gr.set_gauge(gauge_key)` once (`patterns/craigh-na-dun/design.py:30`) and returns
one grid at that gauge, so every cell of a chart is the same stitch.

**`layers.stitch` exists but is inert.** The format documents it, `schema/chart.schema.json`
defines `$defs/layer`, `chartdoc.validate_document` checks it
(`src/graphghan/chartdoc.py:143-157`), `fixtures/chart-format/layers-stitch.chart.json` pins it,
and `ChartDocument.layers` decodes it on iOS. Nothing in `src/graphghan/` writes one, and no
reader exposes it on a run.

**The turning chain is not in the format at all.** `technique.turn` is a bare boolean
(`chartdoc.TECHNIQUE_ROWS`), documented as "informational (true for flat work)". The count exists
only inside an English sentence in `patterns/craigh-na-dun/pattern.toml` `[notes].setup` — "Ch 1,
turn at the end of every row. The chart counts stitches only; the turning chain is not a stitch"
— which `pattern.load_pattern` folds into `instructions[0]` and `export.chart_json` copies to
every chart. `export.written_rows` omits it.

## 3. What the standards actually give us

The v2 spec said "nothing open exists for crochet or knitting charts". That holds for chart
*data*. It is not true for *vocabulary*, and the distinction is the useful one.

| Source | What it standardises | What we should take |
|---|---|---|
| [Craft Yarn Council](https://www.craftyarncouncil.com/standards) | Abbreviations, US/UK terms, chart symbols, yarn weight 0-7, hook mm↔US, project levels, care symbols, submission checklist | The vocabulary, and the checklist as a gap list |
| [BANA](https://brailleauthority.org/sites/default/files/hobbies/Guidelines%20for%20Transcribing%20Knit%20and%20Crochet%20Patterns%202024.pdf) | Transcribing knit and crochet patterns for braille and screen readers | Charts need a written parallel; chart direction rules |
| [Seitz et al., Onward! 2022](https://patrickrein.de/publications/SeitzReinLinckeHirschfeld_2022_DigitalCrochet_preprint.pdf) | Survey of crochet notation and its ambiguities | The genre boundary, stated below |
| ISO/Ginetex + ASTM | Care symbols, five categories | Deferred, #35 |
| [OXS](https://www.ursasoftware.com/OXSFormat/) | Cross-stitch chart interchange: `properties`, palette, stitches | Benchmark only; we already export it |
| [Ravelry](https://www.ravelry.com/api) | Catalogue model: `gauge`, `gauge_divisor`, `gauge_pattern`, `row_gauge`, `yardage` | Confirmation that our gauge shape is right |
| KnitML, knitout, CROML | Nothing usable — XML hand-knitting (dormant), machine-level, and an informal LLM shorthand | Nothing |

Two consequences.

**Our working model has no standard to conform to.** Nothing anywhere models pass order, runs and
a cursor. `technique` / `passes` / `Cursor` stay ours.

**Our genre has a name and a known boundary.** The academic survey calls a grid chart like ours a
"crochet graph", and its assessment is the one to design against: charts like these "leave little
room for ambiguities" but are "very limited with regard to the types of patterns that they can
represent", usable only for patterns "that are flat and whose arrangement of stitches matches a
grid". That is a fair description of the niche and a defensible one. What matters is that
patterns outside it are refused rather than silently mis-measured — today filet crochet would
validate against our schema and then report a wrong stitch count, because one filet cell is a
block of three double crochet, not a stitch (#44).

**Where a standard exists, adopt its vocabulary rather than invent.** The CYC abbreviation list
already names the thing we are missing: `tch` / `t-ch`, turning chain. Their pattern submission
checklist is, read sideways, a required-fields list: yarn type and put-up, fibre content, balls
per size, yarn weight symbol, every hook **in millimetres and US sizes**, every notion with size
and quantity, standard abbreviations with definitions for anything non-standard, finished
measurements, project level, a stitch count after every row with an increase or decrease, stitch
patterns with multiples, repeats marked on charts, finishing details, and a schematic per piece.

## 4. Findings that drive the design

Evidence is the coded corpus under `docs/research/` — 133 sources coded against a fixed codebook
in seven batches (114 usable patterns: 11 on-hand, 58 yarn-company including 5 DMC cross-stitch
charts, 12 DROPS including US/UK twins, 33 independent designers, across rows, rounds, C2C,
filet, mosaic, tapestry, Tunisian, stranded knit and cross-stitch), 39 of them double-coded at
5% field disagreement — plus the CYC standard, BANA, the WIF
specification read in full, and tool teardowns. The research plan, claim register with stopping
criteria, and per-batch log are `docs/research/README.md`, `claims.md`, `log.md`. Counts below
are from batch 1 and will move; the register is the source of truth.

**The turning chain is not derivable from the stitch.** A convention table (sc 1, hdc 2, dc 3)
fails on the one stitch where it matters. From the coded corpus (`docs/research/corpus/corpus.csv`,
109 usable patterns after six batches, 56 of them row-worked crochet or Tunisian):

| Row stitch | Turning chain stated | Split |
|---|---|---|
| sc | 13 | ch 1 in 12/13 |
| hdc | 4 | ch 1 in 3/4 (the table says 2) |
| dc | 12 | **ch 3 in 7/12, ch 2 in 5/12** |
| "in pattern", custom (hhdc, waistcoat, woven, Tunisian) | 21 | ch 0, 1, 2 or 3, per designer |
| filet block / space | 2 | ch 3 before a block, ch 4 before a space — keyed on the *next row's first cell* |

Two patterns alternate ch 1 and ch 2 within one piece because the chain depends on the height of
the row about to be worked; one designer uses a different chain for the same stitch in their own
gauge swatch; DROPS 203-1 states both rules in one pattern (ch 1 not counting before a sc-height
row, ch 3 counting before a dc-height row). The response is to stop deriving, not to derive more
carefully. Full counts and their stopping criteria: `docs/research/claims.md`, claim 1.

**"Counts as a stitch" is a separate, load-bearing fact.** Stated in 26 of 56 row-worked corpus
patterns, both ways (yes 16, no 10). Waffle Washcloth: "Ch 2 [counts as 1st dc]" — so you skip the first stitch *and* work into
the turning chain at the end of the next row. That changes the working sequence at both ends of
every row. Craigh na Dun's own note says the opposite, and the format cannot currently say
either.

**The chain has a colour, and almost nobody writes it down.** Orca Bag writes `R 51: (Black) ch 1,
turn, 1 sc, (Gray) 4 sc…` — the chain in the *next* row's colour. Craigh na Dun chains at the end
of the row in the *old* colour. Different coloured edge; both valid — but the corpus states it in
3 of 32 plain row patterns — and in 13 of 15 mosaic patterns, where the colour changes at the row
start. It is genre-bound, not rare. So `boundary.color` stays optional, is never derived, and the UI says nothing about
colour unless it is present (claim 3).

**`dc` is ambiguous without a terminology declaration.** CYC's own table: US `sc` is UK `dc`, US
`hdc` is UK `htr`, US `dc` is UK `tr`, US `tr` is UK `dtr`. So `dc`, `tr` and `htr` each name
different stitches in the two systems. 42 of 109 corpus patterns declare their system, 55 are only inferable (yarn-company house style: Yarnspirations declares in 0 of 53), 2 carry both, and Ravelry records 157,211 patterns of unknown terminology; and DROPS' UK edition of one pattern carries a leftover US "double
crochet" in a sentence its US edition also has — publishers' own dual-terms text drifts. We are about to start spelling `sc` out as
"single crochet" on the Work screen; for any chart we did not generate that is a coin flip.

**The stitch vocabulary is open.** 39 of 109 corpus patterns define a custom stitch inline (puff,
herringbone hdc, camel/third-loop hdc, picot sc, waistcoat, split hdc, thermal, drop-down dc) and
66 of 109 use a placement modifier (BLO/FLO/third loop/post/chain space). CYC says as much:
"designers and publishers may use special abbreviations in a pattern, which you might not find on
this list". A closed enum is the wrong shape; a known table with a documented escape is right.

**Every pattern opens with a foundation the chart cannot express.** "Ch 139 or any multiple of 6 +
1", "Ch 33 … 1 sc in 2nd ch from hook", "first make 10 chains. From the second stitch from the
hook, make 9 sc". Ours is prose: "Foundation: chain W + 1 in Gold (Y). Row 1 begins in the 2nd
chain from the hook."

**Chart-level stitch is the right model, independently confirmed.** Both chart-driven patterns
and the tapestry-crochet literature treat it that way: "charts show colour information only — the
stitch type is specified separately in the pattern"; "every cell on the chart is one single
crochet in the colour shown".

## 5. Decisions

| Decision | Choice | Why |
|---|---|---|
| Stitch per run | Chart-level `gauge.stitch`, exposed as `Chart.stitch` | Right for every chart we generate; keeps `Run` and the pinned sequences untouched, so #36 stays additive |
| Turning chain source | Authored, never derived | Section 4; a derived badge would contradict the designer on real patterns |
| Turning chain shape | `gauge.boundary {kind, chain, counts_as_stitch, color}` | The last two change what you do at the hook and cannot be squeezed into an integer; `kind` is what makes one object serve rows, joined rounds, mosaic, spiral and Tunisian (genre probes) |
| Placement | `gauge`, not `technique` | `technique` is hashed into `chart.id`; see section 6.6 |
| Terminology | `gauge.terms`, `"US"` default; `terms_also` for paired documents | `dc`/`tr`/`htr` collide between systems; Ravelry records "both" |
| Gauge unit | `gauge.unit`, `"stitches"` default | Tiles, repeats and rounds are stated in the corpus and on Ravelry's form |
| Craft and language | `pattern.craft`, `pattern.language` | Every catalogue keys on craft first; 5,107 Ravelry patterns have no written language |
| Custom stitches | `gauge.stitch_name` overrides the known table | The vocabulary is open |
| Foundation | New optional top-level `foundation` | Not a gauge fact, not hashed, needed before row 1 |

## 6. Phase 1 (normative)

Revised 2026-09-14 from `docs/research/proposal-phase1-revision.md` (accepted): the turning
chain became a pass **boundary** with a `kind`, and four small unhashed fields were added so the
schema records what the catalogues and the corpus record. Phase 1 *implements* `kind: "turn"`
only; the other kinds and the new fields are decoded, written by the generator and otherwise
left alone (#43, #48, #49).

### 6.1 Schema

Inside `gauge`, all optional:

```json
"gauge": {
  "stitches": 14, "rows": 16, "over": { "value": 4, "unit": "in" },
  "unit": "stitches",
  "stitch": "sc",
  "stitch_name": "single crochet",
  "terms": "US",
  "terms_also": "UK",
  "boundary": { "kind": "turn", "chain": 1, "counts_as_stitch": false, "color": "next" },
  "hook": "5 mm (US H-8)", "yarn_weight": "4"
}
```

- `terms`: `"US"` or `"UK"`. Absent means `"US"` — every pattern in the corpus that declares is
  US, and so is ours. A reader MUST NOT spell out an abbreviation under the wrong system.
- `terms_also`: the other system, for a document whose written rows spell both. Readers spell
  out from `terms` only; this field is a statement about the prose, not a second vocabulary.
- `stitch_name`: the spelled-out name. Required when `stitch` is not in the CYC master list;
  ignored when it is, so a chart cannot rename `sc`.
- `unit`: what `stitches` and `rows` count — `"stitches"` (default), `"tiles"`, `"repeats"`,
  `"rounds"`. A reader that does not understand the unit derives no finished size (#48).
- `boundary`: what happens at the end of a pass, one object for every genre:
  - `kind`: `"turn"` (rows: turn the work), `"join"` (rounds closed with a slip stitch),
    `"rejoin"` (fasten off and start the next pass at the same edge — overlay mosaic, one-
    direction tapestry), `"spiral"` (continuous rounds, no boundary at all), `"return"`
    (Tunisian: the return pass is the boundary). Required within the object. Phase 1 readers act
    on `"turn"` and show nothing for the rest.
  - `chain`: chains made at the boundary. Required within the object; `0` is legal.
  - `counts_as_stitch`: default `false`.
  - `color`: `"next"` or `"current"`, optional. Absent means unstated, and a reader says
    nothing about colour rather than guessing.

`pattern` gains two optional keys, `craft` (`"crochet"`, `"knit"`, `"tunisian"`,
`"cross-stitch"`) and `language` (BCP 47). Absent means unstated (#49).

New optional top-level key:

```json
"foundation": { "chain": 190, "first_stitch_in": 2, "note": "in Gold (Y)" }
```

`chain` is the authored chain count and `first_stitch_in` the 1-based chain from the hook where
row 1's first stitch goes. Both are authored. A foundation with extra chains for an edge is
legitimate and must not fail validation; one with fewer than `width + first_stitch_in - 1` cannot
be worked, and the generator's validator and every reader refuse it (#50: nobody may work a chart
that is not physically viable).

`schema` stays `2`. Every field is optional and additive, and readers already MUST ignore unknown
keys at every level.

### 6.2 `pattern.toml` and the generator

```toml
[pattern]
craft = "crochet"
terms = "US"
language = "en"

[stitch.sc]
boundary = "turn"
chain = 1
counts_as_stitch = false
chain_color = "next"
first_stitch_in = 2

[stitch.hdc]
boundary = "turn"
chain = 2
first_stitch_in = 2
```

`[stitch.<key>]` is keyed by gauge key, exactly like `[gauge]`. `pattern.load_pattern` reads it
into `PatternMeta.stitches: dict[str, dict]` and `PatternMeta.terms` / `craft` / `language`.
`export.chart_json` writes `gauge.terms`, `gauge.terms_also`, `gauge.unit`, `gauge.boundary`,
`pattern.craft`, `pattern.language` and `foundation` from the entry for the chart's `gauge_key`,
and omits whichever keys the pattern did not author — the generator never invents a number.
`boundary` defaults to `"turn"` when `chain` is authored and `boundary` is not, because every
chart we generate today is worked in turned rows; it is never written without `chain`.

`foundation.chain` is written as `width + first_stitch_in - 1`.

Craigh na Dun authors `sc` as ch 1 and `hdc` as ch 2 (per review). Note that three of four hdc
patterns in the corpus use ch 1; worth confirming before the hdc chart is republished. #41 covers
the related bug that the shared `[notes].setup` prose already ships single-crochet rules on the
hdc chart, and is largely fixed by rendering that sentence from these fields.

`export.written_rows` gains the stitch and the chain, bringing it in line with what a published
chart pattern prints, and with what Crochetpop generates (`docs/research/tools/README.md`):

```
Row 51 (RS): ch 1, turn, 1 K, 4 G, 9 K, 13 C  (28 sts)
```

### 6.3 Reader: `GraphghanCore`

New `Stitch.swift`:

```swift
public enum Terms: String, Sendable { case us = "US", uk = "UK" }

public enum BoundaryKind: String, Sendable { case turn, join, rejoin, spiral, `return` }

public struct Boundary: Equatable, Sendable {
    public let kind: BoundaryKind
    public let chain: Int
    public let countsAsStitch: Bool
    public let color: ChainColor?      // .next, .current
}

public struct Stitch: Equatable, Sendable {
    public let code: String            // as written in gauge.stitch
    public let name: String?           // CYC table for `terms`, or gauge.stitch_name; nil if unknown
    public let terms: Terms
    public let boundary: Boundary?     // from the document only; never derived
}
```

Two name tables, US and UK, covering the CYC list. An unknown code yields `name == nil` and the
UI shows the abbreviation alone. An unknown `kind` string fails to decode the `boundary` object
only — the rest of `gauge` still loads — so a Phase 1 reader treats a future kind as absent.

- `ChartDocument.Gauge` gains `stitchName`, `terms`, `termsAlso`, `unit`, `boundary`
  (CodingKeys `stitch_name`, `terms`, `terms_also`, `unit`, `boundary`).
- `ChartDocument.Pattern` gains `craft` and `language`.
- New `ChartDocument.Foundation` and `ChartDocument.foundation`.
- `Chart.stitch: Stitch?` and `Chart.foundation`.
- **`Run`, `Pass` and `WorkSequence` do not change.** This is the invariant that keeps every
  `*.sequence.json`, `tests/test_js_parity.py` and the PWA untouched.
- `WorkActivityInfo` gains `stitch: String?` and `turningChain: Int?` (set only when
  `boundary.kind == .turn`). They are static for a project, so they belong in `Info`, not
  `State`; `isLastInRow` already exists.

### 6.4 What the app shows

- **Stitch badge.** Beside the count in the current column, a capsule in `Font.Heather.label` on
  `YarnSurface.foreground(hex)`. Text is `stitch.code`; the accessibility label uses
  `stitch.name` when known, so Done reads "Done with 4 single crochet in Charcoal". No new colour
  or font token, so `DesignRulesTests` stays green.
- **On-deck line, last run of a row, `kind == .turn` only.** `OnDeckRule` prepends the chain:
  `"ch 1, turn — next row starts in Gold"`. With `color == .next`, `"ch 1 in Gold, turn — …"`.
  With `counts_as_stitch`, append `" (counts as a st)"`. With no `boundary`, or any other kind,
  the line is exactly what it is today.
- **Foundation, at `cursor == .start` only.** The on-deck line reads
  `"Chain 190, first sc in the 2nd chain"`. This is the "and at the start of the first" half of
  #25.
- **Live Activity.** The `isLastInRow` state gains `ch N, turn`. Nothing else moves.

Nothing here changes layout, only text and one badge, so §6.1 of the design language spec
(`2026-09-11-ios-design-language-design.md`) still describes the screen.

### 6.5 Fixtures, docs and tests

`docs/chart-format.md`: the gauge section gains `terms`, `terms_also`, `unit`, `stitch_name`
and `boundary` (with the five kinds and which one readers implement today); `pattern` gains
`craft` and `language`; a new Foundation subsection; `technique.turn` cross-references
`boundary`. One documentation-only clarification with no code behind it, because the format is
currently ambiguous and cheap to fix here: **a layer's legend describes each cell as it looks on
the right side of the work**, which is the CYC rule for both crochet and knit chart symbols, and
is what makes a knit legend of `{"k": "knit", "p": "purl"}` mean anything on a WS pass.
Enforcing it is #36.

`schema/chart.schema.json`: `gauge.terms` / `terms_also` (enum), `gauge.unit` (enum),
`gauge.stitch_name` (string), `gauge.boundary` (object; `kind` enum and `chain` integer minimum
0 required), `pattern.craft` (enum), `pattern.language` (string), top-level `foundation`.

`fixtures/chart-format/generate.py`: the hand-built fixtures keep their current `GAUGE`, which
is the "absent" case. The craigh-na-dun fixture picks up the new keys for free when `dist`
regenerates, covering the "present" case. **No fixture gains or loses a name**, so
`tests/test_conformance.py::test_fixture_set_matches_spec` and
`GraphghanCoreTests/FixturesTests.swift` do not change, and no `*.sequence.json` moves.

Tests that change:

| Where | Change |
|---|---|
| `tests/test_export.py` | `gauge.boundary` / `unit` / `terms` / `terms_also`, `pattern.craft` / `language`, `foundation` written from `pattern.toml`; omitted when unauthored; `written_rows` prefix |
| `tests/test_pattern.py` | `[stitch.<key>]` and `[pattern].craft/terms/language` parsing |
| `tests/test_conformance.py` | unchanged set; add an assertion that chart ids are byte-identical across this change |
| `tests/test_drift.py` | passes once `dist/` is regenerated |
| `GraphghanCoreTests/StitchTests.swift` | new: US and UK tables, unknown code, `stitch_name` override, no derivation when absent, unknown `kind` decodes as no boundary |
| `GraphghanCoreTests/ChartDocumentTests.swift` | new gauge and pattern keys and `foundation` decode |
| `GraphghanCoreTests/ChartTests.swift` | `Chart.stitch` resolution |
| `GraphghanCoreTests/LiveActivityStateTests.swift` | `Info.stitch` / `turningChain`; nil for `kind != turn` |
| `ios/Tests/OnDeckRuleTests.swift` | `lastRunInRowNamesNextRowsColor` expectation gains the chain; a `join` boundary leaves it unchanged |
| `ios/Tests/WorkScreenTests.swift` + snapshots | `work-last-in-row.png`, `work-mid-row.png`, `lock-last-in-row.png` re-record |

### 6.6 Compatibility

`chart.id` hashes `{codes, rows, technique}` plus `passes` (`chartdoc.chart_id`,
`ChartID.compute`). `gauge`, `pattern` and the new top-level `foundation` are outside that set,
so **every existing chart id is unchanged**. That matters concretely:
`ProjectService.versionNotice` (`ios/Graphghan/Services/ProjectService.swift:137`) treats a
changed id as "the chart changed", and `switchChart` refuses unless the cursor is at the start —
so putting `boundary` on `technique` would have stranded every project in flight. It is also the
honest answer: a turning chain is not a different chart, in the same way the format already says
renaming a colour is not.

Old app, new chart: unknown keys ignored. New app, old chart: no badge text beyond the
abbreviation, no chain line. Neither errors.

## 7. Deferred, with issues

Adopting the CYC vocabulary: hook as `{mm, us}` and yarn weight as category 0-7 (#32); skill
level and notions (#33); authored yarn amounts — put-up, balls, colorway number, MC/CC role
(#34); care instructions and ISO symbols (#35).

Structural: one cell is not always one stitch, which is the highest-value gap because it is the
only one that is silently wrong rather than refused (#44); per-cell stitch through
`layers.stitch`, for which overlay mosaic is the real motivating genre (#36); shaped rows whose
counts change with increases and decreases (#37); joined versus spiral rounds — the `boundary` kinds other than `turn` (#43); gauge in tiles,
repeats or rounds (#48); craft, language and paired terminology beyond decoding (#49); border and edging as a phase after the chart (#38); stitch
multiples and chart repeat markers (#39, with #22 as the app-side counterpart).

App: the iOS app displays `instructions[]` nowhere, so setup, colour-change technique and
blocking are invisible while working (#40). Phase 1 covers one of those four notes; the rest
still have no home. Accessibility: abbreviations must be expanded for VoiceOver — screen readers
render "st" as "street" — and `written-rows.txt` should be named as the guaranteed chart-free
path the accessibility standards require (#45).

Bug: `[notes].setup` ships single-crochet prose on the hdc chart (#41).

C2C (#18) is unchanged in scope but now has the tile-versus-stitch, tile-gauge and two-turning-
chain findings recorded on it.

## 8. Non-goals

Not in Phase 1, and not implied by it: any change to `Run`, `Pass`, `WorkSequence` or the pass
order; any change to `chart.id` or `schema`; any new UI surface beyond the badge and two lines of
existing text; deriving a turning chain from a stitch under any circumstances.

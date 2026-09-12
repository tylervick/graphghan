# Ravelry: the designer "add a pattern" form (RQ2, primary source)

Read 2026-09-12 from `ravelry.com/patterns/new` while signed in. This is the field list the
largest pattern catalogue asks every designer for; anything here that our format cannot carry is
a gap for G3, because a tool publishing to Ravelry from our JSON would have to invent it.

## Fields, verbatim order

**Pattern info**: Name · Craft (Crochet, Knitting, Loom Knitting, Machine Knitting) · Category
(tree) · "Where was this pattern published?" (book, magazine, website) · Source (primary /
unavailable, add source) · Designer · Pattern page link · Pattern PDF link · Attribute tags
("Choose tags to help people find this pattern").

**Yarns and Needles**: Yarn (add yarn) · Held together (No / Yes, 2+ strands) · Yarn weight —
*Any gauge*, Thread, Cobweb, Lace, Light Fingering, Fingering (14 wpi), Sport (12 wpi), DK
(11 wpi), Worsted (9 wpi), Aran (8 wpi), Bulky (7 wpi), Super Bulky (5-6 wpi), Jumbo (0-4 wpi)
· Needle size (US number with mm, 0.5 mm to 25 mm, including the 4.25 / 4.75 / 7.0 / 7.5 mm
sizes with no US number) · Hook size (mm, with the US letter in parentheses where one exists:
"5.0 mm (H)", "9.0 mm (M/N)", "10.0 mm (N/P)", "15.0 mm (P/Q)") · add needle / add hook.

**Gauge and yardage**: Gauge — *stitches*, *repeats*, *rows* in *1" / 2" / 4"* · Pattern for
gauge (free text) · Yardage — between … and …, yards / meters · Sizes available · Aliases ·
add errata · Notes ("Do not include the pattern in the notes!").

**Published**: month and year. **Buying information**: Price, Currency, Free?, Available
online? **Languages**: a long list plus **"Universal - no written language"**.

## What it tells the format

| Ravelry field | Ours | Note |
|---|---|---|
| Craft | none | We have no craft field; `technique.type` implies crochet. A published format needs `craft` (#33 territory) |
| Category tree, attribute tags | none | Catalogue-level; a manifest concern, not a chart concern |
| Yarn weight by name **and wraps-per-inch** | `gauge.yarn_weight` free string | Ravelry uses WPI, CYC uses 0-7; both are names. #32 should carry the CYC number and let WPI be derived from a table |
| Held together | none | Corpus has it (cypress|textiles: "hold two strands together"). CYC checklist: "If the yarn is used doubled, note it in the gauge". Small field, real |
| Hook size in mm, letter secondary | `gauge.hook` free string | Confirms #32: mm is the key, letter is display |
| Gauge: stitches, **repeats**, rows over 1/2/4 in | `gauge.stitches`, `rows`, `over` | Ravelry has a *repeats* count; we do not. That is the tile-gauge C2C patterns state ("5.5 tiles = 4 in"). A `gauge.unit: stitches \| repeats \| tiles` would close #18's gauge half |
| Pattern for gauge | `gauge.stitch` | Same idea, free text there, a stitch code here |
| Yardage as a range | derived `stats.yards_est` | #34: authored yardage, and a range not a point |
| Sizes available | none | Out of genre for a single-size chart, needed for garments |
| Errata | none | A pattern-level changelog. DROPS prints "This pattern has been corrected"; we have `pattern.version` only |
| Published month/year | none | `pattern` has version but no date |
| Price / free / available online | none | manifest concern |
| Languages, incl. "Universal – no written language" | none | A chart with no prose is a recognised class; our `terms` and `instructions` should be optional in exactly that case |

## Two consequences for the design note

1. **Gauge needs a unit.** Both Ravelry (repeats) and the C2C corpus (tiles) state gauge in a
   unit other than stitches. `gauge.unit` defaulting to `stitches` is additive and unhashed.
2. **`craft` is missing.** Every catalogue (Ravelry, Lion Brand tags, LoveCrafts' "type of
   pattern") keys on it first. It belongs on `pattern`, is not hashed, and is a one-line
   addition to Phase 2.

## Pattern pages (read 2026-09-12: *Which Way Filet Blanket*, *Happy Winter Mosaic*)

Beyond the form, a published pattern page shows: Craft · Category path ("Blanket → Throw") ·
Published (month year) · Suggested yarn (linked, with fibre and put-up "317 yards / 100 grams")
· Yarn weight ("DK (11 wpi)", or "Any gauge - designed for any gauge") · Gauge, sometimes as a
swatch measurement ("Gauge swatch in pattern (13 sts x 9 rows) measures 7 cm x 6 cm") · Hook
size(s) · Yardage range · Sizes available ("115 cm x 150 cm") · **Crochet terminology: `US` or
`both US and UK`** · Languages · attribute tags (`in-the-round`, `one-piece`, `square`,
`mosaic`, `written-pattern`, `video-tutorial`, `captioned-video`) · ratings for overall,
**clarity**, and difficulty · first published / page created / last updated.

**Crochet terminology is a first-class catalogue field on Ravelry**, with a `both` value. That
is the strongest external confirmation of claim 4, and it settles the `both` question: the
catalogue records "both", so a document may too — the format's single primary value should be
accompanied by a way to say a second system is also given (`terms: "US"`, `terms_also: "UK"`),
rather than an enum that forbids what Ravelry records.

Attribute tags are the closest thing to a technique taxonomy in the wild; `in-the-round` versus
worked flat is one of them, which is #43's field from the catalogue side.

## Population counts (advanced search, "Crochet terminology" filter, 2026-09-12)

Across all crochet patterns on Ravelry: **United States 456,772 · United Kingdom 56,507 ·
Unknown 157,211** (≈ 670k total: 68% US, 8% UK, **23% unknown**). Nearly a quarter of the
catalogue has no recorded terminology, and the ratio shows why both systems must be first-class:
UK is a minority but 56k patterns is not a rounding error. (The filter has no "both" bucket;
pattern pages can still say "both US and UK".)

## Catalogue-wide filter counts (crochet, 2026-09-12)

- **Attributes** (top-level groups): Pattern Instructions 858,782 · Construction 677,485 ·
  Shapes 207,426 · Fabric Characteristics 185,282 · Design Elements 165,294 · Crochet Techniques
  110,356 · Colorwork 106,944 · Regional/Ethnic Styles 78,499 · Sock Techniques 3,990 ·
  Mature Content 1,803 · **Accessibility 525**.
- **Yarn weight**: Aran 123,263 · Worsted 114,097 · DK 94,876 · Sport 57,378 · Thread 48,458 ·
  Fingering 43,056 · Super Bulky 32,988 · Bulky 27,722 · Any gauge 13,443 · Light Fingering 9,211
  · Lace 6,269 · Jumbo 2,196 · Cobweb 170 · **No weight specified 68,246** (≈10%).
- **Yarn held together**: single strand 631,153 · 2 yarns 7,915 · 2 yarns same weight 6,214 ·
  3 yarns 488 · individual yarn weights 12,245 — held-together is ≈2% of patterns: small, real,
  and CYC's checklist asks for it (#34).
- **Availability**: Ravelry download 321,032 · purchase online 317,120 · free 182,409 · in print
  64,007 · discontinued 65,542.
- **Yardage** buckets from 0–150 yards (118,360) upward — yardage is a range field in practice.

Ravelry's attribute taxonomy is the largest technique vocabulary in existence for these crafts;
its sub-groups (Colorwork, Construction, Pattern Instructions, Crochet Techniques) are the
external reference for `technique` values and for a future `craft`/`attributes` manifest field.
- **Pattern Instructions** (sub-attributes): written pattern 493,847 · photo tutorial 167,245 ·
  **chart 102,826** · video tutorial 58,559 · has schematic 25,811 · captioned video 7,081 ·
  recipe/percentage 2,180 · color blind accessible 590 · low vision 316 · screen reader access
  285 · machine instructions 24 · digital braille 10 · press braille 5 · digital audio 3.
  Charts are ≈15% of the catalogue, written ≈74%; the accessibility tags together are under
  0.2%, which is the population that BANA and the Accessible Patterns Index serve (claim 8, #45).
- **Colorwork** (sub-attributes): stripes/colorwork 68,487 · other 23,437 · **mosaic 9,796** ·
  intarsia 4,515 · stranded 562 · illusion/shadow 143 · corrugated ribbing 4. (Tapestry and C2C
  are filed under Crochet Techniques, below.)
- **Crochet Techniques** (sub-attributes): front/back post stitch 31,882 · granny square 23,899
  · **filet crochet 13,884** · **tapestry crochet 12,526** · Tunisian/afghan crochet 8,831 ·
  surface crochet 6,482 · pineapple 4,477 · slip stitch crochet 3,007 · Irish 1,887 ·
  broomstick 672 · lover's knot 657 · bullion 643 · hairpin 511 · bruges 437 · cro-hook 288 ·
  clones knot 160 · cro-tatting 113. Filet outnumbers tapestry; mosaic (9,796, under Colorwork)
  is close behind both. The three grid-chart genres we cannot yet represent or refuse correctly
  (#44, #36) are ≈36k patterns on Ravelry alone.
- **Construction** (sub-attributes): **worked in the round 173,120 · worked flat 109,102** ·
  one-piece 100,982 · bottom up 64,850 · seamless 59,746 · seamed 57,980 · top down 40,185 ·
  motifs 23,400 · modular / join as you go 14,062 · sideways 13,381 · buttonholes 6,573 · short
  rows 6,544 · bias 2,253 · felted 1,404 · icord 991 · moebius 743 · selvedge 639 · gusset 531 ·
  freeform 399 · entrelac 366. Rounds outnumber flat rows across crochet as a whole; our corpus
  is blanket-heavy and under-weights them.
- **Pattern source type**: Website 263,291 · Magazine 49,959 · eBook 42,933 · Book 39,615 ·
  Pamphlet/Booklet 23,485 · Webzine 1,461. Print (book + magazine + pamphlet) ≈ 113k, about
  17% — the stratum the coded corpus has none of.
- **Colors used (typical)**: 1 → 94,442 · 2 → 19,312 · 3 → 7,143 · 4 → 3,561 · 5 → 1,835 ·
  6 or more → 2,275 (where recorded). Multicolour work — the whole grid-chart domain — is a
  minority of published crochet; a format for it is a niche format, which is fine, and worth
  saying in the G3 pitch.
- **Difficulty** (crowd-rated 1–10): **unknown 549,974** · 1 "piece of cake" 5,207 · 2 "easy"
  34,127 · 3 29,468 · 4 "medium" 14,134 · 5 5,823 · 6 2,051 · 7 495 · 8 "difficult" 85 · 9 9.
  82% unrated; among rated, the mass sits at 2–4. Ravelry's scale is neither CYC's four levels
  nor Lion Brand's; skill level is designer-declared or nothing (#33).
- **Hook size** (mm, US letter where one exists): 4.0 mm (G) 102,681 · 5.0 mm (H) 101,184 ·
  3.5 mm (E) 62,075 · 5.5 mm (I) 50,128 · **3.0 mm 47,383** · 6.0 mm (J) 40,676 · **2.5 mm
  37,169** · **4.5 mm 32,315** · 3.75 mm (F) 26,018 · 6.5 mm (K) 20,410 · 3.25 mm (D) 13,358 ·
  8.0 mm (L) 11,430 · 2.75 mm (C) 10,434 · 2.25 mm (B) 10,240 · 9.0 mm (M/N) 9,128 · 7.0 mm
  5,967 · 7.5 mm 102 · small hooks 81,027 · large hooks 11,707. Sizes with **no US letter**
  (2.5, 3.0, 4.5, 7.0, 7.5 mm) cover ≈123k patterns: the mm value is the identity, the letter is
  a courtesy (#32).

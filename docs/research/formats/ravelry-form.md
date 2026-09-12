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

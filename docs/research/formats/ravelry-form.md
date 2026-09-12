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

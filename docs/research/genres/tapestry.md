# Genre probe: tapestry / intarsia graphghan worked in rows

Verdict: **works today; Phase 1 fields are exactly what it says in prose.**

## Source

Red Heart *Leaping into Spring Crochet Blanket* (RHC0502-39339M, Yarnspirations, January 2026).
100 stitches × 165 chart rows, five colours, worked in split half double crochet. Verbatim:

> ABBREVIATIONS … Splhdc = Split half double crochet: work hdc between 'legs' at front and back
> of stitch (splitting stitch) instead of through top loops.
> GAUGE 8.5 splhdc and 11.5 rows = 4" [10 cm].
> With A, ch 101.
> Work in chart to end of Chart, reading RS rows from right to left and WS rows from left to
> right as follows:
> 1st row: (RS). 1 hdc in 2nd ch from hook. 1 hdc in each ch to end of chain. Turn. 100 hdc.
> 2nd row: Ch 1. 1 splhdc in each st to end of row. Turn.
> Rep 2nd row until 165 rows of Chart are complete. Fasten off.
> Notes: • Ch 1 at beg of rows does not count as stitch. • Work color changes using intarsia
> technique. … • Each square on chart represents one stitch.

Front matter: `4 MEDIUM` yarn-weight symbol; `SKILL LEVEL: INTERMEDIATE`; per colour
"Contrast A Oatmeal (0326) 4 balls or 1337 yds/1222.5 m"; put-up "(7 oz/198 g; 364 yds/333 m)";
hook "Size U.S. L/11 (8 mm)"; "Susan Bates yarn needle"; measurements "Approx 47" x 57"";
an accessibility contact line.

## Encoding

Everything the working order needs is expressible today: `rows` (100 cells × 165), `palette`
(5 codes), `technique: {type: rows, start: bottom, first_side: RS, rs_direction: rtl, turn:
true}` — the pattern states the direction rule in the same words as our defaults. `gauge:
{stitches: 8.5, rows: 11.5, over: {value: 4, unit: in}}` fits exactly.

What is *not* expressible today, and what the pattern states in words:

| Stated in the PDF | Phase 1 field |
|---|---|
| "Ch 1 at beg of rows does not count as stitch" | `gauge.turning_chain: {count: 1, counts_as_stitch: false}` |
| "Ch 1. 1 splhdc in each st" (chain at the start of the row) | `turning_chain` — position is a rendering choice, not data; see log |
| `Splhdc` defined inline; gauge measured in it | `gauge.stitch: "splhdc"`, `gauge.stitch_name: "split half double crochet"` (custom stitch, not in CYC) |
| "ch 101 … 1 hdc in 2nd ch from hook" | `foundation: {chain: 101, first_stitch_in: 2}` |
| US terms (Yarnspirations house style; `hdc` present) | `gauge.terms: "US"` — inferred here, which is exactly why the field must be written by the publisher |
| Row 1 is `hdc`, rows 2+ are `splhdc` | **not expressible**: the first row is a different stitch from the rest. See below |

## Two things the probe surfaced

1. **Row 1 differs from the body.** The foundation row is worked in plain hdc into the chain,
   every later row in splhdc. Chart-level `gauge.stitch` cannot say that. It is common — Drops
   0-1396 and the Nancy Afghan do the same (a plain first row, then the pattern). The honest
   Phase 1 answer is a `foundation.note` ("row 1 in hdc"); a structural answer is a per-pass
   stitch override, which is #36 territory. Recorded on the claim register as a new
   observation under claim 6.
2. **Intarsia versus tapestry is a technique choice with the same chart.** "Work color changes
   using intarsia technique" (bobbins, no carrying) versus tapestry (carry and work over). Same
   grid, different yarn management, different look on the WS. Our `instructions` carries it as
   prose; nothing structured says which. Adjacent to #38/#40; noted, not filed — one pattern.

## Conclusion

This is the archetype the format was built for, from a major publisher, and it validates Phase
1 field-for-field. The first-row-stitch gap is real and cheap to note; the intarsia/tapestry
flag is worth a field only if the corpus shows publishers stating it routinely.

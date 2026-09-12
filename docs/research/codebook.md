# Codebook: how a pattern is coded into `corpus.csv`

One row per pattern. One value per field. `unstated` means the pattern does not say; `n/a` means
the field cannot apply (a rounds field on a rows pattern, a chart field with no chart, any hook
field on a listing page). Never infer: if the pattern does not say it, code `unstated`. Quote the
source text for any field marked **quote** so a second reader can check it.

For a `tutorial` or `roundup` (see `object`), code only what the page states; every field about
the body of a pattern that the page does not contain is `n/a`, not `unstated`.

`designer`: the site or brand name when no person is named (`cypress|textiles`, `DROPS Design`);
`unstated` only when nothing identifies the author. `title`: as printed, in the page's own case.

Revision 2 (2026-09-12): rules above added from the pilot's inter-coder disagreements
(28 of 560 fields; all formatting or n/a-vs-unstated).

## Identity

| Field | Values |
|---|---|
| `id` | short slug, unique |
| `title` | as printed |
| `designer` | as printed |
| `source_type` | `yarn-company`, `european`, `indie`, `magazine`, `book`, `on-hand` |
| `source_url` | where obtained; `local` for the on-hand PDFs |
| `craft` | `crochet`, `knit`, `cross-stitch`, `tunisian` |
| `technique` | `rows`, `joined-rounds`, `spiral-rounds`, `c2c`, `filet`, `tapestry`, `overlay-mosaic`, `interlocking`, `stranded`, `intarsia`, `mixed` |
| `object` | `blanket`, `washcloth`, `garment`, `accessory`, `toy`, `bag`, `wall-hanging`, `tutorial` (a how-to with no complete pattern), `roundup` (a listing of links), `other` |
| `year` | as printed, or `unstated` |

## Terminology and vocabulary

| Field | Values |
|---|---|
| `terms` | `US`, `UK`, `both`, `unstated` — **quote** the declaration |
| `terms_evidence` | `declared`, `inferred-from-stitches` (e.g. `sc`/`hdc` present means US), `none` |
| `abbrev_list` | `yes`, `no` — is there an abbreviations section |
| `special_stitches` | `yes`, `no` — a section defining non-standard stitches |
| `special_stitch_names` | semicolon-separated, **abbreviation only** when the pattern gives one (`fpdc`, `hhdc`, `splhdc`), else the name in lower case; standard CYC stitches that merely appear in an abbreviations list do not count as special; `none` |
| `placement_modifiers` | semicolon-separated from `BLO`, `FLO`, `3rd-loop`, `FP`, `BP`, `ch-sp`, `none` |

## Structure at the hook

| Field | Values |
|---|---|
| `stitches_used` | semicolon-separated CYC abbreviations in **US terms and CYC spelling** (`sl st` not `slst`, `fsc`, `sc2tog`), lower case, e.g. `sc;hdc;dc;sl st`. Structural ops (`ch`, `inc`, `dec`, `turn`) are not stitches; omit them |
| `gauge_stitch` | the stitch gauge is measured over, or `pattern` if "in pattern", or `unstated` |
| `gauge_form` | `sts-and-rows-over-4in`, `sts-and-rows-over-other`, `over-2in`, `tiles`, `blocks`, `unstated` — **quote** |
| `turning_chain` | integer, or `varies`, or `n/a` (rounds/spiral), or `unstated` — **quote** |
| `turning_chain_by_stitch` | e.g. `sc=1;dc=2` when the pattern chains differently before rows of different stitches; else `single`. For C2C use the keys `inc-row`, `dec-row`, `last-row` (e.g. `inc-row=6;dec-row=3`) |
| `tc_counts_as_stitch` | `yes`, `no`, `unstated` — **quote** |
| `tc_position` | `start-of-row` (chain then work), `end-of-row` (work, chain, turn), `unstated` |
| `tc_color` | `next`, `current`, `unstated` — only codeable when a color change coincides with a turn |
| `foundation_form` | `chain-count`, `chain-multiple` (e.g. "multiple of 6 + 1"), `chain-unspecified` (chain "as many as you need"), `fsc`, `magic-ring`, `other`, `n/a`, `unstated` — **quote** |
| `first_stitch_in` | integer chain from hook, or `unstated`, or `n/a` |
| `round_join` | `slst`, `slst-and-ch`, `spiral`, `n/a`, `unstated` — **quote** |
| `stitch_marker_instructed` | `yes`, `no` |
| `stitch_counts_given` | `every-row` (a count after every row/round), `changes-only` (only after rows whose count changes), `none`. A count given once at the foundation only is `none` |
| `shaping` | `yes`, `no` — any inc/dec in the body |
| `repeats_stated` | `multiple` (a stitch multiple is given), `rows` ("repeat rows 4-5"), `both`, `none` |
| `border` | `yes`, `no` |
| `finishing_steps` | semicolon-separated from `fasten-off`, `weave-ends`, `block`, `seam`, `none` |

## Chart

| Field | Values |
|---|---|
| `has_chart` | `yes`, `no` |
| `chart_type` | `color-grid`, `symbol-grid`, `symbol-diagram`, `both`, `n/a` |
| `chart_cell_means` | `one-stitch`, `block`, `tile`, `two-stitches`, `stitch-and-return`, `n/a` — **quote** any statement |
| `chart_direction_stated` | `yes`, `no`, `n/a` |
| `chart_row1_position` | `bottom-right`, `bottom-left`, `top`, `unstated`, `n/a` |
| `chart_key` | `yes`, `no`, `n/a` |
| `written_also` | `yes`, `no` — full written instructions alongside a chart; `n/a` when `has_chart` is `no` |
| `rs_ws_stated` | `yes`, `no` |

## Front matter

| Field | Values |
|---|---|
| `skill_level` | as printed, mapped to `basic`, `easy`, `intermediate`, `complex`, or `other:<text>`, or `unstated` |
| `hook_mm` | `yes`, `no` — is a millimetre size given |
| `hook_us` | `yes`, `no` — is a US letter/number given |
| `yarn_weight_form` | `cyc-number`, `name-only` (e.g. "worsted"), `both`, `unstated` |
| `yarn_brand_line` | `yes`, `no` |
| `yarn_putup` | `yes`, `no` — grams and/or yards per ball stated |
| `yarn_amount_form` | `yards`, `grams`, `balls`, `mixed`, `unstated` |
| `yarn_per_color` | `yes`, `no`, `n/a` (single color) |
| `fiber_content` | `yes`, `no` |
| `notions` | `yes`, `no` |
| `finished_size` | `yes`, `no` |
| `sizes_count` | integer |
| `care` | `yes`, `no` |
| `substitution_advice` | `yes`, `no` |
| `video_links` | `yes`, `no` |
| `copyright_terms` | `yes`, `no` |

## Coder notes

| Field | Values |
|---|---|
| `coder` | who or which agent |
| `confidence` | `high`, `medium`, `low` |
| `notes` | anything the fields could not capture; these drive codebook revisions |

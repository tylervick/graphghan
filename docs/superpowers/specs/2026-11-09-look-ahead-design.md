# Graphghan: look ahead on the Work screen

Date: 2026-11-09
Status: design agreed in conversation 2026-11-09 (Tyler); written spec for review
Builds on: `2026-09-16-work-screen-field-design.md` (the panel, the band, the whole-chart view,
`Segments`), `2026-09-25-pieces-and-shaped-rows-design.md` §6.3 (the header's shaped-row caption),
`2026-09-11-ios-design-language-design.md` (tokens and type).
Mockups: https://claude.ai/artifact/VCrJtkjRDVGQknQynXwwpT (three phones drawn from the real rows).
Closes the design step for: #245. Takes the visible-control half of #83 (§5.3). Rulings on #88,
#89, #73, #241 are in §9.

## 1. Purpose

A TestFlight tester, working Craigh na Dun at Row 5, wrote: "I want to be able to look at the
pattern and see what is coming up - for example, how long am I doing the chain part? 20 rows? I
want to be able to preview what's ahead."

Row 5 is the first row of the bottom braid strip. The strip runs rows 5 to 14, then two plain
rows, then the side borders and the cream field begin. The chart knows all of this: the run
structure of consecutive rows says how long a texture lasts and what replaces it. The app never
says it. The band shows two rows ahead at 30% and nothing further; the whole-chart view is a
picture with no numbers on it.

Two questions are in the feedback, and they want different answers:

1. **"How long am I doing this?"** wants a number, where her eyes already are, with no tap.
2. **"What's ahead?"** wants a place to look around the blanket, and a way back.

This spec answers the first with one line in the header and the second by finishing the
whole-chart view the band already has. Nothing about the tap, the count, the panel or the band
at stitch scale changes.

## 2. Decisions

1. **The chart is grouped into stretches.** A stretch is a run of consecutive passes that look
   alike to the person working them. The rule is in §3 and is a pure function in `GraphghanCore`,
   pinned by a fixture, the way `Segments` is.
2. **The header carries one look-ahead line.** A Heather caption under the side line: how many
   more rows like this one, then what changes. It turns over as she works. §4.
3. **The look-ahead line says what changes, not what the texture is.** "Cream joins" is a fact
   the chart states; "braid" or "lettering" would be a guess. The pattern's own words for a
   stretch are a follow-on (§9).
4. **The whole-chart view becomes the look-ahead view.** Row ticks, a hairline where each stretch
   begins, the current stretch bracketed, the range and length of each stretch ahead with its
   colours as dots. §5.
5. **The view gets a visible control.** A button in the header's empty trailing slot. The row
   number tap and the pinch keep working. This is the whole-chart half of #83; the capsule
   chevron half stays open there.
6. **No new scroll mode on the band.** A vertical scroll through the rows ahead at stitch scale
   (#88) is a different design and stays its own idea. The band at stitch scale is for the row in
   hand; the look-ahead view is for the blanket.

## 3. Stretches (normative)

### 3.1 The rule

A pure function in `GraphghanCore`:

```swift
public struct Stretch: Equatable, Sendable {
    public let rows: ClosedRange<Int>      // 1-based passes, as `Cursor.row`
    public let kind: Kind                  // .plain, .repeat, .pattern
    public let colours: [String]           // palette codes by cells, most first
}
public enum Stretches {
    public static func of(_ sequence: WorkSequence) -> [Stretch]
    public static func stretch(containing row: Int, in stretches: [Stretch]) -> Int?   // index
}
```

Consecutive passes `a` and `b` are in different stretches when either holds:

- **A colour joins or leaves.** The set of codes in `a.runs` differs from the set in `b.runs`.
- **The run count jumps.** `max(a.runs.count, b.runs.count) / min(…) >= 3` (as a real ratio, not
  integer division). A plain row of 3 runs next to a braid row of 53 is a boundary; a lettering
  row of 23 runs next to one of 35 is not.

Then **one-row stretches are absorbed** into the stretch before them, in a single pass from the
first stretch to the last. A single odd row is a blip in the thing before it, not a stretch of
its own. The first stretch is never absorbed; if it is one row long it stays, so pass 1 is
always in a stretch.

The thresholds (the ratio 3, the minimum length 2) are constants in `Stretches` with a comment
each. They were chosen against Craigh na Dun and the fixture in §3.3 pins them; a second chart
of a different texture (#17) is where they will next be tested.

Passes without runs (an empty explicit pass) have the empty colour set and a run count of 0; the
ratio rule treats a 0 count as a boundary on either side. A sequence with one pass has one
stretch.

### 3.2 Kind and colours

For each stretch, over its passes:

- `kind` is `.plain` when every pass has 3 runs or fewer; else `.repeat` when every pass has a
  `Segments.repeat` segment spanning at least half its cells; else `.pattern`.
- `colours` is the stretch's palette codes ordered by total cells across its passes, most first.
  Ties break by palette order.

`kind` names the two textures the app already has words for (the on-deck line's "plain", the
panel's "repeat"). `.pattern` is everything else and is never shown as a word (§4.2).

### 3.3 Fixture

`StretchesTests` pins the full stretch list of `craigh-na-dun` as literals, as `SegmentsTests` pins
its rows. The expected list, from the rule above run on the committed chart:

| rows | length | kind | colours by share |
|---|---|---|---|
| 1–2 | 2 | plain | Y |
| 3–4 | 2 | plain | G Y |
| 5–14 | 10 | repeat | Y G |
| 15–16 | 2 | plain | G Y |
| 17–20 | 4 | pattern | G Y |
| 21–22 | 2 | pattern | C G Y |
| 23–41 | 19 | pattern | C G Y K P |
| 42–45 | 4 | pattern | C G P Y |
| 46–51 | 6 | pattern | C G Y |
| 52–64 | 13 | pattern | C K G Y |
| 65–69 | 5 | pattern | C G Y |
| 70–84 | 15 | pattern | C K G Y |
| 85–88 | 4 | pattern | C G Y |
| 89–101 | 13 | pattern | C K G Y |
| 102–108 | 7 | pattern | C G Y |
| 109–124 | 16 | pattern | C K G Y |
| 125–139 | 15 | pattern | G C Y |
| 140–160 | 21 | pattern | C G Y K |
| 161–164 | 4 | pattern | C G Y |
| 165–168 | 4 | pattern | G Y |
| 169–170 | 2 | plain | G Y |
| 171–180 | 10 | repeat | Y G |
| 181–182 | 2 | plain | G Y |
| 183–184 | 2 | plain | Y |

The colour order is by cells across the stretch, ties by palette order (§3.2); the whole table is
the contract. Twenty-four stretches. They are the ones a person would name:
the gold edge, the braid strip, the side border, the cream field opening, the dragonfly and
thistles, the four lines of lettering with sky between, the stones, the top border.

Row 41 is the test of the absorption rule: it is the one row where Purple and Charcoal both
appear, and on its own it would be a one-row stretch between 23–40 and 42–45. It is absorbed
into 23–40, making 23–41.

Also pinned: the synthetic cases in §3.1 (one pass; an empty pass; a chart whose every row is the
same is one stretch; the ratio at exactly 3 is a boundary and at 2.9 is not; a one-row first
stretch is kept).

### 3.4 Where it is computed

`Stretches.of` runs once per sequence, not per step. `WorkView` computes it when the sequence
loads and passes the array down; `WorkScreen` takes `stretches: [Stretch]` as a parameter with a
default of `[]`, so every existing call site and test compiles unchanged and an empty array means
"no look-ahead line and no stretch marks", which is also what a written piece gets.

## 4. The look-ahead line (normative)

### 4.1 Placement

In `WorkScreen.header`, under the side line, in `Font.Heather.caption` and `Color.heather`, one
line, `lineLimit(1)`, `minimumScaleFactor(0.8)`, centred. It sits where the shaped-row caption
sits today (spec 2026-09-25 §6.3); a shaped chart shows both, shaping first, look-ahead second.
Nothing in `Theme.swift` or `Typography.swift` changes; `DesignRulesTests` must pass.

The line is present whenever `stretches.count > 1` and the cursor is not at the finished state.
A chart that is one stretch from end to end shows no line, because "183 more rows like this" is
true and useless. The finished state keeps "Every row worked".

### 4.2 Text

A pure function, `LookAheadLine.text(row:stretches:chart:)`, tested as values. With `s` the
stretch containing `row`, `left = s.rows.upperBound - row`, and `next` the stretch after `s`:

| case | text |
|---|---|
| `left > 0`, `next` exists | "N more rows like this · then CHANGE for M rows" |
| `left == 1` | "1 more row like this · then …" |
| `left == 0`, `next` exists | "Last row like this · then CHANGE for M rows" |
| `left > 0`, no `next` | "N more rows like this · then the blanket is done" |
| `left == 0`, no `next` | no line (the finished state follows the next tap, and the turn panel already says what is next) |

`M` is `next.rows.count`; "for 1 row" when it is one. CHANGE is the first of these that applies,
comparing `s` and `next`:

| what differs | CHANGE |
|---|---|
| `next.kind == .plain` and `s.kind != .plain` | "plain rows" |
| `next.kind == .repeat` and `s.kind != .repeat` | "the repeat rows" |
| a code is in `next.colours` and not in `s.colours` | "<Name> joins", the first such code in palette order |
| a code is in `s.colours` and not in `next.colours` | "<Name> ends" |
| `next` starts with more runs than `s` ends with | "busier rows" |
| otherwise | "simpler rows" |

`<Name>` is the palette entry's `name`, as the on-deck line uses it. The two kind words come
first because a plain or repeat stretch is more recognisable than the colour that got it there;
they fire only when the kind changes, so two plain stretches in a row (rows 1–2 then 3–4) fall
through to the colour that separates them ("Deep Green joins"). When `next` is one of the last
two cases the number alone is doing the work; that is accepted. (Builder check: the kind rows
were read as unconditional; they are not.)

Examples from Craigh na Dun: Row 1, "1 more row like this · then Deep Green joins for 2 rows".
Row 5, "9 more rows like this · then plain rows for 2 rows". Row 14,
"Last row like this · then plain rows for 2 rows". Row 20, "Last row like this · then Cream joins
for 2 rows". Row 22, "Last row like this · then Charcoal joins for 19 rows". Row 184, no line.

For a `cellKind` that is not stitches the word "rows" is still right: passes are rows. "the
blanket" is the chart's `pattern.title` when it is short enough to fit, else "the blanket"; the
builder picks the cut-off and pins it.

### 4.3 Accessibility

The header's title stack (row number, side line, captions) becomes one accessibility element
with the row number as its label and the rest as its value, in order, so the whole header reads "Row 5 of 184. Right side,
read right to left. 9 more rows like this, then plain rows for 2 rows." The panel gains a rotor
action "What's ahead" that speaks the same line followed by the next two stretches as sentences
("Rows 15 to 16, 2 plain rows. Rows 17 to 20, 4 rows in Green and Gold."), posted as an
accessibility announcement, so the chart-free path (#45) has it.

### 4.4 Live Activity and intents

Unchanged. The lock screen has a 160 pt budget and already spends it.

## 5. The look-ahead view (normative)

The band's `.whole` mode, drawn by `ChartBand.drawWhole`, gains the following. Everything else
about it (true aspect, worked rows solid, rows ahead at 28%, the Heather line on the current
row, tap or pinch-out returns) is as today.

### 5.1 Marks

- **Row ticks.** Along the leading edge of the chart rect, a 6 pt tick at 50% Ink and the row
  number in `Font.Heather.annotation` Ink 2, every 20 passes for a chart over 60 passes, every 10
  for one over 20, every 5 otherwise. Ticks are at pass numbers, not grid rows, so a bottom-up
  chart's ticks read upward.
- **Stretch hairlines.** A 1 pt line across the chart rect at the boundary before each stretch:
  Heather for the current stretch and those ahead, Heather at 35% for those worked.
- **The current stretch bracket.** A 2 pt Heather bracket at the trailing edge of the chart rect
  spanning the current stretch.
- **Stretch labels.** For the current stretch and each stretch ahead, right-aligned at the
  trailing edge inside the chart rect, in `Font.Heather.annotation` (bold for the current one,
  Heather; Ink for the rest) on a Panel pill at 88%: "Rows 5–14 · 10", preceded by one 7 pt dot
  per colour in `colours` order. A one-row stretch reads "Row 41 · 1". A label is drawn only when
  its stretch is two or more rows tall on screen and its centre is at least 14 pt below the last
  label drawn; otherwise the hairline stands alone. Labels are drawn from the current stretch
  upward and stop after the eighth, so a 24-stretch chart shows the current one and the next
  seven.
- **Return pill.** "Back to Row 5" in `Font.Heather.label` Cream on a Heather capsule, 36 pt tall,
  centred 14 pt above the band's bottom edge. It is the same tap the whole view already has; the
  pill makes the way back visible. Not drawn in the finished state, where the whole view's tap
  closes the screen and there is no row to go back to.

What depends on what (builder check): the row ticks are part of the whole view and are drawn
whenever it is, stretches or none. The return pill and the header button (§5.3) are drawn
whenever the cursor is not finished. Only the hairlines, the bracket, the labels and the header
line depend on `stretches` being non-empty. So a written piece has no whole view and nothing
here; a one-stretch chart gets ticks, pill and button and no stretch marks.

On a top-down chart (`start: top`) passes run downward and the marks follow the passes, which
is what `drawWhole` already does for the current-row line. #75 (the band mirrored against the
whole view on a top-down chart) is unaffected and stays open.

Dark appearance uses the same tokens; `Color.heather`, `.ink`, `.ink2` and `.panel` all have dark
values in the catalog.

### 5.2 Layout

A `LookAheadLayout` struct in `Work/`, pure, computed from the chart rect, the sequence (each
pass's `gridRow` places its marks; a pass without one gets no mark), the stretches and the
current row: tick positions and labels, hairline y's, bracket y's, and the
label list after the collision rule. `ChartBand.drawWhole` only draws what it returns. Tests
pin: tick interval by pass count; the first and last hairline; the current bracket; that labels
never overlap (centres 14 pt apart) and stop at eight; that a chart with one stretch draws no
hairline and no label.

### 5.3 Opening it

- A `Button` in the header's trailing 44 pt slot (today `Color.clear`), the system image
  `rectangle.grid.1x2` at 20 pt semibold in Ink 2, accessibility label "Look ahead" when the band
  is at stitch scale and "Back to the row" in the whole view. It toggles `mode`, as the row-number
  tap does.
- The look-ahead line in the header is also a tap target for the same toggle, with the same
  label.
- The row-number tap, the pinch, and tapping the band in the whole view all keep their meaning.
- In landscape the slot exists in the leading column's header and the button goes there.
- The finished state locks the band to `.whole` today; the button is hidden then, as Back is.

### 5.4 Touch in the view

Unchanged: tap returns, pinch out returns. A long-press on a row in the whole view does nothing
(#73 is about the band at stitch scale and stays open; jumping from the look-ahead view is a
follow-on, §9).

## 6. Design language

`2026-09-16-work-screen-field-design.md` §5.3's "Whole chart" paragraph is superseded by §5 of this
spec; the design-language spec's §6.1 pointer is unchanged. No new tokens or type. The snapshot
set gains: Row 5 with the look-ahead line (`work-look-ahead-line`), Row 14 (`work-look-ahead-last`),
the look-ahead view at Row 5 (`work-look-ahead-view`), and the view at Row 150 where most
stretches are behind (`work-look-ahead-view-late`). `WorkScreenTests.accessibilitySize` is
re-recorded: the line must not clip and may drop its `minimumScaleFactor` to 0.6 at accessibility
sizes. `band-whole`, `band-shaped-whole` and `work-finished` are re-recorded too: the first two
gain row ticks and the pill, the last gains ticks only (§5.1).

## 7. Compatibility

Nothing is stored. Progress documents, SwiftData models, the Live Activity payload and the chart
schema are untouched. A written piece passes `[]` and gets no line and no marks. The PWA and the
site are untouched.

## 8. Testing

- `StretchesTests` in `GraphghanCore`: §3.3.
- `LookAheadLineTests` in `ios/Tests`: every row of the §4.2 tables, the Craigh na Dun examples,
  the one-stretch chart, the finished state.
- `LookAheadLayoutTests`: §5.2.
- `WorkScreenTests`: the four snapshots in §6 and the re-recorded accessibility snapshot; a value
  test that the header's accessibility value contains the line.
- `DesignRulesTests` unchanged and passing.
- `BandLayoutTests` unchanged. `ChartBandTests` unchanged except the two whole-view snapshots
  named in §6.

## 9. Rulings and follow-ons

| issue | ruling |
|---|---|
| #245 | closed by this spec's PR |
| #83 | the whole-chart button lands here; the capsule chevron and the first-fill hint stay open there |
| #88 | out; a different design, stays an idea |
| #89 | out; two levels, no continuous zoom, as before |
| #73 | out; unchanged by this spec |
| #241 | separate; a default-setting change, handled on its own |
| #75 | unaffected, stays open |

Follow-ons, each behind an issue filed when this PR opens:

- The pattern's own name for a stretch: an optional `sections` key in the chart format
  (`{title, rows}`), written by the generator (Craigh na Dun's `instructions` already call rows
  5–14 "braid rows") and the importer when a PDF names its parts, and shown in place of CHANGE
  and in the labels when present.
- Jump from the look-ahead view: long-press a row to jump there (the whole-view half of #11).
- Stretches in Python, with the fixture generated rather than pinned by hand, alongside #70.
- A second chart of a different texture (#17) to test the thresholds against.

## 10. Non-goals

- Any change to how a tap advances, to the panel, or to the band at stitch scale.
- Naming textures ("braid", "lettering") from the chart alone.
- A vertical scroll of the band (#88), continuous zoom (#89), or a third zoom level.
- Anything on the Live Activity or in the intents.
- Written pieces.

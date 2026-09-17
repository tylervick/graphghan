# Graphghan: work on the chart

Date: 2026-09-16
Status: approved design (sections reviewed in conversation), awaiting spec review
Builds on: `2026-09-11-ios-design-language-design.md` §6.1 (which this supersedes),
`2026-09-12-pattern-data-model-design.md` §6.4 (the on-deck line and the stitch badge),
`docs/chart-format.md` §Progress document
Mockups: the two artifacts linked from #59 (card layouts; three forms for the field)
Closes the design step for: #59. Rulings on #20, #52, #11, #26, #23, #22, #40, #45 are in §10.

## 1. Purpose

The Work screen holds two senses of "where I am" that barely relate: the current run (the big
count, the colour, Done) and the position in the piece (`Row 42 of 184` as text). #59 asks for
one integrated thing, and for the affordance problems to be fixed while the screen is open.

Designing it turned up something larger than the affordances. The field is built around one unit
of work, the run, and one tap per run. Measured against the chart people are actually working,
that unit is wrong at both ends:

| Craigh na Dun, 5,496 runs, 34,776 stitches | share of taps | share of stitches |
|---|---|---|
| runs of 1 to 2 (the border braid, lettering) | 48% | 5% |
| runs of 20 or more (sky, hill) | 5% | 54% |
| runs of 3 to 19 | 47% | 41% |

Half of all taps are for a 2-stitch run, mostly the same eight-run braid at both edges of nearly
every row, memorised by row 5. Half of all stitches are worked inside a single run where the app
shows "117" and then nothing. And 185 of the 271 long runs have no colour change anywhere in the
row beneath them, so the crocheter cannot read the row below either; they are counting to 117 in
their head.

So this spec changes the unit of a tap to match the unit of attention, and then draws the screen
around that. The field becomes the chart itself at stitch scale.

## 2. Findings that shaped it

1. **`RowStripView.backdrop` was reversed, not abandoned.** `fc54a70` added the chart as the Done
   backdrop; `cc0940a` removed it thirty minutes later for the sliding colour track. Its snapshot
   shows why: eleven rows full width on a 189-wide chart is 80 pt per row and 2 pt per stitch,
   and the motif reads as vertical bars. The backdrop failed at that scale, not as an idea. At
   8 pt per stitch a row is a row.
2. **The snapshots lie about the card (#67).** `RunChipsView` renders on device and not in any
   reference image. The card is full. This spec removes the chips, so the question of the empty
   half goes away, but the plan must verify the new screen on device, not from snapshots, until
   #67 is fixed.
3. **The strip never marked the current run.** It outlined the row. Run-level position lived only
   in the chip row, a horizontal scroller showing six of a median 23 runs.
4. **The turn was a footnote.** On the last run of a turn row the field carried the count, badge,
   code, name, a two-line turn instruction and Done. That was the hierarchy problem at its worst,
   and the colour sliver was Gold on Gold at exactly that moment because the next row starts in
   the same colour.
5. **Repeat bands exist and are long.** 35 of 184 rows contain a band of period 2 to 4 repeated
   three or more times; row 179 is `5 Y, 2 G` twenty-two times.

## 3. Decisions

1. **The macro view is the chart, filling in as you work.** Worked rows solid, the current row
   marked, rows ahead faint. Not a render of the finished object (#52), not more numbers (#11).
2. **The field is the chart at stitch scale.** The current row drawn at 8 pt a stitch, the row
   below at full strength as the ruler, rows above faint. "Current stitch" and "position in the
   piece" are the same pixels. The colour columns and sliding track of `cc0940a` go.
3. **Segments under everything.** A row's runs are grouped by texture into a border braid, a
   repeat band, a long fill, or a plain run. The display changes with the segment; the event log
   does not. One tap is still one run, except inside a fill (4).
4. **Long fills count by tens.** A tap inside a fill segment advances ten stitches, the big number
   counts up, and the ring on the chart fills in. The step is per project, default 10, choosable
   from 1, 5, 10, 20, or the whole run. Back undoes one step.
5. **The turn is a step.** After the last run of a row the cursor sits at the turn; the panel says
   what the chart knows ("Ch 1, turn", the side, where the next row starts) and one tap turns.
6. **"Done" is gone as a word.** The count leads; the surface responds to touch; the capsule shows
   a checkmark, or "+10" inside a fill, or "Turned" at the turn.
7. **The whole field stays one target.** Tapping the band or the panel advances, hook in hand.
   Long-press on a stitch places the cursor. No split targets, no +1/−1 correction: a miscount
   between taps is in the fabric, and the app cannot know.
8. **The on-deck line stays, shorter.** "then 11 Purple" under the colour name. The turn variant
   is now the turn step, and the sliver is gone with the columns. It stays because VoiceOver reads
   it as the field's value and #45 wants a path that never depends on the chart.
9. **The cursor changes once.** A stitch offset within a run and a turn position after a row.
   Progress documents stay schema 1 with one optional key (§4.5).
10. **Designed before Meaghan's session.** RQ1 is unrun. If her notes reorder this, the spec is
    cheap to revise before it is a plan.

## 4. The step model (normative)

### 4.1 Segments

A pure function in `GraphghanCore`, `Segments.of(pass:)`, partitions a pass's runs, in reading
order, into segments. Each run belongs to exactly one segment. Detection runs in this order and
the first match wins for a given run:

| kind | rule | what the screen adds |
|---|---|---|
| `braid` | the first eight runs of the pass when every one of them has count ≤ 4; likewise the last eight, only when the pass has at least sixteen runs so the two never overlap | the sequence written out, `2Y 2G 4Y 2G 2Y 2G 1Y 3G`, current run underlined |
| `repeat` | a unit of period 2, 3 or 4 runs (count and code) repeated three or more times consecutively; the longest such span starting at the earliest run wins | the unit once, `5 Y · 2 G`, `×22`, and `3 of 22` |
| `fill` | a single run of 20 or more cells | the count counting up, and a landmark when the row below has one |
| `run` | anything else | nothing |

The braid rule is deliberately narrow: eight runs of four or fewer at either edge is what a
twisted-cord border produces, and it stays a border rule rather than a general "short runs"
rule so that the lettering in the middle of a row is not swept into it. The thresholds (8, 4,
period 2 to 4, three repetitions, 20 cells) are constants in one place with a comment each, and
the fixture in §4.6 pins them.

A landmark is the colour start in the row directly below (the previous pass's grid row) nearest
to the fill's end in reading direction, and the sentence is "ends N past where Purple starts
below", "ends N before …", or "ends where …". When no colour starts under the fill's interior,
there is no landmark and no sentence. `Segments.landmark(for:in:)` is the second pure function;
the row below is the ruler on screen regardless.

### 4.2 The cursor

```swift
public struct Cursor { var row: Int; var run: Int; var stitch: Int = 0 }
```

- `row` and `run` mean what they do today: 1-based pass, 0-based run.
- `stitch` is the number of cells of run `run` already worked, `0 ..< count`. A completed run is
  the next run at `stitch` 0, never `stitch == count`.
- `run == runs.count` is the **boundary position**: every run of the row is worked and the
  boundary action (the turn) has not been taken. `stitch` is 0 there. `WorkSequence.isValid`
  already accepts this position; on the last pass it is the finished state, as today.
- `Cursor.start` is unchanged. Equality and hashing include `stitch`.

### 4.3 Actions and the engine

`WorkAction` gains nothing; the existing `advance`, `back` and `jump` change meaning by position.

**advance**

- Inside a fill segment with step `s`: `stitch += s`, clamped so that reaching or passing the run's
  count moves to the next run at `stitch` 0 (the last step takes the remainder). Outside a fill,
  or with step "whole run", one advance is one run, as today.
- From the last run of a row (or from its final step): to the boundary position when the row
  has a boundary step (4.4); otherwise straight to the next row's first run, as today.
- From the boundary position: to the next row's first run, `startedNewRow: true`.
- The finished state is unchanged: `row == passes.count, run == runs.count`.

**back**

- Inside a fill with `stitch > 0`: `stitch -= s`, clamped at 0.
- From `run > 0, stitch == 0`: to the previous run. If the previous run is a fill, land at its
  last step boundary (`stitch = count - (count mod s)` when that is less than `count`, else
  `count - s`), so that Back and advance are inverses along the same steps.
- From the first run of a row: to the previous row's boundary position if that row has one, else
  its last run, as today.
- From the boundary position: to the row's last run (or its last step).

**jump(row:run:stitch:)**

- `stitch` is a new defaulted parameter. A jump to a fill lands at `stitch` rounded down to a
  multiple of `s`, so the ring and the count agree with what a tap would have produced.
- Long-press on a stitch on the chart is a jump to that run at that offset (rounded down).
  `JumpToRowSheet` is unchanged and jumps to `stitch` 0.

`WorkStep` gains `atBoundary: Bool`. `WorkEngine` takes the step size as a parameter
(`step: CountStep`, one of 1, 5, 10, 20 or `wholeRun`), never reads settings. `wholeRun` behaves
as `s == count` for the run in hand, so every rule above holds and a fill is one tap again.

### 4.4 The boundary step

A pass has a boundary step when the sequence's technique is `rows` and it is not the last pass.
Explicit passes have one when the pass declares a `turn` boundary or the technique is `rows`.
`rounds` passes have none in this spec (#69 gives `join`, `rejoin` and `return` theirs; `spiral`
never has one).

The step's label comes from `chart.stitch?.boundary`, the same source the on-deck line used:

| chart says | panel |
|---|---|
| `turn`, `chain > 0`, `color: next` | "Ch 1 in Gold, turn" |
| `turn`, `chain > 0`, no colour | "Ch 1, turn" |
| `turn`, `chain == 0` | "Turn" |
| nothing | "Turn" |

with "(counts as a st)" appended when `counts_as_stitch` is true, then the next row's side and
reading direction, then "Row 43 starts in Gold". The capsule reads "Turned". The Live Activity's
Done fires the same advance.

### 4.5 Events and the progress document

`ProgressEvent` (SwiftData) and `ProgressEventRecord` gain `stitch: Int` defaulting to 0. Every
event still records the cursor after the action. A turn records `kind: advance` with
`run == runs.count`.

The progress document stays **schema 1**. `cursor` and each event accept an optional `stitch`
key, absent meaning 0. This is compatible in both directions: a schema-1 reader that ignores
`stitch` computes `cells_done` low by less than one run, and a document without the key reads as
today. `docs/chart-format.md` §Progress document gets the key, the boundary position's meaning,
and the `stitch < count` rule.

`cells_done` becomes cells in every earlier pass, plus runs before `run`, plus `stitch`.
Sessions and pace are unchanged in form. Both readers change: `graphghan.progress.cells_before`
and `WorkSequence.cellsBefore`. `Pace.summarize` passes `stitch` through.

`Project.cursorStitch` (default 0) and `Project.countStep` (default 10, the raw value of
`CountStep`) are added to the SwiftData model, which is a lightweight migration. `countStep` is
app state, not progress: it is never written to a progress document. The PWA's legacy `{slug,row,run}` code maps to `stitch` 0.

### 4.6 Fixtures and parity

- `fixtures/chart-format/progress-stitch.progress.json` and `.expected.json`: events inside a
  fill, a turn, a Back across a boundary, and a jump into a fill. Both `graphghan.progress` and
  `Pace` must reproduce the expected summary.
- `fixtures/chart-format/segments.expected.json`: for `craigh-na-dun`, the segments of rows 1, 42,
  64, 94 and 179 (braid both ends; braid + fill; braid + fills + lettering runs; lettering with no
  fill; braid + repeat band). Swift reproduces it; Python does not in this spec (#70).
- `WorkEngine` tests: advance and back are inverses along a fill's steps for every step size,
  including a count that is not a multiple of the step; the boundary position round-trips; a
  jump into a fill rounds down; the finished state is reachable and `isFinished` still holds.

## 5. The screen (normative)

Supersedes `2026-09-11-ios-design-language-design.md` §6.1 in full. Tokens and type are the
Heather ramp; nothing new is added to `Theme.swift` or `Typography.swift`, and `DesignRulesTests`
must still pass.

### 5.1 Layout

Ground with the weave, top to bottom:

1. **Header**, unchanged: close glyph, `Row 42 of 184` in Row number, the side line in Caption.
   Long press still jumps.
2. **Panel**: a rounded card, 12 pt inset, 18 pt radius, filled with the current run's yarn
   colour through `YarnSurface` and its readable foreground, 14 pt padding. Its content is the
   step (5.2).
3. **Band**: the chart at stitch scale, 12 pt inset, 10 pt radius, clipped, filling the height
   between the panel and the bar. Drawn with `Canvas`; redrawn on cursor change only.
4. **Bar**: Back and the action capsule, 16 pt from the sides, 44 pt above the display edge,
   72 pt tall, 36 pt radius, clear glass on iOS 26 and thin material before it. Back is 110 pt
   wide in the previous run's colour with the arrow and "Back", at 40% when there is nothing to
   return to. The action capsule fills the rest in the current run's colour (the next row's colour
   at the turn) and carries a checkmark, "+10" (or the chosen step; the checkmark again for
   `wholeRun`) inside a fill, or "Turned".

The card, `RowStripView`, `RunChipsView`, `WorkField`, `TrackStop` and `ColorTrack` are deleted.
`OnDeckRule` keeps the "then N Colour" and foundation cases and loses the turn case.

Landscape keeps two columns: panel and bar leading, band trailing, the band taking the full
height. The finished state is the panel in Cream with "Finished" in Title and the send-off line
in Body, the band showing the whole chart solid, and the capsule reading "Close".

### 5.2 The panel by segment

| state | panel content |
|---|---|
| plain run | count in Count with the stitch badge; `C · Cream` in Heading; on-deck line in Label at 75% |
| braid | the same, plus the sequence line in Label with worked runs at 45% and the current run underlined 3 pt Heather, under a Caption label "border braid" |
| repeat | the same, plus the unit `5 Y · 2 G ×22` in Label with the current half underlined, under a Caption label "repeat · 3 of 22" |
| fill | the count counts up: `40` in Count with `of 130` in Heading beside it; the landmark sentence in Label on an 8% black pill when there is one; on-deck line |
| turn | the boundary label in Title, the next side and direction in Heading, "Row 43 starts in Gold" in Label |

The count is `monospacedDigit` and caps at `minimumScaleFactor(0.5)`, as today. At the largest
accessibility size the sequence and repeat lines wrap to two lines and the landmark pill may
drop; nothing clips (snapshot at `.accessibility5`, as today).

### 5.3 The band

- **Scale**: 8 pt per cell, fixed. Cell hairlines at 10% black; row hairlines at 15%.
- **Rows**: two above the current row at 30% opacity, the current row at 96 pt, then as many
  rows below as fit at 48 pt each, the first at full strength and the rest at 75%. Worked rows
  are drawn solid; the current row's worked stitches (before the cursor, and the fill's counted
  stitches) are drawn solid; everything ahead of the cursor in the current row and above it is
  faint. This is decision 1 at row scale.
- **Position**: the current run is centred when it fits in 80% of the width. A longer run keeps
  its end in reading direction at three quarters of the width, so what you count toward is on
  screen. The band scrolls horizontally on drag and snaps back to the rule on the next step.
- **Ring**: the current run outlined 3 pt Heather. Inside a fill, the counted stitches are drawn
  solid and the remainder faint within the ring, so the ring fills in ten at a time. A tick ruler
  under the current row every ten cells from the run's start in reading direction, in Caption
  Ink 2, for runs of ten or more.
- **Brackets**: a braid or repeat segment gets a 2 pt Heather bracket above the current row
  spanning the segment, labelled in Caption Heather ("border braid", "×22 · 3 of 22"), the label
  kept on screen when the bracket is wider than the view.
- **Turn**: the ring goes; a 3 pt Heather bar marks the row's end and a dotted arc points to the
  next row's first stitch.
- **Whole chart**: pinch out, or tap the row number in the header, shows the whole chart at true
  aspect in the band's frame, worked rows solid, the current row a Heather line, rows ahead
  faint. Tap or pinch in returns. Two levels, not continuous zoom.

### 5.4 Touch

- Tap anywhere on the panel or the band: advance. The whole surface is the target, as the field
  was. The capsule is the visible handle and also advances.
- Long-press on a cell in the band: jump to that run at that stitch (rounded down to the step).
  Haptic on landing.
- Long-press on the action capsule: the step picker, a menu of 1, 5, 10, 20, whole run. Stored
  on the project (`countStep`), default 10.
- Back capsule: back. Swipe right anywhere: back, as today.
- Drag on the band: scroll horizontally; the next step re-centres.
- The header's close and long-press are unchanged.

`WorkFeedbackRule` gains a distinct tick for a fill step (lighter than a run), and the existing
row-change haptic fires on the turn.

### 5.5 Live Activity and intents

`WorkActivityState` gains `stitch: Int`, `runCount: Int?` (the fill's total when counting), and
`atBoundary: Bool`. The lock screen shows `40 of 130` in place of the count inside a fill, and
"Ch 1, turn · Row 43 starts in Gold" at the boundary, with Done reading "Turned". The Dynamic
Island compact view shows the counted stitches when counting. `AdvanceRunIntent` and
`BackRunIntent` apply the same engine with the project's `countStep`. The encoded keys of
`WorkActivityInfo` are unchanged for the reason in its comment.

## 6. Accessibility

- The band is `accessibilityHidden`. The panel is one element with the action label "Done with
  4 single crochet in Gold" (today's `doneLabel` rule), value the on-deck line, and inside a fill
  the label "40 of 130 single crochet in Cream, next ten". At the turn the label is the boundary
  sentence and the action is "Turned".
- Rotor actions on the panel: "Back", "Jump to row", "Choose counting step", and "Jump within
  row" which presents the runs of the row as a list, replacing the chips' jump-to-run labels.
- The segment lines expand abbreviations through `Stitch.name` as §6.4 of the data-model spec
  already routes them. Colour codes are spoken as names.
- Nothing on the screen requires the chart: the panel and the rotor are the complete path.

## 7. Design language

`2026-09-11-ios-design-language-design.md` §6.1 is replaced by a pointer to §5 of this spec. §6.8
(Live Activity) gains the fill and turn states. The snapshot set becomes: mid-row plain run,
braid, repeat band, fill at `40 of 130`, turn, finished, whole-chart level, and the fill at
`.accessibility5`. Each is taken on a device build until #67 is fixed, and the plan says so.

## 8. Compatibility

- Projects created before this change open with `cursorStitch` 0 and behave exactly as before
  on every row that has no fill, except that the turn is now a tap.
- Exported progress documents from the old app read unchanged. Documents from the new app read in
  the old app with `stitch` ignored.
- The PWA is untouched. Its cursor code has no stitch and maps to 0.

## 9. Testing

- `WorkEngine` and `Segments`: §4.6.
- `LiveActivityState.make`: a fill, a turn, and the start, pinned as values.
- `OnDeckRule`: the turn case removed; existing tests updated.
- Snapshots: §7, on device.
- `DesignRulesTests` unchanged and passing.
- Python: `progress-stitch` fixture through `graphghan.progress`; the existing `progress-basic`
  expected output is unchanged.

## 10. Rulings

| issue | ruling | what this spec takes |
|---|---|---|
| #20 zoomable chart grid | in | the band and the whole-chart level; two levels, no continuous zoom |
| #52 3D preview | out | not a working surface; untouched |
| #11 where am I from a count | in | the stitch offset and long-press-to-jump |
| #26 colour key | narrowed | the panel pairs code and name and the chips are gone; open for the Live Activity and Island |
| #23 batch and rapid taps | narrowed | rapid taps read as a count inside a fill; "finish this row" stays open |
| #22 repeat detection | in | `Segments` and the bracket |
| #40 instructions never shown | out | the turn step shows the turning chain; technique and blocking notes still have no home |
| #45 accessibility | narrowed | §6; the app-wide audit and guard test stay open |

Follow-ons, each behind an issue: #68 (a Watch, Siri or hardware control for the step), #69 (the
boundary step for rounds), #70 (the segment detector in Python), #17 (a second chart of a
different texture to work against), #67 (snapshots that show what the device shows).

## 11. Non-goals

- Continuous zoom on the band.
- A numeric "where am I" entry; long-press on the chart replaces it.
- Marking several runs done, or finishing a row in one tap (#23's first half).
- Counting steps other than 1, 5, 10, 20 and whole run.
- Any change to the chart schema, the sequence rules, or the site.

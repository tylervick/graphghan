# Look Ahead on the Work Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group a chart's rows into stretches, say in the Work screen's header how many more rows like this one are left and what changes next, and mark the stretches on the whole-chart view with a visible way in and out.

**Architecture:** A pure `Stretches` function in `GraphghanCore` partitions a `WorkSequence`'s passes. Two pure value types in `ios/Graphghan/Work/` turn stretches into the header's words (`LookAheadLine`) and the whole view's geometry (`LookAheadLayout`). `ChartBand.drawWhole` draws what the layout returns; `WorkScreen` shows the line and the button; `WorkView` computes the stretches once per sequence and passes them down. Nothing is stored.

**Tech Stack:** Swift 6, SwiftUI `Canvas`, Swift Testing, the repo's `Snapshots` helper (ImageRenderer PNGs under `ios/Tests/__Snapshots__`).

**Spec:** `docs/superpowers/specs/2026-11-09-look-ahead-design.md`

## Global Constraints

- Colours only through the token sets (`Color.heather`, `.ink`, `.ink2`, `.panel`, `.ground`, `.cream`); fonts only `Font.Heather.*`. `DesignRulesTests.noRawColorsOrSystemFontsOutsideTheTokens` must pass. Nothing is added to `Theme.swift` or `Typography.swift`.
- Spec §3.1 constants: boundary when the colour sets differ or `max/min >= 3.0` (a real ratio; a 0 count is a boundary on either side); one-row stretches merge into the stretch before them; the first stretch is never merged away.
- Spec §3.2: `.plain` when every pass has ≤ 3 runs; else `.repeat` when every pass has a `Segments` `.repeat` segment covering at least half its cells; else `.pattern`. `colours` by total cells, most first, ties by palette order.
- Spec §4.1: the line is shown only when `stretches.count > 1` and the cursor is not finished. Caption font, Heather, one line, `minimumScaleFactor(0.8)` (0.6 at accessibility sizes).
- Spec §4.2 text, exactly: "N more rows like this · then CHANGE for M rows" (" · " is space, U+00B7, space; the en dash in ranges is U+2013). "1 more row like this", "Last row like this", "for 1 row", "then <title> is done".
- Spec §5.1: ticks every 20 passes when the chart has more than 60, every 10 when more than 20, else every 5; hairlines before each stretch except the first; bracket on the current stretch; labels for the current stretch and those ahead, centres at least 14 pt apart, at most 8; "Back to Row 5" pill, not in the finished state.
- Ticks, pill and button do not depend on `stretches`; hairlines, bracket, labels and the header line do (spec §5.1 "What depends on what").
- Written pieces are untouched. The Live Activity, intents, progress documents and SwiftData models are untouched.
- Commits use the repo's `hk` hooks; commit with `HK_STASH=none` when unstaged files are around. Commit messages end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- App tests: `cd ios && mise run generate` once, then `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -collect-test-diagnostics never -only-testing:GraphghanTests/<Suite>`. Core tests: `cd ios/Packages/GraphghanCore && swift test --filter <Suite>`.
- Snapshot references: a missing PNG under `ios/Tests/__Snapshots__` is recorded on the first compare run and that test fails once; run again to pass. To re-record an existing one, delete the PNG first. Never run `GRAPHGHAN_SNAPSHOTS=record` (it rewrites every reference in the suite).

## Review Focus

1. A chart whose passes are explicit and some lack `gridRow` (`explicit-passes.chart.json`): the whole view must draw ticks and labels only for passes that have a grid row, never crash on a nil. Test in Task 3.
2. A chart worked top-down (`start: top`, passes with increasing grid row): hairlines and the bracket must bound the right passes, which means the hairline "before" a stretch is on the side facing the previous pass, not always the top. Test in Task 3.
3. A one-stretch chart (every row alike, e.g. `minimal-rows.chart.json` if its rows share a colour set and run count, else a synthetic sequence): no header line, no hairlines, no labels, but ticks, pill and button present. Tests in Tasks 2, 3, 5.
4. Two plain stretches in a row (Craigh na Dun rows 1–2 then 3–4): the line must fall through to "Deep Green joins", not say "then plain rows". Test in Task 2.
5. The finished state: the whole view must draw no "Back to Row" pill and the header no button, and the tap must still close the screen. Tests in Tasks 4 and 5.

---

### Task 1: `Stretches` in GraphghanCore

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/Stretches.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/StretchesTests.swift`

**Interfaces:**
- Consumes: `WorkSequence.passes`, `Pass.runs`, `Run.code`/`.count`, `Segments.of(_:)` (`Segment.kind == .repeat`, `.runs: Range<Int>`), `Pass.cells`.
- Produces:
  ```swift
  public struct Stretch: Equatable, Sendable {
      public enum Kind: String, Sendable { case plain, `repeat`, pattern }
      public let rows: ClosedRange<Int>   // 1-based passes
      public let kind: Kind
      public let colours: [String]        // palette codes, most cells first
      public init(rows: ClosedRange<Int>, kind: Kind, colours: [String])
  }
  public enum Stretches {
      public static let boundaryRatio = 3.0
      public static let minimumLength = 2
      public static let plainMaxRuns = 3
      /// `codes` is the palette order, for ties in `colours`.
      public static func of(_ sequence: WorkSequence, codes: [String]) -> [Stretch]
      /// Index into the array of the stretch containing pass `row`, or nil.
      public static func index(containing row: Int, in stretches: [Stretch]) -> Int?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import GraphghanCore

@Suite struct StretchesTests {
    static let chart = try! Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let codes = chart.palette.map(\.code)
    static let stretches = Stretches.of(seq, codes: codes)

    private func pass(_ runs: [(Int, String)]) -> Pass {
        Pass(label: "Row", side: .rs, direction: .ltr, gridRow: 0, runs: runs.map { Run(code: $0.1, count: $0.0, x0: nil) })
    }
    private func seq(_ passes: [Pass]) -> WorkSequence { WorkSequence(passes: passes) }

    @Test func craighNaDunHasTwentyFourStretches() {
        // spec §3.3, the whole table
        let expected: [(ClosedRange<Int>, Stretch.Kind, String)] = [
            (1...2, .plain, "Y"), (3...4, .plain, "G Y"), (5...14, .repeat, "Y G"), (15...16, .plain, "G Y"),
            (17...20, .pattern, "G Y"), (21...22, .pattern, "C G Y"), (23...41, .pattern, "C G Y K P"),
            (42...45, .pattern, "C G P Y"), (46...51, .pattern, "C G Y"), (52...64, .pattern, "C K G Y"),
            (65...69, .pattern, "C G Y"), (70...84, .pattern, "C K G Y"), (85...88, .pattern, "C G Y"),
            (89...101, .pattern, "C K G Y"), (102...108, .pattern, "C G Y"), (109...124, .pattern, "C K G Y"),
            (125...139, .pattern, "G C Y"), (140...160, .pattern, "C G Y K"), (161...164, .pattern, "C G Y"),
            (165...168, .pattern, "G Y"), (169...170, .plain, "G Y"), (171...180, .repeat, "Y G"),
            (181...182, .plain, "G Y"), (183...184, .plain, "Y"),
        ]
        #expect(Self.stretches == expected.map { Stretch(rows: $0.0, kind: $0.1, colours: $0.2.split(separator: " ").map(String.init)) })
    }

    @Test func indexFindsTheStretchOfARow() {
        #expect(Stretches.index(containing: 5, in: Self.stretches) == 2)
        #expect(Stretches.index(containing: 41, in: Self.stretches) == 6)   // absorbed blip
        #expect(Stretches.index(containing: 185, in: Self.stretches) == nil)
    }

    @Test func onePassIsOneStretch() {
        #expect(Stretches.of(seq([pass([(10, "A")])]), codes: ["A"]) == [Stretch(rows: 1...1, kind: .plain, colours: ["A"])])
    }

    @Test func identicalRowsAreOneStretch() {
        let s = seq(Array(repeating: pass([(5, "A"), (5, "B")]), count: 6))
        #expect(Stretches.of(s, codes: ["A", "B"]) == [Stretch(rows: 1...6, kind: .plain, colours: ["A", "B"])])
    }

    @Test func ratioOfThreeIsABoundaryAndJustUnderIsNot() {
        let three = [(1, "A"), (1, "A"), (1, "A")], nine = Array(repeating: (1, "A"), count: 9), eight = Array(repeating: (1, "A"), count: 8)
        #expect(Stretches.of(seq([pass(three), pass(three), pass(nine), pass(nine)]), codes: ["A"]).map(\.rows) == [1...2, 3...4])
        #expect(Stretches.of(seq([pass(three), pass(three), pass(eight), pass(eight)]), codes: ["A"]).map(\.rows) == [1...4])
    }

    @Test func aColourJoiningIsABoundary() {
        let s = seq([pass([(5, "A")]), pass([(5, "A")]), pass([(4, "A"), (1, "B")]), pass([(4, "A"), (1, "B")])])
        #expect(Stretches.of(s, codes: ["A", "B"]).map(\.rows) == [1...2, 3...4])
    }

    @Test func aOneRowStretchJoinsTheOneBefore() {
        let a = pass([(5, "A")]), b = pass([(5, "B")])
        #expect(Stretches.of(seq([a, a, b, a, a]), codes: ["A", "B"]).map(\.rows) == [1...3, 4...5])
    }

    @Test func aOneRowFirstStretchIsKept() {
        let a = pass([(5, "A")]), b = pass([(5, "B")])
        #expect(Stretches.of(seq([a, b, b]), codes: ["A", "B"]).map(\.rows) == [1...1, 2...3])
    }

    @Test func anEmptyPassIsItsOwnBoundary() {
        let a = pass([(5, "A")]), empty = pass([])
        #expect(Stretches.of(seq([a, a, empty, empty, a, a]), codes: ["A"]).map(\.rows) == [1...2, 3...4, 5...6])
    }

    @Test func coloursOrderByCellsThenPalette() {
        let s = seq([pass([(3, "B"), (3, "A")]), pass([(3, "B"), (3, "A")])])
        #expect(Stretches.of(s, codes: ["A", "B"]).first?.colours == ["A", "B"])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter StretchesTests`
Expected: compile error, `Stretch`/`Stretches` not found.

- [ ] **Step 3: Implement `Stretches.swift`**

Partition in one pass over `sequence.passes` with the boundary rule, then one merge pass (a stretch of length `< minimumLength` that is not the first joins the previous one), then compute `kind` and `colours` per stretch. For `.repeat`: `Segments.of(pass)` has a segment with `kind == .repeat` whose runs' cells sum to `>= pass.cells / 2` (integer: `cells * 2 >= pass.cells`). A doc comment on each constant says what it was chosen against (Craigh na Dun, spec §3.1).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios/Packages/GraphghanCore && swift test --filter StretchesTests`
Expected: 10 tests pass. Then `swift test --quiet` for the whole package: passes.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore/Sources/GraphghanCore/Stretches.swift ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/StretchesTests.swift
git commit -m "core: group a sequence's rows into stretches (#245)"
```

---

### Task 2: `LookAheadLine`

**Files:**
- Create: `ios/Graphghan/Work/LookAheadLine.swift`
- Test: `ios/Tests/LookAheadLineTests.swift`

**Interfaces:**
- Consumes: `Stretch`, `Stretches.index(containing:in:)` (Task 1); `Chart.palette`, `Chart.colorIndex(of:)`, `Chart.title`; `WorkSequence.passes`, `WorkEngine.isFinished(_:in:)`.
- Produces:
  ```swift
  enum LookAheadLine {
      /// Titles longer than this say "the blanket" (spec §4.2, builder's call).
      static let titleLimit = 24
      /// The header line; nil for one stretch, the finished state, or the last row of the last stretch.
      static func text(row: Int, stretches: [Stretch], sequence: WorkSequence, chart: Chart) -> String?
      /// "then <title> is done", or "then the blanket is done" when the title is empty or over `titleLimit`.
      static func ending(title: String) -> String
      /// What differs between `s` and `next`: "plain rows", "the repeat rows", "Deep Green joins", "Charcoal ends", "busier rows", "simpler rows".
      static func change(from s: Stretch, to next: Stretch, sequence: WorkSequence, chart: Chart) -> String
      /// "Rows 15 to 16, 2 plain rows." / "Rows 17 to 20, 4 rows in Deep Green and Gold." / "Row 41, 1 row in …".
      static func sentence(for stretch: Stretch, chart: Chart) -> String
      /// `text` followed by `sentence` for the next two stretches; for the rotor action (spec §4.3).
      static func spoken(row: Int, stretches: [Stretch], sequence: WorkSequence, chart: Chart) -> String?
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct LookAheadLineTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))
    private func line(_ row: Int) -> String? { LookAheadLine.text(row: row, stretches: Self.stretches, sequence: Self.seq, chart: Self.chart) }

    @Test func theCraighNaDunExamples() {
        #expect(line(1) == "1 more row like this · then Deep Green joins for 2 rows")
        #expect(line(5) == "9 more rows like this · then plain rows for 2 rows")
        #expect(line(13) == "1 more row like this · then plain rows for 2 rows")
        #expect(line(14) == "Last row like this · then plain rows for 2 rows")
        #expect(line(16) == "Last row like this · then busier rows for 4 rows")
        #expect(line(20) == "Last row like this · then Cream joins for 2 rows")
        #expect(line(22) == "Last row like this · then Charcoal joins for 19 rows")
        #expect(line(45) == "Last row like this · then Purple ends for 6 rows")
        #expect(line(170) == "Last row like this · then the repeat rows for 10 rows")
    }

    @Test func theLastStretchCountsDownToTheEnd() {
        #expect(line(183) == "1 more row like this · then Craigh na Dun Blanket is done")
        #expect(line(184) == nil)
    }

    @Test func aLongTitleIsTheBlanket() {
        #expect(LookAheadLine.ending(title: "Craigh na Dun Blanket") == "then Craigh na Dun Blanket is done")
        #expect(LookAheadLine.ending(title: "A Very Long Pattern Title Indeed") == "then the blanket is done")
        #expect(LookAheadLine.ending(title: "") == "then the blanket is done")
    }

    @Test func oneStretchHasNoLine() {
        let one = [Stretch(rows: 1...184, kind: .pattern, colours: ["C"])]
        #expect(LookAheadLine.text(row: 42, stretches: one, sequence: Self.seq, chart: Self.chart) == nil)
        #expect(LookAheadLine.text(row: 42, stretches: [], sequence: Self.seq, chart: Self.chart) == nil)
    }

    @Test func sentencesNameTheRowsAndColours() {
        #expect(LookAheadLine.sentence(for: Self.stretches[3], chart: Self.chart) == "Rows 15 to 16, 2 plain rows in Deep Green and Gold.")
        #expect(LookAheadLine.sentence(for: Self.stretches[4], chart: Self.chart) == "Rows 17 to 20, 4 rows in Deep Green and Gold.")
        #expect(LookAheadLine.sentence(for: Self.stretches[2], chart: Self.chart) == "Rows 5 to 14, 10 repeat rows in Gold and Deep Green.")
        #expect(LookAheadLine.sentence(for: Stretch(rows: 7...7, kind: .pattern, colours: ["C", "K", "G"]), chart: Self.chart) == "Row 7, 1 row in Cream, Charcoal and Deep Green.")
    }

    @Test func spokenIsTheLineAndTheNextTwoStretches() {
        #expect(LookAheadLine.spoken(row: 14, stretches: Self.stretches, sequence: Self.seq, chart: Self.chart)
                == "Last row like this, then plain rows for 2 rows. Rows 15 to 16, 2 plain rows in Deep Green and Gold. Rows 17 to 20, 4 rows in Deep Green and Gold.")
        #expect(LookAheadLine.spoken(row: 184, stretches: Self.stretches, sequence: Self.seq, chart: Self.chart) == nil)
    }
}
```

(`spoken` replaces " · " with ", " so VoiceOver does not read the dot.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios && mise run generate && xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -collect-test-diagnostics never -only-testing:GraphghanTests/LookAheadLineTests`
Expected: compile error, `LookAheadLine` not found.

- [ ] **Step 3: Implement `LookAheadLine.swift`**

`change` follows the spec §4.2 table in order: kind words only when `next.kind != s.kind`; a joining code is the first in palette order (`chart.palette` order) that is in `next.colours` and not `s.colours`; "busier" when `sequence.pass(at: next.rows.lowerBound)!.runs.count > sequence.pass(at: s.rows.upperBound)!.runs.count`. Colour names come from `chart.palette[chart.colorIndex(of: code)!].name`; list them with ", " and a final " and ". `sentence` uses "plain rows"/"repeat rows"/"rows" after the count and omits "in …" when `colours` is empty.

- [ ] **Step 4: Run the tests to verify they pass**

Same command. Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/LookAheadLine.swift ios/Tests/LookAheadLineTests.swift
git commit -m "work: the look-ahead line's words (#245)"
```

---

### Task 3: `LookAheadLayout`

**Files:**
- Create: `ios/Graphghan/Work/LookAheadLayout.swift`
- Test: `ios/Tests/LookAheadLayoutTests.swift`

**Interfaces:**
- Consumes: `Stretch`, `Stretches.index(containing:in:)` (Task 1); `WorkSequence.pass(at:)`, `Pass.gridRow`; `BandLayout.wholeChartRect(chart:in:)` for the rect in tests.
- Produces:
  ```swift
  /// Where the whole view's marks sit (spec §5.1, §5.2). Pure; y's are in the band's coordinates.
  struct LookAheadLayout {
      static let tickLength: CGFloat = 6
      static let labelSpacing: CGFloat = 14
      static let maxLabels = 8
      static let bracketInset: CGFloat = 8      // bracket 8…14 pt in from the trailing edge
      static let labelInset: CGFloat = 24
      struct Tick: Equatable { let y: CGFloat; let row: Int }
      struct Hairline: Equatable { let y: CGFloat; let ahead: Bool }
      struct Label: Equatable { let y: CGFloat; let text: String; let codes: [String]; let current: Bool }
      let ticks: [Tick]
      let hairlines: [Hairline]
      let bracket: ClosedRange<CGFloat>?
      let labels: [Label]
      init(rect: CGRect, chartHeight: Int, sequence: WorkSequence, stretches: [Stretch], row: Int)
      static func tickInterval(passCount: Int) -> Int   // 20 over 60, 10 over 20, else 5
      static func labelText(_ stretch: Stretch) -> String   // "Rows 5–14 · 10", "Row 41 · 1"
  }
  ```
  A pass's grid row `g` occupies `rect.minY + g*ch ..< rect.minY + (g+1)*ch` with `ch = rect.height / chartHeight`. Tick at the row's centre. A hairline before stretch `i > 0` sits on the edge of its first pass facing the previous pass (the pass before it has a larger grid row → bottom edge; smaller → top edge). The bracket spans the outer edges of the current stretch's first and last passes. A label's `y` is the midpoint of its stretch's span; labels are candidates from the current stretch through the last, kept when `|y - lastKeptY| >= labelSpacing`, at most `maxLabels`. Passes without a `gridRow` produce no tick, hairline, bracket edge or label.

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct LookAheadLayoutTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))
    static let rect = BandLayout.wholeChartRect(chart: chart, in: CGSize(width: 366, height: 420))
    static var ch: CGFloat { rect.height / 184 }
    private func layout(row: Int, stretches: [Stretch] = stretches) -> LookAheadLayout {
        LookAheadLayout(rect: Self.rect, chartHeight: Self.chart.height, sequence: Self.seq, stretches: stretches, row: row)
    }

    @Test func tickIntervalFollowsThePassCount() {
        #expect(LookAheadLayout.tickInterval(passCount: 184) == 20)
        #expect(LookAheadLayout.tickInterval(passCount: 61) == 20)
        #expect(LookAheadLayout.tickInterval(passCount: 60) == 10)
        #expect(LookAheadLayout.tickInterval(passCount: 21) == 10)
        #expect(LookAheadLayout.tickInterval(passCount: 20) == 5)
    }

    @Test func ticksSitOnTheirPassesCentres() {
        let l = layout(row: 5)
        #expect(l.ticks.map(\.row) == Array(stride(from: 20, through: 180, by: 20)))
        // bottom-up: pass 20 is grid row 164
        #expect(abs(l.ticks[0].y - (Self.rect.minY + 164.5 * Self.ch)) < 0.01)
    }

    @Test func hairlinesStandBeforeEveryStretchButTheFirst() {
        let l = layout(row: 5)
        #expect(l.hairlines.count == Self.stretches.count - 1)
        // before stretch 5–14: the bottom edge of pass 5 (grid row 179) in a bottom-up chart
        #expect(abs(l.hairlines[1].y - (Self.rect.minY + 180 * Self.ch)) < 0.01)
        #expect(l.hairlines[0].ahead == false && l.hairlines[1].ahead == true)
    }

    @Test func theBracketSpansTheCurrentStretch() throws {
        let b = try #require(layout(row: 5).bracket)
        // passes 5…14 are grid rows 179…170
        #expect(abs(b.lowerBound - (Self.rect.minY + 170 * Self.ch)) < 0.01)
        #expect(abs(b.upperBound - (Self.rect.minY + 180 * Self.ch)) < 0.01)
    }

    @Test func labelsStartAtTheCurrentStretchNeverOverlapAndStopAtEight() {
        let l = layout(row: 5)
        #expect(l.labels.count == 8)
        #expect(l.labels.first?.text == "Rows 5–14 · 10" && l.labels.first?.current == true)
        #expect(l.labels.first?.codes == ["Y", "G"])
        for (a, b) in zip(l.labels, l.labels.dropFirst()) { #expect(abs(a.y - b.y) >= LookAheadLayout.labelSpacing) }
        #expect(l.labels.allSatisfy { $0.y <= l.labels.first!.y })  // ahead is upward on a bottom-up chart
        #expect(LookAheadLayout.labelText(Stretch(rows: 41...41, kind: .pattern, colours: [])) == "Row 41 · 1")
    }

    @Test func lateInTheBlanketFewLabelsRemain() {
        let l = layout(row: 150)
        #expect(l.labels.count <= 7 && l.labels.first?.text == "Rows 140–160 · 21")
    }

    @Test func oneStretchDrawsTicksOnly() {
        let l = layout(row: 42, stretches: [Stretch(rows: 1...184, kind: .pattern, colours: ["C"])])
        #expect(!l.ticks.isEmpty && l.hairlines.isEmpty && l.bracket == nil && l.labels.isEmpty)
        let none = layout(row: 42, stretches: [])
        #expect(!none.ticks.isEmpty && none.hairlines.isEmpty && none.bracket == nil && none.labels.isEmpty)
    }

    @Test func aTopDownChartPutsTheHairlineOnTheTopEdge() {
        // five passes, grid rows 0…4, top-down; stretches 1–2 and 3–5
        let passes = (0..<5).map { Pass(label: "Row \($0 + 1)", side: .rs, direction: .ltr, gridRow: $0, runs: [Run(code: "A", count: 3, x0: 0)]) }
        let seq = WorkSequence(passes: passes)
        let rect = CGRect(x: 0, y: 0, width: 300, height: 100)
        let l = LookAheadLayout(rect: rect, chartHeight: 5, sequence: seq, stretches: [Stretch(rows: 1...2, kind: .plain, colours: ["A"]), Stretch(rows: 3...5, kind: .plain, colours: ["A"])], row: 1)
        #expect(l.hairlines.map(\.y) == [40])            // top edge of pass 3 (grid row 2)
        #expect(l.bracket == 0...40)
    }

    @Test func passesWithoutAGridRowGetNoMarks() throws {
        let chart = try Chart.load(TestFixtures.data("explicit-passes.chart.json"))
        let seq = try WorkSequence(chart: chart)
        let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))
        let rect = BandLayout.wholeChartRect(chart: chart, in: CGSize(width: 366, height: 420))
        let l = LookAheadLayout(rect: rect, chartHeight: chart.height, sequence: seq, stretches: stretches, row: 1)
        let withRow = Set(seq.passes.indices.filter { seq.passes[$0].gridRow != nil }.map { $0 + 1 })
        #expect(l.ticks.allSatisfy { withRow.contains($0.row) })
    }
}
```

Before Step 2, check `explicit-passes.chart.json`: if every pass has a `grid_row`, the last test still passes trivially; keep it, and add a synthetic sequence with one `gridRow: nil` pass to it asserting that pass yields no tick when it falls on a tick row.

- [ ] **Step 2: Run the tests to verify they fail**

Run: the Task 2 command with `-only-testing:GraphghanTests/LookAheadLayoutTests`.
Expected: compile error, `LookAheadLayout` not found.

- [ ] **Step 3: Implement `LookAheadLayout.swift`**

- [ ] **Step 4: Run the tests to verify they pass**

Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/LookAheadLayout.swift ios/Tests/LookAheadLayoutTests.swift
git commit -m "work: where the whole view's stretch marks sit (#245)"
```

---

### Task 4: The whole view draws the marks and the return pill

**Files:**
- Modify: `ios/Graphghan/Work/ChartBand.swift` (properties after `style`; `drawWhole`)
- Test: `ios/Tests/ChartBandTests.swift`
- Snapshots: create `band-look-ahead.png`, `band-look-ahead-late.png`; re-record `band-whole.png`, `band-shaped-whole.png`.

**Interfaces:**
- Consumes: `LookAheadLayout` (Task 3), `Stretch`.
- Produces: `ChartBand` gains
  ```swift
  /// The stretch marks of the whole view (spec §5.1); empty draws ticks only.
  var stretches: [Stretch] = []
  /// The return pill's text ("Back to Row 5"); nil draws none (the finished state).
  var returnLabel: String? = nil
  ```
  both defaulted so every existing call site compiles.

- [ ] **Step 1: Write the failing snapshot tests**

Add to `ChartBandTests`:

```swift
    static let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))
    private func lookAhead(_ cursor: Cursor) -> some View {
        ChartBand(chart: Self.chart, sequence: Self.seq, cursor: cursor, segmentLabel: nil, mode: .whole, style: .fabric,
                  onAdvance: {}, onJump: { _, _ in }, onToggleMode: {}, stretches: Self.stretches, returnLabel: "Back to Row \(cursor.row)")
            .background(Color.ground)
    }
    /// #245: the whole view with the stretches marked, the current one bracketed, and the way back visible.
    @Test func lookAheadAtRowFive() throws {
        #expect(try Snapshots.assert(lookAhead(Cursor(row: 5, run: 3)), named: "band-look-ahead", size: Self.size))
    }
    @Test func lookAheadLateInTheBlanket() throws {
        #expect(try Snapshots.assert(lookAhead(Cursor(row: 150, run: 0)), named: "band-look-ahead-late", size: Self.size))
    }
```

Keep the parameter order of the `ChartBand` memberwise init: the new `stretches` and `returnLabel` go after `onToggleMode`, as the test above writes them. (If you prefer them beside `style`, update the test to match; the order is yours.) Delete `ios/Tests/__Snapshots__/band-whole.png` and `band-shaped-whole.png` so they re-record with ticks (and, for `band-whole`, no pill: `wholeChart` passes no `returnLabel`).

- [ ] **Step 2: Run to verify they fail**

Run: the Task 2 command with `-only-testing:GraphghanTests/ChartBandTests`.
Expected: compile error on the new parameters.

- [ ] **Step 3: Draw in `drawWhole`**

After the existing rows and current-row line, build `LookAheadLayout(rect:chartHeight:sequence:stretches:row:)` and draw, in this order: ticks (6 pt at `Color.ink.opacity(0.5)` from `rect.minX`, the number in `Font.Heather.annotation` `Color.ink2` at `rect.minX + 9`, left-aligned, vertically centred on the tick); hairlines (1 pt across `rect`, `.heather` or `.heather.opacity(0.35)`); the bracket (2 pt `.heather`, at `rect.maxX - 14 … rect.maxX - 8`, 6 pt feet); labels (right-aligned at `rect.maxX - 24`, `Font.Heather.annotation`, bold and `.heather` when current else `.ink`, on a `Color.panel.opacity(0.88)` 4 pt rounded pill with 6 pt side padding; one 7 pt dot per code in `codes` order to the left of the text, 2 pt apart, filled with `ChartImage.color(hex)` and a 0.5 pt `Color.ink.opacity(0.15)` edge); then the pill when `returnLabel != nil` (`Font.Heather.label` in `.cream` on a `.heather` capsule 36 pt tall, 14 pt side padding, centred horizontally, bottom 14 pt above `size.height`). Measure text with `context.resolve(Text(...))`.

- [ ] **Step 4: Run twice to record, then pass**

Run the ChartBandTests command. Expected first run: `lookAheadAtRowFive`, `lookAheadLateInTheBlanket`, `wholeChart` and `shaped` fail once with "recorded"; second run: all ChartBandTests pass. Open the four PNGs and check against the mockup: ticks at 20, 40 … 180 on the left; a Heather bracket on rows 5–14 at the right; eight labels in `band-look-ahead`; the pill at the bottom; no pill in `band-whole`.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/ChartBand.swift ios/Tests/ChartBandTests.swift ios/Tests/__Snapshots__/band-look-ahead.png ios/Tests/__Snapshots__/band-look-ahead-late.png ios/Tests/__Snapshots__/band-whole.png ios/Tests/__Snapshots__/band-shaped-whole.png
git commit -m "work: the whole view marks the stretches and shows the way back (#245)"
```

---

### Task 5: The header line, the button, and the wiring

**Files:**
- Modify: `ios/Graphghan/Work/WorkScreen.swift` (properties; `header`; `panel`; `band`)
- Modify: `ios/Graphghan/Work/WorkView.swift` (`.task`, `goToNext`, `content(chart:sequence:)`)
- Test: `ios/Tests/WorkScreenTests.swift`
- Snapshots: create `work-look-ahead-line.png`, `work-look-ahead-last.png`; re-record `work-fill-ax5.png`, `work-finished.png`.

**Interfaces:**
- Consumes: `Stretches.of(_:codes:)`, `LookAheadLine.text/spoken`, `ChartBand.stretches/returnLabel`.
- Produces: `WorkScreen` gains `var stretches: [Stretch] = []` (after `onSetBandStyle`), and
  ```swift
  /// The header's spoken value: side text, the shaped caption, the look-ahead line (spec §4.3).
  static func headerValue(chart: Chart, sequence: WorkSequence, cursor: Cursor, stretches: [Stretch]) -> String
  ```

- [ ] **Step 1: Write the failing tests**

In `WorkScreenTests`, give `screen(...)` a `stretches: [Stretch] = []` parameter passed through, add `static let stretches = Stretches.of(seq, codes: chart.palette.map(\.code))`, and add:

```swift
    /// #245: the look-ahead line under the side line, and the button that opens the whole view.
    @Test func lookAheadLine() throws {
        #expect(try Snapshots.assert(screen(Cursor(row: 5, run: 3), stretches: Self.stretches), named: "work-look-ahead-line", size: Self.phone))
    }
    @Test func lookAheadLastRow() throws {
        #expect(try Snapshots.assert(screen(Cursor(row: 14, run: 3), stretches: Self.stretches), named: "work-look-ahead-last", size: Self.phone))
    }
    @Test func theHeaderSpeaksTheLine() {
        #expect(WorkScreen.headerValue(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 5, run: 3), stretches: Self.stretches)
                == "Right side · read right to left. 9 more rows like this · then plain rows for 2 rows")
        #expect(WorkScreen.headerValue(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 5, run: 3), stretches: []) == "Right side · read right to left")
        #expect(WorkScreen.headerValue(chart: Self.chart, sequence: Self.seq, cursor: Self.end, stretches: Self.stretches) == "Every row worked")
    }
```

Change `accessibilitySize` to pass `stretches: Self.stretches` (the line must appear and not clip at `.accessibility5`). The header button appears on every unfinished screen and the finished band gains ticks, so every Work screen reference changes: delete `work-run.png`, `work-braid.png`, `work-repeat.png`, `work-fill.png`, `work-turn.png`, `work-ribbon.png`, `work-shaped.png`, `work-fill-ax5.png` and `work-finished.png` (not `work-snippet.png` or the `written-work-*` files).

- [ ] **Step 2: Run to verify they fail**

Run: the Task 2 command with `-only-testing:GraphghanTests/WorkScreenTests`.
Expected: compile error on `stretches:` / `headerValue`.

- [ ] **Step 3: Implement in `WorkScreen`**

- `header`: under the shaped caption, when `!finished`, `let line = LookAheadLine.text(row: cursor.row, stretches: stretches, sequence: sequence, chart: chart)` shown in `Font.Heather.caption`, `Color.heather`, `lineLimit(1)`, `minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.6 : 0.8)`, tappable to toggle `mode` (same closure as the row number's tap). Make the title `VStack` one accessibility element: `.accessibilityElement(children: .ignore)`, label `pass.label + " of " + count` (as the text reads), value `Self.headerValue(...)`, keep the "Jump to row" action and add "Look ahead"/"Back to the row" toggling `mode`.
- Replace the trailing `Color.clear.frame(width: 44, height: 44)` with a `Button` (image `rectangle.grid.1x2`, 20 pt semibold, `Color.ink2`, 44×44, `.buttonStyle(.plain)`) toggling `mode` with `withAnimation`, accessibility label `mode == .band ? "Look ahead" : "Back to the row"`, hidden (`Color.clear` as today) when `finished`.
- `panel`: add `.accessibilityAction(named: "What's ahead")` that posts `AccessibilityNotification.Announcement(LookAheadLine.spoken(...) ?? "").post()` when `spoken` is non-nil.
- `band`: pass `stretches: stretches` and `returnLabel: finished ? nil : sequence.pass(at: cursor.row).map { "Back to \($0.label)" }`.
- `headerValue`: `[sideText or "Every row worked", ShapedRowText.caption, LookAheadLine.text].compactMap{$0}.joined(separator: ". ")` with the finished case returning only "Every row worked".

In `WorkView`: `@State private var stretches: [Stretch] = []`; set it where `chart`/`sequence` are set in `.task` and `goToNext` (`Stretches.of(s, codes: c.palette.map(\.code))`); clear it with them in `goToNext`; pass `stretches: stretches` to `WorkScreen`.

- [ ] **Step 4: Run twice to record, then pass; then the whole app suite**

Run the WorkScreenTests command. Expected first run: every snapshot test in the suite fails once with "recorded"; second run: all pass. Check the PNGs: the button sits top right on every unfinished screen; Row 5 reads "9 more rows like this · then plain rows for 2 rows" in Heather under the side line with the button at the top right; Row 14 reads "Last row like this · …"; the ax5 image shows the line unclipped; `work-finished` has ticks and no pill or button. Then `cd ios && mise run test`: everything passes, including `DesignRulesTests`.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/WorkScreen.swift ios/Graphghan/Work/WorkView.swift ios/Tests/WorkScreenTests.swift ios/Tests/__Snapshots__/work-*.png
git commit -m "work: the look-ahead line and the whole-view button (#245)"
```

---

### Task 6: Docs, follow-on issues, PR

**Files:**
- Modify: `docs/superpowers/specs/2026-09-16-work-screen-field-design.md` (§5.3 "Whole chart" bullet)
- Modify: `docs/superpowers/specs/2026-11-09-look-ahead-design.md` (§6, §8: the two view snapshots live in `ChartBandTests` as `band-look-ahead` and `band-look-ahead-late`, since `WorkScreen.mode` is private state; every `work-*` reference is re-recorded because the header button is on all of them)
- Modify: `ios/README.md` ("Layout" or "Design language": one sentence that `Work/LookAheadLine.swift` and `Work/LookAheadLayout.swift` are the header line and the whole view's marks)

- [ ] **Step 1: Edit the three documents**

In the 2026-09-16 spec, append to the "Whole chart" bullet: "Superseded on 2026-11-09 by `2026-11-09-look-ahead-design.md` §5: the whole view carries row ticks, stretch marks, a return pill and a header button."

- [ ] **Step 2: File the follow-on issues (spec §9)**

Search first (`gh issue list --search "<words>" --state all`), then `gh issue create` with labels `enhancement`, `idea`, and the area, Idea body shape (What, Why, Rough size, Waits on):
1. `format`+`ios`: "Chart format: optional `sections` naming a pattern's stretches" (shown in place of CHANGE and in the whole-view labels; written by the generator and the importer).
2. `ios`: "Look-ahead view: long-press a row to jump there" (the whole-view half of #11).
3. `python`: "Stretches in Python, with a generated fixture" (alongside #70).
Comment on #17 that the stretch thresholds want a second chart to test against, and on #83 that the whole-chart button landed here and the capsule chevron and first-fill hint remain.

- [ ] **Step 3: Commit and open the PR**

```bash
git add docs ios/README.md
git commit -m "docs: look-ahead follow-ons and the superseded whole-chart paragraph (#245)"
git push -u origin tylervick/look-ahead
gh pr create --title "Work screen: look ahead (#245)" --body "<what and why in a paragraph; the mockup link; the snapshot names to eyeball; the four re-recorded references and why each changed>

Closes #245

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

Then watch CI and CodeRabbit to green (the repo's practice), bounding any watcher.

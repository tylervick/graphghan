# Work on the Chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Work screen's colour-column field with the chart at stitch scale, group a row's runs into segments, count long fills by tens, make the turn a step, and carry a stitch offset in the cursor without changing the progress schema.

**Architecture:** Three layers, built in order. First the model in `GraphghanCore` and `graphghan.progress`: a pure `Segments` function over a pass, a `Cursor` with a `stitch` offset and a boundary position, a `WorkEngine` that counts inside fills and stops at the turn, and a progress document that gains one optional key. Then the screen: a `WorkPanel` whose content is a pure value built from the cursor, a `ChartBand` drawn with `Canvas` from a pure `BandLayout`, and a rebuilt `WorkScreen` that composes them with a bar. Last the Live Activity state and views, accessibility, and docs. Every rule that can be a pure function is one, tested without rendering; snapshots cover composition only.

**Tech Stack:** Swift 6 with Swift Testing (`mise run core-test` and `mise run test` from `ios/`), SwiftUI `Canvas`, SwiftData (lightweight migration), Python 3 with pytest (`uv run pytest -q` from the repo root), JSON Schema 2020-12.

**Spec:** `docs/superpowers/specs/2026-09-16-work-screen-field-design.md`

## Global Constraints

- Heather tokens only: every colour through `Color.*` in `ios/Shared/Theme.swift` and every font through `Font.Heather.*`. `DesignRulesTests` scans `Graphghan/` and `Shared/` and must stay green; no new tokens are added.
- The progress document stays **schema 1**. `stitch` is optional on `cursor` and on every event; absent means 0. Writers omit the key when it is 0, so `fixtures/chart-format/progress-basic.progress.json` stays byte-identical.
- `Cursor.stitch` is `0 ..< count` inside a run and `0` at the boundary position `run == runs.count`. A completed run is the next run at stitch 0, never `stitch == count`.
- Segment thresholds, verbatim from the spec: braid = the first 8 runs when every count ≤ 4, and the last 8 only when the pass has ≥ 16 runs; repeat = period 2 to 4, ≥ 3 consecutive repetitions, longest span at the earliest start wins; fill = a single run of ≥ 20 cells. Detection order: braid, repeat, fill, run.
- Counting steps are exactly `1, 5, 10, 20, wholeRun`. `wholeRun` behaves as `s == count`. Default 10, stored per project, never written to a progress document.
- A boundary step exists after a pass when `row < passes.count` and (the technique is `rows`, or the chart states a `turn` boundary). Never on the last pass; never for `rounds` in this plan (#69).
- Point sizes, verbatim from spec §5: 8 pt per cell; current row 96 pt; other rows 48 pt; two rows above at 30%; rows below, first at 100% then 75%; ring 3 pt Heather; band inset 12 pt, radius 10 pt; bar 16 pt from the sides, 44 pt above the display edge, 72 pt tall, 36 pt radius; Back 110 pt wide; a run is centred when it fits in 80% of the width, otherwise its end sits at 75% of the width.
- Fixtures are generated: change `fixtures/chart-format/generate.py`, run `uv run python fixtures/chart-format/generate.py`, and `tests/test_drift.py` must pass.
- Conventional-commit subjects in the repo's style: `core:`, `format:`, `work:`, `activity:`, `docs:`. Commit after every task with the attribution trailer the session provides.
- Snapshots: record with `TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record mise run test` from `ios/`, commit the PNGs, then run plain `mise run test` to compare. #67 means a simulator snapshot can omit `ViewThatFits`/`ScrollView` content; the new screen uses neither, but Task 14's device check is still required before the PR merges.
- Python baseline: `uv run pytest -q` passes (251 passed, 2 skipped). Swift package: `mise run core-test`. App: `mise run test`.

## File map

| file | responsibility |
|---|---|
| `ios/Packages/GraphghanCore/Sources/GraphghanCore/Segments.swift` (new) | `Segment`, `Segments.of(_:)`, `Segments.segment(containing:in:)`, `Landmark`, `Segments.landmark(for:direction:below:)` |
| `.../WorkSequence.swift` | `Cursor.stitch`; `technique`, `turnBoundary`, `hasBoundaryStep(after:)`; `isValid`, `cellsBefore` with stitch |
| `.../WorkEngine.swift` | `CountStep`, `WorkStep.atBoundary`, `WorkAction.jump(row:run:stitch:)`, counting and boundary rules |
| `.../ProgressDocument.swift` | `ProgressEventRecord.stitch`, optional-key encoding |
| `.../Pace.swift` | cursors carry stitch through sessions |
| `.../LiveActivityState.swift` | `stitch`, `counting`, `atBoundary` on the state; boundary and fill in `make` |
| `src/graphghan/progress.py`, `schema/progress.schema.json`, `fixtures/chart-format/generate.py` | the Python reader, the schema key, the `progress-stitch` fixture |
| `ios/Graphghan/Storage/Project.swift`, `ProgressEvent.swift` | `cursorStitch`, `countStep`, `stitch` |
| `ios/Graphghan/Services/ProjectService.swift` | `apply` with the project's step; `setCountStep` |
| `ios/Graphghan/Work/WorkPanelContent.swift` (new) | the pure value the panel shows, per segment kind |
| `ios/Graphghan/Work/WorkPanel.swift` (new) | the panel view |
| `ios/Graphghan/Work/BandLayout.swift` (new) | pure geometry: offsets, ring, ticks, brackets, whole-chart fit |
| `ios/Graphghan/Work/ChartBand.swift` (new) | the `Canvas` band and its gestures |
| `ios/Graphghan/Work/RunListSheet.swift` (new) | the "Jump within row" list for VoiceOver and long-press fallback |
| `ios/Graphghan/Work/WorkScreen.swift`, `WorkView.swift`, `OnDeckRule.swift`, `WorkFeedback.swift` | recomposed screen, wiring, on-deck without the turn case, the step haptic |
| deleted: `DoneField.swift`, `RowStripView.swift`, `RunChipsView.swift` | replaced by the band and panel |
| `ios/Shared/WorkActivityViews.swift` | fill count, turn text, "Turned" |
| docs: `docs/chart-format.md`, `docs/superpowers/specs/2026-09-11-ios-design-language-design.md`, `ios/docs/qa.md`, `fixtures/chart-format/README.md` | the format key, the superseded §6.1, the QA checklist, the fixture note |

---

## Part A: the step model

### Task 1: Segments

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/Segments.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/SegmentsTests.swift`

**Interfaces:**
- Consumes: `Pass` and `Run` from `WorkSequence.swift` (`pass.runs: [Run]`, `run.count: Int`, `run.code: String`, `run.x0: Int?`, `pass.direction: Direction?`).
- Produces:
  ```swift
  public struct Segment: Equatable, Sendable {
      public enum Kind: String, Sendable { case braid, `repeat`, fill, run }
      public let kind: Kind
      public let runs: Range<Int>      // run indices in reading order
      public let period: Int           // repeat only, else 0
      public let repetitions: Int      // repeat only, else 0
  }
  public struct Landmark: Equatable, Sendable { public let code: String; public let offset: Int }
  public enum Segments {
      public static func of(_ pass: Pass) -> [Segment]
      public static func segment(containing run: Int, in pass: Pass) -> Segment?
      public static func repetition(of run: Int, in segment: Segment) -> Int?   // 0-based, repeat only
      public static func landmark(for run: Run, direction: Direction?, below: Pass?) -> Landmark?
  }
  ```
  Tasks 4, 7 and 8 consume these.

- [ ] **Step 1: Write the failing tests**

`ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/SegmentsTests.swift`:

```swift
import Testing
@testable import GraphghanCore

@Suite struct SegmentsTests {
    static let chart = try! Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static func pass(_ row: Int) -> Pass { seq.pass(at: row)! }

    private func run(_ count: Int, _ code: String, x0: Int? = nil) -> Run { Run(code: code, count: count, x0: x0) }
    private func pass(_ runs: [Run], direction: Direction? = .ltr) -> Pass {
        Pass(label: "Row 1", side: .rs, direction: direction, gridRow: 0, runs: runs)
    }

    @Test func singleRunRowIsOneFill() {
        let segs = Segments.of(Self.pass(1))   // 189 Y
        #expect(segs == [Segment(kind: .fill, runs: 0..<1, period: 0, repetitions: 0)])
    }

    @Test func row42IsBraidFillsAndRuns() {
        // 2Y 2G 4Y 2G 2Y 2G 1Y 3G | 7C 11P 117C 11P 7C | 3G 1Y 2G 4Y 2G 2Y 2G 2Y  (21 runs)
        let segs = Segments.of(Self.pass(42))
        #expect(segs.first == Segment(kind: .braid, runs: 0..<8, period: 0, repetitions: 0))
        #expect(segs.last == Segment(kind: .braid, runs: 13..<21, period: 0, repetitions: 0))
        #expect(segs.map(\.kind) == [.braid, .run, .run, .fill, .run, .run, .braid])
        #expect(Segments.segment(containing: 10, in: Self.pass(42))?.kind == .fill)
        #expect(Segments.segment(containing: 21, in: Self.pass(42)) == nil)   // the boundary position has no segment
    }

    @Test func row179HasARepeatBand() {
        // rtl: 4Y 8G 2Y 1G then (5Y 2G) x 22 ... ; the band starts at run 4
        let segs = Segments.of(Self.pass(179))
        let band = try! #require(segs.first { $0.kind == .repeat })
        #expect(band.runs.lowerBound == 4 && band.period == 2 && band.repetitions == 22)
        #expect(band.runs.count == 44)
        #expect(Segments.repetition(of: 8, in: band) == 2)
        #expect(Segments.repetition(of: 3, in: band) == nil)
    }

    @Test func braidNeedsEightShortRunsAndSixteenForBothEnds() {
        let eight = (0..<8).map { _ in run(2, "A") }
        #expect(Segments.of(pass(eight)).first?.kind == .braid)
        #expect(Segments.of(pass(eight + [run(3, "B")])).map(\.kind) == [.braid, .run])
        // 10 runs: only the leading braid, never an overlapping trailing one
        let ten = eight + [run(1, "B"), run(1, "A")]
        #expect(Segments.of(pass(ten)).map(\.kind) == [.braid, .run, .run])
        // a 5-count run breaks the braid
        var broken = eight; broken[3] = run(5, "A")
        #expect(Segments.of(pass(broken)).first?.kind != .braid)
    }

    @Test func repeatPicksLongestSpanAtEarliestStart() {
        // A B A B A B C : period 2, 3 reps, then a run
        let runs = [run(5, "A"), run(2, "B"), run(5, "A"), run(2, "B"), run(5, "A"), run(2, "B"), run(1, "C")]
        let segs = Segments.of(pass(runs))
        #expect(segs == [Segment(kind: .repeat, runs: 0..<6, period: 2, repetitions: 3), Segment(kind: .run, runs: 6..<7, period: 0, repetitions: 0)])
        // two repetitions are not a band
        #expect(Segments.of(pass(Array(runs.prefix(4)))).allSatisfy { $0.kind == .run })
    }

    @Test func fillIsTwentyOrMore() {
        #expect(Segments.of(pass([run(19, "A")])).first?.kind == .run)
        #expect(Segments.of(pass([run(20, "A")])).first?.kind == .fill)
    }

    @Test func landmarkNamesTheNearestColourStartBelow() {
        // ltr fill x0 10, count 30 → ends at x 40; below: A 0..<25, B 25..<45, C 45..<60
        let below = pass([run(25, "A", x0: 0), run(20, "B", x0: 25), run(15, "C", x0: 45)])
        let fill = run(30, "A", x0: 10)
        #expect(Segments.landmark(for: fill, direction: .ltr, below: below) == Landmark(code: "B", offset: 15))   // 40 - 25
        // rtl: read right to left the fill ends at x 10; a run below "starts" at its right edge, so A starts at 25, B at 45, C at 60;
        // only 25 is inside the fill's span 10..<40, so the landmark is A, 15 cells before the end
        #expect(Segments.landmark(for: fill, direction: .rtl, below: below) == Landmark(code: "A", offset: 15))
        // a plain row below has no landmark
        #expect(Segments.landmark(for: fill, direction: .ltr, below: pass([run(60, "A", x0: 0)])) == nil)
        #expect(Segments.landmark(for: fill, direction: .ltr, below: nil) == nil)
        #expect(Segments.landmark(for: run(30, "A"), direction: .ltr, below: below) == nil)   // no x0, no landmark
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `ios/`: `mise run core-test`
Expected: compile failure, `cannot find 'Segments' in scope`.

- [ ] **Step 3: Implement**

`ios/Packages/GraphghanCore/Sources/GraphghanCore/Segments.swift`:

```swift
/// A group of runs in a pass that the crocheter attends to as one thing (spec §4.1).
public struct Segment: Equatable, Sendable {
    public enum Kind: String, Sendable { case braid, `repeat`, fill, run }
    public let kind: Kind
    /// Run indices in reading order.
    public let runs: Range<Int>
    /// Runs per repetition; 0 unless `kind == .repeat`.
    public let period: Int
    /// How many times the unit repeats; 0 unless `kind == .repeat`.
    public let repetitions: Int
    public init(kind: Kind, runs: Range<Int>, period: Int = 0, repetitions: Int = 0) {
        self.kind = kind; self.runs = runs; self.period = period; self.repetitions = repetitions
    }
}

/// Where a fill ends, said against the row below: `offset` is how many cells past (positive) or
/// before (negative) the place where `code` starts in the row below, in reading direction.
public struct Landmark: Equatable, Sendable {
    public let code: String
    public let offset: Int
    public init(code: String, offset: Int) { self.code = code; self.offset = offset }
}

/// Pure partition of a pass's runs into segments. The thresholds are the spec's; the fixture rows in
/// SegmentsTests pin them.
public enum Segments {
    /// A twisted-cord border produces eight runs of four or fewer at each edge of a row.
    public static let braidRuns = 8
    public static let braidMaxCount = 4
    /// A repeat band is a unit of 2 to 4 runs repeated at least three times in a row.
    public static let repeatMinPeriod = 2
    public static let repeatMaxPeriod = 4
    public static let repeatMinRepetitions = 3
    /// A single run this long is worked by counting, not by reading.
    public static let fillMinCells = 20

    public static func of(_ pass: Pass) -> [Segment] {
        let runs = pass.runs
        let n = runs.count
        var segments: [Segment] = []
        var lo = 0
        var hi = n
        func shortRuns(_ range: Range<Int>) -> Bool { range.allSatisfy { runs[$0].count <= braidMaxCount } }
        if n >= braidRuns, shortRuns(0..<braidRuns) {
            segments.append(Segment(kind: .braid, runs: 0..<braidRuns))
            lo = braidRuns
        }
        if n >= 2 * braidRuns, shortRuns((n - braidRuns)..<n) {
            hi = n - braidRuns
        }
        var i = lo
        while i < hi {
            if let band = repeatBand(at: i, in: runs, until: hi) {
                segments.append(band)
                i = band.runs.upperBound
            } else {
                segments.append(Segment(kind: runs[i].count >= fillMinCells ? .fill : .run, runs: i..<(i + 1)))
                i += 1
            }
        }
        if hi < n { segments.append(Segment(kind: .braid, runs: hi..<n)) }
        return segments
    }

    /// The longest repeat band that starts exactly at `start`, or nil when none reaches three repetitions.
    private static func repeatBand(at start: Int, in runs: [Run], until end: Int) -> Segment? {
        var best: Segment?
        for period in repeatMinPeriod...repeatMaxPeriod {
            guard start + period <= end else { break }
            let unit = runs[start..<(start + period)].map { ($0.count, $0.code) }
            var reps = 1
            while start + (reps + 1) * period <= end,
                  runs[(start + reps * period)..<(start + (reps + 1) * period)].map({ ($0.count, $0.code) }).elementsEqual(unit, by: ==) {
                reps += 1
            }
            guard reps >= repeatMinRepetitions else { continue }
            let span = reps * period
            if best == nil || span > best!.runs.count {
                best = Segment(kind: .repeat, runs: start..<(start + span), period: period, repetitions: reps)
            }
        }
        return best
    }

    public static func segment(containing run: Int, in pass: Pass) -> Segment? {
        of(pass).first { $0.runs.contains(run) }
    }

    public static func repetition(of run: Int, in segment: Segment) -> Int? {
        guard segment.kind == .repeat, segment.runs.contains(run), segment.period > 0 else { return nil }
        return (run - segment.runs.lowerBound) / segment.period
    }

    /// The colour start in the row below nearest to where `run` ends, in reading direction, counting
    /// only starts strictly inside the run's span. Nil without grid columns, without a row below, or
    /// when the row below is plain under the run.
    public static func landmark(for run: Run, direction: Direction?, below: Pass?) -> Landmark? {
        guard let x0 = run.x0, let below, let direction else { return nil }
        let x1 = x0 + run.count
        let end = direction == .ltr ? x1 : x0
        var starts: [(x: Int, code: String)] = []
        for r in below.runs {
            guard let bx0 = r.x0 else { return nil }
            let startX = direction == .ltr ? bx0 : bx0 + r.count
            if startX > x0, startX < x1 { starts.append((startX, r.code)) }
        }
        guard let best = starts.min(by: { abs($0.x - end) < abs($1.x - end) }) else { return nil }
        let offset = direction == .ltr ? end - best.x : best.x - end
        return Landmark(code: best.code, offset: offset)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run from `ios/`: `mise run core-test`
Expected: all pass, including the row 42 and row 179 expectations. If `row42IsBraidFillsAndRuns` disagrees on the run count, print `Self.pass(42).runs.count` once and correct the literal ranges in the test, not the rule.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore/Sources/GraphghanCore/Segments.swift ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/SegmentsTests.swift
git commit -m "core: Segments partitions a pass into braid, repeat, fill and run (#59)"
```

---

### Task 2: A stitch offset and a boundary position in the Swift cursor

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/WorkSequence.swift:5-10` (Cursor), `:138-148` (`isValid`, `cellsBefore`), the `init(passes:cellKind:)` and `init(chart:)`
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ProgressDocument.swift:26-32` (`ProgressEventRecord`)
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/Pace.swift:56-58` (session cursors)
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/WorkSequenceTests.swift`, `ProgressDocumentTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Cursor { public var row: Int; public var run: Int; public var stitch: Int; public init(row: Int, run: Int, stitch: Int = 0) }
  public struct ProgressEventRecord { ... public let stitch: Int; public init(t: Date, row: Int, run: Int, stitch: Int = 0, kind: EventKind) }
  extension WorkSequence {
      public let technique: String?      // "rows", "rounds", or nil for explicit passes
      public let turnBoundary: Bool      // chart.stitch?.boundary?.kind == .turn
      public func hasBoundaryStep(after row: Int) -> Bool
  }
  ```
  Tasks 3, 4, 5 and 6 consume these.

- [ ] **Step 1: Write the failing tests**

Append to `WorkSequenceTests.swift`:

```swift
    @Test func cursorStitchCountsTowardCellsDone() throws {
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))
        #expect(seq.cellsBefore(Cursor(row: 1, run: 0, stitch: 10)) == 10)
        #expect(seq.cellsBefore(Cursor(row: 3, run: 1, stitch: 5)) == 28 + 2 + 5)
        #expect(seq.isValid(Cursor(row: 1, run: 0, stitch: 13)))
        #expect(!seq.isValid(Cursor(row: 1, run: 0, stitch: 14)))      // a completed run is the next run at 0
        #expect(seq.isValid(Cursor(row: 1, run: 1, stitch: 0)))        // the boundary position
        #expect(!seq.isValid(Cursor(row: 1, run: 1, stitch: 1)))
        #expect(seq.cellsBefore(Cursor(row: 1, run: 1)) == 14)
    }

    @Test func boundaryStepFollowsRowsButNotTheLastPass() throws {
        let rows = try WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))
        #expect(rows.technique == "rows" && !rows.turnBoundary)
        #expect(rows.hasBoundaryStep(after: 1) && rows.hasBoundaryStep(after: 11) && !rows.hasBoundaryStep(after: 12))
        let rounds = try WorkSequence(chart: Chart.load(Fixtures.data("minimal-rounds.chart.json")))
        #expect(rounds.technique == "rounds" && !rounds.hasBoundaryStep(after: 1))
        let explicit = try WorkSequence(chart: Chart.load(Fixtures.data("explicit-passes.chart.json")))
        #expect(explicit.technique == nil && !explicit.hasBoundaryStep(after: 1))
        let craigh = try WorkSequence(chart: Chart.load(Fixtures.data("craigh-na-dun.chart.json")))
        #expect(craigh.turnBoundary && craigh.hasBoundaryStep(after: 42))
        #expect(!WorkSequence(passes: []).hasBoundaryStep(after: 1))
    }
```

Append to `ProgressDocumentTests.swift`:

```swift
    @Test func stitchIsOptionalAndOmittedWhenZero() throws {
        let doc = try ProgressDocument.decode(Fixtures.data("progress-basic.progress.json"))
        #expect(doc.cursor.stitch == 0 && doc.events.allSatisfy { $0.stitch == 0 })
        let text = String(decoding: try doc.encode(), as: UTF8.self)
        #expect(!text.contains("\"stitch\""))
        var withStitch = ProgressDocument.legacy(slug: "x", row: 3, run: 1)
        withStitch.cursor.stitch = 5
        withStitch.events = [ProgressEventRecord(t: Date(timeIntervalSince1970: 0), row: 3, run: 1, stitch: 5, kind: .advance)]
        let encoded = String(decoding: try withStitch.encode(), as: UTF8.self)
        #expect(encoded.contains("\"cursor\":{\"row\":3,\"run\":1,\"stitch\":5}"))
        #expect(try ProgressDocument.decode(try withStitch.encode()) == withStitch)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `ios/`: `mise run core-test`
Expected: compile errors on `stitch:`, `technique`, `hasBoundaryStep`.

- [ ] **Step 3: Implement**

In `WorkSequence.swift`, replace the `Cursor` struct:

```swift
/// Where the crocheter is: 1-based pass, 0-based run, and how many cells of that run are worked.
/// `run == runs.count` is the boundary position (every run worked, the turn not yet taken); on the
/// last pass that is the finished state. `stitch` is `0 ..< count` inside a run and 0 at the boundary.
public struct Cursor: Equatable, Hashable, Codable, Sendable {
    public var row: Int
    public var run: Int
    public var stitch: Int
    public init(row: Int, run: Int, stitch: Int = 0) { self.row = row; self.run = run; self.stitch = stitch }
    public static let start = Cursor(row: 1, run: 0)

    enum CodingKeys: String, CodingKey { case row, run, stitch }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        row = try c.decode(Int.self, forKey: .row)
        run = try c.decode(Int.self, forKey: .run)
        stitch = try c.decodeIfPresent(Int.self, forKey: .stitch) ?? 0
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(row, forKey: .row)
        try c.encode(run, forKey: .run)
        if stitch != 0 { try c.encode(stitch, forKey: .stitch) }   // schema 1 stays byte-identical for old documents
    }
}
```

In `WorkSequence`, add two stored properties after `cellKind`, thread them through both inits, and add `hasBoundaryStep`:

```swift
    /// `"rows"`, `"rounds"`, or nil when explicit passes were given.
    public let technique: String?
    /// The chart states a `turn` boundary (`gauge.boundary.kind == "turn"`).
    public let turnBoundary: Bool

    public init(passes: [Pass], cellKind: CellKind = .stitch, technique: String? = nil, turnBoundary: Bool = false) {
        self.passes = passes
        self.cellKind = cellKind
        self.technique = technique
        self.turnBoundary = turnBoundary
        var before: [Int] = []
        var total = 0
        for p in passes { before.append(total); total += p.cells }
        self.before = before
        self.totalCells = total
    }

    /// A pass has a boundary step when flat work turns after it, or the chart says so; never after the last pass (spec §4.4).
    public func hasBoundaryStep(after row: Int) -> Bool {
        guard row >= 1, row < passes.count else { return false }
        return technique == "rows" || turnBoundary
    }
```

In `init(chart:)`, the explicit-passes branch becomes
`self.init(passes: ..., cellKind: chart.cellKind, technique: nil, turnBoundary: chart.stitch?.boundary?.kind == .turn)`
and the derived branch's final line becomes
`self.init(passes: passes, cellKind: chart.cellKind, technique: type, turnBoundary: chart.stitch?.boundary?.kind == .turn)`.

Replace `isValid` and `cellsBefore`:

```swift
    public func isValid(_ cursor: Cursor) -> Bool {
        guard let p = pass(at: cursor.row), cursor.run >= 0, cursor.run <= p.runs.count, cursor.stitch >= 0 else { return false }
        if cursor.run < p.runs.count { return cursor.stitch < p.runs[cursor.run].count }
        return cursor.stitch == 0
    }

    /// Cells completed at the cursor: every earlier pass, the runs before `run`, and `stitch` cells of the run in hand.
    public func cellsBefore(_ cursor: Cursor) -> Int? {
        guard isValid(cursor) else { return nil }
        let p = passes[cursor.row - 1]
        return before[cursor.row - 1] + p.runs.prefix(cursor.run).reduce(0) { $0 + $1.count } + cursor.stitch
    }
```

In `ProgressDocument.swift`, replace `ProgressEventRecord`:

```swift
public struct ProgressEventRecord: Codable, Equatable, Sendable {
    public let t: Date
    public let row: Int
    public let run: Int
    public let stitch: Int
    public let kind: EventKind
    public init(t: Date, row: Int, run: Int, stitch: Int = 0, kind: EventKind) { self.t = t; self.row = row; self.run = run; self.stitch = stitch; self.kind = kind }
    public var cursor: Cursor { Cursor(row: row, run: run, stitch: stitch) }

    enum CodingKeys: String, CodingKey { case t, row, run, stitch, kind }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Date.self, forKey: .t)
        row = try c.decode(Int.self, forKey: .row)
        run = try c.decode(Int.self, forKey: .run)
        stitch = try c.decodeIfPresent(Int.self, forKey: .stitch) ?? 0
        kind = try c.decode(EventKind.self, forKey: .kind)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t)
        try c.encode(row, forKey: .row)
        try c.encode(run, forKey: .run)
        if stitch != 0 { try c.encode(stitch, forKey: .stitch) }
        try c.encode(kind, forKey: .kind)
    }
}
```

In `Pace.summarize`, the line `toCursor = Cursor(row: e.row, run: e.run)` becomes `toCursor = e.cursor`.

- [ ] **Step 4: Run the tests to verify they pass**

Run from `ios/`: `mise run core-test`
Expected: all pass. `PaceTests.matchesTheProgressFixture` must still pass unchanged.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "core: Cursor carries a stitch offset and a boundary position; progress stays schema 1 (#59)"
```

---

### Task 3: The Python reader, the schema key, and the `progress-stitch` fixture

**Files:**
- Modify: `src/graphghan/progress.py:22-30` (`cells_before`), `:33-50` (`summarize`)
- Modify: `schema/progress.schema.json` (optional `stitch` on `cursor` and events)
- Modify: `fixtures/chart-format/generate.py:229-243` (`progress_fixtures`)
- Create (generated): `fixtures/chart-format/progress-stitch.progress.json`, `progress-stitch.progress.expected.json`
- Test: `tests/test_progress.py`; `tests/test_conformance.py` and `tests/test_drift.py` already parametrize over every `*.progress.json`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/PaceTests.swift` (parametrize over both fixtures)

**Interfaces:**
- Produces: `progress.cells_before(passes, row, run, stitch=0) -> int`; documents whose `cursor` and `events` may carry `stitch`.

- [ ] **Step 1: Write the failing Python tests**

Append to `tests/test_progress.py`:

```python
def test_cells_before_counts_the_stitch_offset():
    assert progress.cells_before(PASSES, 1, 0, 10) == 10
    assert progress.cells_before(PASSES, 3, 1, 5) == 35
    assert progress.cells_before(PASSES, 1, 1, 0) == 14  # the boundary position
    with pytest.raises(ValueError):
        progress.cells_before(PASSES, 1, 0, 14)  # a completed run is the next run at 0
    with pytest.raises(ValueError):
        progress.cells_before(PASSES, 1, 1, 1)  # nothing is worked at the boundary


def test_summarize_reads_stitch_from_cursor_and_events():
    doc = {
        "schema": 1,
        "pattern_id": "minimal",
        "chart_id": "sha256:" + "0" * 64,
        "cursor": {"row": 3, "run": 2},
        "events": [
            {"t": "2026-09-12T18:00:00Z", "row": 1, "run": 0, "stitch": 10, "kind": "advance"},
            {"t": "2026-09-12T18:00:30Z", "row": 1, "run": 1, "kind": "advance"},
            {"t": "2026-09-12T18:01:00Z", "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T18:01:30Z", "row": 1, "run": 1, "kind": "back"},
            {"t": "2026-09-12T18:02:00Z", "row": 2, "run": 0, "kind": "advance"},
            {"t": "2026-09-12T19:00:00Z", "row": 3, "run": 1, "stitch": 5, "kind": "jump"},
            {"t": "2026-09-12T19:03:00Z", "row": 3, "run": 2, "kind": "advance"},
        ],
    }
    s = progress.summarize(doc, PASSES)
    assert s["cells_done"] == 40
    assert [x["cells"] for x in s["sessions"]] == [14, 26]
    assert s["active_seconds"] == 300
    assert s["stitches_per_hour"] == 480.0
    assert s["percent"] == 23.8
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `uv run pytest -q tests/test_progress.py`
Expected: `TypeError: cells_before() takes 3 positional arguments but 4 were given`.

- [ ] **Step 3: Implement the reader and the schema**

In `src/graphghan/progress.py` replace `cells_before` and the cursor handling in `summarize`:

```python
def cells_before(passes: list[dict], row: int, run: int, stitch: int = 0) -> int:
    """Cells completed at (row, run, stitch): every earlier pass, the runs before `run`, and `stitch`
    cells of the run in hand. `run == len(runs)` is the boundary position and takes stitch 0 only."""
    if not 1 <= row <= len(passes):
        raise ValueError(f"row {row} outside 1..{len(passes)}")
    runs = passes[row - 1]["runs"]
    if not 0 <= run <= len(runs):
        raise ValueError(f"run {run} outside 0..{len(runs)} for row {row}")
    limit = runs[run]["count"] if run < len(runs) else 1
    if not 0 <= stitch < limit:
        raise ValueError(f"stitch {stitch} outside 0..{limit - 1} for row {row} run {run}")
    before = sum(r["count"] for p in passes[: row - 1] for r in p["runs"])
    return before + sum(r["count"] for r in runs[:run]) + stitch


def _cursor(obj: dict) -> tuple[int, int, int]:
    return (obj["row"], obj["run"], obj.get("stitch", 0))
```

and in `summarize`:

```python
    cur = doc["cursor"]
    done = cells_before(passes, *_cursor(cur))
    ...
    prev_cursor = (1, 0, 0)
    ...
        current["to"] = _cursor(e)
        prev_cursor, prev_t = _cursor(e), t
```

(`st = max(0, cells_before(passes, *s["to"]) - cells_before(passes, *s["from"]))` already unpacks the tuple.)

In `schema/progress.schema.json`, add `"stitch": { "type": "integer", "minimum": 0 }` to the event `properties` and to `$defs.cursor.properties`. Neither becomes required.

- [ ] **Step 4: Add the fixture to the generator**

In `fixtures/chart-format/generate.py`, after `PROGRESS_BASIC_EXPECTED`, add:

```python
PROGRESS_STITCH_EVENTS = [
    {"t": "2026-09-12T18:00:00Z", "row": 1, "run": 0, "stitch": 10, "kind": "advance"},  # ten of the 14
    {"t": "2026-09-12T18:00:30Z", "row": 1, "run": 1, "kind": "advance"},  # the boundary position: row worked, not turned
    {"t": "2026-09-12T18:01:00Z", "row": 2, "run": 0, "kind": "advance"},  # turned
    {"t": "2026-09-12T18:01:30Z", "row": 1, "run": 1, "kind": "back"},  # back to the boundary
    {"t": "2026-09-12T18:02:00Z", "row": 2, "run": 0, "kind": "advance"},
    {"t": "2026-09-12T19:00:00Z", "row": 3, "run": 1, "stitch": 5, "kind": "jump"},  # a jump into a run
    {"t": "2026-09-12T19:03:00Z", "row": 3, "run": 2, "kind": "advance"},  # the step that completes it
]

PROGRESS_STITCH_EXPECTED = {
    "percent": 23.8,
    "cells_done": 40,
    "total_cells": 168,
    "stitches_done": 40,
    "total_stitches": 168,
    "sessions": [
        {"start": "2026-09-12T18:00:00Z", "end": "2026-09-12T18:02:00Z", "cells": 14, "stitches": 14},
        {"start": "2026-09-12T19:00:00Z", "end": "2026-09-12T19:03:00Z", "cells": 26, "stitches": 26},
    ],
    "active_seconds": 300,
    "stitches_per_hour": 480.0,
}
```

and make `progress_fixtures` return both:

```python
    stitch_doc = {
        "schema": 1,
        "pattern_id": "minimal",
        "chart_id": minimal["chart"]["id"],
        "pattern_version": "1.0.0",
        "cursor": {"row": 3, "run": 2},
        "started": "2026-09-12T18:00:00Z",
        "finished": None,
        "events": PROGRESS_STITCH_EVENTS,
        "ext": {"fixture": {"chart": "minimal-rows"}},
    }
    return {"progress-basic": (doc, PROGRESS_BASIC_EXPECTED), "progress-stitch": (stitch_doc, PROGRESS_STITCH_EXPECTED)}
```

Run: `uv run python fixtures/chart-format/generate.py`
Expected: two new files under `fixtures/chart-format/`; `progress-basic.*` unchanged (`git diff --stat fixtures/` shows only the new files).

- [ ] **Step 5: Parametrize the Swift pace test over both fixtures**

In `PaceTests.swift`, change `matchesTheProgressFixture` to `@Test(arguments: ["progress-basic", "progress-stitch"]) func matchesTheProgressFixture(_ name: String) throws` and replace the two literal file names with `"\(name).progress.json"` and `"\(name).progress.expected.json"`.

- [ ] **Step 6: Run everything**

Run: `uv run pytest -q` (expect 254 passed, 2 skipped: the two new tests plus one new parametrized conformance case), then from `ios/`: `mise run core-test`.

- [ ] **Step 7: Commit**

```bash
git add src/graphghan/progress.py schema/progress.schema.json fixtures/chart-format tests/test_progress.py ios/Packages/GraphghanCore/Tests
git commit -m "format: optional stitch on the progress cursor and events; progress-stitch fixture (#59)"
```

---

### Task 4: The engine counts inside fills and stops at the turn

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/WorkEngine.swift` (whole file)
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/WorkEngineTests.swift` (existing expectations change where the spec changes them)

**Interfaces:**
- Consumes: `Segments.segment(containing:in:)` (Task 1); `Cursor.stitch`, `WorkSequence.hasBoundaryStep(after:)` (Task 2).
- Produces:
  ```swift
  public enum CountStep: Int, Codable, Sendable, CaseIterable { case one = 1, five = 5, ten = 10, twenty = 20, wholeRun = 0 }
  public enum WorkAction { case advance; case back; case jump(row: Int, run: Int = 0, stitch: Int = 0) }
  public struct WorkStep { cursor, kind, startedNewRow, finished, atBoundary: Bool }   // init(..., atBoundary: Bool = false)
  extension WorkEngine {
      public static func isCounting(_ cursor: Cursor, in seq: WorkSequence) -> Bool   // the run in hand is a fill
      public static func stride(_ step: CountStep, for run: Run) -> Int
      public static func apply(_ action: WorkAction, to cursor: Cursor, in seq: WorkSequence, step: CountStep = .ten) -> WorkStep?
  }
  ```
  Tasks 5, 6, 7, 10 and 11 consume these.

- [ ] **Step 1: Rewrite the tests**

Replace `WorkEngineTests.swift` with:

```swift
import Testing
@testable import GraphghanCore

@Suite struct WorkEngineTests {
    // 12 passes (rows, so every pass but the last has a boundary step); rows 1,2,11,12 have one run of 14;
    // rows 3-10 have 2A 10B 2A. No run reaches 20, so nothing counts.
    static let seq = try! WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))
    // Craigh na Dun row 42 (ltr): run 10 is 117 C, a fill.
    static let craigh = try! WorkSequence(chart: Chart.load(Fixtures.data("craigh-na-dun.chart.json")))
    static let fill = Cursor(row: 42, run: 10)

    @Test func advanceWithinRow() {
        let step = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 0), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 1), kind: .advance, startedNewRow: false, finished: false))
    }

    @Test func advanceReachesTheBoundaryThenTheNextRow() {
        let toBoundary = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 2), in: Self.seq)
        #expect(toBoundary == WorkStep(cursor: Cursor(row: 3, run: 3), kind: .advance, startedNewRow: false, finished: false, atBoundary: true))
        let turned = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 3), in: Self.seq)
        #expect(turned == WorkStep(cursor: Cursor(row: 4, run: 0), kind: .advance, startedNewRow: true, finished: false))
        #expect(WorkEngine.apply(.advance, to: .start, in: Self.seq)?.cursor == Cursor(row: 1, run: 1))
    }

    @Test func roundsHaveNoBoundaryStep() throws {
        let rounds = try WorkSequence(chart: Chart.load(Fixtures.data("minimal-rounds.chart.json")))
        let last = rounds.passes[0].runs.count - 1
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 1, run: last), in: rounds)?.cursor == Cursor(row: 2, run: 0))
    }

    @Test func advanceAtTheEndFinishes() {
        let last = Cursor(row: 12, run: 0)
        let step = WorkEngine.apply(.advance, to: last, in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 12, run: 1), kind: .advance, startedNewRow: false, finished: true))
        #expect(WorkEngine.isFinished(Cursor(row: 12, run: 1), in: Self.seq))
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 12, run: 1), in: Self.seq) == nil)
    }

    @Test func backWithinAndAcrossRows() {
        #expect(WorkEngine.apply(.back, to: Cursor(row: 3, run: 2), in: Self.seq)?.cursor == Cursor(row: 3, run: 1))
        // from a row's first run, Back returns to the previous row's boundary position
        let step = WorkEngine.apply(.back, to: Cursor(row: 4, run: 0), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 3), kind: .back, startedNewRow: false, finished: false, atBoundary: true))
        // and from the boundary to the row's last run
        #expect(WorkEngine.apply(.back, to: Cursor(row: 3, run: 3), in: Self.seq)?.cursor == Cursor(row: 3, run: 2))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 12, run: 1), in: Self.seq)?.cursor == Cursor(row: 12, run: 0))
    }

    @Test func backAtTheStartIsNoOp() {
        #expect(WorkEngine.apply(.back, to: .start, in: Self.seq) == nil)
    }

    @Test func jump() {
        #expect(WorkEngine.apply(.jump(row: 7), to: .start, in: Self.seq) == WorkStep(cursor: Cursor(row: 7, run: 0), kind: .jump, startedNewRow: true, finished: false))
        #expect(WorkEngine.apply(.jump(row: 0), to: .start, in: Self.seq) == nil)
        #expect(WorkEngine.apply(.jump(row: 13), to: .start, in: Self.seq) == nil)
        #expect(WorkEngine.apply(.jump(row: 3, run: 2), to: Cursor(row: 3, run: 0), in: Self.seq)
            == WorkStep(cursor: Cursor(row: 3, run: 2), kind: .jump, startedNewRow: false, finished: false))
        #expect(WorkEngine.apply(.jump(row: 3, run: 3), to: .start, in: Self.seq) == nil)  // the boundary is reached only by advancing
        // a stitch offset on a run that is not a fill is ignored
        #expect(WorkEngine.apply(.jump(row: 3, run: 1, stitch: 4), to: .start, in: Self.seq)?.cursor == Cursor(row: 3, run: 1))
    }

    @Test func fillCountsByTheStep() {
        #expect(WorkEngine.isCounting(Self.fill, in: Self.craigh))
        #expect(!WorkEngine.isCounting(Cursor(row: 42, run: 8), in: Self.craigh))
        let ten = WorkEngine.apply(.advance, to: Self.fill, in: Self.craigh, step: .ten)
        #expect(ten?.cursor == Cursor(row: 42, run: 10, stitch: 10) && ten?.startedNewRow == false)
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 42, run: 10, stitch: 110), in: Self.craigh, step: .ten)?.cursor == Cursor(row: 42, run: 11))  // 120 ≥ 117
        #expect(WorkEngine.apply(.advance, to: Self.fill, in: Self.craigh, step: .wholeRun)?.cursor == Cursor(row: 42, run: 11))
        #expect(WorkEngine.apply(.advance, to: Self.fill, in: Self.craigh, step: .one)?.cursor == Cursor(row: 42, run: 10, stitch: 1))
    }

    @Test(arguments: CountStep.allCases) func advanceAndBackAreInversesAlongAFill(_ step: CountStep) {
        var forward: [Cursor] = [Self.fill]
        while let s = WorkEngine.apply(.advance, to: forward.last!, in: Self.craigh, step: step), s.cursor.run == 10 { forward.append(s.cursor) }
        let afterFill = WorkEngine.apply(.advance, to: forward.last!, in: Self.craigh, step: step)!.cursor
        #expect(afterFill == Cursor(row: 42, run: 11))
        var back = afterFill
        for expected in forward.reversed() {
            back = WorkEngine.apply(.back, to: back, in: Self.craigh, step: step)!.cursor
            #expect(back == expected)
        }
        #expect(WorkEngine.stride(step, for: Self.craigh.pass(at: 42)!.runs[10]) == (step == .wholeRun ? 117 : step.rawValue))
    }

    @Test func backIntoAFillLandsOnItsLastStep() {
        #expect(WorkEngine.apply(.back, to: Cursor(row: 42, run: 11), in: Self.craigh, step: .ten)?.cursor == Cursor(row: 42, run: 10, stitch: 110))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 42, run: 11), in: Self.craigh, step: .wholeRun)?.cursor == Cursor(row: 42, run: 10))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 42, run: 11), in: Self.craigh, step: .one)?.cursor == Cursor(row: 42, run: 10, stitch: 116))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 42, run: 10, stitch: 10), in: Self.craigh, step: .ten)?.cursor == Self.fill)
    }

    @Test func jumpIntoAFillRoundsDownToTheStep() {
        #expect(WorkEngine.apply(.jump(row: 42, run: 10, stitch: 47), to: .start, in: Self.craigh, step: .ten)?.cursor == Cursor(row: 42, run: 10, stitch: 40))
        #expect(WorkEngine.apply(.jump(row: 42, run: 10, stitch: 47), to: .start, in: Self.craigh, step: .wholeRun)?.cursor == Self.fill)
        #expect(WorkEngine.apply(.jump(row: 42, run: 10, stitch: 117), to: .start, in: Self.craigh) == nil)
    }

    @Test func invalidCursorIsRejected() {
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 99, run: 0), in: Self.seq) == nil)
        #expect(WorkEngine.apply(.back, to: Cursor(row: 3, run: 9), in: Self.seq) == nil)
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 3, run: 0, stitch: 2), in: Self.seq) == nil)  // 2A has no stitch 2
        #expect(WorkEngine.apply(.jump(row: 1), to: Cursor(row: 99, run: 0), in: Self.seq) == nil)
    }

    @Test func emptySequenceIsNeverFinished() {
        #expect(!WorkEngine.isFinished(.start, in: WorkSequence(passes: [])))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `ios/`: `mise run core-test`
Expected: compile errors on `CountStep`, `atBoundary:`, `stitch:`.

- [ ] **Step 3: Implement**

Replace `WorkEngine.swift`:

```swift
public enum EventKind: String, Codable, Sendable {
    case advance, back, jump
}

/// How many cells one tap counts inside a fill (spec §3 decision 4). Raw values are what
/// `Project.countStep` stores; `wholeRun` is 0 so the default 10 is a real step.
public enum CountStep: Int, Codable, Sendable, CaseIterable {
    case one = 1, five = 5, ten = 10, twenty = 20, wholeRun = 0
    public static let `default`: CountStep = .ten
}

public enum WorkAction: Equatable, Sendable {
    case advance
    case back
    case jump(row: Int, run: Int = 0, stitch: Int = 0)
}

public struct WorkStep: Equatable, Sendable {
    public let cursor: Cursor
    public let kind: EventKind
    /// The step moved the cursor onto a different pass (advance across a row, or a jump).
    public let startedNewRow: Bool
    /// The step completed the last run of the last pass.
    public let finished: Bool
    /// The step landed on a boundary position: the row is worked and the turn is next.
    public let atBoundary: Bool
    public init(cursor: Cursor, kind: EventKind, startedNewRow: Bool, finished: Bool, atBoundary: Bool = false) {
        self.cursor = cursor; self.kind = kind; self.startedNewRow = startedNewRow; self.finished = finished; self.atBoundary = atBoundary
    }
}

/// The one place cursor movement is defined. Screens, intents and the Live Activity all call this.
public enum WorkEngine {
    public static func isFinished(_ cursor: Cursor, in seq: WorkSequence) -> Bool {
        guard let last = seq.passes.last else { return false }
        return cursor.row == seq.passes.count && cursor.run == last.runs.count
    }

    /// The run under the cursor is a fill segment, so taps count cells rather than runs.
    public static func isCounting(_ cursor: Cursor, in seq: WorkSequence) -> Bool {
        guard let pass = seq.pass(at: cursor.row), cursor.run < pass.runs.count else { return false }
        return Segments.segment(containing: cursor.run, in: pass)?.kind == .fill
    }

    /// Cells per tap for `run`: the step, or the whole run.
    public static func stride(_ step: CountStep, for run: Run) -> Int {
        step == .wholeRun ? run.count : step.rawValue
    }

    /// The cursor Back lands on when it re-enters `runIndex` of `pass` from the run after it: the
    /// fill's last step boundary, so advance and back walk the same stitches; stitch 0 elsewhere.
    private static func landing(row: Int, runIndex: Int, in seq: WorkSequence, step: CountStep) -> Cursor {
        let pass = seq.passes[row - 1]
        let run = pass.runs[runIndex]
        guard Segments.segment(containing: runIndex, in: pass)?.kind == .fill else { return Cursor(row: row, run: runIndex) }
        let s = stride(step, for: run)
        let last = run.count - (run.count % s)
        return Cursor(row: row, run: runIndex, stitch: max(0, last < run.count ? last : run.count - s))
    }

    public static func apply(_ action: WorkAction, to cursor: Cursor, in seq: WorkSequence, step: CountStep = .default) -> WorkStep? {
        guard seq.isValid(cursor) else { return nil }
        switch action {
        case .advance:
            if isFinished(cursor, in: seq) { return nil }
            let pass = seq.passes[cursor.row - 1]
            let runs = pass.runs.count
            if cursor.run < runs {
                if isCounting(cursor, in: seq) {
                    let next = cursor.stitch + stride(step, for: pass.runs[cursor.run])
                    if next < pass.runs[cursor.run].count {
                        return WorkStep(cursor: Cursor(row: cursor.row, run: cursor.run, stitch: next), kind: .advance, startedNewRow: false, finished: false)
                    }
                }
                if cursor.run + 1 < runs {
                    return WorkStep(cursor: Cursor(row: cursor.row, run: cursor.run + 1), kind: .advance, startedNewRow: false, finished: false)
                }
                if seq.hasBoundaryStep(after: cursor.row) {
                    return WorkStep(cursor: Cursor(row: cursor.row, run: runs), kind: .advance, startedNewRow: false, finished: false, atBoundary: true)
                }
            }
            if cursor.row < seq.passes.count {
                return WorkStep(cursor: Cursor(row: cursor.row + 1, run: 0), kind: .advance, startedNewRow: true, finished: false)
            }
            return WorkStep(cursor: Cursor(row: cursor.row, run: runs), kind: .advance, startedNewRow: false, finished: true)
        case .back:
            let pass = seq.passes[cursor.row - 1]
            if cursor.run < pass.runs.count, cursor.stitch > 0 {
                let s = stride(step, for: pass.runs[cursor.run])
                return WorkStep(cursor: Cursor(row: cursor.row, run: cursor.run, stitch: max(0, cursor.stitch - s)), kind: .back, startedNewRow: false, finished: false)
            }
            if cursor.run > 0 {
                return WorkStep(cursor: landing(row: cursor.row, runIndex: cursor.run - 1, in: seq, step: step), kind: .back, startedNewRow: false, finished: false)
            }
            if cursor.row > 1 {
                let prevRuns = seq.passes[cursor.row - 2].runs.count
                if seq.hasBoundaryStep(after: cursor.row - 1) {
                    return WorkStep(cursor: Cursor(row: cursor.row - 1, run: prevRuns), kind: .back, startedNewRow: false, finished: false, atBoundary: true)
                }
                return WorkStep(cursor: landing(row: cursor.row - 1, runIndex: max(0, prevRuns - 1), in: seq, step: step), kind: .back, startedNewRow: false, finished: false)
            }
            return nil
        case .jump(let row, let run, let stitch):
            guard let pass = seq.pass(at: row), run >= 0, run < pass.runs.count, stitch >= 0, stitch < pass.runs[run].count else { return nil }
            var target = Cursor(row: row, run: run)
            if Segments.segment(containing: run, in: pass)?.kind == .fill {
                let s = stride(step, for: pass.runs[run])
                target.stitch = stitch - (stitch % s)
            }
            return WorkStep(cursor: target, kind: .jump, startedNewRow: row != cursor.row, finished: false)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run from `ios/`: `mise run core-test`
Expected: all pass. `LiveActivityStateTests` still pass (they only use two-letter-codes cursors inside runs).

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "core: WorkEngine counts inside fills by a step and stops at the boundary position (#59)"
```

---
### Task 5: Live Activity state knows fills and the boundary

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/LiveActivityState.swift:40-64` (`WorkActivityState`), `:76-95` (`make`)
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/LiveActivityStateTests.swift`

**Interfaces:**
- Consumes: `WorkEngine.isCounting`, `WorkEngine.apply(.back, …)` (Task 4); `Cursor.stitch`, `hasBoundaryStep` (Task 2).
- Produces: `WorkActivityState.stitch: Int`, `.counting: Bool`, `.atBoundary: Bool`, each decoding to `0`/`false` when absent so an activity started by the previous app version still decodes. Task 12 consumes them.

- [ ] **Step 1: Write the failing tests**

Append to `LiveActivityStateTests.swift`:

```swift
    // Craigh na Dun row 42 (ltr): run 10 is 117 C, a fill; 21 runs, then the boundary.
    static let craigh = try! Chart.load(Fixtures.data("craigh-na-dun.chart.json"))
    static let craighSeq = try! WorkSequence(chart: craigh)

    @Test func fillReportsTheCount() throws {
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 42, run: 10, stitch: 40), sequence: Self.craighSeq))
        #expect(s.counting && s.stitch == 40 && s.currentCode == "C" && s.currentCount == 117 && !s.atBoundary)
        let plain = try #require(LiveActivityState.make(cursor: Cursor(row: 42, run: 8), sequence: Self.craighSeq))
        #expect(!plain.counting && plain.stitch == 0)
    }

    @Test func boundaryCarriesTheNextRowsFirstRun() throws {
        let runs = Self.craighSeq.pass(at: 42)!.runs.count
        let s = try #require(LiveActivityState.make(cursor: Cursor(row: 42, run: runs), sequence: Self.craighSeq))
        #expect(s.atBoundary && s.isLastInRow && !s.finished && s.currentCode == nil && s.currentCount == nil)
        let first = Self.craighSeq.pass(at: 43)!.runs[0]
        #expect(s.nextCode == first.code && s.nextCount == first.count)
        #expect(s.previousCode == Self.craighSeq.pass(at: 42)!.runs[runs - 1].code)
        #expect(s.percent == LiveActivityState.make(cursor: Cursor(row: 43, run: 0), sequence: Self.craighSeq)!.percent)
    }

    @Test func oldStatePayloadsDecodeWithDefaults() throws {
        let json = #"{"row":1,"rowCount":2,"runIndex":0,"currentCode":"Kb","currentCount":3,"isLastInRow":false,"percent":0,"finished":false}"#
        let s = try JSONDecoder().decode(WorkActivityState.self, from: Data(json.utf8))
        #expect(s.stitch == 0 && !s.counting && !s.atBoundary)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `ios/`: `mise run core-test`
Expected: compile errors on `counting`, `atBoundary`.

- [ ] **Step 3: Implement**

In `WorkActivityState`, add three properties after `previousCount` and a decoder with defaults:

```swift
    /// Cells of the current run already worked; only meaningful when `counting`.
    public var stitch: Int
    /// The current run is a fill: the lock screen shows `stitch of currentCount`.
    public var counting: Bool
    /// The row is worked and the turn is the next tap.
    public var atBoundary: Bool
```

Extend `init` with `stitch: Int = 0, counting: Bool = false, atBoundary: Bool = false` at the end of the parameter list and assign them. Add:

```swift
    enum CodingKeys: String, CodingKey {
        case row, rowCount, side, runIndex, currentCode, currentCount, nextCode, nextCount, isLastInRow, percent, finished, message
        case previousCode, previousCount, stitch, counting, atBoundary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        row = try c.decode(Int.self, forKey: .row)
        rowCount = try c.decode(Int.self, forKey: .rowCount)
        side = try c.decodeIfPresent(String.self, forKey: .side)
        runIndex = try c.decode(Int.self, forKey: .runIndex)
        currentCode = try c.decodeIfPresent(String.self, forKey: .currentCode)
        currentCount = try c.decodeIfPresent(Int.self, forKey: .currentCount)
        nextCode = try c.decodeIfPresent(String.self, forKey: .nextCode)
        nextCount = try c.decodeIfPresent(Int.self, forKey: .nextCount)
        isLastInRow = try c.decode(Bool.self, forKey: .isLastInRow)
        percent = try c.decode(Double.self, forKey: .percent)
        finished = try c.decode(Bool.self, forKey: .finished)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        previousCode = try c.decodeIfPresent(String.self, forKey: .previousCode)
        previousCount = try c.decodeIfPresent(Int.self, forKey: .previousCount)
        stitch = try c.decodeIfPresent(Int.self, forKey: .stitch) ?? 0
        counting = try c.decodeIfPresent(Bool.self, forKey: .counting) ?? false
        atBoundary = try c.decodeIfPresent(Bool.self, forKey: .atBoundary) ?? false
    }
```

(The synthesized `encode(to:)` stays.) Replace `make`:

```swift
    public static func make(cursor: Cursor, sequence: WorkSequence) -> WorkActivityState? {
        guard let pass = sequence.pass(at: cursor.row), let done = sequence.cellsBefore(cursor) else { return nil }
        let finished = WorkEngine.isFinished(cursor, in: sequence)
        let atBoundary = !finished && cursor.run == pass.runs.count
        let current: Run? = cursor.run < pass.runs.count ? pass.runs[cursor.run] : nil
        let next: Run? = atBoundary
            ? sequence.pass(at: cursor.row + 1)?.runs.first
            : (cursor.run + 1 < pass.runs.count ? pass.runs[cursor.run + 1] : nil)
        let total = sequence.totalCells
        let percent = total > 0 ? (100 * Double(done) / Double(total) * 10).rounded(.toNearestOrEven) / 10 : 0
        let previous: Run? = WorkEngine.apply(.back, to: cursor, in: sequence).flatMap { step in
            sequence.pass(at: step.cursor.row).flatMap { step.cursor.run < $0.runs.count ? $0.runs[step.cursor.run] : nil }
        }
        return WorkActivityState(
            row: cursor.row, rowCount: sequence.passes.count, side: pass.side?.rawValue, runIndex: cursor.run,
            currentCode: current?.code, currentCount: current?.count, nextCode: next?.code, nextCount: next?.count,
            isLastInRow: atBoundary || cursor.run + 1 >= pass.runs.count, percent: percent, finished: finished, message: nil,
            previousCode: previous?.code, previousCount: previous?.count,
            stitch: cursor.stitch, counting: WorkEngine.isCounting(cursor, in: sequence), atBoundary: atBoundary)
    }
```

Note `previous` at the boundary: `apply(.back)` from the boundary lands on the row's last run, which is what Back returns to, so `previousCode` is that run's code.

- [ ] **Step 4: Run the tests to verify they pass**

Run from `ios/`: `mise run core-test`
Expected: all pass, including `roundTripsThroughJSON` (the custom decoder round-trips the synthesized encoder).

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "core: activity state carries stitch, counting and the boundary (#59)"
```

---

### Task 6: Storage and the service: `cursorStitch`, `countStep`, `stitch` on events

**Files:**
- Modify: `ios/Graphghan/Storage/Project.swift`, `ios/Graphghan/Storage/ProgressEvent.swift`
- Modify: `ios/Graphghan/Services/ProjectService.swift:82-105` (`apply`) and its export/summary helpers
- Test: `ios/Tests/ProjectServiceTests.swift`

**Interfaces:**
- Consumes: `CountStep`, `WorkEngine.apply(…, step:)` (Task 4); `ProgressEventRecord(t:row:run:stitch:kind:)` (Task 2).
- Produces: `Project.cursorStitch: Int`, `Project.countStep: Int`, `Project.step: CountStep` (get/set), `ProjectService.setCountStep(_:for:) throws`. `apply` uses `project.step`. Tasks 10 and 11 consume `step` and `setCountStep`.

- [ ] **Step 1: Write the failing tests**

Append to `ProjectServiceTests.swift` (the two-letter-codes harness has no fill, so the fixture-backed craigh chart is loaded through the stub client too):

```swift
    @Test func applyCountsAFillWithTheProjectsStepAndRecordsStitch() async throws {
        let h = try await makeHarness()
        let craigh = try TestFixtures.data("craigh-na-dun.chart.json")
        let craighID = try Chart.load(craigh).id
        await h.client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: craigh)
        let manifest = TestManifest.make(chartID: craighID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        #expect(p.step == .ten && p.cursorStitch == 0)
        _ = h.service.apply(.jump(row: 42, run: 10), to: p, in: seq)   // the 117 C fill
        _ = h.service.apply(.advance, to: p, in: seq)
        #expect(p.cursor == Cursor(row: 42, run: 10, stitch: 10) && p.cursorStitch == 10)
        #expect(p.eventRecords.last == ProgressEventRecord(t: p.eventRecords.last!.t, row: 42, run: 10, stitch: 10, kind: .advance))
        try h.service.setCountStep(.twenty, for: p)
        #expect(p.step == .twenty && p.countStep == 20)
        _ = h.service.apply(.advance, to: p, in: seq)
        #expect(p.cursor.stitch == 30)
        let doc = h.service.exportDocument(for: p)
        #expect(doc.cursor.stitch == 30 && doc.events.last?.stitch == 30)
    }

    @Test func aTurnIsAnEventAndBackUndoesIt() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        for _ in 0..<3 { _ = h.service.apply(.advance, to: p, in: seq) }   // three runs of row 1
        #expect(p.cursor == Cursor(row: 1, run: 3) && !p.isFinished)          // the boundary, not row 2
        #expect(h.service.apply(.advance, to: p, in: seq)?.cursor == Cursor(row: 2, run: 0))
        #expect(h.service.apply(.back, to: p, in: seq)?.cursor == Cursor(row: 1, run: 3))
        #expect(try h.context.fetchCount(FetchDescriptor<ProgressEvent>()) == 5)
    }
```

Also update the existing `applyWritesCursorAndEventTogether`: the line `for _ in 0..<3 { _ = h.service.apply(.advance, to: p, in: seq) }` after the jump to row 2 becomes `for _ in 0..<3 { … }` still (row 2 is the last pass, so no boundary step) — leave it. In `workingBackwardsReopensAFinishedProject` nothing changes.

- [ ] **Step 2: Run the tests to verify they fail**

Run from `ios/`: `mise run test`
Expected: compile errors on `step`, `cursorStitch`, `setCountStep`.

- [ ] **Step 3: Implement**

`Project.swift`: add after `cursorRun`:

```swift
    /// Cells of the current run already worked (spec §4.2). Added after build 5; the default is
    /// what makes this a lightweight migration.
    var cursorStitch: Int = 0
    /// `CountStep.rawValue`: how many cells a tap counts inside a fill. App state, never exported.
    var countStep: Int = CountStep.default.rawValue
```

initialise both in `init` (`self.cursorStitch = 0; self.countStep = CountStep.default.rawValue`), and replace the `cursor` accessor and add `step`:

```swift
    var cursor: Cursor {
        get { Cursor(row: cursorRow, run: cursorRun, stitch: cursorStitch) }
        set { cursorRow = newValue.row; cursorRun = newValue.run; cursorStitch = newValue.stitch }
    }

    var step: CountStep {
        get { CountStep(rawValue: countStep) ?? .default }
        set { countStep = newValue.rawValue }
    }
```

and `eventRecords` maps `stitch: $0.stitch`.

`ProgressEvent.swift`: add `var stitch: Int = 0`, take `stitch: Int = 0` in `init` before `kind`, assign it.

`ProjectService.swift`: in `apply`, `WorkEngine.apply(action, to: project.cursor, in: sequence)` becomes `WorkEngine.apply(action, to: project.cursor, in: sequence, step: project.step)`; the event line becomes `ProgressEvent(t: t, row: step.cursor.row, run: step.cursor.run, stitch: step.cursor.stitch, kind: step.kind)`. Add next to `setNotes`:

```swift
    func setCountStep(_ step: CountStep, for project: Project) throws {
        project.step = step
        try save()
    }
```

`exportDocument` already builds from `eventRecords` and `project.cursor`; confirm it compiles with no change.

- [ ] **Step 4: Run the tests to verify they pass**

Run from `ios/`: `mise run test`
Expected: the new tests pass. `WorkFeedbackTests.rowBoundaryAndNewColor` now fails (the advance from row 1's last run lands on the boundary); Task 11 fixes it. `WorkScreenTests` still pass because nothing on screen changed yet.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Storage ios/Graphghan/Services ios/Tests/ProjectServiceTests.swift
git commit -m "work: projects store the stitch offset and the counting step; events record stitch (#59)"
```

---

## Part B: the screen

### Task 7: `WorkPanelContent`, the panel's pure value, and the on-deck line without the turn

**Files:**
- Create: `ios/Graphghan/Work/WorkPanelContent.swift`
- Modify: `ios/Graphghan/Work/OnDeckRule.swift:35-49` (delete the next-row case)
- Test: `ios/Tests/WorkPanelContentTests.swift` (new), `ios/Tests/OnDeckRuleTests.swift`

**Interfaces:**
- Consumes: `Segments`, `Landmark` (Task 1); `WorkEngine.isCounting`, `CountStep`, `stride` (Task 4); `OnDeckRule.onDeck`; `Stitch.name`, `chart.stitch?.boundary`.
- Produces:
  ```swift
  struct WorkPanelContent: Equatable {
      enum Kind: Equatable { case run, braid, `repeat`, fill, turn, finished }
      struct Part: Equatable { let text: String; let state: PartState }   // a run in a sequence line
      enum PartState { case done, current, upcoming }
      let kind: Kind
      let hex: String                 // the surface colour (Cream at the turn and when finished)
      let count: Int?                 // the run's count, or the counted cells inside a fill
      let total: Int?                 // the fill's count; nil elsewhere
      let badge: String?              // stitch abbreviation
      let code: String?; let name: String?
      let segmentLabel: String?       // "border braid", "repeat · 3 of 22"
      let parts: [Part]               // the sequence or unit; empty for run/fill/turn
      let repetitions: Int?           // "×22"
      let landmark: String?           // "ends 7 past where Purple starts below"
      let onDeck: String?
      let title: String?; let subtitle: String?; let detail: String?   // the turn and finished states
      let actionLabel: String         // "Done with 7 single crochet in Cream", "40 of 130 single crochet in Cream, next ten", the turn sentence, "Close"
      let capsule: String             // "checkmark", "+10", "Turned", "Close"
      static func make(chart: Chart, sequence: WorkSequence, cursor: Cursor, step: CountStep) -> WorkPanelContent
      static func landmarkText(_ landmark: Landmark, chart: Chart) -> String
      static func boundaryTitle(chart: Chart, nextColorName: String?) -> String
  }
  ```
  Tasks 8, 10 and 13 consume it.

- [ ] **Step 1: Write the failing tests**

`ios/Tests/WorkPanelContentTests.swift`:

```swift
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct WorkPanelContentTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static func make(_ cursor: Cursor, step: CountStep = .ten) -> WorkPanelContent {
        WorkPanelContent.make(chart: chart, sequence: seq, cursor: cursor, step: step)
    }
    static func name(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].name }

    @Test func plainRun() {
        let c = Self.make(Cursor(row: 42, run: 8))   // 7 C
        #expect(c.kind == .run && c.count == 7 && c.total == nil && c.code == "C" && c.name == "Cream" && c.badge == "sc")
        #expect(c.parts.isEmpty && c.segmentLabel == nil && c.landmark == nil)
        #expect(c.onDeck == "then 11 Purple")
        #expect(c.actionLabel == "Done with 7 single crochet in Cream" && c.capsule == "checkmark")
        #expect(c.hex == "#f2e8d5")
    }

    @Test func braidListsTheSequence() {
        let c = Self.make(Cursor(row: 42, run: 2))   // 4 Y, third run of the braid
        #expect(c.kind == .braid && c.segmentLabel == "border braid" && c.count == 4)
        #expect(c.parts.map(\.text) == ["2Y", "2G", "4Y", "2G", "2Y", "2G", "1Y", "3G"])
        #expect(c.parts.map(\.state) == [.done, .done, .current, .upcoming, .upcoming, .upcoming, .upcoming, .upcoming])
    }

    @Test func repeatShowsTheUnitAndTheRepetition() {
        let c = Self.make(Cursor(row: 179, run: 8))   // third repetition, first half
        #expect(c.kind == .repeat && c.segmentLabel == "repeat · 3 of 22" && c.repetitions == 22)
        #expect(c.parts.map(\.text) == ["5 Y", "2 G"] && c.parts.map(\.state) == [.current, .upcoming])
    }

    @Test func fillCountsUpWithALandmark() {
        let c = Self.make(Cursor(row: 42, run: 10, stitch: 40))   // 117 C
        #expect(c.kind == .fill && c.count == 40 && c.total == 117)
        #expect(c.landmark == "ends 1 before where Purple starts below")
        #expect(c.actionLabel == "40 of 117 single crochet in Cream, next ten" && c.capsule == "+10")
        #expect(Self.make(Cursor(row: 42, run: 10), step: .wholeRun).capsule == "checkmark")
        #expect(Self.make(Cursor(row: 42, run: 10), step: .five).capsule == "+5")
    }

    @Test func turnSaysWhatTheChartKnows() {
        let runs = Self.seq.pass(at: 42)!.runs.count
        let c = Self.make(Cursor(row: 42, run: runs))
        #expect(c.kind == .turn && c.title == "Ch 1 in Gold, turn")
        #expect(c.subtitle == "Right side · read right to left" && c.detail == "Row 43 starts in Gold")
        #expect(c.capsule == "Turned" && c.actionLabel == "Ch 1 in Gold, turn. Right side, read right to left. Row 43 starts in Gold")
        #expect(c.hex == "#F4F5F0" && c.onDeck == nil)
    }

    @Test func boundaryTitleVariants() {
        // craigh: turn, chain 1, color next → named colour
        #expect(WorkPanelContent.boundaryTitle(chart: Self.chart, nextColorName: "Gold") == "Ch 1 in Gold, turn")
        let plain = try! Chart.load(TestFixtures.data("two-letter-codes.chart.json"))   // no boundary at all
        #expect(WorkPanelContent.boundaryTitle(chart: plain, nextColorName: "Gold") == "Turn")
        let zero = OnDeckRuleTests.authored(boundary: #"{"kind":"turn","chain":0}"#)
        #expect(WorkPanelContent.boundaryTitle(chart: zero, nextColorName: nil) == "Turn")
        let counts = OnDeckRuleTests.authored(boundary: #"{"kind":"turn","chain":3,"counts_as_stitch":true}"#)
        #expect(WorkPanelContent.boundaryTitle(chart: counts, nextColorName: nil) == "Ch 3, turn (counts as a st)")
    }

    @Test func finishedState() {
        let end = Cursor(row: Self.seq.passes.count, run: Self.seq.passes.last!.runs.count)
        let c = Self.make(end)
        #expect(c.kind == .finished && c.title == "Finished" && c.capsule == "Close" && c.actionLabel == "Close")
    }
}
```

In `OnDeckRuleTests.swift`, replace `lastRunInRowNamesNextRowsColor` and `turnBoundaryPrependsTheChain` (and any other test that expects "next row starts in" or "turn" text) with:

```swift
    @Test func lastRunInRowHasNothingOnDeck() {
        // the turn is a step of its own now (spec §3 decision 5); the on-deck line only names the next run in the row
        #expect(OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: Self.chart, sequence: Self.seq) == nil)
        let chart = Self.authored(boundary: #"{"kind":"turn","chain":1}"#)
        let seq = try! WorkSequence(chart: chart)
        #expect(OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: chart, sequence: seq) == nil)
    }
```

Keep `nextRunInRow`, `stitchKindOnDeckLineIsByteIdentical`, `nonStitchKindAppendsTheNoun`, `lastRunOfPatternHasNothingOnDeck`, and the foundation tests.

- [ ] **Step 2: Run the tests to verify they fail**

Run from `ios/`: `mise run test`
Expected: compile error, `cannot find 'WorkPanelContent'`.

- [ ] **Step 3: Implement**

`OnDeckRule.swift`: delete the block beginning `if let nextPass = sequence.pass(at: cursor.row + 1)` through its `return OnDeck(text: text, hex: e.hex)`, so after the `cursor.run + 1 < pass.runs.count` case the function returns `nil`. Update the file comment to "the next run in the row, or the foundation at the start; the turn is its own step".

`ios/Graphghan/Work/WorkPanelContent.swift`:

```swift
import GraphghanCore

/// Everything the panel shows for one cursor position, computed once and rendered by `WorkPanel`
/// (spec §5.2). Pure, so every state is a value test.
struct WorkPanelContent: Equatable {
    enum Kind: Equatable { case run, braid, `repeat`, fill, turn, finished }
    enum PartState: Equatable { case done, current, upcoming }
    struct Part: Equatable { let text: String; let state: PartState }

    let kind: Kind
    let hex: String
    let count: Int?
    let total: Int?
    let badge: String?
    let code: String?
    let name: String?
    let segmentLabel: String?
    let parts: [Part]
    let repetitions: Int?
    let landmark: String?
    let onDeck: String?
    let title: String?
    let subtitle: String?
    let detail: String?
    let actionLabel: String
    let capsule: String

    /// The turn and finished surfaces. Lives in `YarnSurface` because `Work/` may not hold a raw hex (DesignRulesTests).
    static let creamHex = YarnSurface.creamHex

    static func make(chart: Chart, sequence: WorkSequence, cursor: Cursor, step: CountStep) -> WorkPanelContent {
        if WorkEngine.isFinished(cursor, in: sequence) {
            return WorkPanelContent(kind: .finished, hex: creamHex, count: nil, total: nil, badge: nil, code: nil, name: nil,
                                    segmentLabel: nil, parts: [], repetitions: nil, landmark: nil, onDeck: nil,
                                    title: "Finished", subtitle: "Every row is done. Block it, weave in the ends, and take a picture.", detail: nil,
                                    actionLabel: "Close", capsule: "Close")
        }
        guard let pass = sequence.pass(at: cursor.row) else {
            return WorkPanelContent(kind: .finished, hex: creamHex, count: nil, total: nil, badge: nil, code: nil, name: nil, segmentLabel: nil,
                                    parts: [], repetitions: nil, landmark: nil, onDeck: nil, title: nil, subtitle: nil, detail: nil, actionLabel: "Close", capsule: "Close")
        }
        func entry(_ code: String) -> ChartDocument.PaletteEntry { chart.palette[chart.colorIndex(of: code) ?? 0] }
        let stitchName = chart.stitch.map { $0.name ?? $0.code }

        if cursor.run >= pass.runs.count {
            let next = sequence.pass(at: cursor.row + 1)
            let nextName = next?.runs.first.map { entry($0.code).name }
            let side = next?.side == .ws ? "Wrong side" : "Right side"
            let direction = next?.direction == .ltr ? "read left to right" : "read right to left"
            let title = boundaryTitle(chart: chart, nextColorName: nextName)
            let detail = nextName.map { "Row \(cursor.row + 1) starts in \($0)" }
            return WorkPanelContent(kind: .turn, hex: creamHex, count: nil, total: nil, badge: nil, code: nil, name: nil, segmentLabel: nil,
                                    parts: [], repetitions: nil, landmark: nil, onDeck: nil,
                                    title: title, subtitle: "\(side) · \(direction)", detail: detail,
                                    actionLabel: [title, "\(side), \(direction)", detail].compactMap { $0 }.joined(separator: ". "), capsule: "Turned")
        }

        let run = pass.runs[cursor.run]
        let e = entry(run.code)
        let segment = Segments.segment(containing: cursor.run, in: pass)
        let onDeck = OnDeckRule.onDeck(cursor: cursor, chart: chart, sequence: sequence)?.text
        let noun = stitchName ?? (chart.cellKind == .stitch ? "" : chart.cellKind.nounPlural)
        func label(_ n: Int) -> String { ["Done with \(n)", stitchName, "in \(e.name)"].compactMap { $0 }.joined(separator: " ") }

        switch segment?.kind {
        case .fill:
            let counting = WorkEngine.isCounting(cursor, in: sequence)
            let stride = WorkEngine.stride(step, for: run)
            let capsule = step == .wholeRun || !counting ? "checkmark" : "+\(stride)"
            let below = sequence.pass(at: cursor.row - 1)
            let landmark = Segments.landmark(for: run, direction: pass.direction, below: below).map { landmarkText($0, chart: chart) }
            let nextWord = step == .wholeRun ? "next \(run.count - cursor.stitch)" : "next \(stride == 10 ? "ten" : String(stride))"
            let action = "\(cursor.stitch) of \(run.count) \(noun.isEmpty ? "" : noun + " ")in \(e.name), \(nextWord)".replacingOccurrences(of: "  ", with: " ")
            return WorkPanelContent(kind: .fill, hex: e.hex, count: cursor.stitch, total: run.count, badge: chart.stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: nil, parts: [], repetitions: nil, landmark: landmark, onDeck: onDeck,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: action, capsule: capsule)
        case .braid:
            let parts = segment!.runs.map { i -> Part in
                let r = pass.runs[i]
                return Part(text: "\(r.count)\(r.code)", state: i < cursor.run ? .done : i == cursor.run ? .current : .upcoming)
            }
            return WorkPanelContent(kind: .braid, hex: e.hex, count: run.count, total: nil, badge: chart.stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: "border braid", parts: parts, repetitions: nil, landmark: nil, onDeck: onDeck,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: label(run.count), capsule: "checkmark")
        case .repeat:
            let seg = segment!
            let which = Segments.repetition(of: cursor.run, in: seg) ?? 0
            let position = (cursor.run - seg.runs.lowerBound) % seg.period
            let parts = (0..<seg.period).map { j -> Part in
                let r = pass.runs[seg.runs.lowerBound + j]
                return Part(text: "\(r.count) \(r.code)", state: j < position ? .done : j == position ? .current : .upcoming)
            }
            return WorkPanelContent(kind: .repeat, hex: e.hex, count: run.count, total: nil, badge: chart.stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: "repeat · \(which + 1) of \(seg.repetitions)", parts: parts, repetitions: seg.repetitions, landmark: nil, onDeck: onDeck,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: label(run.count), capsule: "checkmark")
        default:
            return WorkPanelContent(kind: .run, hex: e.hex, count: run.count, total: nil, badge: chart.stitch?.code, code: e.code, name: e.name,
                                    segmentLabel: nil, parts: [], repetitions: nil, landmark: nil, onDeck: onDeck,
                                    title: nil, subtitle: nil, detail: nil, actionLabel: label(run.count), capsule: "checkmark")
        }
    }

    /// "ends 7 past where Purple starts below" / "ends 2 before …" / "ends where the Purple starts below".
    static func landmarkText(_ landmark: Landmark, chart: Chart) -> String {
        let name = chart.palette[chart.colorIndex(of: landmark.code) ?? 0].name
        if landmark.offset == 0 { return "ends where the \(name) starts below" }
        return "ends \(abs(landmark.offset)) \(landmark.offset > 0 ? "past" : "before") where \(name) starts below"
    }

    /// The boundary step's title from what the chart states (spec §4.4).
    static func boundaryTitle(chart: Chart, nextColorName: String?) -> String {
        guard let boundary = chart.stitch?.boundary, boundary.kind == .turn, boundary.chain > 0 else { return "Turn" }
        var title = boundary.color == .next, let name = nextColorName ? "Ch \(boundary.chain) in \(name), turn" : "Ch \(boundary.chain), turn"
        if boundary.countsAsStitch { title += " (counts as a st)" }
        return title
    }
}
```

Note the fill's `actionLabel` builds "40 of 117 single crochet in Cream, next ten"; when the chart has no stitch the noun is empty and the double space is collapsed.

In `ios/Shared/YarnSurface.swift` (allow-listed by `DesignRulesTests`), add next to `unknownHex`:

```swift
    /// Cream (#F4F5F0) as a hex, for surfaces that take a yarn colour but have none: the turn and the finished panel.
    static let creamHex = "#F4F5F0"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run from `ios/`: `mise run test`
Expected: `WorkPanelContentTests` and `OnDeckRuleTests` pass. `WorkScreenTests.lastRunInRow` fails on its snapshot because the on-deck line lost the turn text; Task 10 replaces those snapshots. If `plainRun`'s hex literal differs in case, match the fixture's palette hex exactly (`#f2e8d5`).

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/WorkPanelContent.swift ios/Graphghan/Work/OnDeckRule.swift ios/Tests/WorkPanelContentTests.swift ios/Tests/OnDeckRuleTests.swift
git commit -m "work: WorkPanelContent, the panel by segment; the on-deck line loses the turn (#59)"
```

---

### Task 8: `BandLayout`, the band's pure geometry

**Files:**
- Create: `ios/Graphghan/Work/BandLayout.swift`
- Test: `ios/Tests/BandLayoutTests.swift`

**Interfaces:**
- Consumes: `Pass`, `Run.x0`, `Segments.segment(containing:in:)`, `Cursor`.
- Produces:
  ```swift
  struct BandLayout: Equatable {
      static let cell: CGFloat = 8, currentRowHeight: CGFloat = 96, rowHeight: CGFloat = 48, rowsAbove = 2, rulerHeight: CGFloat = 22
      let width: CGFloat; let height: CGFloat; let chartWidth: Int
      let rowsBelow: Int                          // how many fit under the current row
      let offsetX: CGFloat                        // content translation; 0 ≤ offsetX ≤ chartWidth*cell - width
      let ring: CGRect?                           // the current run in content coordinates; nil at the boundary
      let ticks: [(x: CGFloat, label: Int)]       // every 10 cells from the run's start, run ≥ 10 only
      let bracket: (x0: CGFloat, x1: CGFloat, label: String)?
      let boundaryX: CGFloat?                     // the row's end in reading direction, at the boundary
      init(width: CGFloat, height: CGFloat, chart: Chart, pass: Pass, cursor: Cursor, segmentLabel: String?)
      func rowTop(_ k: Int) -> CGFloat            // k = -rowsAbove ... rowsBelow, 0 is the current row
      func rowHeight(_ k: Int) -> CGFloat
      func rowOpacity(_ k: Int) -> Double         // 0.3 above, 1 current and first below, 0.75 further below
      func cellAt(x: CGFloat) -> Int              // view x → grid column
      static func wholeChartRect(chart: Chart, in size: CGSize) -> CGRect   // true-aspect fit
  }
  ```
  Task 9 consumes it.

- [ ] **Step 1: Write the failing tests**

`ios/Tests/BandLayoutTests.swift`:

```swift
import CoreGraphics
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct BandLayoutTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))   // 189 × 184
    static let seq = try! WorkSequence(chart: chart)
    static let pass42 = seq.pass(at: 42)!   // ltr; run 10 = 117 C at x0 36; run 2 = 4 Y at x0 4
    static func layout(_ cursor: Cursor, width: CGFloat = 366, height: CGFloat = 420, label: String? = nil) -> BandLayout {
        BandLayout(width: width, height: height, chart: chart, pass: seq.pass(at: cursor.row)!, cursor: cursor, segmentLabel: label)
    }

    @Test func rowsBelowFillTheHeight() {
        // 420 = 2×48 above + 96 + 22 ruler + 206 left → 4 rows below (4×48 = 192)
        #expect(Self.layout(Cursor(row: 42, run: 8)).rowsBelow == 4)
        #expect(Self.layout(Cursor(row: 42, run: 8), height: 250).rowsBelow == 1)   // never fewer than one
        let l = Self.layout(Cursor(row: 42, run: 8))
        #expect(l.rowTop(-2) == 0 && l.rowTop(0) == 96 && l.rowHeight(0) == 96 && l.rowTop(1) == 192 && l.rowHeight(1) == 48)
        #expect(l.rowOpacity(-1) == 0.3 && l.rowOpacity(0) == 1 && l.rowOpacity(1) == 1 && l.rowOpacity(2) == 0.75)
    }

    @Test func shortRunIsCentred() {
        let l = Self.layout(Cursor(row: 42, run: 2))   // 4 Y at x0 4: 32 pt wide, centre at 48 → clamped to 0
        #expect(l.offsetX == 0)
        let ring = try! #require(l.ring)
        #expect(ring.minX == 4 * 8 && ring.width == 4 * 8)
        // a run in the middle of the row is centred on the view
        let mid = Self.layout(Cursor(row: 42, run: 11))   // 11 P at x0 153: centre 158.5 cells = 1268 pt
        #expect(abs(mid.offsetX - (1268 - 183)) < 0.5)
    }

    @Test func longRunKeepsItsEndAtThreeQuarters() {
        let l = Self.layout(Cursor(row: 42, run: 10))   // 117 C, x0 36..153, ltr: end at x 153 → 1224 pt
        #expect(abs(l.offsetX - (1224 - 366 * 0.75)) < 0.5)
        #expect(l.ticks.map(\.label) == [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110])
        #expect(l.ticks[1].x == (36 + 10) * 8)
        #expect(Self.layout(Cursor(row: 42, run: 8)).ticks.isEmpty)   // 7 C: under ten, no ruler
    }

    @Test func rtlLongRunCountsFromItsRightEdge() {
        // row 41 is rtl; take its first run of 20+ if any, else synthesise: use row 43 (rtl) run index of the 117 C mirror
        let pass = Self.seq.pass(at: 43)!
        let i = pass.runs.firstIndex { $0.count >= 20 }!
        let run = pass.runs[i]
        let l = Self.layout(Cursor(row: 43, run: i))
        #expect(l.ticks.first?.x == CGFloat(run.x0! + run.count) * 8)   // the start, in reading direction, is the right edge
        #expect(abs(l.offsetX - (CGFloat(run.x0!) * 8 - 366 * 0.25)) < 0.5)   // the end (left edge) sits at one quarter from the left
    }

    @Test func bracketSpansTheSegment() {
        let l = Self.layout(Cursor(row: 42, run: 2), label: "border braid")
        let b = try! #require(l.bracket)
        #expect(b.x0 == 0 && b.x1 == CGFloat(Self.pass42.runs[7].x0! + Self.pass42.runs[7].count) * 8 && b.label == "border braid")
        #expect(Self.layout(Cursor(row: 42, run: 8)).bracket == nil)
    }

    @Test func boundaryMarksTheRowEnd() {
        let l = Self.layout(Cursor(row: 42, run: Self.pass42.runs.count))
        #expect(l.ring == nil && l.boundaryX == 189 * 8)
        #expect(l.offsetX == 189 * 8 - 366)   // the end is in view
    }

    @Test func cellAtInvertsTheOffset() {
        let l = Self.layout(Cursor(row: 42, run: 10))
        #expect(l.cellAt(x: 366 * 0.75) == 153 || l.cellAt(x: 366 * 0.75) == 152)
        #expect(l.cellAt(x: -1000) == 0 && l.cellAt(x: 100_000) == 188)
    }

    @Test func wholeChartFitsTrueAspect() {
        let r = BandLayout.wholeChartRect(chart: Self.chart, in: CGSize(width: 366, height: 420))
        #expect(abs(r.width / r.height - 189.0 / 184.0) < 0.01 && r.width == 366)
        #expect(abs(r.midY - 210) < 0.5)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run from `ios/`: `mise run test`
Expected: compile error, `cannot find 'BandLayout'`.

- [ ] **Step 3: Implement**

`ios/Graphghan/Work/BandLayout.swift`:

```swift
import CoreGraphics
import GraphghanCore

/// Where everything in the band sits, in content coordinates (grid column × cell), and how far the
/// content is shifted so the current run reads (spec §5.3). Pure, so the rules are value tests.
struct BandLayout {
    static let cell: CGFloat = 8
    static let currentRowHeight: CGFloat = 96
    static let rowHeight: CGFloat = 48
    static let rowsAbove = 2
    static let rulerHeight: CGFloat = 22
    static let rulerEvery = 10

    let width: CGFloat
    let height: CGFloat
    let chartWidth: Int
    let rowsBelow: Int
    let offsetX: CGFloat
    let ring: CGRect?
    let ticks: [(x: CGFloat, label: Int)]
    let bracket: (x0: CGFloat, x1: CGFloat, label: String)?
    let boundaryX: CGFloat?

    init(width: CGFloat, height: CGFloat, chart: Chart, pass: Pass, cursor: Cursor, segmentLabel: String?) {
        self.width = width
        self.height = height
        chartWidth = chart.width
        let cell = Self.cell
        let content = CGFloat(chart.width) * cell
        let fixed = CGFloat(Self.rowsAbove) * Self.rowHeight + Self.currentRowHeight + Self.rulerHeight
        rowsBelow = max(1, Int((height - fixed) / Self.rowHeight))
        let ltr = pass.direction != .rtl
        func clamp(_ x: CGFloat) -> CGFloat { min(max(0, x), max(0, content - width)) }

        if cursor.run < pass.runs.count, let x0 = pass.runs[cursor.run].x0 {
            let run = pass.runs[cursor.run]
            let x1 = x0 + run.count
            let w = CGFloat(run.count) * cell
            ring = CGRect(x: CGFloat(x0) * cell, y: 0, width: w, height: Self.currentRowHeight)
            if w <= width * 0.8 {
                offsetX = clamp(CGFloat(x0) * cell + w / 2 - width / 2)
            } else {
                let end = CGFloat(ltr ? x1 : x0) * cell
                offsetX = clamp(ltr ? end - width * 0.75 : end - width * 0.25)
            }
            if run.count >= Self.rulerEvery {
                ticks = stride(from: 0, through: run.count, by: Self.rulerEvery).map { k in
                    (x: CGFloat(ltr ? x0 + k : x1 - k) * cell, label: k)
                }
            } else {
                ticks = []
            }
            if let label = segmentLabel, let seg = Segments.segment(containing: cursor.run, in: pass), seg.kind == .braid || seg.kind == .repeat {
                let lo = seg.runs.compactMap { pass.runs[$0].x0 }.min() ?? x0
                let hi = seg.runs.compactMap { i in pass.runs[i].x0.map { $0 + pass.runs[i].count } }.max() ?? x1
                bracket = (x0: CGFloat(lo) * cell, x1: CGFloat(hi) * cell, label: label)
            } else {
                bracket = nil
            }
            boundaryX = nil
        } else {
            ring = nil
            ticks = []
            bracket = nil
            let endX = CGFloat(ltr ? chart.width : 0) * cell
            boundaryX = endX
            offsetX = clamp(ltr ? endX - width : 0)
        }
    }

    func rowTop(_ k: Int) -> CGFloat {
        if k < 0 { return CGFloat(Self.rowsAbove + k) * Self.rowHeight }
        if k == 0 { return CGFloat(Self.rowsAbove) * Self.rowHeight }
        return CGFloat(Self.rowsAbove) * Self.rowHeight + Self.currentRowHeight + CGFloat(k - 1) * Self.rowHeight
    }
    func rowHeight(_ k: Int) -> CGFloat { k == 0 ? Self.currentRowHeight : Self.rowHeight }
    func rowOpacity(_ k: Int) -> Double { k < 0 ? 0.3 : k <= 1 ? 1 : 0.75 }

    /// The grid column under a view x, clamped to the chart.
    func cellAt(x: CGFloat) -> Int {
        min(max(0, Int((x + offsetX) / Self.cell)), chartWidth - 1)
    }

    /// The whole chart at true aspect, as wide as the band and vertically centred (spec §5.3).
    static func wholeChartRect(chart: Chart, in size: CGSize) -> CGRect {
        let aspect = CGFloat(chart.width) / CGFloat(chart.height)
        var w = size.width
        var h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}
```

The bracket spans from the segment's leftmost `x0` to its rightmost right edge, whatever the reading direction.

- [ ] **Step 4: Run the tests to verify they pass**

Run from `ios/`: `mise run test`
Expected: pass. If `shortRunIsCentred`'s `mid` expectation is off by the run's true `x0`, read `Self.pass42.runs[11].x0` once and correct the literal (the rule is centre − width/2).

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/BandLayout.swift ios/Tests/BandLayoutTests.swift
git commit -m "work: BandLayout, the band's geometry as a value (#59)"
```

---
### Task 9: `ChartBand`, the `Canvas` band and its gestures

**Files:**
- Create: `ios/Graphghan/Work/ChartBand.swift`
- Test: `ios/Tests/ChartBandTests.swift` (component snapshots)

**Interfaces:**
- Consumes: `BandLayout` (Task 8); `Chart.runsByRow`, `Chart.palette`, `ChartImage.color(_:)`; `Segments`.
- Produces:
  ```swift
  struct ChartBand: View {
      enum Mode: Equatable { case band, whole }
      let chart: Chart; let sequence: WorkSequence; let cursor: Cursor
      let segmentLabel: String?
      let mode: Mode
      let onAdvance: () -> Void
      let onJump: (_ run: Int, _ stitch: Int) -> Void     // long-press on a cell of the current row
      let onToggleMode: () -> Void                         // pinch past the thresholds
  }
  ```
  Task 10 consumes it.

- [ ] **Step 1: Write the failing snapshot tests**

`ios/Tests/ChartBandTests.swift`:

```swift
import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct ChartBandTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let size = CGSize(width: 366, height: 420)

    private func band(_ cursor: Cursor, label: String? = nil, mode: ChartBand.Mode = .band) -> some View {
        ChartBand(chart: Self.chart, sequence: Self.seq, cursor: cursor, segmentLabel: label, mode: mode, onAdvance: {}, onJump: { _, _ in }, onToggleMode: {})
            .background(Color.ground)
    }

    @Test func fillKeepsItsEndInView() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: 10, stitch: 40)), named: "band-fill", size: Self.size))
    }
    @Test func braidBracket() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: 2), label: "border braid"), named: "band-braid", size: Self.size))
    }
    @Test func repeatBracket() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 179, run: 8), label: "×22 · 3 of 22"), named: "band-repeat", size: Self.size))
    }
    @Test func boundary() throws {
        let runs = Self.seq.pass(at: 42)!.runs.count
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: runs)), named: "band-turn", size: Self.size))
    }
    @Test func wholeChart() throws {
        #expect(try Snapshots.assert(band(Cursor(row: 42, run: 8), mode: .whole), named: "band-whole", size: Self.size))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run from `ios/`: `mise run test`
Expected: compile error, `cannot find 'ChartBand'`.

- [ ] **Step 3: Implement**

`ios/Graphghan/Work/ChartBand.swift`:

```swift
import SwiftUI
import GraphghanCore

/// The chart at stitch scale (spec §5.3): the current row tall and ringed, two rows above faint,
/// the rows below at full strength as the ruler; or the whole chart at true aspect. Drawn with
/// `Canvas` and redrawn only when the cursor or size changes. The band is hidden from VoiceOver;
/// the panel is the spoken path.
struct ChartBand: View {
    enum Mode: Equatable { case band, whole }

    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    let segmentLabel: String?
    let mode: Mode
    let onAdvance: () -> Void
    let onJump: (_ run: Int, _ stitch: Int) -> Void
    let onToggleMode: () -> Void

    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let pass = sequence.pass(at: cursor.row)
            let layout = pass.map { BandLayout(width: geo.size.width, height: geo.size.height, chart: chart, pass: $0, cursor: cursor, segmentLabel: segmentLabel) }
            Canvas(rendersAsynchronously: false) { context, size in
                if mode == .whole || layout == nil {
                    drawWhole(context: &context, size: size)
                } else if let layout, let pass {
                    drawBand(context: &context, layout: layout, pass: pass, size: size)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onAdvance() }
            .gesture(longPressJump(layout: layout, pass: pass))
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { drag = $0.translation.width }.onEnded { _ in
                withAnimation(reduceMotion ? nil : .spring(duration: 0.25)) { drag = 0 }
            })
            .simultaneousGesture(MagnifyGesture().onEnded { value in
                if (mode == .band && value.magnification < 0.8) || (mode == .whole && value.magnification > 1.2) { onToggleMode() }
            })
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
        .onChange(of: cursor) { _, _ in drag = 0 }
        .accessibilityHidden(true)
    }

    private func longPressJump(layout: BandLayout?, pass: Pass?) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5).sequenced(before: DragGesture(minimumDistance: 0)).onEnded { value in
            guard case .second(true, let drag?) = value, let layout, let pass, mode == .band else { return }
            let x = layout.cellAt(x: drag.location.x - self.drag)
            guard let i = pass.runs.firstIndex(where: { r in r.x0.map { $0 <= x && x < $0 + r.count } ?? false }) else { return }
            let run = pass.runs[i]
            let ltr = pass.direction != .rtl
            let stitch = ltr ? x - run.x0! : run.x0! + run.count - 1 - x
            onJump(i, stitch)
        }
    }

    private func fill(_ code: Int) -> Color { ChartImage.color(chart.palette[code].hex) }

    private func drawRow(gridRow: Int, top: CGFloat, height: CGFloat, opacity: Double, workedUpTo: Int?, context: inout GraphicsContext, offset: CGFloat) {
        guard gridRow >= 0, gridRow < chart.height else { return }
        let cell = BandLayout.cell
        for run in chart.runsByRow[gridRow] {
            let rect = CGRect(x: CGFloat(run.x0) * cell - offset, y: top, width: CGFloat(run.count) * cell, height: height)
            context.fill(Path(rect), with: .color(fill(run.colorIndex).opacity(opacity)))
        }
        // cell hairlines, then the row's bottom hairline
        for x in 0...chart.width {
            let px = CGFloat(x) * cell - offset
            context.fill(Path(CGRect(x: px - 0.25, y: top, width: 0.5, height: height)), with: .color(.black.opacity(0.10 * opacity)))
        }
        context.fill(Path(CGRect(x: -offset, y: top + height - 0.25, width: CGFloat(chart.width) * cell, height: 0.5)), with: .color(.black.opacity(0.15 * opacity)))
    }

    private func drawBand(context: inout GraphicsContext, layout: BandLayout, pass: Pass, size: CGSize) {
        guard let y = pass.gridRow else { return }
        let offset = layout.offsetX - drag
        let cell = BandLayout.cell
        // rows: the two above faint, the current, then the rows below
        for k in -BandLayout.rowsAbove...layout.rowsBelow {
            let gridRow = y - k * (sequence.pass(at: cursor.row + 1)?.gridRow.map { $0 < y ? 1 : -1 } ?? -1)
            drawRow(gridRow: gridRow, top: layout.rowTop(k), height: layout.rowHeight(k), opacity: layout.rowOpacity(k), workedUpTo: nil, context: &context, offset: offset)
        }
        // the current row ahead of the cursor is faint: cover it with Ground at 70%
        let top = layout.rowTop(0)
        if let ring = layout.ring, cursor.run < pass.runs.count {
            let ltr = pass.direction != .rtl
            let workedCells = CGFloat(cursor.stitch) * cell
            let aheadInRun = ltr
                ? CGRect(x: ring.minX + workedCells - offset, y: top, width: ring.width - workedCells, height: ring.height)
                : CGRect(x: ring.minX - offset, y: top, width: ring.width - workedCells, height: ring.height)
            context.fill(Path(aheadInRun), with: .color(Color.ground.opacity(0.7)))
            let restOfRow = ltr
                ? CGRect(x: ring.maxX - offset, y: top, width: CGFloat(chart.width) * cell - ring.maxX, height: ring.height)
                : CGRect(x: -offset, y: top, width: ring.minX, height: ring.height)
            context.fill(Path(restOfRow), with: .color(Color.ground.opacity(0.7)))
            // the ring
            let ringRect = CGRect(x: ring.minX - offset + 1.5, y: top + 1.5, width: ring.width - 3, height: ring.height - 3)
            context.stroke(Path(ringRect), with: .color(.heather), lineWidth: 3)
            // ruler
            let base = layout.rowTop(layout.rowsBelow) + layout.rowHeight(layout.rowsBelow) + 4
            for tick in layout.ticks {
                context.fill(Path(CGRect(x: tick.x - offset - 0.5, y: base, width: 1, height: 6)), with: .color(.ink2))
                if tick.label > 0 {
                    context.draw(Text("\(tick.label)").font(Font.Heather.caption).foregroundStyle(Color.ink2), at: CGPoint(x: tick.x - offset, y: base + 14))
                }
            }
        } else if let bx = layout.boundaryX {
            // the whole row is worked: mark its end and point at the next row's first stitch
            let ltr = pass.direction != .rtl
            context.fill(Path(CGRect(x: bx - offset - (ltr ? 3 : 0), y: top - 8, width: 3, height: layout.rowHeight(0) + 8)), with: .color(.heather))
            var arc = Path()
            arc.move(to: CGPoint(x: bx - offset, y: top - 8))
            arc.addQuadCurve(to: CGPoint(x: bx - offset + (ltr ? -80 : 80), y: top - 8), control: CGPoint(x: bx - offset + (ltr ? -40 : 40), y: top - 22))
            context.stroke(arc, with: .color(.heather), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        }
        // bracket above the current row
        if let b = layout.bracket {
            var path = Path()
            path.move(to: CGPoint(x: b.x0 - offset + 1, y: top - 4))
            path.addLine(to: CGPoint(x: b.x0 - offset + 1, y: top - 10))
            path.addLine(to: CGPoint(x: b.x1 - offset - 1, y: top - 10))
            path.addLine(to: CGPoint(x: b.x1 - offset - 1, y: top - 4))
            context.stroke(path, with: .color(.heather), lineWidth: 2)
            let lx = min(max((b.x0 + b.x1) / 2 - offset, 60), size.width - 60)
            context.draw(Text(b.label).font(Font.Heather.caption).foregroundStyle(Color.heather), at: CGPoint(x: lx, y: top - 19))
        }
    }

    /// The whole chart at true aspect: worked rows solid, the current row a Heather line, rows ahead faint (decision 1).
    private func drawWhole(context: inout GraphicsContext, size: CGSize) {
        let rect = BandLayout.wholeChartRect(chart: chart, in: size)
        let cw = rect.width / CGFloat(chart.width)
        let ch = rect.height / CGFloat(chart.height)
        let currentGridRow = sequence.pass(at: cursor.row)?.gridRow
        let worked = Set((1..<cursor.row).compactMap { sequence.pass(at: $0)?.gridRow })
        for gy in 0..<chart.height {
            let opacity: Double = worked.contains(gy) || gy == currentGridRow ? 1 : 0.28
            for run in chart.runsByRow[gy] {
                let r = CGRect(x: rect.minX + CGFloat(run.x0) * cw, y: rect.minY + CGFloat(gy) * ch, width: CGFloat(run.count) * cw + 0.3, height: ch + 0.3)
                context.fill(Path(r), with: .color(fill(run.colorIndex).opacity(opacity)))
            }
        }
        if let gy = currentGridRow {
            context.fill(Path(CGRect(x: rect.minX, y: rect.minY + CGFloat(gy) * ch - 1, width: rect.width, height: 2)), with: .color(.heather))
        }
    }
}
```

One note for the implementer on row direction: `rows` charts count passes from the bottom, so the row below the current one is `gridRow + 1`; the expression in `drawBand` derives the sign from the next pass so a `start: top` chart draws the right way up too.

- [ ] **Step 4: Record the snapshots, then compare**

Run from `ios/`: `TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record mise run test`, open `ios/Tests/__Snapshots__/band-*.png` and check against the spec: the fill's ring ends at three quarters with ticks 10 … 110 beneath, the braid bracket is labelled, the repeat label stays on screen, the turn shows the bar and arc at the right edge, the whole chart is solid below row 42 and faint above. Then `mise run test` must pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/ChartBand.swift ios/Tests/ChartBandTests.swift ios/Tests/__Snapshots__/band-*.png
git commit -m "work: ChartBand draws the row at stitch scale and the whole chart (#59)"
```

---

### Task 10: The panel view, the rebuilt screen, and the wiring

**Files:**
- Create: `ios/Graphghan/Work/WorkPanel.swift`, `ios/Graphghan/Work/RunListSheet.swift`
- Modify: `ios/Graphghan/Work/WorkScreen.swift` (rewrite), `ios/Graphghan/Work/WorkView.swift:64-72` (the `WorkScreen` call and the new callbacks)
- Delete: `ios/Graphghan/Work/DoneField.swift`, `ios/Graphghan/Work/RowStripView.swift`, `ios/Graphghan/Work/RunChipsView.swift`, `ios/Tests/__Snapshots__/work-*.png`
- Test: `ios/Tests/WorkScreenTests.swift` (rewrite)

**Interfaces:**
- Consumes: `WorkPanelContent` (Task 7), `ChartBand` (Task 9), `CountStep`, `Project.step`, `ProjectService.setCountStep` (Tasks 4, 6).
- Produces:
  ```swift
  struct WorkScreen: View {
      let chart: Chart; let sequence: WorkSequence; let cursor: Cursor; let step: CountStep
      let onDone: () -> Void; let onBack: () -> Void; let onClose: () -> Void; let onJump: () -> Void
      let onJumpWithinRow: (_ run: Int, _ stitch: Int) -> Void
      let onSetStep: (CountStep) -> Void
      static func actionLabel(chart:sequence:cursor:step:) -> String   // for tests; delegates to WorkPanelContent
  }
  ```
  Tasks 11 and 13 consume nothing new; Task 14 reads the snapshot names.

- [ ] **Step 1: Rewrite the screen tests**

Replace `WorkScreenTests.swift`:

```swift
import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct WorkScreenTests {
    static let chart = try! Chart.load(TestFixtures.data("craigh-na-dun.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static let phone = CGSize(width: 390, height: 844)
    static let turn = Cursor(row: 42, run: seq.pass(at: 42)!.runs.count)
    static let end = Cursor(row: seq.passes.count, run: seq.passes.last!.runs.count)

    private func screen(_ cursor: Cursor, step: CountStep = .ten) -> some View {
        WorkScreen(chart: Self.chart, sequence: Self.seq, cursor: cursor, step: step,
                   onDone: {}, onBack: {}, onClose: {}, onJump: {}, onJumpWithinRow: { _, _ in }, onSetStep: { _ in })
    }

    @Test func plainRun() throws { #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 8)), named: "work-run", size: Self.phone)) }
    @Test func braid() throws { #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 2)), named: "work-braid", size: Self.phone)) }
    @Test func repeatBand() throws { #expect(try Snapshots.assert(screen(Cursor(row: 179, run: 8)), named: "work-repeat", size: Self.phone)) }
    @Test func fill() throws { #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 10, stitch: 40)), named: "work-fill", size: Self.phone)) }
    @Test func turn() throws { #expect(try Snapshots.assert(screen(Self.turn), named: "work-turn", size: Self.phone)) }
    @Test func finished() throws { #expect(try Snapshots.assert(screen(Self.end), named: "work-finished", size: Self.phone)) }

    /// At the largest accessibility size the count may cap and the landmark pill may drop; nothing clips.
    @Test func accessibilitySize() throws {
        let view = screen(Cursor(row: 42, run: 10, stitch: 40)).environment(\.dynamicTypeSize, .accessibility5)
        #expect(try Snapshots.assert(view, named: "work-fill-ax5", size: Self.phone))
    }

    @Test func actionLabelsSpellOutTheStitch() {
        let run = Self.seq.pass(at: 42)!.runs[8]
        let name = Self.chart.palette[Self.chart.colorIndex(of: run.code)!].name
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 42, run: 8), step: .ten) == "Done with \(run.count) single crochet in \(name)")
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Cursor(row: 42, run: 10, stitch: 40), step: .ten) == "40 of 117 single crochet in Cream, next ten")
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Self.turn, step: .ten).hasPrefix("Ch 1 in Gold, turn"))
        #expect(WorkScreen.actionLabel(chart: Self.chart, sequence: Self.seq, cursor: Self.end, step: .ten) == "Close")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run from `ios/`: `mise run test`
Expected: compile errors on the new `WorkScreen` signature.

- [ ] **Step 3: The panel view**

`ios/Graphghan/Work/WorkPanel.swift`:

```swift
import SwiftUI
import GraphghanCore

/// The current step on a card in its yarn colour (spec §5.2). Everything it shows comes from
/// `WorkPanelContent`; this file only lays it out.
struct WorkPanel: View {
    let content: WorkPanelContent

    var body: some View {
        VStack(spacing: 6) {
            switch content.kind {
            case .turn, .finished:
                Text(content.title ?? "").font(Font.Heather.title).multilineTextAlignment(.center)
                if let subtitle = content.subtitle { Text(subtitle).font(content.kind == .turn ? Font.Heather.heading : Font.Heather.body).multilineTextAlignment(.center) }
                if let detail = content.detail { Text(detail).font(Font.Heather.label).opacity(0.75) }
            default:
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(content.count ?? 0)").font(Font.Heather.count).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    if let total = content.total { Text("of \(total)").font(Font.Heather.heading).monospacedDigit() }
                    if let badge = content.badge {
                        Text(badge).font(Font.Heather.label).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 4)
                            .overlay(Capsule().strokeBorder(YarnSurface.foreground(content.hex).opacity(0.6), lineWidth: 1.5))
                    }
                }
                Text("\(content.code ?? "") · \(content.name ?? "")").font(Font.Heather.heading).lineLimit(1).minimumScaleFactor(0.7)
                if let label = content.segmentLabel {
                    Text(label.uppercased()).font(Font.Heather.caption).opacity(0.7).tracking(0.6)
                }
                if !content.parts.isEmpty { sequenceLine }
                if let landmark = content.landmark {
                    Text(landmark).font(Font.Heather.label).lineLimit(2).multilineTextAlignment(.center)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let onDeck = content.onDeck { Text(onDeck).font(Font.Heather.label).opacity(0.75).lineLimit(2).multilineTextAlignment(.center) }
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .yarnSurface(content.hex, radius: 18)
    }

    private var sequenceLine: some View {
        HStack(spacing: 8) {
            ForEach(Array(content.parts.enumerated()), id: \.offset) { _, part in
                Text(part.text).font(Font.Heather.label)
                    .opacity(part.state == .done ? 0.45 : 1)
                    .overlay(alignment: .bottom) {
                        if part.state == .current { Rectangle().fill(Color.heather).frame(height: 3).offset(y: 4) }
                    }
            }
            if let reps = content.repetitions { Text("×\(reps)").font(Font.Heather.label).opacity(0.7) }
        }
        .lineLimit(2)
    }
}
```

`Color.black.opacity(0.08)` is a `Color` literal on a shape fill, not a `foregroundStyle`, so `DesignRulesTests` accepts it (the rule flags `foregroundStyle(.black)` only). If the guard still flags it, use `Color.ink.opacity(0.08)` instead.

- [ ] **Step 4: The run list sheet**

`ios/Graphghan/Work/RunListSheet.swift`:

```swift
import SwiftUI
import GraphghanCore

/// Every run of the current row as a list, for the "Jump within row" VoiceOver action and as the
/// fallback for a long-press that misses (spec §6).
struct RunListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chart: Chart
    let pass: Pass
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(Array(pass.runs.enumerated()), id: \.offset) { i, run in
                let entry = chart.palette[chart.colorIndex(of: run.code) ?? 0]
                Button { onSelect(i); dismiss() } label: {
                    HStack {
                        Chip(text: "\(run.count) \(run.code)", hex: entry.hex, state: i < current ? .done : i == current ? .current : .upcoming)
                        Text(entry.name).font(Font.Heather.body).foregroundStyle(Color.ink)
                        Spacer()
                    }
                }
                .accessibilityLabel("\(run.count) \(entry.name)\(i == current ? ", current" : i < current ? ", done" : "")")
            }
            .scrollContentBackground(.hidden)
            .background(Color.ground.weave().ignoresSafeArea())
            .navigationTitle(pass.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 5: The screen**

Replace `ios/Graphghan/Work/WorkScreen.swift`:

```swift
import SwiftUI
import GraphghanCore

/// The Work screen without the model (spec §5): header, the panel in the run's colour, the chart
/// band at stitch scale, and the bar. `WorkView` owns state, persistence and haptics and feeds this.
struct WorkScreen: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    let step: CountStep
    let onDone: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let onJump: () -> Void
    let onJumpWithinRow: (_ run: Int, _ stitch: Int) -> Void
    let onSetStep: (CountStep) -> Void

    @State private var mode: ChartBand.Mode = .band
    @State private var showRunList = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var finished: Bool { WorkEngine.isFinished(cursor, in: sequence) }
    private var content: WorkPanelContent { WorkPanelContent.make(chart: chart, sequence: sequence, cursor: cursor, step: step) }
    private var canGoBack: Bool { WorkEngine.apply(.back, to: cursor, in: sequence, step: step) != nil }

    static func actionLabel(chart: Chart, sequence: WorkSequence, cursor: Cursor, step: CountStep) -> String {
        WorkPanelContent.make(chart: chart, sequence: sequence, cursor: cursor, step: step).actionLabel
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 14) {
                    VStack(spacing: 14) { header; panel; Spacer(minLength: 0); bar }.frame(maxWidth: .infinity)
                    band.frame(maxWidth: .infinity)
                }
                .padding(.bottom, 16)
            } else {
                VStack(spacing: 14) { header; panel; band; bar }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .background(Color.ground.weave().ignoresSafeArea())
        .sheet(isPresented: $showRunList) {
            if let pass = sequence.pass(at: cursor.row) {
                RunListSheet(chart: chart, pass: pass, current: cursor.run) { onJumpWithinRow($0, 0) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink2)
            .accessibilityLabel("Close")
            Spacer()
            VStack(spacing: 4) {
                if let pass = sequence.pass(at: cursor.row) {
                    (Text("\(pass.label) ") + Text("of").fontWeight(.medium).foregroundStyle(Color.ink2) + Text(" \(sequence.passes.count)"))
                        .font(Font.Heather.rowNumber).monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .onTapGesture { withAnimation { mode = mode == .band ? .whole : .band } }
                        .onLongPressGesture(perform: onJump)
                        .accessibilityHint("Long press to jump to a row")
                        .accessibilityAction(named: "Jump to row", onJump)
                    Text(finished ? "Every row worked" : sideText(pass)).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                }
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// The panel is the spoken element: one label, the on-deck line as its value, the actions as rotor actions (spec §6).
    private var panel: some View {
        let c = content
        return WorkPanel(content: c)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture(perform: finished ? onClose : onDone)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(c.actionLabel)
            .accessibilityValue(c.onDeck ?? "")
            .accessibilityAction { finished ? onClose() : onDone() }
            .accessibilityAction(named: "Back", onBack)
            .accessibilityAction(named: "Jump to row", onJump)
            .accessibilityAction(named: "Jump within row") { showRunList = true }
            .accessibilityAction(named: "Choose counting step") { onSetStep(step.next) }
    }

    private var band: some View {
        ChartBand(chart: chart, sequence: sequence, cursor: cursor, segmentLabel: content.segmentLabel, mode: mode,
                  onAdvance: finished ? onClose : onDone, onJump: onJumpWithinRow,
                  onToggleMode: { withAnimation { mode = mode == .band ? .whole : .band } })
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
    }

    private var bar: some View {
        let c = content
        let nextHex = sequence.pass(at: cursor.row + 1)?.runs.first.map { chart.palette[chart.colorIndex(of: $0.code) ?? 0].hex }
        let doneHex = c.kind == .turn ? (nextHex ?? WorkPanelContent.creamHex) : c.hex
        let prevHex = WorkEngine.apply(.back, to: cursor, in: sequence, step: step).flatMap { s in
            sequence.pass(at: s.cursor.row).flatMap { s.cursor.run < $0.runs.count ? $0.runs[s.cursor.run] : nil }
        }.map { chart.palette[chart.colorIndex(of: $0.code) ?? 0].hex } ?? YarnSurface.creamHex
        return HStack(spacing: 12) {
            if !finished {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 22, weight: .semibold))
                        Text("Back").font(Font.Heather.label)
                    }
                    .frame(width: 110, height: 72)
                    .foregroundStyle(YarnSurface.foreground(prevHex).opacity(canGoBack ? 1 : 0.4))
                    .contentShape(Capsule())
                    .capsuleGlass(prevHex)
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .accessibilityLabel("Back")
            }
            Button(action: finished ? onClose : onDone) {
                Group {
                    if c.capsule == "checkmark" { Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)) }
                    else { Text(c.capsule).font(Font.Heather.done).minimumScaleFactor(0.6).lineLimit(1) }
                }
                .frame(maxWidth: .infinity).frame(height: 72)
                .foregroundStyle(YarnSurface.foreground(doneHex))
                .contentShape(Capsule())
                .capsuleGlass(doneHex)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(c.actionLabel)
            .contextMenu {
                if !finished, c.kind == .fill || c.kind == .run {
                    ForEach(CountStep.allCases, id: \.rawValue) { s in
                        Button { onSetStep(s) } label: {
                            if s == step { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 44)
    }

    private func sideText(_ pass: Pass) -> String {
        let dir = pass.direction.map { $0 == .ltr ? "read left to right" : "read right to left" } ?? "read direction not specified"
        guard let side = pass.side else { return dir }
        return "\(side == .ws ? "Wrong side" : "Right side") · \(dir)"
    }
}

extension CountStep {
    var title: String {
        switch self {
        case .one: "Count every stitch"
        case .five: "Count by 5"
        case .ten: "Count by 10"
        case .twenty: "Count by 20"
        case .wholeRun: "One tap per run"
        }
    }
    /// The next step in the picker's order, for the VoiceOver action that cycles it.
    var next: CountStep {
        let all = CountStep.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

private extension View {
    /// Clear Liquid Glass over the yarn colour on iOS 26; a thin material over it before that.
    @ViewBuilder func capsuleGlass(_ hex: String) -> some View {
        if #available(iOS 26, *) {
            background(YarnSurface.fill(hex).opacity(0.85), in: Capsule())
                .glassEffect(.clear.interactive(), in: Capsule())
        } else {
            background(YarnSurface.fill(hex), in: Capsule())
                .overlay(Capsule().strokeBorder(YarnSurface.hairline, lineWidth: 1))
        }
    }
}
```

At the very start there is no previous run, so Back sits on cream at 40%, which is what "nothing to return to" looks like. No raw hex appears in `Work/`; both cream references go through `YarnSurface.creamHex` from Task 7.

- [ ] **Step 6: Wire `WorkView`**

In `WorkView.swift`, the `WorkScreen(...)` call becomes:

```swift
        WorkScreen(chart: chart, sequence: sequence, cursor: cursor, step: project.step,
                   onDone: { perform(.advance, sequence: sequence) },
                   onBack: { perform(.back, sequence: sequence) },
                   onClose: { dismiss() },
                   onJump: { showJump = true },
                   onJumpWithinRow: { run, stitch in perform(.jump(row: cursor.row, run: run, stitch: stitch), sequence: sequence) },
                   onSetStep: { step in try? model.projects.setCountStep(step, for: project) })
```

Delete `DoneField.swift`, `RowStripView.swift`, `RunChipsView.swift` and the old `work-mid-row.png`, `work-mid-row-ax5.png`, `work-last-in-row.png` snapshots. Search the app target for `RowStripView`, `WorkField`, `TrackStop` and `RunChipsView` (`grep -rn` under `ios/Graphghan ios/Tests`) and remove every remaining reference; `ProjectDetailView` does not use them.

- [ ] **Step 7: Record, review, compare**

Run from `ios/`: `TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record mise run test`, then open the seven `work-*.png` files and check each against spec §5.2 and §5.3 (the panel's content per state, the band's position rule, the bar's labels "checkmark", "+10", "Turned", "Close"). Then `mise run test` must pass, including `DesignRulesTests`.

- [ ] **Step 8: Commit**

```bash
git add -A ios/Graphghan/Work ios/Shared/YarnSurface.swift ios/Tests
git commit -m "work: the field is the chart at stitch scale; panel, band and bar replace the colour columns (#59)"
```

---

### Task 11: Haptics for the fill step and the turn

**Files:**
- Modify: `ios/Graphghan/Work/WorkFeedback.swift`, `ios/Graphghan/UI/Haptics.swift`
- Test: `ios/Tests/WorkFeedbackTests.swift`

**Interfaces:**
- Consumes: `WorkStep.atBoundary`, `Cursor.stitch`, `WorkSequence.hasBoundaryStep(after:)`.
- Produces: `WorkFeedback.step`.

- [ ] **Step 1: Rewrite the tests**

Replace `WorkFeedbackTests.swift`:

```swift
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct WorkFeedbackTests {
    // two-letter-codes (rows): Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3
    static let seq = try! WorkSequence(chart: Chart.load(TestFixtures.data("two-letter-codes.chart.json")))
    static let craigh = try! WorkSequence(chart: Chart.load(TestFixtures.data("craigh-na-dun.chart.json")))

    @Test func runWithinRow() {
        let step = WorkEngine.apply(.advance, to: .start, in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: step, in: Self.seq) == .run)
    }

    @Test func theTurnIsTheRowHaptic() {
        let toBoundary = WorkEngine.apply(.advance, to: Cursor(row: 1, run: 2), in: Self.seq)!
        #expect(toBoundary.atBoundary && WorkFeedbackRule.feedback(for: toBoundary, in: Self.seq) == .row)
        // the tap after the turn is an ordinary run (the row haptic already fired at the turn)
        let turned = WorkEngine.apply(.advance, to: Cursor(row: 1, run: 3), in: Self.seq)!
        #expect(turned.startedNewRow && WorkFeedbackRule.feedback(for: turned, in: Self.seq) == .run)
        let toY = WorkEngine.apply(.advance, to: Cursor(row: 2, run: 1), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: toY, in: Self.seq) == .newColor)
    }

    @Test func roundsKeepTheRowHapticOnTheNewRow() throws {
        let rounds = try WorkSequence(chart: Chart.load(TestFixtures.data("minimal-rounds.chart.json")))
        let last = rounds.passes[0].runs.count - 1
        let step = WorkEngine.apply(.advance, to: Cursor(row: 1, run: last), in: rounds)!
        #expect(step.startedNewRow && WorkFeedbackRule.feedback(for: step, in: rounds) == .row)
    }

    @Test func aFillStepIsLighterThanARun() {
        let step = WorkEngine.apply(.advance, to: Cursor(row: 42, run: 10), in: Self.craigh, step: .ten)!
        #expect(step.cursor.stitch == 10 && WorkFeedbackRule.feedback(for: step, in: Self.craigh) == .step)
        let completes = WorkEngine.apply(.advance, to: Cursor(row: 42, run: 10, stitch: 110), in: Self.craigh, step: .ten)!
        #expect(WorkFeedbackRule.feedback(for: completes, in: Self.craigh) == .run)
    }

    @Test func backAndFinished() {
        let back = WorkEngine.apply(.back, to: Cursor(row: 2, run: 1), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: back, in: Self.seq) == nil)
        let done = WorkEngine.apply(.advance, to: Cursor(row: 2, run: 2), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: done, in: Self.seq) == .finished)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run from `ios/`: `mise run test`
Expected: `.step` not a member; `theTurnIsTheRowHaptic` fails.

- [ ] **Step 3: Implement**

`WorkFeedback.swift`:

```swift
import GraphghanCore

enum WorkFeedback: Equatable {
    case step, run, row, newColor, finished
}

/// Which haptic a step deserves. Pure so it is testable; Haptics plays it.
enum WorkFeedbackRule {
    static func feedback(for step: WorkStep, in seq: WorkSequence) -> WorkFeedback? {
        if step.kind == .back { return nil }
        if step.finished { return .finished }
        if step.atBoundary { return .row }
        if step.cursor.stitch > 0 { return .step }
        guard let pass = seq.pass(at: step.cursor.row), step.cursor.run < pass.runs.count else { return nil }
        let code = pass.runs[step.cursor.run].code
        let previousRowCodes = Set(seq.pass(at: step.cursor.row - 1)?.runs.map(\.code) ?? [])
        let introducesColor = seq.pass(at: step.cursor.row - 1) != nil && !previousRowCodes.contains(code)
        if introducesColor { return .newColor }
        // the row haptic already fired at the turn; only rows without a boundary step get it here
        if step.startedNewRow, !seq.hasBoundaryStep(after: step.cursor.row - 1) { return .row }
        return .run
    }
}
```

`Haptics.play`: add `case .step: light.impactOccurred(intensity: 0.6)` before `.run`.

- [ ] **Step 4: Run to verify they pass**

Run from `ios/`: `mise run test`

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Work/WorkFeedback.swift ios/Graphghan/UI/Haptics.swift ios/Tests/WorkFeedbackTests.swift
git commit -m "work: a lighter tick for a fill step; the row haptic fires at the turn (#59)"
```

---

## Part C: the Live Activity, the docs, the device check

### Task 12: Live Activity views show the count and the turn

**Files:**
- Modify: `ios/Shared/WorkActivityViews.swift` (`RunPanel`, `RunButtons`, `WorkCompactLeadingView`, `WorkMinimalView`)
- Test: `ios/Tests/WorkActivityViewsTests.swift`

**Interfaces:**
- Consumes: `WorkActivityState.stitch`, `.counting`, `.atBoundary` (Task 5); `WorkActivityInfo.turningChain`.
- Produces: `RunPanel.nextText(info:state:)` now returns the turn sentence at the boundary; `RunPanel.countText(state:)`.

- [ ] **Step 1: Write the failing tests**

Append to `WorkActivityViewsTests.swift`:

```swift
    static let fill = LiveActivityState.make(cursor: Cursor(row: 42, run: 10, stitch: 40), sequence: seq)!
    static let turn = LiveActivityState.make(cursor: Cursor(row: 42, run: seq.pass(at: 42)!.runs.count), sequence: seq)!

    @Test func countTextCountsUpInsideAFill() {
        #expect(RunPanel.countText(state: Self.fill) == "40 of 117")
        #expect(RunPanel.countText(state: Self.midway) == "\(Self.midway.currentCount!)")
    }

    @Test func boundaryTextNamesTheTurnAndTheNextRow() {
        #expect(RunPanel.nextText(info: Self.info, state: Self.turn) == "ch 1, turn · Row 43 starts in Gold")
        let plain = WorkActivityInfo(projectID: Self.info.projectID, title: Self.info.title, totalRows: Self.info.totalRows, totalCells: Self.info.totalCells, palette: Self.info.palette)
        #expect(RunPanel.nextText(info: plain, state: Self.turn) == "turn · Row 43 starts in Gold")
    }

    @Test func lockScreenFillAndTurn() throws {
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.fill).background(Color.activityCard).environment(\.colorScheme, .dark), named: "lock-fill", size: CGSize(width: 360, height: 170)))
        #expect(try Snapshots.assert(WorkLockScreenView(info: Self.info, state: Self.turn).background(Color.activityCard).environment(\.colorScheme, .dark), named: "lock-turn", size: CGSize(width: 360, height: 170)))
    }
```

Update `lastInRowTextNamesTheChain`: the state built from `Cursor(row: 1, run: 0)` is the last run of row 1, which now reads `"last in row"` only when the sequence has no boundary step; for Craigh na Dun (rows) the on-panel text for a last run is the empty string and the turn text moves to the boundary state. Replace its first three expectations with `#expect(RunPanel.nextText(info: Self.info, state: Self.lastInRow) == "")` and keep the `.hasPrefix("then ")` and the `final` (last pass, no boundary) `"last in row"` checks.

- [ ] **Step 2: Run to verify they fail**

Run from `ios/`: `mise run test`
Expected: `countText` not found; `boundaryTextNamesTheTurnAndTheNextRow` fails.

- [ ] **Step 3: Implement**

In `RunPanel`, the count `Text("\(count)")` becomes `Text(Self.countText(state: state))`, and the body's `if let code = state.currentCode, let count = state.currentCount` becomes `if let code = state.currentCode ?? (state.atBoundary ? state.nextCode : nil), let count = state.currentCount ?? state.nextCount`, so the boundary paints the next row's colour. Add:

```swift
    static func countText(state: WorkActivityState) -> String {
        guard let count = state.currentCount else { return "" }
        return state.counting ? "\(state.stitch) of \(count)" : "\(count)"
    }

    /// The trailing line of the panel: the next run, the turn, or nothing.
    static func nextText(info: WorkActivityInfo, state: WorkActivityState) -> String {
        if state.atBoundary {
            let chain = info.turningChain.map { $0 > 0 ? "ch \($0), turn" : "turn" } ?? "turn"
            let next = state.nextCode.map { info.swatch(for: $0)?.name ?? $0 }
            return [chain, next.map { "Row \(state.row + 1) starts in \($0)" }].compactMap { $0 }.joined(separator: " · ")
        }
        if let code = state.nextCode, let count = state.nextCount { return "then \(count) \(info.swatch(for: code)?.name ?? code)" }
        guard state.isLastInRow else { return "" }
        return state.row < state.rowCount ? "" : "last in row"
    }
```

At the boundary the panel shows no count: in the `HStack`, wrap the count and code texts in `if !state.atBoundary { … }` and let `nextText` fill the panel. In `RunButtons`, the Done label becomes `Text(state.atBoundary ? "Turned" : "Done")` and `doneHex` at the boundary uses `state.nextCode`. In `WorkCompactLeadingView` and `WorkMinimalView`, `RunSwatch(... count: state.counting ? state.stitch : count ...)`.

- [ ] **Step 4: Record the two new snapshots, then compare**

Run from `ios/`: `TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record mise run test`, check `lock-fill.png` reads "40 of 117" and `lock-turn.png` shows the turn line and "Turned"; then `mise run test`.

- [ ] **Step 5: Commit**

```bash
git add ios/Shared/WorkActivityViews.swift ios/Tests/WorkActivityViewsTests.swift ios/Tests/__Snapshots__/lock-*.png
git commit -m "activity: the lock screen counts inside a fill and shows the turn (#59)"
```

---

### Task 13: Docs, the superseded design-language section, and the QA checklist

**Files:**
- Modify: `docs/chart-format.md` (§Technique and passes, §Progress document), `docs/superpowers/specs/2026-09-11-ios-design-language-design.md` §6.1 and §6.8, `ios/docs/qa.md` (Work screen and Looks right), `fixtures/chart-format/README.md`
- Test: `uv run pytest -q` (docs are not tested; run it anyway for the fixture README's neighbours)

- [ ] **Step 1: `docs/chart-format.md`**

In §Technique and passes, after the sentence defining the cursor, add:

> A cursor may carry `stitch`, the number of cells of run `run` already worked, `0 ≤ stitch < count`; absent means 0. `run` equal to the pass's run count is the boundary position: every run worked and the end-of-pass action (the turn) not yet taken, with `stitch` 0. A completed run is the next run at stitch 0, never `stitch == count`.

In §Progress document, change the example to `"cursor": { "row": 42, "run": 3, "stitch": 10 }`, add `stitch` to the event description ("every event records the cursor after the action; `stitch` is optional on both and absent means 0; writers omit it when 0"), and change the `cells_done` definition to "cells in every earlier pass + runs before `run` in the current pass + `stitch`". Add the sentence "The `progress-stitch` fixture pins an offset inside a run, a boundary position, and a jump into a run."

- [ ] **Step 2: The design-language spec**

Replace the body of §6.1 with:

> Superseded on 2026-09-16 by `2026-09-16-work-screen-field-design.md` §5: the field is the chart at stitch scale with a panel above it and a bar below. The tokens and the header are unchanged.

In §6.8, after the run panel sentence, add: "Inside a fill the count reads `40 of 130`; at the turn the panel carries the turn line ('ch 1, turn · Row 43 starts in Gold') in the next row's colour and Done reads 'Turned'."

- [ ] **Step 3: `ios/docs/qa.md`**

Replace the Work screen block with:

```markdown
## Work screen
- [ ] Open a project, tap Work: the panel shows the run in its colour, the band shows the row at stitch scale with the row below underneath, the bar shows Back and a checkmark.
- [ ] Tap the panel, the band, and the capsule: each advances exactly one run. Swipe right: back.
- [ ] Row 42 of Craigh na Dun: the first eight runs show the braid sequence; run 11 (117 Cream) shows "0 of 117", the capsule reads "+10", each tap adds ten and the ring fills in; the ticks under the row read 10 … 110.
- [ ] Long-press the capsule: the step picker; choose "One tap per run": the capsule is a checkmark and one tap finishes the fill.
- [ ] Last run of a row, tap: the panel reads "Ch 1 in Gold, turn"; the capsule reads "Turned"; tap again: row 43.
- [ ] Long-press a stitch in the current row: the cursor jumps there.
- [ ] Pinch in on the band, or tap the row number: the whole chart, worked rows solid, row 42 a Heather line. Pinch out or tap again: the band.
- [ ] Long-press the row number and jump to row 40.
- [ ] Rotate mid-row; the band takes the trailing column and Back stays reachable.
- [ ] VoiceOver on the panel: it reads "Done with 7 single crochet in Cream", the value is "then 11 Purple", and the rotor offers Back, Jump to row, Jump within row, Choose counting step.
```

In "Looks right", replace the two Work bullets with one: "Work: stone ground, the panel in the yarn colour, the band at 8 pt a stitch with the current run ringed in heather, capsules at the bottom; nothing says 'Done'."

- [ ] **Step 4: `fixtures/chart-format/README.md`**

Add after the `tiles-gauge` paragraph:

> `progress-stitch` pins the optional `stitch` on the progress cursor and events (#59): an offset inside a run, the boundary position after a row, a Back onto the boundary, and a jump into a run. A reader that ignores `stitch` still validates the document; one that reads it reproduces the expected summary.

- [ ] **Step 5: Commit**

```bash
git add docs/chart-format.md docs/superpowers/specs/2026-09-11-ios-design-language-design.md ios/docs/qa.md fixtures/chart-format/README.md
git commit -m "docs: stitch on the progress cursor; Work screen §6.1 superseded; QA for the band (#59)"
```

---

### Task 14: Device check and the PR

**Files:** none new.

- [ ] **Step 1: Full test pass**

From the repo root: `uv run pytest -q`. From `ios/`: `mise run core-test`, `mise run test`, `mise run script-test`. All green.

- [ ] **Step 2: Device build and the QA list**

Build to a device per `ios/README.md` ("Device build") and walk `ios/docs/qa.md` §Work screen and §Live Activity. This is the check #67 makes necessary: the simulator snapshots are review evidence, not proof. Record any mismatch between the snapshots and the device as a comment on #67.

- [ ] **Step 3: Open the PR**

```bash
git push -u origin tylervick/work-screen-field
gh pr create --title "Work on the chart: the field at stitch scale, segments, counting by tens, the turn as a step" --body "$(cat <<'EOF'
Implements docs/superpowers/specs/2026-09-16-work-screen-field-design.md.

Closes #59, closes #20, closes #11, closes #22.
Narrows #26, #23, #45 (comments on each say what remains).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Then comment on #26, #23 and #45 with the "what this spec takes" line from spec §10 so each stays open for its remainder.

---

## Self-review notes

- Spec §4.1 (segments) → Task 1. §4.2 (cursor) → Task 2. §4.3 (engine) → Task 4. §4.4 (boundary step) → Tasks 2 and 4. §4.5 (events and the document) → Tasks 2, 3, 6. §4.6 (fixtures and parity) → Tasks 3 and 4; the `segments.expected.json` fixture the spec names is pinned as literals in `SegmentsTests` until #70 gives Python the rule, because fixtures are generated by `generate.py` and there is no Python implementation to generate it from. §5.1–5.4 (screen) → Tasks 7–10. §5.5 (Live Activity and intents) → Tasks 5, 12; the intents need no change because `ProjectService.apply` reads the project's step. §6 (accessibility) → Task 10's panel modifiers and `RunListSheet`. §7 (design language and snapshots) → Tasks 9, 10, 12, 13. §8 (compatibility) → Tasks 2, 3, 6. §9 (testing) → every task. §10 rulings → Task 14's PR body.
- Names used across tasks: `Segments.segment(containing:in:)`, `Segments.landmark(for:direction:below:)`, `Cursor(row:run:stitch:)`, `WorkSequence.hasBoundaryStep(after:)`, `CountStep` with `.default`, `WorkEngine.apply(_:to:in:step:)`, `WorkEngine.isCounting(_:in:)`, `WorkEngine.stride(_:for:)`, `WorkStep.atBoundary`, `WorkActivityState.stitch/counting/atBoundary`, `Project.step`, `ProjectService.setCountStep(_:for:)`, `WorkPanelContent.make(chart:sequence:cursor:step:)`, `BandLayout(width:height:chart:pass:cursor:segmentLabel:)`, `ChartBand(chart:sequence:cursor:segmentLabel:mode:onAdvance:onJump:onToggleMode:)`, `WorkScreen(... step: onJumpWithinRow: onSetStep:)`, `RunPanel.countText(state:)`, `WorkFeedback.step`.

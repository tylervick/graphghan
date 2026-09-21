# Phone PDF import, PR 2: written rows on the phone — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A PDF with written rows and no chart the app can read becomes a chart on a device with Apple Intelligence, read row by row by `ProseReaderKit` behind a progress sheet that can be cancelled, validated by the width check, and refused with the right sentence everywhere else.

**Architecture:** `ProseReaderKit` becomes an app dependency (iOS platform, cancellation, a row total for progress) behind a `RowReading` protocol so the app's tests run without a model. `GraphghanCore` gains `RowsChart`, the port of the Python rows-only assembler (`written_to_grid`, the row-total and row-number checks, placeholder hexes). `PDFImporter` gains the §4.3 path after the own-PDF one: detect row heads, gate on the model, read with progress, assemble, validate, and the same save as PR 1; and the §4.4 and §7 sentences. The sheet gains a "reading written rows" state with a row counter and Cancel.

**Tech Stack:** Swift 6, SwiftUI, FoundationModels (iOS 26, gated at run time), PDFKit, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-20-phone-pdf-import-design.md` (§4.3, §4.4, §5.1–§5.4, §6.1, §6.3, §7, §8 item 2, §9)

## Global Constraints

- Deployment target stays iOS 17.0; every FoundationModels symbol stays behind `@available(iOS 26.0, *)`, and the `#available` guard lives in one place, `PDFImporter` (spec §7).
- The reader is used unchanged in what it does (spec §2): this PR adds cancellation and a row total to it, nothing to its grammar.
- Nothing is written unless the chart validates through `Chart.load`; a read writes nothing; Cancel writes nothing (spec §2, §5.4).
- Sentences are the fixed ones in spec §5.4, plus the §4.3 preface: "This pattern has no chart the app can read, so it is reading the N written rows. About M minutes."
- The model is never called from a test: the app's tests use a `RowReading` stub; the model path is measured by hand on a device (spec §8 item 2, §9).
- `mise run check` before every commit; Blink before the PR. Branch: `tylervick/phone-import-2`, stacked on `tylervick/phone-import` (PR #162); retarget to `main` when that merges.

---

### Task 1: `ProseReaderKit` on iOS, cancellable, with a row total

**Files:**
- Modify: `ios/Packages/ProseReader/Package.swift` (platforms)
- Modify: `ios/Packages/ProseReader/Sources/ProseReaderKit/ProseReader.swift` (`ReaderProgress`, `read`)
- Create: `ios/Packages/ProseReader/Sources/ProseReaderKit/RowReading.swift`
- Modify: `ios/Packages/ProseReader/Tests/ProseReaderKitTests/RowTextTests.swift` (one test on `rowCount`)

**Interfaces:**
- Produces: `public protocol RowReading: Sendable { func read(pages: [String], progress: (@Sendable (ReaderProgress) -> Void)?) async -> ProseDocument }` with `ProseReader: RowReading` (iOS 26 / macOS 26); `ReaderProgress` gains `public let rowsTotal: Int`; `public static func rowCount(in pages: [String]) -> Int` on `RowText`; `read` returns early with what it has when `Task.isCancelled`, marking `doc.uncertain` with "cancelled after N rows".

- [x] **Step 1: Write the failing test**

Append to `RowTextTests.swift`:

```swift
@Test func theRowCountIsTheNumberOfBlocksAcrossPages() {
    let pages = ["Key\nA red\nRow 1: 3 A, 4 B\nRow 2: 7 A\n", "Row 3: 7 B\nCraigh Page 2\n", "Nothing here"]
    #expect(RowText.rowCount(in: pages) == 3)
    #expect(RowText.rowCount(in: []) == 0)
}
```

- [x] **Step 2: Run to see it fail**

Run: `cd ios/Packages/ProseReader && swift test --filter theRowCountIs 2>&1 | tail -3`
Expected: compile error, `rowCount` undefined.

- [x] **Step 3: Platforms, protocol, progress total, cancellation**

`Package.swift`: `platforms: [.macOS("26.0"), .iOS(.v17)]`. Everything that touches FoundationModels is already `@available(macOS 26.0, iOS 26.0, *)`; `RowText` and `ProseDocument` are not, and compile for iOS 17.

`RowReading.swift`:

```swift
import Foundation

/// What the app asks of a written-row reader (phone import spec §9): the same call `ProseReader`
/// answers, so a test can stand a canned document in for the model.
public protocol RowReading: Sendable {
    func read(pages: [String], progress: (@Sendable (ReaderProgress) -> Void)?) async -> ProseDocument
}

@available(macOS 26.0, iOS 26.0, *)
extension ProseReader: RowReading {}
```

In `ProseReader.swift`, `ReaderProgress` becomes:

```swift
public struct ReaderProgress: Sendable {
    public let page: Int
    public let rowsSoFar: Int
    /// Every row head the pages hold, counted before any is read, so a sheet can say "row 34 of 77".
    public let rowsTotal: Int
    public let seconds: Double
}
```

In `read(pages:progress:)`: compute `let rowsTotal = RowText.rowCount(in: pages)` at the top, pass it in every `ReaderProgress(...)` construction (there are three), and at the top of the `for block in blocks` loop add:

```swift
                if Task.isCancelled {
                    doc.uncertain = (doc.uncertain ?? []) + ["cancelled after \(rows.count) rows"]
                    if !rows.isEmpty { doc.written_rows = rows }
                    return doc
                }
```

In `RowText`, beside `blocks(in:)`:

```swift
    /// How many written rows the pages hold, by their heads: what a progress bar is out of.
    public static func rowCount(in pages: [String]) -> Int {
        pages.reduce(0) { $0 + blocks(in: $1).count }
    }
```

The `prosereader` tool's progress print (`main.swift`) gains the total: `"  page \(p.page): \(p.rowsSoFar) of \(p.rowsTotal) rows, \(Int(p.seconds)) s\r"`.

- [x] **Step 4: Run the package tests and build the tool**

Run: `cd ios/Packages/ProseReader && swift test 2>&1 | grep -E '✘|Test run with' && swift build -c release 2>&1 | grep -E 'error|Build complete'`
Expected: 27 tests pass; build complete.

- [x] **Step 5: Commit**

```bash
git add ios/Packages/ProseReader
git commit -m "ios: ProseReaderKit builds for iOS, can be cancelled, and counts its rows up front (#112 PR 2)"
```

---

### Task 2: `RowsChart` — the rows-only assembler in `GraphghanCore`

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/RowsChart.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/RowsChartTests.swift`

**Interfaces:**
- Produces: `public enum RowsChart { struct Row { row: Int; runs: [(code: String, count: Int)]; total: Int? }; static func rowStrings(rows: [Row], codes: [String], width: Int, height: Int, row1: String = "bottom-right") -> Result<[String], Problems>; struct Problems: Error, Equatable { let sentences: [String] }; static func placeholderHex(avoiding: [String]) -> String; static let placeholders: [String] }`. The strings are chart rows top to bottom in the format's run-string encoding.

The port of `written_to_grid`, `row_total_problems`, `row_number_problems`, `reads_right_to_left`, `grid_row`, `_placeholder_hex` (`prose.py`, `importers.py`), sentences word for word.

- [x] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import GraphghanCore

/// The rows-only assembler (phone import spec §4.3): the port of the Python `written_to_grid`
/// and its checks, so a chart built from written rows on the phone is the one the Mac builds.
@Suite struct RowsChartTests {
    typealias Row = RowsChart.Row

    @Test func rowsBecomeTheGridInDisplayOrderWithRSRowsReversed() throws {
        // Row 1 (RS, right to left) "2 A, 1 B" is drawn as B A A left to right; row 2 (WS) as written.
        let rows = [Row(row: 1, runs: [("A", 2), ("B", 1)], total: 3), Row(row: 2, runs: [("B", 3)], total: nil)]
        let strings = try RowsChart.rowStrings(rows: rows, codes: ["A", "B"], width: 3, height: 2).get()
        #expect(strings == ["3B", "1B2A"])
    }

    @Test func aRowThatDoesNotSumToTheWidthIsNamed() {
        let rows = [Row(row: 1, runs: [("A", 2)], total: nil), Row(row: 2, runs: [("A", 3)], total: nil)]
        let result = RowsChart.rowStrings(rows: rows, codes: ["A"], width: 3, height: 2)
        #expect(result == .failure(RowsChart.Problems(sentences: ["row 1: runs sum to 2, chart width is 3"])))
    }

    @Test func aPrintedTotalThatDisagreesWithTheRunsIsNamedFirst() {
        let rows = [Row(row: 1, runs: [("A", 3)], total: 4)]
        let result = RowsChart.rowStrings(rows: rows, codes: ["A"], width: 3, height: 1)
        #expect(result == .failure(RowsChart.Problems(sentences: ["row 1: runs sum to 3 but the pattern prints 4 sts"])))
    }

    @Test func duplicateMissingAndBeyondRowsAreNamed() {
        let rows = [Row(row: 1, runs: [("A", 1)], total: nil), Row(row: 1, runs: [("A", 1)], total: nil), Row(row: 5, runs: [("A", 1)], total: nil)]
        let result = RowsChart.rowStrings(rows: rows, codes: ["A"], width: 1, height: 3)
        #expect(result == .failure(RowsChart.Problems(sentences: ["row 1 printed twice", "missing rows 2-3 of 3", "rows 5 are beyond the chart height 3"])))
    }

    @Test func aCodeNotInThePaletteIsNamed() {
        let rows = [Row(row: 1, runs: [("Q", 1)], total: nil)]
        let result = RowsChart.rowStrings(rows: rows, codes: ["A"], width: 1, height: 1)
        #expect(result == .failure(RowsChart.Problems(sentences: ["row 1 uses code 'Q', not in the palette [\"A\"]"])))
    }

    @Test func theOwnPDFsRowsRebuildTheMacsChart() throws {
        let reading = try ChartWriterTests.reading("craigh-na-dun-final-sc")
        let rows = reading.rows.map { Row(row: $0.row, runs: $0.runs.map { ($0.code, $0.count) }, total: $0.total) }
        let strings = try RowsChart.rowStrings(rows: rows, codes: reading.palette.map(\.code), width: reading.width, height: reading.height).get()
        let id = ChartID.compute(codes: reading.palette.map(\.code), rows: strings, technique: ChartWriter.techniqueRows, passes: nil)
        #expect(id == "sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f")
    }

    @Test func placeholdersAreLoudAndFarFromTheTakenColours() {
        #expect(RowsChart.placeholderHex(avoiding: []) == "#ff00ff")
        #expect(RowsChart.placeholderHex(avoiding: ["#ff00ff"]) == "#00ffff")
        #expect(RowsChart.placeholders.count == 8)
    }
}
```

`ChartWriterTests.reading` is `static func` today; make it `static func reading(_:) throws -> OwnPDFReading` internal (drop `private` if any) so this suite can call it.

- [x] **Step 2: Run to see them fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter RowsChartTests 2>&1 | tail -3`
Expected: compile error, `RowsChart` undefined.

- [x] **Step 3: Write the assembler**

```swift
import Foundation

/// The chart the written rows describe, when there is no picture to check them against (phone
/// import spec §4.3): a port of `prose.written_to_grid` and its checks, sentence for sentence.
public enum RowsChart {
    public struct Row: Sendable {
        public let row: Int
        public let runs: [(code: String, count: Int)]
        public let total: Int?
        public init(row: Int, runs: [(code: String, count: Int)], total: Int?) {
            self.row = row
            self.runs = runs
            self.total = total
        }
    }
    public struct Problems: Error, Equatable, Sendable {
        public let sentences: [String]
        public init(sentences: [String]) { self.sentences = sentences }
    }

    /// Working direction of a written row: row 1 starts at the printed corner; rows alternate.
    static func readsRightToLeft(row: Int, row1: String) -> Bool {
        let startsRight = row1.hasSuffix("right")
        return row % 2 == 1 ? startsRight : !startsRight
    }

    static func gridRow(row: Int, height: Int, row1: String) -> Int {
        row1.hasPrefix("bottom") ? height - row : row - 1
    }

    /// The chart rows, top to bottom, in the format's run strings, or every problem found.
    public static func rowStrings(rows: [Row], codes: [String], width: Int, height: Int, row1: String = "bottom-right") -> Result<[String], Problems> {
        var problems = totalProblems(rows, width: width) + numberProblems(rows, height: height)
        let index = Set(codes)
        for r in rows {
            if let bad = r.runs.first(where: { !index.contains($0.code) }) {
                problems.append("row \(r.row) uses code '\(bad.code)', not in the palette \(codes.map { "\"\($0)\"" }.joined(separator: ", ").wrappedInBrackets)")
            }
        }
        if !problems.isEmpty { return .failure(Problems(sentences: problems)) }
        var grid = [[(code: String, count: Int)]](repeating: [], count: height)
        for r in rows {
            let runs = readsRightToLeft(row: r.row, row1: row1) ? Array(r.runs.reversed()) : r.runs
            grid[gridRow(row: r.row, height: height, row1: row1)] = runs
        }
        return .success(grid.map { ChartWriter.runString($0) })
    }

    /// Every written row whose runs do not sum to the chart width, or to its own printed total.
    static func totalProblems(_ rows: [Row], width: Int) -> [String] {
        rows.compactMap { r in
            let total = r.runs.reduce(0) { $0 + $1.count }
            if let printed = r.total, printed != total { return "row \(r.row): runs sum to \(total) but the pattern prints \(printed) sts" }
            if total != width { return "row \(r.row): runs sum to \(total), chart width is \(width)" }
            return nil
        }
    }

    static func numberProblems(_ rows: [Row], height: Int) -> [String] {
        var counts: [Int: Int] = [:]
        for r in rows { counts[r.row, default: 0] += 1 }
        var out: [String] = []
        let dup = counts.filter { $0.value > 1 }.keys.sorted()
        if !dup.isEmpty { out.append("row " + dup.map(String.init).joined(separator: ", ") + " printed twice") }
        let present = Set(counts.keys)
        let missing = (1...max(1, height)).filter { !present.contains($0) && height >= 1 }
        if !missing.isEmpty { out.append("missing rows \(ranges(missing)) of \(height)") }
        let beyond = present.filter { $0 > height }.sorted()
        if !beyond.isEmpty { out.append("rows \(ranges(beyond)) are beyond the chart height \(height)") }
        return out
    }

    /// "2-3", "5, 7-9": the Python `_ranges`.
    static func ranges(_ nums: [Int]) -> String {
        var out: [String] = []
        var i = 0
        while i < nums.count {
            var j = i
            while j + 1 < nums.count, nums[j + 1] == nums[j] + 1 { j += 1 }
            out.append(j > i ? "\(nums[i])-\(nums[j])" : "\(nums[i])")
            i = j + 1
        }
        return out.joined(separator: ", ")
    }

    /// Loud colours no palette entry is near, for a key colour the pages give no hex for.
    public static let placeholders = ["#ff00ff", "#00ffff", "#ffff00", "#ff8000", "#8000ff", "#00ff80", "#ff0080", "#0080ff"]

    public static func placeholderHex(avoiding taken: [String]) -> String {
        let have = taken.compactMap(rgb)
        for candidate in placeholders {
            guard let c = rgb(candidate) else { continue }
            if have.allSatisfy({ distance($0, c) > 60 }) { return candidate }
        }
        return placeholders[placeholders.count - 1]
    }

    static func rgb(_ hex: String) -> (Double, Double, Double)? {
        guard hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (Double((v >> 16) & 0xff), Double((v >> 8) & 0xff), Double(v & 0xff))
    }

    /// Euclidean RGB distance: a stand-in for the Python Lab distance, enough to keep placeholders
    /// away from real colours (the threshold, 60 of 441, is the Lab 20 scaled).
    static func distance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
    }
}

private extension String {
    var wrappedInBrackets: String { "[" + self + "]" }
}
```

- [x] **Step 4: Run the tests**

Run: `cd ios/Packages/GraphghanCore && swift test --filter RowsChartTests 2>&1 | grep -E '✘|✔ Test run|error:'`
Expected: 7 pass. The `missing rows` computation must not range over `1...0` when `height` is 0; the `max(1, height)` guard keeps it safe.

- [x] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "ios: GraphghanCore builds a chart from written rows alone, with the Python checks (phone import §4.3)"
```

---

### Task 3: `PDFImporter` reads written rows, with progress, cancellation and the sentences

**Files:**
- Modify: `ios/project.yml` (add the `ProseReader` package and the `ProseReaderKit` dependency on the app target)
- Modify: `ios/Graphghan/Services/PDFImporter.swift`
- Modify: `ios/Tests/PDFImportTests.swift`

**Interfaces:**
- `PDFImporter` gains `let rowReader: (any RowReading)?` (nil when the device has no model; the app supplies `ProseReader(model: .onDevice, options: .init(examples: true))` under `#available(iOS 26, *)` when `unavailableReason() == nil`, else nil with the reason), and `read(_:fileName:progress:)` gains a `progress: (@Sendable (PDFImportProgress) -> Void)?` parameter: `enum PDFImportProgress: Sendable, Equatable { case pages(done: Int, of: Int); case rows(done: Int, of: Int, secondsElapsed: Int) }`.
- `PDFImportError` gains `.rowsArePictures`, `.needsAppleIntelligence`, `.rowsDoNotAssemble([String])`, `.cancelled`, with the §5.4 sentences.
- Produces: `PDFImportReading` gains `let source: PDFImportSource` (`enum { case ownPDF, writtenRows(count: Int, gaugePrinted: Bool) }`) so the sheet and the detail screen can say what happened.

- [x] **Step 1: Link the package**

`ios/project.yml`, under `packages:` add `ProseReader:\n    path: Packages/ProseReader`, and under the `Graphghan` target's `dependencies:` add `- package: ProseReader\n        product: ProseReaderKit`.

- [x] **Step 2: Write the failing tests**

Append to `PDFImportTests.swift` (the `PDFTestDocuments` helper gains an image page):

```swift
    /// A canned answer standing in for the model (phone import spec §9).
    struct StubRowReader: RowReading {
        let document: ProseDocument
        let delayPerRow: Duration
        func read(pages: [String], progress: (@Sendable (ReaderProgress) -> Void)?) async -> ProseDocument {
            let total = RowText.rowCount(in: pages)
            for i in 0..<total {
                if Task.isCancelled { return ProseDocument() }
                try? await Task.sleep(for: delayPerRow)
                progress?(ReaderProgress(page: 1, rowsSoFar: i + 1, rowsTotal: total, seconds: Double(i)))
            }
            return document
        }
    }

    static let twoRowText = "Key\nA red\nB blue\nRow 1: 2 A, 1 B\nRow 2: 3 B\n"

    static func twoRowDocument() -> ProseDocument {
        var doc = ProseDocument()
        doc.pattern = ["title": "Two Rows"]
        doc.palette = [.init(code: "A", name: "red", hex: "#ff0000", key_label: "red"), .init(code: "B", name: "blue", hex: "#0000ff", key_label: "blue")]
        doc.chart = .init(width: 3, height: 2, row1: "bottom-right")
        doc.written_rows = [
            .init(row: 1, page: 1, text: "Row 1: 2 A, 1 B", runs: [[.code("A"), .count(2)], [.code("B"), .count(1)]], total: nil, error: nil),
            .init(row: 2, page: 1, text: "Row 2: 3 B", runs: [[.code("B"), .count(3)]], total: nil, error: nil),
        ]
        return doc
    }

    @Test func writtenRowsWithNoChartBecomeAChartThroughTheReader() async throws {
        let (base, _, _) = try await make()
        let importer = PDFImporter(charts: base.charts, local: base.local, rowReader: StubRowReader(document: Self.twoRowDocument(), delayPerRow: .zero), modelUnavailable: nil)
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        var seen: [PDFImportProgress] = []
        let reading = try await importer.read(pdf, fileName: "two-rows.pdf") { seen.append($0) }
        #expect(reading.width == 3 && reading.height == 2 && reading.colours == 2)
        #expect(reading.bundle.manifest.title == "Two Rows" && reading.bundle.manifest.id == "two-rows")
        #expect(reading.bundle.charts[0].chart.document.rows == ["3B", "1B2A"])  // RS row 1 reversed, drawn last
        #expect(reading.source == .writtenRows(count: 2, gaugePrinted: false))
        #expect(seen.contains(.rows(done: 2, of: 2, secondsElapsed: 1)))
        let ext = reading.bundle.charts[0].chart.document.ext?["graphghan"]?["import"]
        #expect(ext?["source"]?.stringValue == "pdf" && ext?["grid"]?.boolValue == false && ext?["check"]?.stringValue == "none")
    }

    @Test func aRowThatDoesNotAssembleIsReportedNotWritten() async throws {
        let (base, _, _) = try await make()
        var doc = Self.twoRowDocument()
        doc.written_rows?[1].runs = [[.code("B"), .count(2)]]
        let importer = PDFImporter(charts: base.charts, local: base.local, rowReader: StubRowReader(document: doc, delayPerRow: .zero), modelUnavailable: nil)
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        await #expect(throws: PDFImportError.rowsDoNotAssemble(["row 2: runs sum to 2, chart width is 3"])) { try await importer.read(pdf, fileName: "x.pdf") }
        #expect(PDFImportError.rowsDoNotAssemble(["row 2: runs sum to 2, chart width is 3"]).message == "The written rows in this PDF don't add up: row 2: runs sum to 2, chart width is 3.")
    }

    @Test func withoutAModelWrittenRowsNeedAppleIntelligence() async throws {
        let (base, _, _) = try await make()
        let importer = PDFImporter(charts: base.charts, local: base.local, rowReader: nil, modelUnavailable: "on-device model unavailable")
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        await #expect(throws: PDFImportError.needsAppleIntelligence) { try await importer.read(pdf, fileName: "x.pdf") }
        #expect(PDFImportError.needsAppleIntelligence.message.hasPrefix("Reading written rows needs Apple Intelligence on this iPhone."))
    }

    @Test func aPageOfPicturesWithNoTextIsNamed() async throws {
        let (base, _, _) = try await make()
        let importer = PDFImporter(charts: base.charts, local: base.local, rowReader: StubRowReader(document: Self.twoRowDocument(), delayPerRow: .zero), modelUnavailable: nil)
        let pdf = try #require(PDFTestDocuments.imageOnly())
        await #expect(throws: PDFImportError.rowsArePictures) { try await importer.read(pdf, fileName: "scan.pdf") }
        #expect(PDFImportError.rowsArePictures.message == "This pattern's rows are printed as a picture; the app can't read that yet.")
    }

    @Test func cancellingTheReadThrowsCancelledAndWritesNothing() async throws {
        let (base, chartsDir, _) = try await make()
        let importer = PDFImporter(charts: base.charts, local: base.local, rowReader: StubRowReader(document: Self.twoRowDocument(), delayPerRow: .seconds(1)), modelUnavailable: nil)
        let pdf = try #require(PDFTestDocuments.plain(text: Self.twoRowText))
        let task = Task { try await importer.read(pdf, fileName: "x.pdf") }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: PDFImportError.cancelled) { try await task.value }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: chartsDir.path)) ?? []).isEmpty)
    }
```

`make()` returns a tuple today; give it a `base` shape: `func make() async throws -> (base: (charts: ChartLibrary, local: LocalPatternStore), chartsDir: URL, localDir: URL)` and update the existing tests' destructuring (`let (base, chartsDir, localDir) = try await make(); let importer = PDFImporter(charts: base.charts, local: base.local, rowReader: nil, modelUnavailable: nil)`).

In `PDFTestDocuments`:

```swift
    /// One page that is only a picture: what a Canva export of the rows looks like to PDFKit.
    static func imageOnly() -> Data? {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { ctx in
            UIColor.gray.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }
        return renderer.pdfData { ctx in
            ctx.beginPage()
            image.draw(in: CGRect(x: 100, y: 100, width: 400, height: 400))
        }
    }
```

- [x] **Step 3: Run to see them fail**

Run: `cd ios && xcodegen generate --quiet && xcodebuild test -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GraphghanTests/PDFImportTests 2>&1 | grep -E 'error:|Test run with|TEST' | head`
Expected: compile errors (`rowReader`, `PDFImportProgress` undefined).

- [x] **Step 4: The importer**

`PDFImporter.swift` changes:

```swift
import ProseReaderKit

struct PDFImporter: Sendable {
    let charts: ChartLibrary
    let local: LocalPatternStore
    /// The written-row reader, nil when this device has no model; then `modelUnavailable` says why.
    let rowReader: (any RowReading)?
    let modelUnavailable: String?

    static let maximumBytes = 20 << 20
    /// A page with an image and this little text is a picture of text (spec §4.4).
    static let pictureTextLimit = 200
    /// Seconds a row takes on the on-device model, for the sheet's estimate (spec §4.3, measured).
    static let secondsPerRow = 3.0

    func read(_ data: Data, fileName: String, progress: (@Sendable (PDFImportProgress) -> Void)? = nil) async throws(PDFImportError) -> PDFImportReading {
        guard data.count <= Self.maximumBytes else { throw .tooBig }
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw .cannotOpen }
        var texts: [String] = []
        var pictureOnly = false
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let text = page.string ?? ""
            texts.append(text)
            if text.count < Self.pictureTextLimit, Self.hasImage(page) { pictureOnly = true }
            progress?(.pages(done: i + 1, of: document.pageCount))
        }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if OwnPDFReader.isOwn(pageTexts: texts) {
            return try await assembleOwn(texts: texts, title: title, fileName: fileName)
        }
        // PR 3 adds the grid reader here, before the rows.
        let rowCount = RowText.rowCount(in: texts)
        guard rowCount >= 2 else { throw pictureOnly ? .rowsArePictures : .nothingFound }
        guard let rowReader else { throw .needsAppleIntelligence }
        return try await assembleRows(texts: texts, rowCount: rowCount, reader: rowReader, title: title, fileName: fileName, progress: progress)
    }

    static func hasImage(_ page: PDFPage) -> Bool {
        // PDFKit exposes no object list; a page whose text is this short and whose media box is a
        // full page is treated as a picture. Annotations do not count.
        page.bounds(for: .mediaBox).width >= 200
    }
```

`assembleOwn` is the body of PR 1's `read` from `guard OwnPDFReader.isOwn` on, unchanged except that it ends by calling a shared `assemble(draft:title:fileName:source:)`. `assembleRows`:

```swift
    func assembleRows(texts: [String], rowCount: Int, reader: any RowReading, title: String, fileName: String,
                      progress: (@Sendable (PDFImportProgress) -> Void)?) async throws(PDFImportError) -> PDFImportReading {
        let started = Date()
        let doc = await reader.read(pages: texts) { p in
            progress?(.rows(done: p.rowsSoFar, of: p.rowsTotal, secondsElapsed: Int(Date().timeIntervalSince(started))))
        }
        if Task.isCancelled { throw .cancelled }
        let rows = (doc.written_rows ?? []).filter { $0.error == nil && !$0.runs.isEmpty }.map { r -> RowsChart.Row in
            var runs: [(code: String, count: Int)] = []
            for pair in r.runs {
                var code = "", count = 0
                for v in pair { switch v { case .code(let s): code = s; case .count(let n): count = n } }
                runs.append((code, count))
            }
            return RowsChart.Row(row: r.row, runs: runs, total: r.total)
        }
        let errored = (doc.written_rows ?? []).filter { $0.error != nil }.map { "row \($0.row): \($0.error ?? "")" }
        guard !rows.isEmpty else { throw .rowsDoNotAssemble(errored.isEmpty ? ["no written rows were read"] : errored) }
        // Width and height: what the front matter says, else the widest row and the highest number.
        let width = doc.chart?.width ?? rows.map { $0.runs.reduce(0) { $0 + $1.count } }.max() ?? 0
        let height = doc.chart?.height ?? rows.map(\.row).max() ?? 0
        // Every colour the rows use must be in the key; a key colour with no hex gets a placeholder.
        var palette = (doc.palette ?? []).map { ChartDraft.Palette(code: $0.code, name: $0.name, hex: $0.hex ?? "") }
        let used = Set(rows.flatMap { $0.runs.map(\.code) })
        for code in used.sorted() where !palette.contains(where: { $0.code == code }) {
            palette.append(ChartDraft.Palette(code: code, name: code, hex: ""))
        }
        for i in palette.indices where palette[i].hex.isEmpty {
            palette[i] = ChartDraft.Palette(code: palette[i].code, name: palette[i].name, hex: RowsChart.placeholderHex(avoiding: palette.map(\.hex).filter { !$0.isEmpty }))
        }
        let strings: [String]
        switch RowsChart.rowStrings(rows: rows, codes: palette.map(\.code), width: width, height: height, row1: doc.chart?.row1 ?? "bottom-right") {
        case .success(let s): strings = s
        case .failure(let problems): throw .rowsDoNotAssemble(problems.sentences + errored)
        }
        let patternTitle = (doc.pattern?["title"]).flatMap { $0.isEmpty ? nil : $0 } ?? (title.isEmpty ? Self.stem(fileName) : title)
        var gauge = ChartDraft.Gauge()
        var gaugePrinted = false
        if let g = doc.gauge, let st = g.stitches, let rows = g.rows, let over = g.over, st > 0, rows > 0, over.value > 0 {
            gauge.stitches = Double(st); gauge.rows = Double(rows); gauge.overValue = Double(over.value); gauge.overUnit = over.unit
            gaugePrinted = true
        }
        gauge.stitch = doc.gauge?.stitch.flatMap { $0.isEmpty ? nil : $0 } ?? "sc"
        gauge.hook = doc.gauge?.hook.flatMap { $0.isEmpty ? nil : $0 }
        gauge.yarnWeight = doc.gauge?.yarn_weight.flatMap { $0.isEmpty ? nil : $0 }
        let ext: JSONValue = .object(["graphghan": .object(["import": .object([
            "source": .string("pdf"), "grid": .bool(false), "check": .string("none"),
            "rows_checked": .int(0), "rows_disagree": .array([]), "gauge_printed": .bool(gaugePrinted),
        ])])])
        let draft = ChartDraft(pattern: .init(id: "", title: patternTitle, version: "0.1.0"), palette: palette, rows: strings, width: width, height: height, gauge: gauge, ext: ext)
        return try await assemble(draft: draft, title: patternTitle, fileName: fileName, source: .writtenRows(count: rows.count, gaugePrinted: gaugePrinted))
    }
```

`assemble(draft:title:fileName:source:)`: the slug, `ChartWriter.encode` (with `draft.pattern.id = slug` set first), `Chart.load`, the preview, the manifest, the bundle, exactly PR 1's tail, returning `PDFImportReading(bundle:preview:width:height:colours:source:)`.

`PDFImportError` gains:

```swift
    case rowsArePictures
    case needsAppleIntelligence
    case rowsDoNotAssemble([String])
    case cancelled
    ...
        case .rowsArePictures: return "This pattern's rows are printed as a picture; the app can't read that yet."
        case .needsAppleIntelligence: return "Reading written rows needs Apple Intelligence on this iPhone. Open the PDF on a Mac with graphghan, or send a .graphghan file instead."
        case .rowsDoNotAssemble(let why): return "The written rows in this PDF don't add up: \(why.joined(separator: "; "))."
        case .cancelled: return ""
```

`PDFImportProgress` and `PDFImportSource` as in the Interfaces block.

- [x] **Step 5: Run the tests**

Run: the Step 3 command.
Expected: all `PDFImportTests` pass, PR 1's five included. If `rowsBecomeTheGrid…` in the app differs from `["3B", "1B2A"]`, the stub's `chart.row1` is `bottom-right` and row 1 is RS: reversed, drawn last; row 2 WS as written, drawn first.

- [x] **Step 6: Commit**

```bash
git add ios/project.yml ios/Graphghan/Services/PDFImporter.swift ios/Tests/PDFImportTests.swift
git commit -m "ios: PDFImporter reads written rows through the on-device model, with progress, cancel and the sentences (phone import §4.3, §4.4, §7)"
```

---

### Task 4: The sheet's reading-rows state, the gate, and the detail screen's gauge line

**Files:**
- Modify: `ios/Graphghan/Patterns/PDFImportSheet.swift`
- Modify: `ios/Graphghan/AppModel.swift`
- Modify: `ios/Graphghan/Patterns/PatternDetailContent.swift`
- Modify: `ios/Tests/PDFImportSheetTests.swift`

**Interfaces:**
- `PDFImportState.Stage` gains `.readingRows(done: Int, of: Int, secondsElapsed: Int)`; `PDFImportState` gains `var task: Task<Void, Never>?`.
- `AppModel` gains `var rowReader: (any RowReading)?` and `var modelUnavailable: String?` resolved once at init under `#available(iOS 26, *)` (tests inject through a new `init` parameter `rowReader:` defaulting to the resolved one), and `cancelPDFImport()` cancels the task.
- `PatternDetailContent` shows "Gauge not printed; using 14 × 16 over 4 in" under the specs when the chart's `ext.graphghan.import.gauge_printed` is `false`.

- [x] **Step 1: Write the failing tests**

Append to `PDFImportSheetTests.swift`:

```swift
    @Test func writtenRowsShowProgressThenTheChart() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.twoRowDocument(), delayPerRow: .milliseconds(50)))
        let pdf = try #require(PDFTestDocuments.plain(text: PDFImportTests.twoRowText))
        let task = Task { await model.importPDF(data: pdf, fileName: "two-rows.pdf") }
        try await Task.sleep(for: .milliseconds(60))
        if case .readingRows(_, let of, _) = model.pdfImport?.stage { #expect(of == 2) } else { Issue.record("expected readingRows, got \(String(describing: model.pdfImport?.stage))") }
        await task.value
        #expect(model.pdfImport?.stage == .found && model.pdfImport?.reading?.source == .writtenRows(count: 2, gaugePrinted: false))
    }

    @Test func cancelDuringTheReadClosesTheSheetAndWritesNothing() async throws {
        let model = try await make(rowReader: PDFImportTests.StubRowReader(document: PDFImportTests.twoRowDocument(), delayPerRow: .seconds(1)))
        let pdf = try #require(PDFTestDocuments.plain(text: PDFImportTests.twoRowText))
        let task = Task { await model.importPDF(data: pdf, fileName: "two-rows.pdf") }
        try await Task.sleep(for: .milliseconds(100))
        model.cancelPDFImport()
        await task.value
        #expect(model.pdfImport == nil && model.libraryItems.isEmpty)
    }

    @Test func withoutAModelTheSheetSaysSo() async throws {
        let model = try await make(rowReader: nil, modelUnavailable: "on-device model unavailable")
        let pdf = try #require(PDFTestDocuments.plain(text: PDFImportTests.twoRowText))
        await model.importPDF(data: pdf, fileName: "two-rows.pdf")
        #expect(model.pdfImport?.stage == .failed(PDFImportError.needsAppleIntelligence.message))
    }
```

and change `make()` to `make(rowReader: (any RowReading)? = nil, modelUnavailable: String? = nil)` passing both to `AppModel`'s init. The existing four tests keep working with the defaults (PR 1's own-PDF path needs no reader).

- [x] **Step 2: Run to see them fail**

Run: `cd ios && xcodebuild test ... -only-testing:GraphghanTests/PDFImportSheetTests 2>&1 | grep -E 'error:|Test run with|TEST' | head`
Expected: compile errors.

- [x] **Step 3: The model, the state, the sheet, the detail line**

`AppModel`: two stored properties and the init parameters:

```swift
    /// The written-row reader for PDFs (#112): the on-device model when this iPhone has one.
    let rowReader: (any RowReading)?
    let modelUnavailable: String?
```

In `init(...)`, add `rowReader: (any RowReading)?? = nil, modelUnavailable: String?? = nil` (double optional so "not given" resolves and "given nil" means none) and resolve:

```swift
        if let rowReader { self.rowReader = rowReader; self.modelUnavailable = modelUnavailable ?? nil }
        else if #available(iOS 26, *) {
            let reader = ProseReader(model: .onDevice, options: ReaderOptions(examples: true))
            let why = reader.unavailableReason()
            self.rowReader = why == nil ? reader : nil
            self.modelUnavailable = why
        } else {
            self.rowReader = nil
            self.modelUnavailable = "needs iOS 26"
        }
```

`importPDF(data:fileName:)` becomes:

```swift
    func importPDF(data: Data, fileName: String) async {
        let state = PDFImportState(fileName: fileName)
        pdfImport = state
        let importer = PDFImporter(charts: charts, local: localPatterns, rowReader: rowReader, modelUnavailable: modelUnavailable)
        let task = Task { [weak self] in
            do {
                let reading = try await importer.read(data, fileName: fileName) { p in
                    Task { @MainActor in
                        if case .rows(let done, let of, let seconds) = p { state.stage = .readingRows(done: done, of: of, secondsElapsed: seconds) }
                    }
                }
                state.reading = reading
                state.preview = UIImage(data: reading.preview)
                state.stage = .found
            } catch PDFImportError.cancelled {
                if self?.pdfImport === state { self?.pdfImport = nil }
            } catch let error as PDFImportError {
                state.stage = .failed(error.message)
            } catch {
                state.stage = .failed(PDFImportError.cannotOpen.message)
            }
        }
        state.task = task
        await task.value
    }

    func cancelPDFImport() {
        guard let state = pdfImport, state.stage != .saving else { return }
        state.task?.cancel()
        pdfImport = nil
    }
```

`PDFImportState`: `case readingRows(done: Int, of: Int, secondsElapsed: Int)` in `Stage`, `var task: Task<Void, Never>? = nil`.

`PDFImportSheet`, a new case between `.reading` and `.found`:

```swift
                case .readingRows(let done, let of, let seconds):
                    VStack(spacing: 12) {
                        Text("This pattern has no chart the app can read, so it is reading the \(of) written rows. About \(max(1, Int((Double(of) * PDFImporter.secondsPerRow / 60).rounded(.up)))) minutes.")
                            .font(Font.Heather.body).foregroundStyle(Color.ink2).multilineTextAlignment(.center)
                        ProgressView(value: Double(done), total: Double(max(of, 1)))
                        Text("Row \(done) of \(of), \(seconds) s").font(Font.Heather.caption).foregroundStyle(Color.ink2)
                    }
                    .padding()
```

and the toolbar button reads "Cancel" for `.found` and `.readingRows`, "Done" otherwise; `interactiveDismissDisabled` stays for `.reading` and `.saving` only (a swipe during `.readingRows` cancels, through the sheet binding's `set`).

`PatternDetailContent`, under `specs`:

```swift
            if let chart, chart.document.ext?["graphghan"]?["import"]?["gauge_printed"]?.boolValue == false {
                Text("Gauge not printed in the PDF; using \(chart.document.gauge.stitches.formatted()) × \(chart.document.gauge.rows.formatted()) over \(chart.document.gauge.over.value.formatted()) \(chart.document.gauge.over.unit).")
                    .font(Font.Heather.caption).foregroundStyle(Color.ink2)
            }
```

(`ChartDocument.ext` exists as `JSONValue?`; check the property name in `ChartDocument.swift` and use it.)

- [x] **Step 4: Run the tests**

Run: `cd ios && xcodebuild test ... 2>&1 | grep -E '✘|Test run with|TEST' | tail -3` (the whole app suite).
Expected: all green, `DesignRulesTests` included (the new texts use `Font.Heather` and `Color.*`).

- [x] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: the import sheet reads written rows with progress and cancel, and the detail screen says when the gauge was not printed (#112 PR 2)"
```

---

### Task 5: Docs, the manual gate, and the PR

**Files:**
- Modify: `ios/README.md` (the PDF section)
- Modify: `docs/superpowers/specs/2026-09-20-phone-pdf-import-design.md` §11 (the Orca criterion: mark "manual gate pending" with the device it needs)
- Modify: this plan (tick every box)

- [x] **Step 1: README**

Replace the sentence about "any other PDF" with: "A PDF with written rows and no chart goes to `ProseReaderKit` on a device with Apple Intelligence (iOS 26), row by row behind a progress sheet with Cancel, and is assembled by `RowsChart` under the same width and row-number checks the Python importer applies; without the model the sheet says so. A page that is a picture of text is named as such (#151)."

- [x] **Step 2: The manual gate**

Spec §11, the Orca bullet: append "(manual gate: needs an iPhone with Apple Intelligence; the simulator has no model. Not yet run.)" Tyler runs it; the number goes into §11 when it lands.

- [x] **Step 3: Check, Blink, push, PR**

Run: `mise run check`, `cd ios/Packages/ProseReader && swift test`, `cd ios/Packages/GraphghanCore && swift test`, the app suite; then Blink on the branch, push, and open the PR against `tylervick/phone-import` (retarget to `main` when #162 merges) with the body: the four tasks, the sentences, the stub-based tests, and the manual gate.

# Pieced PDF Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Opening Orca's PDF on the phone offers the whole bag — its two shaped chart panels, the written pieces code can find, and the unused pages as assembly — in a review list the maker can rename, remove, reorder and set `make × N` on, and saves it as one manifest-2 pattern with the source PDF kept beside it, whose assembly pages open that PDF.

**Architecture:** The importer stops keeping only the largest chart region: every region and every `RowText` section becomes a *found part*. A pure, code-only `FoundOutline` (behind a `PieceReading` protocol, the slot #200's server reader would fill) pairs regions with their own rows, parses the rest into written pieces, guesses titles from page headings and proposes assembly pages, producing a `PatternOutline`. The sheet shows it as an editable `OutlineDraft`; checks run per chart piece; saving writes each chart, each rows document, a manifest 2 and `source.pdf`. A PDF with one chart and nothing else takes today's path unchanged.

**Tech Stack:** Swift 6 / Swift Testing (the iOS app, `GraphghanCore`, `ProseReaderKit`), SwiftUI, PDFKit, SwiftData untouched; xcodebuild on the iPhone 17 simulator.

**Spec:** `docs/superpowers/specs/2026-09-25-pieces-and-shaped-rows-design.md` — this plan is §8's PR 3 ("The importer"): §7.1–§7.5, §5.5's source PDF, §6.2's "a step with pages opens the source PDF at the first page", §10's Orca criterion. It also closes #222 (range heads written "R 2 - R 26") and #224 (manifest decode stricter than the schema), which the importer needs.

## Measured facts this plan is built on (Orca, PDFKit text, 2026-09-30)

`RowText.sections` finds nine sections: 0 — pages 7–8, the "how to read a graph" example (`R 1`, `R 2`, then a step caption `2. 1 inc with white.` read as row 2 again, then `R 3`, `R 4` on page 8); 1 — page 10, the side panel, whose blocks today are `R 1`, `R 26` (PDFKit's line `R 2 - R 26: …` is split by `blocks(in:)` at the inner `R 26`, and the `R 2 -` fragment is dropped — the real form of #222), `R 27 - 86`, `R 87 - 104`, then a stray `R 8.` from prose; 2 — page 11, 14 rows (dorsal fin); 3 — page 11, 13 rows (pectoral front); 4 — pages 11–12, 15 rows (pectoral back); 5 — page 12, 10 rows (tail, white); 6 — pages 12 and 16: `R 1`, `R 2 - 7`, `R 8 - 15: same as` (the rest of that line, `R3 - R 10 of the instruction for the white side.`, is split off as its own block with row 3), then assembly prose from page 16 (`R 34 - R 46.`, …); 7 — pages 17–18, 77 rows (front panel); 8 — pages 18–20, 77 rows (back panel). Page 9 holds both 29 × 77 chart regions. Heading-like lines, one per page, in text order: 10 `Head Tail`, `Side Panel`; 11 `Dorsal Fin`, `Pectoral Fin (Front)`, `Pectoral Fin (Back)`; 12 `Tail`; 13 `Strap`; 17 `Front Panel`, `Written Instructions`; 18 `Back Panel`; page 9's only line is `Front Back` (one line over both charts, so a chart is titled from its paired rows' heading, not a label beside it — a ruling on spec §7.3's example).

## Global Constraints

- "A single chart with nothing else found shows no list and saves exactly as today" (spec §7.4); "A single found chart saves as manifest 1, as today" (§7.5). Every existing `PDFImportTests`, `PDFImportRealTests` and `PDFImportSheetTests` test passes unchanged, including the word-for-word `PDFContents.sentence` pins.
- "Pairing is code and needs no model" (§7.2); regions in reading order (page, then left to right), height-matched colour sections in document order, the k-th region gets the k-th section.
- "A paired section becomes the chart's `written` text … and its cross-check … once per chart piece, in order, with progress and cancel. Each chart piece gets its own `ImportRecord`. … the importer does not re-pair." (§7.2)
- Written pieces are parsed by code, never the model: heads and ranges → `from`/`to`, a trailing `[n]` → `count`, a leading `(Name)` → `code` when a chart's palette names that colour (§7.2). A written-rows document may not have a gap (§5.2), so parsing stops at the first head that does not continue the rows, and what follows is left out, named in the sheet.
- "Every chart and rows document validates before anything is written; the bundle importer's atomic order applies." (§7.5) The source PDF is kept beside the local pattern as `source.pdf`, "never packed into a `.graphghan` bundle", deleted with the pattern (§5.5, §7.5).
- The on-device model is used only by the check, exactly as today (`RowReading`); outline building never calls it.
- Deployment iOS 17; CI runs Xcode 26.2 while the mini has 27: no API newer than neighbouring files use. `ProseReaderKit` is also built for macOS 26 (`swift test` in `ios/Packages/ProseReader`).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`; `HK_STASH=none git commit …` if the hk stash fails on a partial commit.
- App tests: from `ios/`, `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -collect-test-diagnostics never -only-testing:GraphghanTests/<Suite>`; whole suite `mise run test` (capture its exit status: `; echo "exit $?"`). New app/test files need `mise run generate`. ImageRenderer cannot flatten `List`, `Form`, `Toggle` or `ScrollView`: snapshot plain stacks and Read every new PNG. Never use snapshot record mode. Real PDFs live in the gitignored `fixtures/import/real/`; real tests `print("SKIP …")` and return when the file is absent (copy it with `mkdir -p fixtures/import/real && cp -n ~/orca/workspaces/graphghan/row-check-on-a-device-foundation-models-answers/fixtures/import/real/* fixtures/import/real/`).

## Review Focus

1. **The maker removes everything but one chart.** The save must fall back to today's single-chart manifest 1 (spec §7.5), not write a one-piece manifest 2. Pinned in Task 8 (`removingAllButOneChartSavesAsToday`).
2. **Two pieces renamed to the same title.** Piece ids must stay unique slugs (`strap`, `strap-2`), or the bundle reader refuses the pattern. Pinned in Task 6 (`OutlineDraftTests.sameTitlesGetUniqueIDs`).
3. **Cancel or Skip during the second chart piece's check.** The first piece keeps its finished record, the second is saved as stopped, and Add still works. Pinned in Task 7 (`skippingTheSecondPiecesCheckKeepsTheFirst`).
4. **A save that fails half way** (one rows document invalid after an edit, or a disk error) writes nothing: no charts, no rows, no pattern directory, no stray `source.pdf`. Pinned in Task 8 (`aFailedPiecedSaveWritesNothing`).
5. **A PDF the maker imported twice.** The second import gets its own slug and its own `source.pdf`; deleting one pattern never deletes the other's PDF. Pinned in Task 9 (`eachImportKeepsItsOwnPDF`).

---

### Task 1: ProseReaderKit — range heads written with the letter twice (#222), and the head's parts

**Files:**
- Modify: `ios/Packages/ProseReader/Sources/ProseReaderKit/ProseReader.swift` (`RowText.headPattern`, `RowText.blocks(in:)`, add `RowText.splitHead`)
- Test: the ProseReader test file that tests `rowNumbers` (grep `rowNumbers` under `ios/Packages/ProseReader/Tests`)

**Interfaces:**
- Produces: `public struct RowHead: Equatable, Sendable { public let label: String; public let rows: [Int]; public let body: String }` and `public static func splitHead(_ block: String) -> RowHead?` on `RowText` — `label` is the printed head without its trailing `:`/`.`/marker punctuation (e.g. `"R 2 - R 26"`, `"R 1 [←]"`), `rows` is `rowNumbers(of:)`, `body` the text after the head, trimmed.

- [ ] **Step 1: Write the failing tests**

```swift
    /// #222: Orca's side panel prints "R 2 - R 26"; the letter repeats before the range's end.
    @Test func aRangeHeadMayRepeatItsLetter() {
        #expect(RowText.rowNumbers(of: "R 2 - R 26: ch 1, turn, 6 sc [6]") == Array(2...26))
        #expect(RowText.rowNumbers(of: "Rows 3 - Row 5: 4 sc") == [3, 4, 5])
        #expect(RowText.rowNumbers(of: "R 27 - 86: (White) ch 1, turn, 6 sc [6]") == Array(27...86))
        #expect(!RowText.isSingleRow("R 2 - R 26: ch 1, turn, 6 sc [6]"))
    }

    /// #222 as Orca's PDF actually reads: `blocks(in:)` must not split a line inside its own leading head.
    @Test func aRangeHeadStaysOneBlock() {
        #expect(RowText.blocks(in: "R 2 - R 26: ch 1, turn, 6 sc [6]") == ["R 2 - R 26: ch 1, turn, 6 sc [6]"])
        #expect(RowText.blocks(in: "R 1: 6 sc [6]\nR 2 - R 26: ch 1, turn, 6 sc [6]\nR 27 - 86: 6 sc [6]").count == 3)
        // a head later in the line still starts a new block, as today
        #expect(RowText.blocks(in: "R 1: 6 sc R 2: 6 sc").count == 2)
    }

    @Test func splitHeadGivesTheLabelRowsAndBody() {
        #expect(RowText.splitHead("R 2 - R 26: ch 1, turn, 6 sc [6]") == RowHead(label: "R 2 - R 26", rows: Array(2...26), body: "ch 1, turn, 6 sc [6]"))
        #expect(RowText.splitHead("R 1 [←]: (Black) ch 10, 9 sc [9]") == RowHead(label: "R 1 [←]", rows: [1], body: "(Black) ch 10, 9 sc [9]"))
        #expect(RowText.splitHead("Row 12: 3 B, 17 A")?.label == "Row 12")
        #expect(RowText.splitHead("no head here") == nil)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd ios/Packages/ProseReader && swift test --quiet --filter <the suite>`
Expected: FAIL — `rowNumbers` returns `[2]` for "R 2 - R 26"; `RowHead`/`splitHead` do not exist.

- [ ] **Step 3: Implement**

In `headPattern`, let a range's second number be preceded by an optional repeated row word: change

```swift
        let range = #"(\d+(?:\s*(?:[-–]|&|and)\s*\d+)?)"#
```

to

```swift
        // "R 2 - R 26" and "Rows 3 - Row 5" repeat the row word before the range's end (#222).
        let range = #"(\d+(?:\s*(?:[-–]|&|and)\s*(?:(?:Rows?|ROWS?|R)\s*\.?\s*)?\d+)?)"#
```

`rowNumbers(of:)` already splits `number` on non-digits, so `"2 - R 26"` yields `[2, 26]`; `isSingleRow` (all digits) is false for it.

In `blocks(in:)`, split a line at `rowInside` matches only *after* the end of the line's own leading head: if `rowStart` matches at the start of the line, run the `rowInside` replacement on the text after that match's end and prepend the head unchanged (today the replacement runs over the whole line, so the inner `R 26` of `R 2 - R 26:` becomes a split point and the `R 2 -` fragment is dropped).

Add, next to `rowNumbers`:

```swift
/// A written row's head, split: the label as printed, the rows it covers, and the text after it.
public struct RowHead: Equatable, Sendable {
    public let label: String
    public let rows: [Int]
    public let body: String
    public init(label: String, rows: [Int], body: String) { self.label = label; self.rows = rows; self.body = body }
}
```

(at file scope) and on `RowText`:

```swift
    /// The head's printed label ("R 2 - R 26", "R 1 [←]"), its rows, and the row's own text.
    public static func splitHead(_ block: String) -> RowHead? {
        guard let h = head(of: block) else { return nil }
        let head = block[..<h.end].trimmingCharacters(in: .whitespaces)
        let label = head.trimmingCharacters(in: CharacterSet(charactersIn: ":.-–—").union(.whitespaces))
        return RowHead(label: label, rows: rowNumbers(of: block), body: block[h.end...].trimmingCharacters(in: .whitespacesAndNewlines))
    }
```

- [ ] **Step 4: Run to verify**

Run the whole package: `cd ios/Packages/ProseReader && swift test --quiet` → PASS (every existing head and block test unchanged; the breadth scripts are not part of the suite). Then from `ios/`: `-only-testing:GraphghanTests/PDFImportTests -only-testing:GraphghanTests/PDFImportRealTests` → PASS unchanged (the Orca left-out sentence still says 9 sets: sections split only on a repeated row 1, which this does not change). If any existing ProseReader test pins today's split of a range head, report it rather than change its expectation.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/ProseReader
git commit -m "ProseReaderKit: read a range head that repeats its row letter, and split a head's parts (#222)"
```

---

### Task 2: GraphghanCore — manifest decode as permissive as its schema (#224)

**Files:**
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/SiteModels.swift` (`PatternManifest.init(from:)`), `PatternBundle.swift` (`read`: skip an empty preview path)
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/SiteModelsTests.swift`, `PatternBundleTests.swift`

**Interfaces:**
- Produces: `PatternManifest` decodes with `dedication`, `quote`, `author`, `license`, `preview` and `updated` absent (each defaults to `""`); `PatternBundle.read` does not require a preview file when `manifest.preview` is `""`.

- [ ] **Step 1: Write the failing tests**

```swift
    @Test func aManifestMayOmitWhatItsSchemaDoesNotRequire() throws {
        let json = #"{"schema":2,"id":"bag","title":"Bag","version":"1","charts":[],"palette":[],"pieces":[{"id":"strip","title":"Strip","rows":"pieces/strip.rows.json","rows_id":"sha256:\#(String(repeating: "a", count: 64))"}]}"#
        let m = try JSONDecoder().decode(PatternManifest.self, from: Data(json.utf8))
        #expect(m.preview == "" && m.dedication == "" && m.updated == "" && m.isPieced)
    }
```

and in `PatternBundleTests`, a written-only bundle with no preview: build it from `Fixtures.pieces` files as the existing written-only test does, with a manifest whose `preview` key is removed and without `preview.png`; `PatternBundle.read` succeeds and `bundle.previews` is empty.

(`palette` is also required by the Swift type but not by the schema; default it to `[]` too, and add it to the test's omitted keys if you do.)

- [ ] **Step 2: Run to verify they fail**

Run: `cd ios/Packages/GraphghanCore && swift test --quiet --filter "SiteModelsTests|PatternBundleTests"`
Expected: FAIL — `keyNotFound(preview)`.

- [ ] **Step 3: Implement**

In `PatternManifest.init(from:)`, decode `dedication`, `quote`, `author`, `license`, `preview`, `updated` with `decodeIfPresent(String.self, …) ?? ""` and `palette` with `decodeIfPresent([Swatch].self, …) ?? []`; `schema`, `id`, `title`, `version`, `charts` stay required (the schema requires them). In `PatternBundle.read`, filter empty strings out of the `checkPaths` list and out of the previews loop (the loop already skips empty paths; `checkPaths` must too).

- [ ] **Step 4: Run to verify**

`cd ios/Packages/GraphghanCore && swift test --quiet` → PASS; then build the app once (`xcodebuild build -quiet … -destination 'platform=iOS Simulator,name=iPhone 17'`).

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "GraphghanCore: a manifest decodes as permissively as manifest.schema.json allows (#224)"
```

---

### Task 3: GraphghanCore — writing rows documents and a pieced manifest

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/RowsWriter.swift`
- Modify: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ManifestWriter.swift`
- Test: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/RowsWriterTests.swift`, `ManifestWriterTests.swift`

**Interfaces:**
- Produces:
  - `public enum RowsWriter { public static func encode(title: String, palette: [ChartDraft.Palette], entries: [RowsDocument.Entry], pages: [Int]) -> (data: Data, id: String) }` — canonical JSON in the `docs/chart-format.md` §Written-rows shape (`schema`, `id`, `piece.title`, `palette` only when non-empty, `rows`, `source.pages` only when non-empty); the id is `RowsDocument.computeID(entries)`.
  - `public struct PieceEntry: Sendable, Equatable { public var id: String; public var title: String; public var make: Int; public var chart: String?; public var rows: String?; public var rowsID: String?; public var pages: [Int] }` and `public struct AssemblyEntry: Sendable, Equatable { public var title: String; public var text: String?; public var pages: [Int] }` (plain writer inputs; the Decodable `ManifestPiece`/`AssemblyStep` stay as they are).
  - `public struct ManifestChartInput { public let chart: Chart; public let chartID: String; public let variant: String; public let gaugeKey: String; public let palette: [ChartDraft.Palette] }`
  - `ManifestWriter.encodePieced(id: String, title: String, version: String, dedication: String, charts: [ManifestChartInput], pieces: [PieceEntry], assembly: [AssemblyEntry], palette: [ChartDraft.Palette]) -> Data` — schema 2; one `charts[]` entry per input, built exactly as `encode` builds its one entry (factor that entry builder into a private function both use, so the single-chart bytes stay identical), `default: true` on the first only, paths `charts/<variant>-<gaugeKey>/chart.json`; `pieces` in order with `make` always written; `assembly` with `text` only when present and `pages` only when non-empty.

- [ ] **Step 1: Write the failing tests**

`RowsWriterTests`:

```swift
    @Test func aWrittenDocumentLoadsBackWithTheSameID() throws {
        let entries = [RowsDocument.Entry(label: "R 1", from: 1, to: 1, text: "(Black) ch 7, 6 sc [6]", count: 6, code: "A", repeatText: nil),
                       RowsDocument.Entry(label: "R 2 - R 26", from: 2, to: 26, text: "ch 1, turn, 6 sc [6]", count: 6, code: nil, repeatText: nil)]
        let (data, id) = RowsWriter.encode(title: "Side Panel", palette: [.init(code: "A", name: "black", hex: "#201b18")], entries: entries, pages: [10])
        let doc = try RowsDocument.load(data)
        #expect(doc.id == id && doc.title == "Side Panel" && doc.entries == entries && doc.pages == [10])
    }

    @Test func theIDMatchesTheFixtureThePythonWrote() throws {
        let fixture = try RowsDocument.load(Fixtures.pieces("pieces/strip.rows.json"))
        let palette = fixture.palette.map { ChartDraft.Palette(code: $0.code, name: $0.name, hex: $0.hex) }
        let (data, id) = RowsWriter.encode(title: fixture.title, palette: palette, entries: fixture.entries, pages: fixture.pages)
        #expect(id == fixture.id)
        #expect(try RowsDocument.load(data) == fixture)
    }
```

`ManifestWriterTests`:

```swift
    @Test func aPiecedManifestReadsAsSchema2() throws {
        let chart = try Chart.load(Fixtures.data("shaped-basic.chart.json"))
        let input = ManifestChartInput(chart: chart, chartID: chart.id, variant: "front-panel", gaugeKey: "sc",
                                       palette: chart.palette.map { .init(code: $0.code, name: $0.name, hex: $0.hex) })
        let pieces = [PieceEntry(id: "front-panel", title: "Front Panel", make: 1, chart: chart.id, rows: nil, rowsID: nil, pages: [9, 17]),
                      PieceEntry(id: "dorsal-fin", title: "Dorsal Fin", make: 1, chart: nil, rows: "pieces/dorsal-fin.rows.json",
                                 rowsID: "sha256:" + String(repeating: "b", count: 64), pages: [11])]
        let data = ManifestWriter.encodePieced(id: "orca", title: "Orca", version: "0.1.0", dedication: "", charts: [input], pieces: pieces,
                                               assembly: [AssemblyEntry(title: "Pages 13–16", text: nil, pages: [13, 14, 15, 16])], palette: input.palette)
        let m = try JSONDecoder().decode(PatternManifest.self, from: data)
        #expect(m.schema == 2 && m.charts.count == 1 && m.charts[0].isDefault && m.charts[0].path == "charts/front-panel-sc/chart.json")
        #expect(m.pieces?.map(\.id) == ["front-panel", "dorsal-fin"] && m.pieces?[1].rows == "pieces/dorsal-fin.rows.json")
        #expect(m.assembly.map(\.title) == ["Pages 13–16"] && m.assembly[0].text == nil)
    }
```

plus: the existing single-chart `encode` output is byte-identical before and after the refactor (compare against a hard-coded SHA-256 of today's output for the minimal-rows fixture computed in Step 2 before changing the file).

- [ ] **Step 2: Run to verify they fail** (before implementing, also record `encode`'s current SHA-256 for the byte-identity test)

Run: `cd ios/Packages/GraphghanCore && swift test --quiet --filter "RowsWriterTests|ManifestWriterTests"` → FAIL (types missing).

- [ ] **Step 3: Implement** as the Interfaces block says, encoding with `CanonicalJSON.encode` as `ChartWriter`/`ManifestWriter` do. Rows document keys: `{"schema": 1, "id", "piece": {"title"}, "palette"?, "rows": [{"label","from","to"?,"text","count"?,"code"?,"repeat"?}], "source"? {"pages"}}`.

- [ ] **Step 4: Run to verify** — `swift test --quiet` → PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "GraphghanCore: write rows documents and a pieced manifest (#206)"
```

---

### Task 4: The outline — parsing written pieces, headings, pairing (`FoundOutline`)

**Files:**
- Create: `ios/Graphghan/Services/Import/PatternOutline.swift` (types and `PieceReading`), `ios/Graphghan/Services/Import/WrittenPieceParser.swift`, `ios/Graphghan/Services/Import/PageHeadings.swift`, `ios/Graphghan/Services/Import/FoundOutline.swift`
- Test: `ios/Tests/WrittenPieceParserTests.swift`, `ios/Tests/FoundOutlineTests.swift`, `ios/Tests/PDFImportRealTests.swift` (one new test)

**Interfaces:**
- Consumes: Task 1's `RowText.splitHead`; `RowText.sections(in:)`, `RowSection`, `RowText.namesColour`; `GraphghanCore`'s `RowsDocument.Entry`, `ChartDraft.Palette`.
- Produces:

```swift
/// A chart region found on a page: its page (1-based), its left edge in the page image, and its size.
struct FoundChart: Sendable, Equatable { let page: Int; let x0: Int; let cols: Int; let rows: Int }

/// Everything code found in the PDF before anything is offered (spec §7.1).
struct FoundParts: Sendable {
    let charts: [FoundChart]          // in reading order: page, then left to right
    let sections: [RowSection]        // RowText.sections, document order
    let pageTexts: [String]
    let palette: [ChartDraft.Palette] // the first chart's palette, for (Name) → code
}

enum PieceKind: Sendable, Equatable { case chart(Int) /* index into FoundParts.charts */; case rows(Int) /* index into sections */ }

struct PieceOutline: Sendable, Equatable {
    var title: String
    var kind: PieceKind
    var make: Int
    var pages: [Int]                  // 1-based
    var pairedSection: Int?           // for a chart piece: its own rows (spec §7.2)
    var entries: [RowsDocument.Entry] // for a written piece: its parsed rows; empty for a chart
}
struct AssemblyOutline: Sendable, Equatable { var title: String; var text: String?; var pages: [Int] }
struct PatternOutline: Sendable, Equatable { var pieces: [PieceOutline]; var assembly: [AssemblyOutline]; var leftOut: [String] }

/// Where a better reader (#200) plugs in: the same list, filled differently.
protocol PieceReading: Sendable { func outline(pages: [String], found: FoundParts) async -> PatternOutline }

struct ParsedPiece: Sendable, Equatable { let entries: [RowsDocument.Entry]; let pages: [Int]; let stoppedAt: (page: Int, afterRow: Int)? }
enum WrittenPieceParser { static func parse(_ section: RowSection, palette: [ChartDraft.Palette]) -> ParsedPiece }
enum PageHeadings { static func isHeading(_ line: String) -> Bool; static func headings(in pageTexts: [String]) -> [[String]] }
struct FoundOutline: PieceReading { func outline(pages: [String], found: FoundParts) async -> PatternOutline }
```

(`ParsedPiece` holds a tuple, so implement `Equatable` by hand or store `stoppedAtPage`/`stoppedAfterRow` as two optionals — the latter is simpler; use `let stoppedAtPage: Int?; let stoppedAfterRow: Int?` and update the tests below accordingly.)

**Rules (each pinned by a test below):**
- **Parsing a written piece** (`WrittenPieceParser.parse`): walk the section's blocks with `RowText.splitHead`. An entry is `label` = the head's label; `from`/`to` = the first and last of its rows (a single row has `to == from`); `text` = the head's body; `count` = the integer in a trailing `[n]` of the body (regex `\[(\d+)\]\s*\.?\s*$`), else nil; `code` = the palette code whose `name` matches, case-insensitively, a leading `(Name)` of the body (regex `^\(([A-Za-z][A-Za-z ]*)\)`), else nil. The first entry must start at row 1 and each next one at the previous `to + 1`; the first block that does not (a gap, an overlap, a head that goes backwards like page 10's stray `R 8.`) stops the parse: `stoppedAtPage` = that block's page (1-based), `stoppedAfterRow` = the last row parsed. `pages` = the 1-based pages of the parsed blocks only. A block without a head is skipped.
- **Headings** (`PageHeadings.isHeading`): the trimmed line is 1–4 words of letters, spaces and parentheses only; every word (parentheses stripped) starts with an uppercase letter; a one-word heading has at least 4 letters; not every word is a single letter. `headings(in:)` returns, per page, the heading lines in text order, leaving out any line that is a heading on more than one page (running headers).
- **Pairing**: the colour sections (`isColour`) whose `lastRow` equals a chart's `rows`, in document order, go to the charts of that height in reading order, k-th to k-th. A chart with no section left is unpaired (its check has no rows).
- **Written pieces**: every section not paired to a chart, in document order, parsed as above; a section whose parse yields no entry is not offered.
- **Titles**: for each page, the k-th heading titles the k-th section that *starts* on that page (a section starts on the page of its first block). A chart piece takes its paired section's title; an unpaired chart is `Chart <n> (page <p>)` (n counts charts from 1). A written piece with no heading is `Rows, page <p>, R 1–<last>` (en dash).
- **Order**: pieces sorted by their first page, then (on one page) charts before written pieces, then document/reading order.
- **Assembly**: the pages after the first page any piece uses that no piece uses, as one step per run of consecutive pages, titled `Page <n>` or `Pages <a>–<b>`; no text.
- **Left out**: for each parse that stopped, `text after R <n> (page <p>)`.

- [ ] **Step 1: Write the failing tests**

`WrittenPieceParserTests`:

```swift
import Testing
import GraphghanCore
import ProseReaderKit
@testable import Graphghan

@Suite struct WrittenPieceParserTests {
    static let palette: [ChartDraft.Palette] = [.init(code: "A", name: "black", hex: "#201b18"), .init(code: "B", name: "white", hex: "#ffffff")]
    static func section(_ page: String) -> RowSection { RowText.sections(in: [page])[0] }

    @Test func rangesCountsAndColoursParse() {
        let s = Self.section("R 1: (Black) ch 7, from the second stitch from the hook, 6 sc [6]\nR 2 - R 26: ch 1, turn, 6 sc [6]\nR 27 - 86: (White) ch 1, turn, 6 sc [6]")
        let p = WrittenPieceParser.parse(s, palette: Self.palette)
        #expect(p.entries == [
            .init(label: "R 1", from: 1, to: 1, text: "(Black) ch 7, from the second stitch from the hook, 6 sc [6]", count: 6, code: "A", repeatText: nil),
            .init(label: "R 2 - R 26", from: 2, to: 26, text: "ch 1, turn, 6 sc [6]", count: 6, code: nil, repeatText: nil),
            .init(label: "R 27 - 86", from: 27, to: 86, text: "(White) ch 1, turn, 6 sc [6]", count: 6, code: "B", repeatText: nil),
        ])
        #expect(p.pages == [1] && p.stoppedAtPage == nil && p.stoppedAfterRow == nil)
    }

    @Test func aHeadThatGoesBackwardsStopsTheParse() {
        let s = Self.section("R 1: 6 sc [6]\nR 2 - R 4: ch 1, turn, 6 sc [6]\nsew around the head to R 8. Later, add a zipper")
        let p = WrittenPieceParser.parse(s, palette: [])
        #expect(p.entries.map(\.to) == [1, 4] && p.stoppedAtPage == 1 && p.stoppedAfterRow == 4)
    }

    @Test func aColourTheKeyDoesNotNameHasNoCode() {
        let p = WrittenPieceParser.parse(Self.section("R 1: (Pink) 3 sc [3]"), palette: Self.palette)
        #expect(p.entries[0].code == nil && p.entries[0].count == 3)
    }
}
```

`FoundOutlineTests` — synthetic pages mimicking Orca's shape:

```swift
import Testing
import GraphghanCore
import ProseReaderKit
@testable import Graphghan

@Suite struct FoundOutlineTests {
    static let pages = [
        "Materials\nhook",                                                               // 1
        "Front Back",                                                                    // 2: both charts
        "R 1: (Black) ch 7, 6 sc [6]\nR 2 - R 10: ch 1, turn, 6 sc [6]\nSide Panel",      // 3: 10 rows, so no 4-row chart pairs with it
        "R 1: ch 3, 2 sc [2]\nR 2: ch 1, turn, 2 sc [2]\nR 1: ch 2, 1 inc [2]\nR 2: ch 1, turn, 2 sc [2]\nDorsal Fin\nPectoral Fin (Front)", // 4
        "Sew the fins on",                                                               // 5
        "Lining and zipper",                                                             // 6
        "Front Panel\n" + (1...4).map { "R \($0): (Black) \($0) sc, (White) 1 sc [\($0 + 1)]" }.joined(separator: "\n"), // 7
        "Back Panel\n" + (1...4).map { "R \($0): (Black) \($0) sc, (White) 1 sc [\($0 + 1)]" }.joined(separator: "\n"),  // 8
    ]
    static let charts = [FoundChart(page: 2, x0: 100, cols: 5, rows: 4), FoundChart(page: 2, x0: 900, cols: 5, rows: 4)]
    static let palette: [ChartDraft.Palette] = [.init(code: "A", name: "black", hex: "#201b18"), .init(code: "B", name: "white", hex: "#ffffff")]
    static func outline() async -> PatternOutline {
        await FoundOutline().outline(pages: pages, found: FoundParts(charts: charts, sections: RowText.sections(in: pages), pageTexts: pages, palette: palette))
    }

    @Test func chartsPairWithTheirOwnRowsInOrder() async {
        let o = await Self.outline()
        let charts = o.pieces.filter { if case .chart = $0.kind { true } else { false } }
        #expect(charts.map(\.title) == ["Front Panel", "Back Panel"])
        #expect(charts.map(\.pairedSection) == [3, 4])   // sections: 0 side, 1 and 2 page 4, 3 front, 4 back
    }

    @Test func writtenPiecesTakeTheirPagesHeadingsInOrder() async {
        let o = await Self.outline()
        #expect(o.pieces.map(\.title) == ["Front Panel", "Back Panel", "Side Panel", "Dorsal Fin", "Pectoral Fin (Front)"])
        #expect(o.pieces[2].entries.map(\.to) == [1, 10])
    }

    @Test func unusedPagesAfterTheFirstPieceAreAssembly() async {
        #expect(await Self.outline().assembly == [AssemblyOutline(title: "Pages 5–6", text: nil, pages: [5, 6])])
    }

    @Test func headingsSkipProseAndRunningHeaders() {
        #expect(PageHeadings.isHeading("Pectoral Fin (Front)") && PageHeadings.isHeading("Tail") && PageHeadings.isHeading("Side Panel"))
        #expect(!PageHeadings.isHeading("Edging with sc along the side") && !PageHeadings.isHeading("C B A") && !PageHeadings.isHeading("Row 3")
                && !PageHeadings.isHeading("Sew") && !PageHeadings.isHeading("jins.crochetory"))
        #expect(PageHeadings.headings(in: ["Contents\nFront Panel", "Contents\nBack Panel"]) == [["Front Panel"], ["Back Panel"]])
    }

    @Test func aChartWithoutRowsIsNamedByPage() async {
        let o = await FoundOutline().outline(pages: ["x", "y"], found: FoundParts(charts: [FoundChart(page: 2, x0: 0, cols: 9, rows: 9)],
                                                                               sections: [], pageTexts: ["x", "y"], palette: []))
        #expect(o.pieces.map(\.title) == ["Chart 1 (page 2)"] && o.pieces[0].pairedSection == nil)
    }
}
```

(Before committing, check the sections `RowText.sections` actually produces for `pages`: if the fixture's text splits differently from the comment in `chartsPairWithTheirOwnRowsInOrder`, adjust the synthetic page text — never the rules — so the fixture reads as the comment says.)

In `PDFImportRealTests`, a text-only real test (no grid read; the two regions stand in as `FoundChart`s on page 9):

```swift
    /// The outline code finds in Orca's text (spec §7.3), with page 9's two 29 × 77 regions standing in.
    @Test func orcasOutline() async throws {
        let url = TestFixtures.root.appendingPathComponent("fixtures/import/real/EN_OrcaCrossbodyBagPDFPattern.pdf")
        guard let doc = PDFDocument(url: url) else { print("SKIP real fixture EN_OrcaCrossbodyBagPDFPattern.pdf is absent; see fixtures/import/real/README.md"); return }
        let pages = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        let found = FoundParts(charts: [FoundChart(page: 9, x0: 100, cols: 29, rows: 77), FoundChart(page: 9, x0: 1200, cols: 29, rows: 77)],
                               sections: RowText.sections(in: pages), pageTexts: pages,
                               palette: [.init(code: "A", name: "black", hex: "#201b18"), .init(code: "B", name: "white", hex: "#ffffff")])
        let o = await FoundOutline().outline(pages: pages, found: found)
        #expect(o.pieces.map(\.title) == ["Rows, page 7, R 1–2", "Front Panel", "Back Panel", "Head Tail", "Dorsal Fin", "Pectoral Fin (Front)",
                                          "Pectoral Fin (Back)", "Tail", "Rows, page 12, R 1–15"])
        #expect(o.pieces[1].pairedSection == 7 && o.pieces[2].pairedSection == 8)
        #expect(o.pieces[3].entries.map { [$0.from, $0.to ?? -1] } == [[1, 1], [2, 26], [27, 86], [87, 104]])
        #expect(o.pieces[8].entries.map { [$0.from, $0.to ?? -1] } == [[1, 1], [2, 7], [8, 15]])
        #expect(o.assembly == [AssemblyOutline(title: "Page 8", text: nil, pages: [8]), AssemblyOutline(title: "Pages 13–16", text: nil, pages: [13, 14, 15, 16])])
        #expect(o.leftOut == ["text after R 2 (page 7)", "text after R 104 (page 10)", "text after R 15 (page 12)"])
        #expect(o.pieces[8].entries[2].text == "same as")   // a known limit of code-only reading: the line's rest was split off (#200 would read it)
    }
```

These expectations are the measured facts above (with Task 1's block fix) run through the rules; if the real run differs, report the difference (with the sections' blocks) rather than bending a rule to fit — the controller rules on it.

- [ ] **Step 2: Run to verify they fail** — `mise run generate`, then `-only-testing:GraphghanTests/WrittenPieceParserTests -only-testing:GraphghanTests/FoundOutlineTests -only-testing:GraphghanTests/PDFImportRealTests` → FAIL to compile.

- [ ] **Step 3: Implement** the four files per the Interfaces and Rules. Keep each function small and pure; `FoundOutline.outline` composes `PageHeadings`, the pairing, `WrittenPieceParser` and the ordering/assembly/left-out rules. Doc comments cite spec §7 and say *why* (e.g. why parsing stops rather than skips: a rows document may not have a gap, §5.2).

- [ ] **Step 4: Run to verify** — the Step 2 command → PASS; then `mise run test`.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan/Services/Import ios/Tests
git commit -m "ios: the found outline — pair charts with their rows, parse written pieces, guess titles and assembly (#206)"
```

---

### Task 5: The importer finds every part and keeps the PDF

**Files:**
- Modify: `ios/Graphghan/Services/PDFImporter.swift`, `ios/Graphghan/AppModel.swift` (the `pdfImporter` passes `rows:` and a `pieceReader:`)
- Test: `ios/Tests/PDFImportTests.swift`, `ios/Tests/PDFImportRealTests.swift`

**Interfaces:**
- Consumes: Task 4's types and `FoundOutline`.
- Produces:
  - `PDFImporter` gains `let rows: RowsLibrary` and `let pieceReader: any PieceReading` (default `FoundOutline()` at the `AppModel` call site; tests pass their own or `FoundOutline()`).
  - `struct PiecedChart: Sendable { let found: FoundChart; let draft: ChartDraft /* with written from its paired section via writtenRows */; let preview: Data; let width: Int; let height: Int; let colours: Int }`
  - `struct PiecedReading: Sendable { let outline: PatternOutline; let charts: [PiecedChart] /* index = FoundParts.charts index */; let sections: [RowSection]; let pdf: Data }`
  - `PDFImportReading.pieced: PiecedReading?` — nil exactly when one chart and nothing else was found (then everything is as today).
  - `PDFImportReading.pdf: Data` — the source bytes (kept for every import, so a single-chart import can keep its PDF too — see Task 8).

**Behaviour:**
- `readGrid` records every region of at least `minimumGridSide` on every page with its page and `bbox.0` (`x0`), in reading order (page, then `x0`), instead of keeping only the largest; the largest still becomes `reading.draft`/`bundle` exactly as today (so every existing test and the `PDFContents` sentence are unchanged).
- It then builds `FoundParts` (the first found chart's palette, `RowText.sections(in: texts)`) and asks `pieceReader.outline`. If the outline has exactly one piece and it is a chart, and no assembly, `pieced` is nil. Otherwise it drafts every chart region (`GridChart.draft` on its page image, rendered once per page — cache page images by page index within the call), sets each draft's `written` from its paired section (`writtenRows(section, height:)`), and returns `pieced`.
- Every page is still rendered once for finding; a chart page is rendered at most once more.

- [ ] **Step 1: Write the failing tests**

Add a synthetic two-chart page to `PDFTestDocuments` (`twoCharts(rowsText:)`: two 20 × 15 grids side by side on page 1 at x origins 40 and 330 with 12 pt cells, colours as `chart`, then a page 2 with `rowsText`). Tests in `PDFImportTests`:

```swift
    @Test func aPageWithTwoChartsIsReadAsPieces() async throws {
        let rows = "Front\n" + PDFTestDocuments.colourRows.joined(separator: "\n") + "\nBack\n" + PDFTestDocuments.colourRows.joined(separator: "\n")
        let reading = try await Base.importer().read(PDFTestDocuments.twoCharts(rowsText: rows), fileName: "bag.pdf")
        let pieced = try #require(reading.pieced)
        #expect(pieced.charts.count == 2 && pieced.charts.map(\.found.page) == [1, 1] && pieced.charts[0].found.x0 < pieced.charts[1].found.x0)
        #expect(pieced.outline.pieces.map(\.title) == ["Front", "Back"])
        #expect(pieced.charts.allSatisfy { $0.draft.written?.count == 15 })
        #expect(reading.pdf.count > 0)
    }

    @Test func oneChartAndNothingElseIsReadAsToday() async throws {
        let reading = try await Base.importer().read(PDFTestDocuments.chart(rows: true), fileName: "x.pdf")
        #expect(reading.pieced == nil)
    }
```

(`Base.importer` gains the `rows:` and `pieceReader:` arguments with test defaults.) In `PDFImportRealTests`, add `orcaIsReadAsPieces`: reading the real Orca PDF gives `pieced` with two charts on page 9, both schema-3 shaped drafts of 29 × 77, the outline titles of Task 4's real test, and each chart draft's `written.count == 77`.

- [ ] **Step 2: Run to verify they fail** — `-only-testing:GraphghanTests/PDFImportTests -only-testing:GraphghanTests/PDFImportRealTests` → FAIL to compile.

- [ ] **Step 3: Implement** per Behaviour. Keep `readGrid` readable: extract `findCharts(document:progress:) -> (found: [(FoundChart, Region)], warnings)` and `draftPieced(...)`.

- [ ] **Step 4: Run to verify** — the Step 2 command → PASS, every pre-existing test in both suites unchanged; then `mise run test`.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: the PDF importer finds every chart and set of rows and asks for an outline (#206)"
```

---

### Task 6: The review list — an editable outline in the import sheet

**Files:**
- Create: `ios/Graphghan/Patterns/OutlineDraft.swift`, `ios/Graphghan/Patterns/OutlineReviewSection.swift`, `ios/Tests/OutlineDraftTests.swift`
- Modify: `ios/Graphghan/Patterns/PDFImportSheet.swift` (show the section when `reading.pieced != nil`; the found state's content goes in a `ScrollView`), `PDFImportState` (holds `var draft: OutlineDraft?`)
- Test: `ios/Tests/OutlineDraftTests.swift`, `ios/Tests/PDFImportSheetTests.swift` (snapshot of the rows)

**Interfaces:**
- Consumes: Task 4's `PatternOutline`; Task 5's `PiecedReading`.
- Produces:

```swift
struct OutlineDraft: Equatable, Sendable {
    struct Piece: Equatable, Sendable, Identifiable {
        let id: Int              // index into the outline's pieces; stable while editing
        var title: String
        var make: Int
        let isChart: Bool
        let pages: [Int]
        let rows: Int            // passes for a chart, last row for a written piece
    }
    struct Step: Equatable, Sendable, Identifiable { let id: Int; var title: String; let pages: [Int] }
    var pieces: [Piece]
    var assembly: [Step]
    init(_ outline: PatternOutline, charts: [PiecedChart])
    mutating func rename(_ id: Int, to title: String)
    mutating func remove(_ id: Int)
    mutating func move(fromOffsets: IndexSet, toOffset: Int)
    mutating func setMake(_ id: Int, _ make: Int)         // clamped to 1...20
    mutating func removeStep(_ id: Int)
    mutating func renameStep(_ id: Int, to title: String)
    /// Unique slugs in the current order, from each title ("Front Panel" → "front-panel", a repeat → "front-panel-2", empty → "piece").
    func pieceIDs() -> [Int: String]
    /// One chart, nothing else: save as today (spec §7.4, §7.5).
    var isSingleChart: Bool
}
```

**Behaviour:** The section, below the sheet's "N × M stitches, K colours", lists each piece: a `TextField` with its title, its kind ("Chart" / "Written rows"), "pages 9, 17" and "77 rows", its check line for a chart (Task 7 fills it; until then nothing), a stepper "Make × 1", a delete button; drag to reorder via `onMove` is not available outside `List`, so use up/down buttons. Then each assembly step: title field, "pages 13–16 of this PDF", delete. Then the outline's left-out sentence ("Left out: text after R 2 (page 7); text after R 104 (page 10); text after R 15 (page 12).") when non-empty. Everything in `PDFImportSheet`'s found state sits in a `ScrollView` so a long list scrolls.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct OutlineDraftTests {
    static func draft() -> OutlineDraft {
        let outline = PatternOutline(pieces: [
            PieceOutline(title: "Front Panel", kind: .chart(0), make: 1, pages: [9, 17], pairedSection: 7, entries: []),
            PieceOutline(title: "Strap", kind: .rows(1), make: 1, pages: [13], pairedSection: nil,
                         entries: [.init(label: "R 1", from: 1, to: 20, text: "6 sc", count: 6, code: nil, repeatText: nil)]),
            PieceOutline(title: "Strap", kind: .rows(2), make: 1, pages: [14], pairedSection: nil,
                         entries: [.init(label: "R 1", from: 1, to: 5, text: "6 sc", count: 6, code: nil, repeatText: nil)]),
        ], assembly: [AssemblyOutline(title: "Pages 13–16", text: nil, pages: [13, 14, 15, 16])], leftOut: [])
        return OutlineDraft(outline, charts: [])
    }

    /// Review focus 2.
    @Test func sameTitlesGetUniqueIDs() {
        #expect(Self.draft().pieceIDs() == [0: "front-panel", 1: "strap", 2: "strap-2"])
    }

    @Test func editsKeepIDsAndRespectOrder() {
        var d = Self.draft()
        d.rename(1, to: "Handle")
        d.setMake(2, 2); d.setMake(2, 0)
        d.move(fromOffsets: [2], toOffset: 0)
        #expect(d.pieces.map(\.id) == [2, 0, 1] && d.pieces[0].make == 1 && d.pieces[2].title == "Handle")
        d.remove(0)
        #expect(d.pieces.map(\.id) == [0, 1])
    }

    @Test func oneChartAloneIsSingle() {
        var d = Self.draft()
        #expect(!d.isSingleChart)
        d.remove(1); d.remove(2); d.removeStep(0)
        #expect(d.isSingleChart)
    }
}
```

`charts: []` above means the draft's `rows` for the chart piece falls back to 0; give `init` that fallback. Add to `PDFImportSheetTests` a snapshot `pdf-import-review-rows` of `OutlineReviewSection`'s rows (in a `VStack`, as `project-pieces-rows` does) for the draft above; Read the PNG.

- [ ] **Step 2: Run to verify they fail** — `mise run generate`, `-only-testing:GraphghanTests/OutlineDraftTests -only-testing:GraphghanTests/PDFImportSheetTests` → FAIL to compile.

- [ ] **Step 3: Implement** per Interfaces and Behaviour. `slug(_:)` reuses `PDFImporter.slug` (the existing title → slug function) if it produces lowercase-hyphen slugs matching `^[a-z0-9-]+$`; otherwise write one in `OutlineDraft`.

- [ ] **Step 4: Run to verify** — the Step 2 command twice (the new snapshot records then compares); every existing sheet snapshot compares unchanged; then `mise run test`.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: the import sheet lists the pieces it found, to rename, remove, reorder and make more than once (#206)"
```

---

### Task 7: Checks, one per chart piece

**Files:**
- Modify: `ios/Graphghan/Services/PDFImporter.swift` (`check` gains a piece form), `ios/Graphghan/AppModel.swift` (`startPDFCheck`, `skipPDFCheck`), `PDFImportSheet.swift`/`PDFImportState` (per-piece check stages), `OutlineReviewSection.swift` (the check line per chart piece)
- Test: `ios/Tests/PDFImportTests.swift`, `ios/Tests/PDFImportSheetTests.swift`

**Interfaces:**
- Consumes: Task 5's `PiecedReading` (`charts[i].draft`, `outline.pieces[*].pairedSection`, `sections`); Task 6's `OutlineDraft`.
- Produces:
  - `PDFImporter.check(chart: PiecedChart, section: RowSection?, pageTexts: [String], progress:) async -> ImportRecord` — today's `check` body with the section and chart passed in (`check(_ reading:progress:)` becomes a thin wrapper that passes today's section and `charts[0]`, so its behaviour and tests are unchanged).
  - `PDFImportState.pieceChecks: [Int: PDFImportState.CheckStage]` keyed by chart index (`FoundParts.charts` index).

**Behaviour:** For a pieced reading, `startPDFCheck` checks each chart piece that has a paired section, one after another in outline order, in one task: before each, the sheet shows "Checking <title>: written row x of y…"; each finished record goes into `pieceChecks[chart]`. "Skip the check" cancels the running piece's read (it is saved as stopped, as today) and the pieces not yet checked (saved with `.noRows`-like "not checked" — reuse the record the single-chart path saves when Skip lands before a read starts). The per-piece line in the review list is the record's existing `sentence` (or "Written rows agree with the chart." when finished clean), the same words the single-chart sheet shows.

- [ ] **Step 1: Write the failing tests**

In `PDFImportTests`: `eachChartPieceIsCheckedAgainstItsOwnRows` — a `StubRowReader` that records the sections it was asked (the existing `Asked` actor); read the two-chart synthetic PDF and run the pieced checks: the reader was asked twice, each time with a 15-row section, the first section's first block from the "Front" run and the second from the "Back" run.

In `PDFImportSheetTests` (Review Focus 3): `skippingTheSecondPiecesCheckKeepsTheFirst` — with a slow stub reader (`delayPerRow`), wait until the second piece's check is running, call `skipPDFCheck()`, then `addImportedPDF()`: the first chart's saved `ext.graphghan.import` is `finished`, the second's is `stopped`, and the pattern is in the library.

- [ ] **Step 2: Run to verify they fail**, **Step 3: implement**, **Step 4: run** `-only-testing:GraphghanTests/PDFImportTests -only-testing:GraphghanTests/PDFImportSheetTests` → PASS with every existing test unchanged, then `mise run test`.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: each chart piece of a PDF is checked against its own written rows (#206)"
```

---

### Task 8: Saving a pieced pattern, with its PDF

**Files:**
- Modify: `ios/Graphghan/Services/PDFImporter.swift` (`savePieced`), `ios/Graphghan/Storage/LocalPatternStore.swift` (`save(_:sourcePDF:)`, `sourcePDF(for:)`), `ios/Graphghan/AppModel.swift` (`addImportedPDF` routes a pieced reading to `savePieced`)
- Test: `ios/Tests/PDFImportTests.swift`, `ios/Tests/LocalPatternStoreTests.swift`

**Interfaces:**
- Consumes: Task 3's `RowsWriter`, `ManifestWriter.encodePieced`, `PieceEntry`, `AssemblyEntry`, `ManifestChartInput`; Task 5's `PiecedReading`; Task 6's `OutlineDraft`; Task 7's per-chart records.
- Produces:
  - `LocalPatternStore.save(_ bundle: PatternBundle, sourcePDF: Data? = nil) throws` — writes `source.pdf` into the same staging directory before the atomic move (so it lands or nothing does); existing callers unchanged.
  - `LocalPatternStore.sourcePDF(for id: String) -> Data?`
  - `PDFImporter.savePieced(_ reading: PDFImportReading, draft: OutlineDraft, records: [Int: ImportRecord]) async throws -> PatternManifest`

**Behaviour (spec §7.5):**
- If `draft.isSingleChart`, save exactly as today's `save(reading, record:)` for that chart (its own draft, not necessarily the largest: build the single-chart bundle from the kept chart's `PiecedChart.draft`), passing `sourcePDF: reading.pdf`.
- Otherwise, in the draft's order, with ids from `draft.pieceIDs()`:
  1. For each chart piece: its `ChartDraft` with `ext` = its record's JSON (as `save` does today), `ChartWriter.encode`, `Chart.load` (throws → refuse), `ChartPreview.png`; variant = the piece id, gauge key = `draft.gauge.stitch ?? "sc"`.
  2. For each written piece: `RowsWriter.encode(title:palette:entries:pages:)` with the palette entries its `code`s use, then `RowsDocument.load` (throws → refuse).
  3. `ManifestWriter.encodePieced(…)` with `pieces` (`PieceEntry` per piece, `rows: "pieces/<id>.rows.json"`), `assembly` (the draft's steps), palette = the first chart's; decode it as `PatternManifest`.
  4. Only when all of that succeeded: store every chart in `ChartLibrary`, every rows document in `RowsLibrary`, then `local.save(bundle, sourcePDF: reading.pdf)` with `bundle` = `PatternBundle(manifest:manifestData:charts:previews:rows:)` whose previews are `preview.png` (the first chart's) and each chart's preview path.
- A single-chart import through today's `save` also keeps its PDF (pass `sourcePDF: reading.pdf`): the spec keeps the PDF with every local pattern made from one.

- [ ] **Step 1: Write the failing tests**

In `PDFImportTests`:
- `aPiecedImportSavesManifest2WithItsPDF` — read the two-chart synthetic PDF with written pieces on further pages (add a page with `"Strap\nR 1: 6 sc [6]\nR 2 - R 10: ch 1, turn, 6 sc [6]"`), build the draft, `savePieced`: the local manifest is schema 2 with pieces `["front", "back", "strap"]`, both charts and the rows document are in their libraries, `local.sourcePDF(for:)` equals the input bytes.
- Review Focus 1: `removingAllButOneChartSavesAsToday` — remove every piece but the first chart and every step: the saved manifest is schema 1 with one chart.
- Review Focus 4: `aFailedPiecedSaveWritesNothing` — make one written piece invalid (a draft whose entries start at row 2, built by editing the outline before drafting) and `savePieced` throws; `ChartLibrary`, `RowsLibrary` and the local store's directory are empty.

In `LocalPatternStoreTests`: `aSourcePDFIsSavedBesideThePatternAndGoesWithIt` — `save(bundle, sourcePDF:)` then `sourcePDF(for:)` returns it; saving the same id again without a PDF removes the old one (the directory is replaced whole).

- [ ] **Step 2–4:** run → FAIL, implement, run `-only-testing:GraphghanTests/PDFImportTests -only-testing:GraphghanTests/LocalPatternStoreTests -only-testing:GraphghanTests/PDFImportSheetTests` → PASS (existing tests unchanged), then `mise run test`.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: save a pieced PDF as one manifest-2 pattern, its PDF kept beside it (#206)"
```

---

### Task 9: Assembly pages open the kept PDF

**Files:**
- Create: `ios/Graphghan/UI/PDFPageView.swift` (a `UIViewRepresentable` over PDFKit's `PDFView`, opened at a page)
- Modify: `ios/Graphghan/Projects/PieceListSection.swift` (`AssemblyStepRow`: a "Open page N" button when the PDF is on this phone), `ios/Graphghan/Projects/ProjectDetailView.swift` (loads whether the PDF exists; presents the viewer sheet), `ios/Graphghan/AppModel.swift` (`func sourcePDF(for patternID:) async -> Data?`)
- Test: `ios/Tests/ProjectDetailViewTests.swift`, `ios/Tests/LocalPatternStoreTests.swift`

**Interfaces:**
- Produces: `struct PDFPageView: UIViewRepresentable { let data: Data; let page: Int /* 1-based */ }`; `AssemblyStepRow` gains `onOpenPage: ((Int) -> Void)?` — nil keeps today's "page 15 of the original PDF" text; non-nil shows a button "Open page 15" (or "Open pages 13–16", opening the first).

**Behaviour:** A pieced project whose pattern has a kept PDF shows the button; tapping it presents a sheet with `PDFPageView` at the step's first page and a Done button. A bundle opened on another phone (no PDF) shows the text as today.

- [ ] **Step 1: Write the failing tests**

- `ProjectDetailViewTests.aStepOpensThePDFWhenItIsKept` — `AssemblyStepRow.pageAction(pages: [13, 14, 15, 16], hasPDF: true) == "Open pages 13–16"`, `pageAction(pages: [15], hasPDF: true) == "Open page 15"`, and `pageAction(pages: [15], hasPDF: false) == nil` (a static helper the row uses).
- Review Focus 5: `LocalPatternStoreTests.eachImportKeepsItsOwnPDF` — save two patterns with different ids and PDFs; each `sourcePDF(for:)` returns its own; deleting one pattern directory (the store's existing removal path, or `FileManager` if the store has none — check `AppModel`'s delete of a local pattern) leaves the other's PDF.
- A snapshot `project-assembly-open` of an `AssemblyStepRow` with the button, in a `VStack`; Read the PNG.

- [ ] **Step 2–4:** run → FAIL, implement, run `-only-testing:GraphghanTests/ProjectDetailViewTests -only-testing:GraphghanTests/LocalPatternStoreTests` twice (snapshot), then `mise run test`.

- [ ] **Step 5: Commit**

```bash
git add ios/Graphghan ios/Tests
git commit -m "ios: an assembly step opens the kept PDF at its page (#206)"
```

---

### Task 10: Orca end to end, verify, and the PR

**Files:**
- Modify: `ios/Tests/PDFImportRealTests.swift`, `docs/superpowers/specs/2026-09-25-pieces-and-shaped-rows-design.md` (§10: record the Orca result)

- [ ] **Step 1: The real end-to-end test**

`orcaImportsAsAPiecedPattern` in `PDFImportRealTests` (skips when absent): read the Orca PDF with `rowReader: nil`; build `OutlineDraft`; remove the page-7 example piece (`"Rows, page 7, R 1–2"`) and the `"Page 8"` assembly step; rename `"Head Tail"` to `"Side Panel"` and `"Rows, page 12, R 1–15"` to `"Tail (Black)"`; `savePieced` with no records. Assert: manifest schema 2; pieces `["front-panel", "back-panel", "side-panel", "dorsal-fin", "pectoral-fin-front", "pectoral-fin-back", "tail", "tail-black"]`; two charts, both schema 3, 29 × 77, with `written.count == 77`; the side panel's rows document has 104 rows in 4 entries; assembly `["Pages 13–16"]`; `sourcePDF(for:)` is the file's bytes. Record the wall time of the read in the test output (`print`).

(If `pieceIDs()` slugs "Pectoral Fin (Front)" differently, e.g. keeping the parentheses' content as "pectoral-fin-front", use what Task 6's slug rule produces and say so in the report.)

- [ ] **Step 2: Record the result in the spec**

Under §10's Orca bullet, add a dated sentence with what the test shows (the pieces offered, what the maker had to rename or remove, the read time on the simulator) and that the device run is still to do. Keep the spec's voice.

- [ ] **Step 3: Verify everything**

From the repo root: `uv run pytest -q`, `mise run lint`. From `ios/`: `mise run core-test`, `mise run prose-test`, `mise run test` (capture exit status). All green; no existing snapshot reference changed (`git diff origin/main --stat -- ios/Tests/__Snapshots__` lists only added PNGs).

- [ ] **Step 4: Commit, push, open the PR**

```bash
git add ios/Tests/PDFImportRealTests.swift docs/superpowers/specs/2026-09-25-pieces-and-shaped-rows-design.md
git commit -m "ios: Orca imports as a pieced pattern; record it in the spec (#206)"
git push -u origin HEAD
```

PR title "Pieced PDF import: charts, written pieces, assembly and the kept PDF (#206)". Body: "Closes #206, #222, #224. PR 3 of `docs/superpowers/specs/2026-09-25-pieces-and-shaped-rows-design.md` §8." then What changes (found parts and the outline behind `PieceReading`; the review list; a check per chart piece; saving manifest 2 with `source.pdf`; assembly pages opening it; #222; #224), Tests (each suite's real numbers, the new snapshots, the Orca result), Follow-ons (#211 numbered-step pieces such as the strap, #212 split/merge/add in the review list, #200 a server reader behind `PieceReading`, #223). End with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 5: See it to green**

Bounded watcher (at most 25 minutes, `gh pr checks <n>` every 30 s, stop when nothing is pending); fix every valid CodeRabbit finding with a failing-first test; when the re-review is rate-limited and the fix is verified, reply on each comment and dismiss the stale review naming the fixing commit.

# Phone PDF import, PR 1: the type and the exact reader — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A PDF that `graphghan export --format pdf` wrote opens from Files, Mail or AirDrop into the library with the same chart id the Mac computed, through an import sheet; every other PDF gets one honest sentence.

**Architecture:** `GraphghanCore` gains the pieces that need no UI and no PDFKit: `OwnPDFReader` (the text-layer grammar of our own PDFs, a port of `pdfself.py`), `ChartWriter` and `ManifestWriter` (the JSON the library stores, canonical so the id matches Python's), and `ChartPreview` (the preview PNG). The app gains `PDFImporter` (PDFKit in, `PatternBundle` out, then the bundle importer's atomic order), the document type, an `@Observable` `PDFImportState` and a sheet over it, and one branch in `AppModel` that routes a `.pdf` to it.

**Tech Stack:** Swift 6, SwiftUI, PDFKit (app and core tests only), CoreGraphics + ImageIO for the PNG, Swift Testing, XcodeGen (`ios/project.yml`).

**Spec:** `docs/superpowers/specs/2026-09-20-phone-pdf-import-design.md` (§4.1, §5, §6.1, §8 item 1, §9)

## Global Constraints

- Deployment target stays iOS 17.0 (spec §2); nothing in this PR touches a model.
- Nothing is written unless the whole chart validates through `Chart.load` (spec §2); the order is `PatternBundle` in memory → `ChartLibrary.store` → `LocalPatternStore.save` (bundle design §6.2).
- A PDF over 20 MB is refused before it is read (spec §5.1).
- Every failure is one of the fixed sentences in spec §5.4, never a raw error.
- The chart id of an imported own PDF equals the id in `fixtures/bundle/craigh-na-dun.graphghan` for the same chart (spec §11).
- `GraphghanCore` does not import PDFKit in its sources; PDFKit is used by the app and by the core *tests* to turn the fixture PDFs into page texts.
- `mise run check` before every commit; Blink on the branch before the PR.
- Branch: `tylervick/phone-import` (holds the spec); commits go there.

---

### Task 1: `OwnPDFReader` — the text-layer grammar of our own PDFs

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/OwnPDFReader.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/OwnPDFReaderTests.swift`
- Modify: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/Fixtures.swift` (add `importPDF(_:)`)

**Interfaces:**
- Produces: `public struct OwnPDFReading { pattern: OwnPDFReader.PatternInfo; gauge: OwnPDFReader.Gauge?; finishedSize: OwnPDFReader.FinishedSize?; palette: [OwnPDFReader.KeyEntry]; width: Int; height: Int; rows: [OwnPDFReader.WrittenRow] }`, `public enum OwnPDFReader { static func isOwn(pageTexts: [String]) -> Bool; static func read(pageTexts: [String], title: String) throws -> OwnPDFReading }`, `public enum OwnPDFError: Error, Equatable { case noChartHeader, badRow(page: Int, text: String), rowsDoNotMatch(String) }`.

- [ ] **Step 1: Add the fixture helper**

In `Fixtures.swift`, beside `bundle(_:)`:

```swift
    /// `fixtures/import/<name>.pdf`, written by `graphghan export --format pdf` (the round-trip
    /// fixtures of the import spec §7.1).
    static func importPDF(_ name: String) -> URL {
        root.appendingPathComponent("fixtures/import/\(name).pdf")
    }
```

- [ ] **Step 2: Write the failing tests**

`OwnPDFReaderTests.swift`:

```swift
import Foundation
import PDFKit
import Testing
@testable import GraphghanCore

/// Our own PDFs read exactly from their text layer (phone import spec §4.1), against the two
/// committed round-trip fixtures. PDFKit here is the test's way to get page texts; the reader
/// itself never sees a PDF.
@Suite struct OwnPDFReaderTests {
    static func texts(_ name: String) throws -> (texts: [String], title: String) {
        let doc = try #require(PDFDocument(url: Fixtures.importPDF(name)))
        let texts = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        return (texts, title)
    }

    @Test func recognisesItsOwnCoverAndNothingElse() throws {
        let (texts, _) = try Self.texts("craigh-na-dun-final-sc")
        #expect(OwnPDFReader.isOwn(pageTexts: texts))
        #expect(!OwnPDFReader.isOwn(pageTexts: ["Row 1: 3 A, 4 B", "Key\nA red"]))
        #expect(!OwnPDFReader.isOwn(pageTexts: []))
    }

    @Test func readsTheCoverKeyChartHeadersAndRows() throws {
        let (texts, title) = try Self.texts("craigh-na-dun-final-sc")
        let r = try OwnPDFReader.read(pageTexts: texts, title: title)
        #expect(r.pattern.title == "Craigh na Dun Blanket")
        #expect(r.pattern.author == "Tyler Vick" && r.pattern.license == "CC-BY-NC-SA-4.0" && r.pattern.version == "1.0.0")
        #expect(r.pattern.dedication == "For Meaghan")
        #expect(r.pattern.quote == "Lord, you gave me a rare woman, and God! I loved her well.")
        #expect(r.gauge?.stitches == 14 && r.gauge?.rows == 16 && r.gauge?.over.value == 4 && r.gauge?.over.unit == "in")
        #expect(r.gauge?.hook == "5 mm (US H-8)" && r.gauge?.yarnWeight == "worsted (#4)" && r.gauge?.stitchName == "single crochet")
        #expect(r.gauge?.chain == 1)
        #expect(r.finishedSize?.width == 54 && r.finishedSize?.height == 46 && r.finishedSize?.unit == "in")
        #expect(r.width == 189 && r.height == 184)
        #expect(r.palette.map(\.code) == ["C", "K", "G", "P", "Y"])
        #expect(r.palette[0].name == "Cream" && r.palette[0].hex == "#f2e8d5" && r.palette[0].yarnNote == "Aran / off-white")
        #expect(r.rows.count == 184 && r.rows.first?.row == 1 && r.rows.last?.row == 184)
        #expect(r.rows[0].runs.map { "\($0.count)\($0.code)" } == ["189Y"])
        #expect(r.rows.allSatisfy { row in row.runs.reduce(0) { $0 + $1.count } == row.total && row.total == 189 })
    }

    @Test func theHdcFixtureReadsToo() throws {
        let (texts, title) = try Self.texts("craigh-na-dun-final-hdc")
        let r = try OwnPDFReader.read(pageTexts: texts, title: title)
        #expect(r.width == 189 && r.rows.count == r.height && r.gauge?.stitchName == "half double crochet")
    }

    @Test func aRowItCannotReadNamesThePageAndTheText() throws {
        var (texts, title) = try Self.texts("craigh-na-dun-final-sc")
        let page = try #require(texts.firstIndex { $0.hasPrefix("Written rows") })
        texts[page] = texts[page].replacingOccurrences(of: "Row 1 (RS): 189 Y (189 sts)", with: "Row 1 (RS): 189 Y and a bit (189 sts)")
        #expect(throws: OwnPDFError.badRow(page: page + 1, text: "Row 1 (RS): 189 Y and a bit (189 sts)")) {
            try OwnPDFReader.read(pageTexts: texts, title: title)
        }
    }

    @Test func aMissingChartHeaderIsRefused() throws {
        let (texts, title) = try Self.texts("craigh-na-dun-final-sc")
        let stripped = texts.map { $0.hasPrefix("Chart ") ? "" : $0 }
        #expect(throws: OwnPDFError.noChartHeader) { try OwnPDFReader.read(pageTexts: stripped, title: title) }
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter OwnPDFReaderTests 2>&1 | tail -5`
Expected: compile errors, `OwnPDFReader` undefined.

- [ ] **Step 4: Write the reader**

`OwnPDFReader.swift`. The grammar is `graphghan/pdf.py`'s, byte for byte: `KEY_ROW` is "`{code}  {name}  {hex}  {yarn}`" (two spaces, which PDFKit gives back as one or two; the regex allows either), `CHART_HEADER` is "Chart k of n: columns a-b of W, rows c-d of H", a written row is "Row N (RS): [ch 1, turn, ]189 Y, 3 G (189 sts)". Page texts arrive with `\r\n` or `\n` line ends; both are split.

```swift
import Foundation

/// What a graphghan-made PDF says about itself (phone import spec §4.1): a port of `pdfself.py`.
/// The text layer is in the grammars `graphghan/pdf.py` fixes, so the model's job is done here by
/// regular expressions and the result is exact.
public struct OwnPDFReading: Sendable, Equatable {
    public let pattern: OwnPDFReader.PatternInfo
    public let gauge: OwnPDFReader.Gauge?
    public let finishedSize: OwnPDFReader.FinishedSize?
    public let palette: [OwnPDFReader.KeyEntry]
    public let width: Int
    public let height: Int
    /// Row 1 first, every row present once, checked by `read`.
    public let rows: [OwnPDFReader.WrittenRow]
}

public enum OwnPDFError: Error, Equatable {
    case noChartHeader
    case badRow(page: Int, text: String)
    case rowsDoNotMatch(String)
}

public enum OwnPDFReader {
    public struct PatternInfo: Sendable, Equatable {
        public var title: String
        public var version: String = "0.1.0"
        public var author: String? = nil
        public var license: String? = nil
        public var dedication: String? = nil
        public var quote: String? = nil
        public var terms: String? = nil
    }
    public struct Gauge: Sendable, Equatable {
        public struct Over: Sendable, Equatable { public let value: Double; public let unit: String }
        public var stitches: Double
        public var rows: Double
        public var over: Over
        public var hook: String? = nil
        public var yarnWeight: String? = nil
        public var stitchName: String? = nil
        /// The turning chain the rows print ("ch 1, turn"), nil when the rows print none.
        public var chain: Int? = nil
    }
    public struct FinishedSize: Sendable, Equatable { public let width: Double; public let height: Double; public let unit: String }
    public struct KeyEntry: Sendable, Equatable { public let code: String; public let name: String; public let hex: String; public let yarnNote: String? }
    public struct Run: Sendable, Equatable { public let code: String; public let count: Int }
    public struct WrittenRow: Sendable, Equatable { public let row: Int; public let side: String; public let page: Int; public let runs: [Run]; public let total: Int }

    static let keyTitle = "Key"
    static let rowsTitle = "Written rows"
    static let metaRe = try! NSRegularExpression(pattern: #"^(?:(.+?) - )?(?:([A-Za-z0-9.+-]+) - )?version (\S+)$"#)
    static let gaugeRe = try! NSRegularExpression(pattern: #"^Gauge: ([\d.]+) sts and ([\d.]+) rows = ([\d.]+) (in|cm)(?: \((.*)\))?$"#)
    static let sizeRe = try! NSRegularExpression(pattern: #"^Finished size: ([\d.]+) x ([\d.]+) (in|cm)$"#)
    static let keyRe = try! NSRegularExpression(pattern: #"^([A-Za-z]{1,3}) +(.+?) +(#[0-9a-fA-F]{6})(?: +(.*))?$"#)
    static let headerRe = try! NSRegularExpression(pattern: #"^Chart (\d+) of (\d+): columns (\d+)-(\d+) of (\d+), rows (\d+)-(\d+) of (\d+)"#)
    static let rowRe = try! NSRegularExpression(pattern: #"^Row (\d+) \((RS|WS)\): (?:ch (\d+), turn, |turn, )?(.*?) ?\((\d+) sts\)$"#)
    static let runRe = try! NSRegularExpression(pattern: #"^(\d+) ([A-Za-z]{1,3})$"#)

    static func lines(_ text: String) -> [String] {
        text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    static func groups(_ re: NSRegularExpression, _ s: String) -> [String?]? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } }
    }

    /// A cover in our grammar: a "Materials" heading and a "Gauge:" line on the first page, and a
    /// chart header on some page. Anything else is not ours, whatever it looks like.
    public static func isOwn(pageTexts: [String]) -> Bool {
        guard let first = pageTexts.first else { return false }
        let l = lines(first)
        return l.contains("Materials") && l.contains { $0.hasPrefix("Gauge: ") }
            && pageTexts.contains { groups(headerRe, lines($0).first ?? "") != nil }
    }

    public static func read(pageTexts: [String], title: String) throws -> OwnPDFReading {
        var (pattern, gauge, size) = cover(pageTexts.first ?? "", title: title)
        let palette = key(pageTexts)
        var width: Int? = nil, height: Int? = nil
        for text in pageTexts {
            if let g = groups(headerRe, lines(text).first ?? ""), let w = Int(g[4] ?? ""), let h = Int(g[7] ?? "") {
                width = w; height = h
            }
        }
        guard let width, let height else { throw OwnPDFError.noChartHeader }
        let (rows, chain) = try writtenRows(pageTexts, title: title)
        if let chain, gauge != nil { gauge?.chain = chain }
        guard rows.count == height, rows.enumerated().allSatisfy({ $0.element.row == $0.offset + 1 }) else {
            throw OwnPDFError.rowsDoNotMatch("\(rows.count) written rows for a chart of \(height)")
        }
        if let bad = rows.first(where: { $0.total != width || $0.runs.reduce(0, { $0 + $1.count }) != width }) {
            throw OwnPDFError.rowsDoNotMatch("row \(bad.row) does not sum to \(width)")
        }
        _ = pattern.title  // silence the var warning when nothing on the cover changes it
        return OwnPDFReading(pattern: pattern, gauge: gauge, finishedSize: size, palette: palette, width: width, height: height, rows: rows)
    }

    static func number(_ s: String?) -> Double? { s.flatMap(Double.init) }

    static func cover(_ text: String, title: String) -> (PatternInfo, Gauge?, FinishedSize?) {
        let l = lines(text).filter { !$0.isEmpty }
        var pattern = PatternInfo(title: title)
        var gauge: Gauge? = nil
        var hook: String? = nil, yarn: String? = nil, size: FinishedSize? = nil
        var i = (l.first == title) ? 1 : 0
        // dedication, quote and the author line sit between the title and the Materials heading
        while i < l.count, l[i] != "Materials" {
            let ln = l[i]
            if let g = groups(metaRe, ln), (g[0] != nil || g[1] != nil || ln.contains("version")) {
                pattern.author = g[0]; pattern.license = g[1]; pattern.version = g[2] ?? pattern.version
            } else if ln.hasPrefix("\""), ln.hasSuffix("\""), ln.count >= 2 {
                pattern.quote = String(ln.dropFirst().dropLast())
            } else if pattern.dedication == nil {
                pattern.dedication = ln
            }
            i += 1
        }
        for ln in l[i...] {
            if ln.hasPrefix("Yarn: ") { yarn = String(ln.dropFirst(6)) }
            else if ln.hasPrefix("Hook: ") { hook = String(ln.dropFirst(6)) }
            else if let g = groups(gaugeRe, ln), let st = number(g[0]), let rows = number(g[1]), let over = number(g[2]), let unit = g[3] {
                gauge = Gauge(stitches: st, rows: rows, over: .init(value: over, unit: unit))
                for d in (g[4] ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !d.isEmpty {
                    if d.hasSuffix(" terms") { pattern.terms = String(d.dropLast(6)) } else { gauge?.stitchName = d }
                }
            } else if let g = groups(sizeRe, ln), let w = number(g[0]), let h = number(g[1]), let unit = g[2] {
                size = FinishedSize(width: w, height: h, unit: unit)
            } else if ln == "Colours" { break }
        }
        gauge?.hook = hook; gauge?.yarnWeight = yarn
        return (pattern, gauge, size)
    }

    static func key(_ texts: [String]) -> [KeyEntry] {
        var out: [KeyEntry] = []
        for text in texts {
            let l = lines(text)
            guard l.first == keyTitle else { continue }
            for ln in l.dropFirst() {
                guard let g = groups(keyRe, ln), let code = g[0], let name = g[1], let hex = g[2] else { continue }
                out.append(KeyEntry(code: code, name: name, hex: hex.lowercased(), yarnNote: g[3]))
            }
        }
        return out
    }

    /// Written rows from the rows pages: wrapped lines rejoined, footers skipped, in page order.
    static func writtenRows(_ texts: [String], title: String) throws -> ([WrittenRow], Int?) {
        let footer = try NSRegularExpression(pattern: "^" + NSRegularExpression.escapedPattern(for: title) + #" Page \d+$"#)
        var rows: [WrittenRow] = []
        var chain: Int? = nil
        var started = false
        for (index, text) in texts.enumerated() {
            let page = index + 1
            var l = lines(text)
            if !started {
                guard l.first == rowsTitle else { continue }
                started = true; l = Array(l.dropFirst())
            } else if !(l.first ?? "").hasPrefix("Row ") {
                break  // a page after the rows that is not rows
            }
            var joined: [String] = []
            for ln in l where !ln.isEmpty && footer.firstMatch(in: ln, range: NSRange(ln.startIndex..., in: ln)) == nil {
                if ln.hasPrefix("Row "), ln.range(of: #"^Row \d+ \((RS|WS)\):"#, options: .regularExpression) != nil { joined.append(ln) }
                else if !joined.isEmpty { joined[joined.count - 1] += " " + ln }
            }
            for ln in joined {
                guard let g = groups(rowRe, ln), let row = Int(g[0] ?? ""), let side = g[1], let total = Int(g[4] ?? "") else {
                    throw OwnPDFError.badRow(page: page, text: ln)
                }
                var runs: [Run] = []
                for part in (g[3] ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                    guard let r = groups(runRe, part), let n = Int(r[0] ?? ""), let code = r[1] else { throw OwnPDFError.badRow(page: page, text: ln) }
                    runs.append(Run(code: code, count: n))
                }
                rows.append(WrittenRow(row: row, side: side, page: page, runs: runs, total: total))
                if chain == nil, let c = g[2], let n = Int(c) { chain = n }
            }
        }
        return (rows, chain)
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `cd ios/Packages/GraphghanCore && swift test --filter OwnPDFReaderTests 2>&1 | grep -E '✘|✔ Test run|error'`
Expected: `✔ Test run with 5 tests ... passed`. If `readsTheCoverKeyChartHeadersAndRows` fails on the palette or the quote, print the first three page texts (`print(texts[0])`) and adjust only the whitespace handling: PDFKit collapses the double spaces of `KEY_ROW` on some versions, which `keyRe`'s ` +` already allows.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "ios: GraphghanCore reads our own PDF's text layer exactly (phone import §4.1)"
```

---

### Task 2: `ChartWriter` — the chart document, canonical, with Python's id

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ChartWriter.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartWriterTests.swift`

**Interfaces:**
- Consumes: `OwnPDFReading` (Task 1), `ChartID.compute`, `CanonicalJSON.encode`, `Chart.load`.
- Produces: `public struct ChartDraft { pattern: ChartDraft.Pattern; palette: [ChartDraft.Palette]; rows: [String]; width: Int; height: Int; gauge: ChartDraft.Gauge; ext: JSONValue? }` and `public enum ChartWriter { static func encode(_ draft: ChartDraft) -> (data: Data, id: String); static func draft(from: OwnPDFReading, id slug: String) -> ChartDraft; static func runString(_ runs: [(code: String, count: Int)]) -> String }`. `Chart.load(data)` on the result succeeds and `chart.id == id`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import PDFKit
import Testing
@testable import GraphghanCore

/// A chart document the phone writes decodes like one the Mac wrote and hashes to the same id
/// (phone import spec §5.3).
@Suite struct ChartWriterTests {
    static func reading(_ name: String) throws -> OwnPDFReading {
        let doc = try #require(PDFDocument(url: Fixtures.importPDF(name)))
        let texts = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        let title = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        return try OwnPDFReader.read(pageTexts: texts, title: title)
    }

    @Test func runStringsRoundTrip() {
        #expect(ChartWriter.runString([(code: "Y", count: 189)]) == "189Y")
        #expect(ChartWriter.runString([(code: "Y", count: 1), (code: "G", count: 187), (code: "Y", count: 1)]) == "1Y187G1Y")
        #expect(RunString.parse("1Y187G1Y")!.map { "\($0.count)\($0.code)" } == ["1Y", "187G", "1Y"])
    }

    @Test func theOwnPDFWritesTheChartTheMacExported() throws {
        let draft = ChartWriter.draft(from: try Self.reading("craigh-na-dun-final-sc"), id: "craigh-na-dun")
        let (data, id) = ChartWriter.encode(draft)
        let chart = try Chart.load(data)
        #expect(chart.id == id)
        #expect(id == "sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f")  // fixtures/bundle/craigh-na-dun.graphghan, charts/final-sc
        #expect(chart.width == 189 && chart.height == 184 && chart.palette.count == 5 && chart.title == "Craigh na Dun Blanket")
        #expect(chart.document.gauge.hook == "5 mm (US H-8)" && chart.document.gauge.boundary?.chain == 1)
        #expect(chart.document.pattern.author == "Tyler Vick" && chart.document.pattern.version == "1.0.0")
    }

    @Test func encodingIsCanonicalAndStable() throws {
        let draft = ChartWriter.draft(from: try Self.reading("craigh-na-dun-final-hdc"), id: "craigh-na-dun")
        let a = ChartWriter.encode(draft), b = ChartWriter.encode(draft)
        #expect(a.data == b.data && a.id == b.id)
        let text = String(decoding: a.data, as: UTF8.self)
        #expect(text.hasPrefix("{\"chart\":{") && !text.contains("\n"))
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter ChartWriterTests 2>&1 | tail -3`
Expected: compile error, `ChartWriter` undefined.

- [ ] **Step 3: Write the writer**

```swift
import Foundation

/// A chart document the phone assembles (phone import spec §5.3). Encoded with `CanonicalJSON`
/// so the bytes are the same every time and `chart.id` is the id `ChartID.compute` hashes, the
/// way the Mac computed it: codes, rows, technique and (when present) cell.
public struct ChartDraft: Sendable, Equatable {
    public struct Pattern: Sendable, Equatable {
        public var id: String
        public var title: String
        public var version: String
        public var author: String? = nil
        public var license: String? = nil
        public var dedication: String? = nil
        public var quote: String? = nil
        public init(id: String, title: String, version: String) { self.id = id; self.title = title; self.version = version }
    }
    public struct Palette: Sendable, Equatable {
        public let code: String, name: String, hex: String
        public var yarnNote: String? = nil
        public init(code: String, name: String, hex: String, yarnNote: String? = nil) { self.code = code; self.name = name; self.hex = hex; self.yarnNote = yarnNote }
    }
    public struct Gauge: Sendable, Equatable {
        public var stitches: Double = 14, rows: Double = 16, overValue: Double = 4, overUnit: String = "in"
        public var stitch: String? = nil, hook: String? = nil, yarnWeight: String? = nil, stitchName: String? = nil, terms: String? = nil
        public var chain: Int? = nil
        public init() {}
    }
    public var pattern: Pattern
    public var palette: [Palette]
    public var rows: [String]
    public var width: Int
    public var height: Int
    public var gauge: Gauge
    /// `ext.graphghan.import` and the like; nil for none. The id ignores it.
    public var ext: JSONValue? = nil
    public init(pattern: Pattern, palette: [Palette], rows: [String], width: Int, height: Int, gauge: Gauge, ext: JSONValue? = nil) {
        self.pattern = pattern; self.palette = palette; self.rows = rows; self.width = width; self.height = height; self.gauge = gauge; self.ext = ext
    }
}

public enum ChartWriter {
    /// The one technique the phone writes: rows from the bottom, RS first, right to left, turning.
    public static let techniqueRows: JSONValue = .object([
        "type": .string("rows"), "start": .string("bottom"), "first_side": .string("RS"),
        "rs_direction": .string("rtl"), "turn": .bool(true),
    ])

    public static func runString(_ runs: [(code: String, count: Int)]) -> String {
        runs.map { "\($0.count)\($0.code)" }.joined()
    }

    static func num(_ d: Double) -> JSONValue { d.rounded() == d && abs(d) < 1e15 ? .int(Int(d)) : .double(d) }

    public static func encode(_ draft: ChartDraft) -> (data: Data, id: String) {
        let codes = draft.palette.map(\.code)
        let id = ChartID.compute(codes: codes, rows: draft.rows, technique: techniqueRows, passes: nil)
        var pattern: [String: JSONValue] = ["id": .string(draft.pattern.id), "title": .string(draft.pattern.title), "version": .string(draft.pattern.version)]
        if let a = draft.pattern.author { pattern["author"] = .string(a) }
        if let l = draft.pattern.license { pattern["license"] = .string(l) }
        if let d = draft.pattern.dedication { pattern["dedication"] = .string(d) }
        if let q = draft.pattern.quote { pattern["quote"] = .string(q) }
        var gauge: [String: JSONValue] = [
            "stitches": num(draft.gauge.stitches), "rows": num(draft.gauge.rows),
            "over": .object(["value": num(draft.gauge.overValue), "unit": .string(draft.gauge.overUnit)]),
        ]
        if let s = draft.gauge.stitch { gauge["stitch"] = .string(s) }
        if let h = draft.gauge.hook { gauge["hook"] = .string(h) }
        if let y = draft.gauge.yarnWeight { gauge["yarn_weight"] = .string(y) }
        if let n = draft.gauge.stitchName { gauge["stitch_name"] = .string(n) }
        if let t = draft.gauge.terms { gauge["terms"] = .string(t) }
        if let c = draft.gauge.chain {
            gauge["boundary"] = .object(["kind": .string("turn"), "chain": .int(c), "counts_as_stitch": .bool(false), "color": .string("next")])
        }
        var doc: [String: JSONValue] = [
            "schema": .int(2),
            "pattern": .object(pattern),
            "chart": .object(["id": .string(id), "width": .int(draft.width), "height": .int(draft.height)]),
            "generator": .object(["name": .string("graphghan-ios"), "version": .string("0.1.0")]),
            "palette": .array(draft.palette.map { p in
                var e: [String: JSONValue] = ["code": .string(p.code), "name": .string(p.name), "hex": .string(p.hex)]
                if let n = p.yarnNote { e["yarn"] = .object(["note": .string(n)]) }
                return .object(e)
            }),
            "rows": .array(draft.rows.map(JSONValue.string)),
            "gauge": .object(gauge),
            "technique": techniqueRows,
        ]
        if let ext = draft.ext { doc["ext"] = ext }
        return (Data(CanonicalJSON.encode(.object(doc)).utf8), id)
    }

    /// The draft an own PDF describes (Task 1's reading), under the library id it will have.
    public static func draft(from r: OwnPDFReading, id slug: String) -> ChartDraft {
        var pattern = ChartDraft.Pattern(id: slug, title: r.pattern.title, version: r.pattern.version)
        pattern.author = r.pattern.author; pattern.license = r.pattern.license
        pattern.dedication = r.pattern.dedication; pattern.quote = r.pattern.quote
        var gauge = ChartDraft.Gauge()
        if let g = r.gauge {
            gauge.stitches = g.stitches; gauge.rows = g.rows; gauge.overValue = g.over.value; gauge.overUnit = g.over.unit
            gauge.hook = g.hook; gauge.yarnWeight = g.yarnWeight; gauge.stitchName = g.stitchName; gauge.chain = g.chain
            gauge.stitch = Self.stitchKey(for: g.stitchName)
        }
        gauge.terms = r.pattern.terms
        let rows = r.rows.map { runString($0.runs.map { (code: $0.code, count: $0.count) }) }
        return ChartDraft(pattern: pattern, palette: r.palette.map { .init(code: $0.code, name: $0.name, hex: $0.hex, yarnNote: $0.yarnNote) },
                          rows: rows, width: r.width, height: r.height, gauge: gauge)
    }

    /// "single crochet" → "sc": the stitch key the format uses, from the name the cover prints.
    static func stitchKey(for name: String?) -> String? {
        switch name {
        case "single crochet": return "sc"
        case "half double crochet": return "hdc"
        case "double crochet": return "dc"
        case "treble crochet": return "tr"
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd ios/Packages/GraphghanCore && swift test --filter ChartWriterTests 2>&1 | grep -E '✘|✔ Test run|error'`
Expected: 3 pass. If the id differs from the fixture's, compare `draft.rows` with the fixture's `rows` (unzip `fixtures/bundle/craigh-na-dun.graphghan`, `charts/final-sc/chart.json`): the codes must be in the key's order and the rows top-to-bottom as displayed, which is row 184 first — **the written rows are numbered from the bottom** (`DIRECTION`: "Row 1 starts at the bottom right"), so `draft(from:)` must reverse: `rows: r.rows.sorted { $0.row > $1.row }.map(...)`. Apply that fix in `draft(from:)` when the test says so; it will.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "ios: GraphghanCore writes a chart document canonically, with the Mac's id (phone import §5.3)"
```

---

### Task 3: `ManifestWriter` — a local pattern's `pattern.json`

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ManifestWriter.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ManifestWriterTests.swift`

**Interfaces:**
- Consumes: `ChartDraft`, `Chart` (for stats).
- Produces: `public enum ManifestWriter { static func encode(id: String, title: String, version: String, dedication: String, chart: Chart, chartID: String, variant: String, gaugeKey: String, palette: [ChartDraft.Palette]) -> Data }` whose bytes `JSONDecoder().decode(PatternManifest.self, ...)` accepts, with `charts[0].path == "charts/<variant>-<gaugeKey>/chart.json"`, `preview == "charts/<variant>-<gaugeKey>/preview.png"`, and the top-level `preview == "preview.png"`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import GraphghanCore

/// A manifest the phone writes decodes as `PatternManifest` and carries what the library shows.
@Suite struct ManifestWriterTests {
    @Test func aWrittenManifestDecodesWithTheLibrarysFields() throws {
        let draft = ChartDraft(pattern: .init(id: "orca", title: "Orca", version: "0.1.0"),
                               palette: [.init(code: "A", name: "black", hex: "#000000"), .init(code: "B", name: "white", hex: "#ffffff")],
                               rows: ["2A1B", "1A2B", "3A"], width: 3, height: 3, gauge: .init())
        let (data, id) = ChartWriter.encode(draft)
        let chart = try Chart.load(data)
        let bytes = ManifestWriter.encode(id: "orca", title: "Orca", version: "0.1.0", dedication: "Imported from Orca.pdf on 20 Sep 2026",
                                          chart: chart, chartID: id, variant: "final", gaugeKey: "sc", palette: draft.palette)
        let m = try JSONDecoder().decode(PatternManifest.self, from: bytes)
        #expect(m.schema == 1 && m.id == "orca" && m.title == "Orca" && m.version == "0.1.0" && m.preview == "preview.png")
        #expect(m.dedication == "Imported from Orca.pdf on 20 Sep 2026" && m.author == "" && m.license == "")
        #expect(m.palette.map(\.code) == ["A", "B"])
        let c = try #require(m.charts.first)
        #expect(c.id == id && c.isDefault && c.path == "charts/final-sc/chart.json" && c.preview == "charts/final-sc/preview.png")
        #expect(c.width == 3 && c.height == 3 && c.colors == 2 && c.stitches == 9 && c.stitch == "sc")
        #expect(c.changesPerRow.max == 1 && c.changesPerRow.mean == 0.7)  // rows have 1, 1, 0 changes
        #expect(c.yardsEst > 0 && c.size?.unit == "in")
        #expect(m.updated == "1980-01-01T00:00:00Z")
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter ManifestWriterTests 2>&1 | tail -3`
Expected: compile error, `ManifestWriter` undefined.

- [ ] **Step 3: Write the writer**

The numbers follow `manifest.py` and `export.py`'s `stats`: `stitches = width × height`, `colors = palette.count`, `changes_per_row` from the runs (`runs − 1` per row, mean to one decimal, max), `yards_est = Σ cells × cell_sqin × 1.1 × 1.2` with `cell_sqin` from the gauge in inches (cm ÷ 2.54), `size` = `width × over/stitches` by `height × over/rows` in the gauge's unit.

```swift
import Foundation

/// `pattern.json` (manifest schema 1) for a pattern the phone imported (phone import spec §5.3),
/// with the numbers `manifest.py` derives from a chart's stats, derived here the same way.
public enum ManifestWriter {
    public static let fixedUpdated = "1980-01-01T00:00:00Z"  // a bundle is content, not a build (bundle design §3.2)

    public static func encode(id: String, title: String, version: String, dedication: String, chart: Chart, chartID: String,
                              variant: String, gaugeKey: String, palette: [ChartDraft.Palette]) -> Data {
        let perRow = chart.runsByRow.map { max(0, $0.count - 1) }
        let mean = perRow.isEmpty ? 0.0 : (Double(perRow.reduce(0, +)) / Double(perRow.count) * 10).rounded() / 10
        let g = chart.document.gauge
        let inches = g.over.unit == "cm" ? g.over.value / 2.54 : g.over.value
        let sw = inches / g.stitches, sh = inches / g.rows
        let yards = Int((Double(chart.width * chart.height) * sw * sh * 1.1 * 1.2).rounded())
        let sizeW = Double(chart.width) * g.over.value / g.stitches, sizeH = Double(chart.height) * g.over.value / g.rows
        let dir = "charts/\(variant)-\(gaugeKey)"
        let entry: JSONValue = .object([
            "id": .string(chartID), "variant": .string(variant), "gauge_key": .string(gaugeKey), "default": .bool(true),
            "path": .string("\(dir)/chart.json"), "preview": .string("\(dir)/preview.png"),
            "width": .int(chart.width), "height": .int(chart.height),
            "size": .object(["width": .double((sizeW * 10).rounded() / 10), "height": .double((sizeH * 10).rounded() / 10), "unit": .string(g.over.unit)]),
            "stitch": .string(g.stitch ?? ""), "colors": .int(palette.count), "stitches": .int(chart.width * chart.height),
            "changes_per_row": .object(["mean": .double(mean), "max": .int(perRow.max() ?? 0)]),
            "yards_est": .int(yards),
        ])
        let manifest: JSONValue = .object([
            "schema": .int(1), "id": .string(id), "title": .string(title), "version": .string(version),
            "dedication": .string(dedication), "quote": .string(""), "author": .string(""), "license": .string(""),
            "preview": .string("preview.png"),
            "palette": .array(palette.map { .object(["code": .string($0.code), "name": .string($0.name), "hex": .string($0.hex)]) }),
            "charts": .array([entry]), "updated": .string(fixedUpdated),
        ])
        return Data(CanonicalJSON.encode(manifest).utf8)
    }
}
```

- [ ] **Step 4: Run the test**

Run: `cd ios/Packages/GraphghanCore && swift test --filter ManifestWriterTests 2>&1 | grep -E '✘|✔ Test run|error'`
Expected: pass. If `changesPerRow.mean` decodes as `0.7` but the expectation fails on floating error, compare with `abs(c.changesPerRow.mean - 0.7) < 0.001`.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "ios: GraphghanCore writes a local pattern's manifest (phone import §5.3)"
```

---

### Task 4: `ChartPreview` — the preview PNG

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/ChartPreview.swift`
- Create: `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/ChartPreviewTests.swift`

**Interfaces:**
- Consumes: `Chart` (`cells: [UInt8]` row-major top to bottom, `palette[i].hex`).
- Produces: `public enum ChartPreview { static func png(_ chart: Chart, maxSide: Int = 512) -> Data? }`: one pixel per cell scaled by nearest neighbour so the long side is at most `maxSide` and at least one pixel per cell, the fabric proportion of `chart.cellAspect` applied to rows (as `export.py`'s `preview_image` does).

- [ ] **Step 1: Write the failing test**

```swift
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GraphghanCore

@Suite struct ChartPreviewTests {
    @Test func aPreviewIsAPNGOfTheRightShape() throws {
        let draft = ChartDraft(pattern: .init(id: "t", title: "T", version: "0.1.0"),
                               palette: [.init(code: "A", name: "black", hex: "#000000"), .init(code: "B", name: "white", hex: "#ffffff")],
                               rows: ["2A1B", "3B"], width: 3, height: 2, gauge: .init())
        let chart = try Chart.load(ChartWriter.encode(draft).data)
        let png = try #require(ChartPreview.png(chart, maxSide: 300))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 300)  // the long side
        #expect(image.height == Int((Double(300) / 3 * 2 * chart.cellAspect).rounded()))
        #expect(CGImageSourceGetType(source) as String? == "public.png")
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `cd ios/Packages/GraphghanCore && swift test --filter ChartPreviewTests 2>&1 | tail -3`
Expected: compile error, `ChartPreview` undefined.

- [ ] **Step 3: Write the drawer**

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The library preview of a chart the phone imported: one pixel per cell, nearest-neighbour
/// scaled, rows at the fabric's proportion (`export.py` `preview_image`).
public enum ChartPreview {
    public static func png(_ chart: Chart, maxSide: Int = 512) -> Data? {
        let w = chart.width, h = chart.height
        guard w > 0, h > 0, chart.cells.count == w * h else { return nil }
        let rgb: [(UInt8, UInt8, UInt8)] = chart.palette.map { entry in
            let hex = entry.hex.dropFirst()
            let v = UInt32(hex, radix: 16) ?? 0
            return (UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff))
        }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let p = Int(chart.cells[i]) < rgb.count ? rgb[Int(chart.cells[i])] : (0, 0, 0)
            pixels[i * 4] = p.0; pixels[i * 4 + 1] = p.1; pixels[i * 4 + 2] = p.2; pixels[i * 4 + 3] = 255
        }
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cells = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let aspect = chart.cellAspect  // row height relative to a cell's width
        let scale = min(Double(maxSide) / Double(w), Double(maxSide) / (Double(h) * aspect))
        let outW = max(w, Int((Double(w) * max(scale, 1)).rounded()))
        let outH = max(1, Int((Double(h) * aspect * max(scale, 1)).rounded()))
        guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cells, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
```

- [ ] **Step 4: Run the test**

Run: `cd ios/Packages/GraphghanCore && swift test --filter ChartPreviewTests 2>&1 | grep -E '✘|✔ Test run|error'`
Expected: pass. If `image.height` is off by one, the test's expected value uses the same rounding as the drawer (`Int((...).rounded())`); match the drawer's formula exactly in the test rather than loosening it.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "ios: GraphghanCore draws a chart's preview PNG (phone import §5.3)"
```

---

### Task 5: `PDFImporter` — from PDF bytes to a stored pattern

**Files:**
- Create: `ios/Graphghan/Services/PDFImporter.swift`
- Create: `ios/Tests/PDFImportTests.swift`
- Modify: `ios/Tests/TestSupport.swift` (add `TestFixtures.importPDF(_:)`)

**Interfaces:**
- Consumes: `OwnPDFReader`, `ChartWriter`, `ManifestWriter`, `ChartPreview`, `ChartLibrary.store(_:)`, `LocalPatternStore.save(_:)`, `PatternBundle(manifest:manifestData:charts:previews:)`, `BundleChart(entry:chart:data:)`.
- Produces: `struct PDFImporter { let charts: ChartLibrary; let local: LocalPatternStore; static let maximumBytes = 20 << 20; func read(_ data: Data, fileName: String) async throws(PDFImportError) -> PDFImportReading; func save(_ reading: PDFImportReading) async throws -> PatternManifest }`, `struct PDFImportReading { let bundle: PatternBundle; let preview: Data; let width: Int; let height: Int; let colours: Int }`, `enum PDFImportError: Error, Equatable { case tooBig, cannotOpen, nothingFound, invalidChart(String), badRow(String); var message: String }`.

Reading is split from saving because the sheet (Task 6) shows the chart before "Add to library" saves it.

- [ ] **Step 1: Add the app fixture helper**

In `ios/Tests/TestSupport.swift` inside `TestFixtures`:

```swift
    /// `fixtures/import/<name>.pdf`, written by `graphghan export --format pdf`.
    static func importPDF(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("fixtures/import/\(name).pdf"))
    }
```

- [ ] **Step 2: Write the failing tests**

```swift
import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

/// A PDF our own exporter wrote, from bytes to a pattern in the library (phone import spec §4.1,
/// §5.3), and the sentences for what is not that (§5.4).
@MainActor
@Suite struct PDFImportTests {
    func make() async throws -> (importer: PDFImporter, charts: URL, local: URL) {
        let charts = try temporaryDirectory(), local = try temporaryDirectory()
        return (PDFImporter(charts: ChartLibrary(directory: charts), local: LocalPatternStore(directory: local)), charts, local)
    }

    @Test func ourOwnPDFReadsToTheMacsChartAndSaves() async throws {
        let (importer, chartsDir, localDir) = try await make()
        let reading = try await importer.read(try TestFixtures.importPDF("craigh-na-dun-final-sc"), fileName: "craigh-na-dun-final-sc.pdf")
        #expect(reading.width == 189 && reading.height == 184 && reading.colours == 5)
        #expect(reading.bundle.manifest.id == "craigh-na-dun-blanket" && reading.bundle.manifest.title == "Craigh na Dun Blanket")
        #expect(reading.bundle.charts.first?.chart.id == "sha256:cead3fa1e728d2f1510d0e2014641fe7b1197c3cda2c16960a4f341806a7c76f")
        #expect(reading.bundle.manifest.dedication.hasPrefix("Imported from craigh-na-dun-final-sc.pdf on "))
        #expect(!reading.preview.isEmpty)
        // Nothing is written by a read.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: chartsDir.path)) ?? []).isEmpty)
        let manifest = try await importer.save(reading)
        #expect(manifest.id == "craigh-na-dun-blanket")
        let stored = (try? FileManager.default.contentsOfDirectory(atPath: chartsDir.path)) ?? []
        #expect(stored.count == 1)
        #expect(FileManager.default.fileExists(atPath: localDir.appendingPathComponent("craigh-na-dun-blanket/pattern.json").path))
        #expect(FileManager.default.fileExists(atPath: localDir.appendingPathComponent("craigh-na-dun-blanket/charts/final-sc/preview.png").path))
        #expect(FileManager.default.fileExists(atPath: localDir.appendingPathComponent("craigh-na-dun-blanket/preview.png").path))
    }

    @Test func aFileThatIsNotAPDFCannotBeOpened() async throws {
        let (importer, _, _) = try await make()
        await #expect(throws: PDFImportError.cannotOpen) { try await importer.read(Data("hello".utf8), fileName: "x.pdf") }
        #expect(PDFImportError.cannotOpen.message == "That PDF couldn't be opened.")
    }

    @Test func aPDFThatIsNotOursReportsNothingFoundForNow() async throws {
        let (importer, _, _) = try await make()
        let pdf = try #require(PDFTestDocuments.plain(text: "Row 1: 3 A, 4 B\nRow 2: 7 A"))
        await #expect(throws: PDFImportError.nothingFound) { try await importer.read(pdf, fileName: "other.pdf") }
        #expect(PDFImportError.nothingFound.message == "No chart or written rows were found in this PDF.")
    }

    @Test func tooBigIsRefusedBeforeReading() async throws {
        let (importer, _, _) = try await make()
        let big = Data(count: PDFImporter.maximumBytes + 1)
        await #expect(throws: PDFImportError.tooBig) { try await importer.read(big, fileName: "big.pdf") }
        #expect(PDFImportError.tooBig.message == "That file is too big to be a pattern.")
    }

    @Test func theSlugComesFromTheTitleAndStaysUniqueWithinTheStore() async throws {
        let (importer, _, _) = try await make()
        let data = try TestFixtures.importPDF("craigh-na-dun-final-sc")
        let first = try await importer.read(data, fileName: "a.pdf")
        _ = try await importer.save(first)
        let second = try await importer.read(data, fileName: "b.pdf")
        #expect(second.bundle.manifest.id == "craigh-na-dun-blanket-2")
    }
}

/// A PDF made in the test from plain text, for the paths that are not ours.
enum PDFTestDocuments {
    static func plain(text: String) -> Data? {
        let page = PDFPage()
        let doc = PDFDocument()
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        page.setBounds(bounds, for: .mediaBox)
        doc.insert(page, at: 0)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            (text as NSString).draw(in: bounds.insetBy(dx: 36, dy: 36), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        }
        return data
    }
}
```

Add `import PDFKit` and `import UIKit` at the top of the test file.

- [ ] **Step 3: Run to see them fail**

Run: `cd ios && xcodegen generate --quiet && xcodebuild test -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GraphghanTests/PDFImportTests 2>&1 | grep -E 'error:|Test Suite|passed|failed' | head`
Expected: compile errors, `PDFImporter` undefined.

- [ ] **Step 4: Write the importer**

```swift
import Foundation
import GraphghanCore
import PDFKit

/// A pattern PDF, from bytes to a pattern the library shows (phone import spec §5.1, §5.3). PDFKit
/// turns the pages into text here; every decision about that text is `GraphghanCore`'s. Reading
/// and saving are two steps because the sheet shows the chart before "Add to library" saves it,
/// and a read writes nothing.
struct PDFImporter: Sendable {
    let charts: ChartLibrary
    let local: LocalPatternStore

    /// A pattern PDF is a few MB; the Orca bag, all photos, is 18 MB.
    static let maximumBytes = 20 << 20

    func read(_ data: Data, fileName: String) async throws(PDFImportError) -> PDFImportReading {
        guard data.count <= Self.maximumBytes else { throw .tooBig }
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw .cannotOpen }
        let texts = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard OwnPDFReader.isOwn(pageTexts: texts) else { throw .nothingFound }  // PR 2 and 3 add the other readers here
        let reading: OwnPDFReading
        do { reading = try OwnPDFReader.read(pageTexts: texts, title: title.isEmpty ? Self.stem(fileName) : title) }
        catch let error as OwnPDFError { throw .badRow(Self.describe(error)) }
        catch { throw .badRow("\(error)") }
        let slug = await Self.uniqueSlug(Self.slug(reading.pattern.title.isEmpty ? Self.stem(fileName) : reading.pattern.title), in: local)
        let draft = ChartWriter.draft(from: reading, id: slug)
        let (chartData, chartID) = ChartWriter.encode(draft)
        let chart: Chart
        do { chart = try Chart.load(chartData) } catch { throw .invalidChart("\(error)") }
        guard let preview = ChartPreview.png(chart) else { throw .invalidChart("no preview") }
        let gaugeKey = draft.gauge.stitch ?? "sc"
        let dedication = "Imported from \(fileName) on \(Self.today())"
        let manifestData = ManifestWriter.encode(id: slug, title: reading.pattern.title, version: reading.pattern.version, dedication: dedication,
                                                 chart: chart, chartID: chartID, variant: "final", gaugeKey: gaugeKey, palette: draft.palette)
        let manifest: PatternManifest
        do { manifest = try JSONDecoder().decode(PatternManifest.self, from: manifestData) } catch { throw .invalidChart("manifest: \(error)") }
        let entry = manifest.charts[0]
        let bundle = PatternBundle(manifest: manifest, manifestData: manifestData,
                                   charts: [BundleChart(entry: entry, chart: chart, data: chartData)],
                                   previews: ["preview.png": preview, entry.preview: preview])
        return PDFImportReading(bundle: bundle, preview: preview, width: chart.width, height: chart.height, colours: chart.palette.count)
    }

    /// The bundle importer's order (bundle design §6.2): charts, then the pattern directory whole.
    func save(_ reading: PDFImportReading) async throws -> PatternManifest {
        for chart in reading.bundle.charts { _ = try await charts.store(chart.data) }
        try await local.save(reading.bundle)
        return reading.bundle.manifest
    }

    static func stem(_ fileName: String) -> String { (fileName as NSString).deletingPathExtension }

    /// `site/build.py`'s slug rule: lowercase, runs of anything but letters and digits become one dash.
    static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = "", dash = false
        for ch in folded.unicodeScalars {
            if (ch.value >= 0x61 && ch.value <= 0x7a) || (ch.value >= 0x30 && ch.value <= 0x39) { out.unicodeScalars.append(ch); dash = false }
            else if !dash, !out.isEmpty { out += "-"; dash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "pattern" : out
    }

    static func uniqueSlug(_ base: String, in store: LocalPatternStore) async -> String {
        var slug = base, n = 2
        while await store.has(id: slug) { slug = "\(base)-\(n)"; n += 1 }
        return slug
    }

    static func today() -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; f.locale = Locale(identifier: "en_GB")
        return f.string(from: Date())
    }

    static func describe(_ error: OwnPDFError) -> String {
        switch error {
        case .noChartHeader: return "no chart header"
        case .badRow(let page, let text): return "page \(page), \"\(text.prefix(40))\""
        case .rowsDoNotMatch(let why): return why
        }
    }
}

struct PDFImportReading: Sendable {
    let bundle: PatternBundle
    let preview: Data
    let width: Int
    let height: Int
    let colours: Int
}

/// Why a PDF was refused; `message` is the sentence the sheet shows (phone import spec §5.4).
enum PDFImportError: Error, Equatable {
    case tooBig
    case cannotOpen
    case nothingFound
    case invalidChart(String)
    case badRow(String)

    var message: String {
        switch self {
        case .tooBig: return "That file is too big to be a pattern."
        case .cannotOpen: return "That PDF couldn't be opened."
        case .nothingFound: return "No chart or written rows were found in this PDF."
        case .invalidChart(let why): return "The chart in this PDF isn't one the app can work: \(why)."
        case .badRow(let where_): return "A written row in this PDF couldn't be read (\(where_))."
        }
    }
}
```

- [ ] **Step 5: Run the tests**

Run: the Step 3 command.
Expected: 5 pass. If `theSlugComesFromTheTitle...` finds `has(id:)` missing, it exists on `LocalPatternStore` (`func has(id: String) -> Bool`); if `save` of the second reading is needed to make the third unique, it is not: the test saves the first only.

- [ ] **Step 6: Commit**

```bash
git add ios/Graphghan/Services/PDFImporter.swift ios/Tests/PDFImportTests.swift ios/Tests/TestSupport.swift
git commit -m "ios: PDFImporter reads our own PDF into a pattern the library stores (phone import §5.1, §5.3)"
```

---

### Task 6: The document type, the route in `AppModel`, the import sheet

**Files:**
- Modify: `ios/project.yml` (the `CFBundleDocumentTypes` list under the app target's info)
- Modify: `ios/Graphghan/AppModel.swift` (`importBundle(at:)` → `importFile(at:)`; add `pdfImport`)
- Modify: `ios/Graphghan/GraphghanApp.swift:45,50` (call `importFile(at:)`)
- Create: `ios/Graphghan/Patterns/PDFImportSheet.swift`
- Modify: `ios/Graphghan/RootView.swift` (present the sheet)
- Modify: `ios/Tests/BundleImportTests.swift` (rename call sites to `importFile(at:)` where the URL path is used)
- Create: `ios/Tests/PDFImportSheetTests.swift`

**Interfaces:**
- Produces on `AppModel`: `var pdfImport: PDFImportState?` (non-nil while the sheet is up), `func importFile(at url: URL) async` (routes by extension: `.graphghan` → the bundle path, `.pdf` → `importPDF(data:fileName:)`), `func importPDF(data: Data, fileName: String) async`, `func addImportedPDF() async` (saves `pdfImport.reading`, then the same landing as a bundle), `func cancelPDFImport()`.
- `@Observable final class PDFImportState { enum Stage: Equatable { case reading, found, failed(String) }; var stage: Stage; var fileName: String; var reading: PDFImportReading?; var preview: UIImage? }` (`@MainActor`).

- [ ] **Step 1: Register the type**

In `ios/project.yml`, under the existing `CFBundleDocumentTypes:` list (the one with `LSItemContentTypes: [com.tylervick.graphghan.pattern-bundle]`), add a second entry:

```yaml
          - CFBundleTypeName: Pattern PDF
            CFBundleTypeRole: Viewer
            LSHandlerRank: Alternate
            LSItemContentTypes:
              - com.adobe.pdf
```

`Alternate`, not `Owner`: the app can open a PDF; it is not the app for PDFs.

- [ ] **Step 2: Write the failing sheet-state tests**

`ios/Tests/PDFImportSheetTests.swift`:

```swift
import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

/// The import sheet's states, driven through `AppModel` the way the app drives them (phone import
/// spec §5.2), without a screen.
@MainActor
@Suite struct PDFImportSheetTests {
    func make() async throws -> AppModel {
        let container = try makeInMemoryContainer()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: StubClient())
        return AppModel(context: container.mainContext, patterns: patterns,
                        charts: ChartLibrary(directory: try temporaryDirectory()), localPatterns: LocalPatternStore(directory: try temporaryDirectory()))
    }

    @Test func ourOwnPDFGoesReadingThenFoundThenAdds() async throws {
        let model = try await make()
        await model.importPDF(data: try TestFixtures.importPDF("craigh-na-dun-final-sc"), fileName: "craigh.pdf")
        let state = try #require(model.pdfImport)
        #expect(state.stage == .found && state.reading?.width == 189 && state.preview != nil)
        #expect(model.libraryItems.isEmpty)  // nothing saved yet
        await model.addImportedPDF()
        #expect(model.pdfImport == nil && model.tab == .patterns)
        #expect(model.libraryItems.contains { $0.source == .local && $0.slug == "craigh-na-dun-blanket" })
        #expect(model.libraryPath.first?.slug == "craigh-na-dun-blanket")
    }

    @Test func cancelLeavesTheLibraryUntouched() async throws {
        let model = try await make()
        await model.importPDF(data: try TestFixtures.importPDF("craigh-na-dun-final-sc"), fileName: "craigh.pdf")
        model.cancelPDFImport()
        #expect(model.pdfImport == nil && model.libraryItems.isEmpty)
    }

    @Test func aBadFileFailsWithItsSentence() async throws {
        let model = try await make()
        await model.importPDF(data: Data("nope".utf8), fileName: "nope.pdf")
        #expect(model.pdfImport?.stage == .failed("That PDF couldn't be opened."))
        model.cancelPDFImport()
        #expect(model.pdfImport == nil)
    }

    @Test func aURLIsRoutedByItsExtension() async throws {
        let model = try await make()
        let dir = try temporaryDirectory()
        let pdf = dir.appendingPathComponent("craigh.pdf")
        try TestFixtures.importPDF("craigh-na-dun-final-sc").write(to: pdf)
        await model.importFile(at: pdf)
        #expect(model.pdfImport?.stage == .found)
        model.cancelPDFImport()
        let bundle = dir.appendingPathComponent("craigh.graphghan")
        try TestFixtures.bundle("craigh-na-dun").write(to: bundle)
        await model.importFile(at: bundle)
        #expect(model.libraryItems.contains { $0.source == .local && $0.slug == "craigh-na-dun" })
    }
}
```

- [ ] **Step 3: Run to see them fail**

Run: `cd ios && xcodegen generate --quiet && xcodebuild test -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GraphghanTests/PDFImportSheetTests 2>&1 | grep -E 'error:|Test Suite|passed|failed' | head`
Expected: compile errors (`pdfImport`, `importPDF`, `importFile` undefined).

- [ ] **Step 4: The state and the model**

`PDFImportSheet.swift` (state at the top, view below):

```swift
import GraphghanCore
import SwiftUI

/// What the import sheet shows (phone import spec §5.2). Driven by `AppModel`, read by the sheet
/// and by tests.
@MainActor @Observable
final class PDFImportState {
    enum Stage: Equatable {
        case reading
        case found
        case failed(String)
    }
    var stage: Stage = .reading
    let fileName: String
    var reading: PDFImportReading? = nil
    var preview: UIImage? = nil
    init(fileName: String) { self.fileName = fileName }
}

struct PDFImportSheet: View {
    @Environment(AppModel.self) private var model
    let state: PDFImportState

    var body: some View {
        NavigationStack {
            Group {
                switch state.stage {
                case .reading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading the pages…")
                    }
                case .found:
                    VStack(spacing: 16) {
                        if let preview = state.preview {
                            Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        if let r = state.reading {
                            Text(r.bundle.manifest.title).font(.headline)
                            Text("\(r.width) × \(r.height) stitches, \(r.colours) colours").foregroundStyle(.secondary)
                        }
                        Button("Add to library") { Task { await model.addImportedPDF() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                case .failed(let sentence):
                    VStack(spacing: 12) {
                        Image(systemName: "doc.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text(sentence).multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(state.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(state.stage == .found ? "Cancel" : "Done") { model.cancelPDFImport() }
                }
            }
        }
        .interactiveDismissDisabled(state.stage == .reading)
    }
}
```

In `AppModel.swift`, beside the bundle section, add:

```swift
    // MARK: opening a PDF (#112)

    /// The import sheet while a PDF is being read or shown; nil otherwise.
    var pdfImport: PDFImportState? = nil

    /// A file, however it arrived, routed by what it is: a bundle imports at once, a PDF opens the
    /// sheet. The Inbox copy, the size cap and the scoped read are shared.
    func importFile(at url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        defer { removeInboxCopy(at: url) }
        let isPDF = url.pathExtension.lowercased() == "pdf"
        let cap = isPDF ? PDFImporter.maximumBytes : Self.maximumBundleBytes
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= cap else {
            if isPDF { pdfImport = PDFImportState(fileName: url.lastPathComponent); pdfImport?.stage = .failed(PDFImportError.tooBig.message) }
            else { importFailure = "That file is too big to be a pattern." }
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            importFailure = "That file couldn't be read."
            return
        }
        if isPDF { await importPDF(data: data, fileName: url.lastPathComponent) } else { await importBundle(data: data) }
    }

    /// The sheet's first two states: reading, then the chart found or the sentence for why not.
    func importPDF(data: Data, fileName: String) async {
        let state = PDFImportState(fileName: fileName)
        pdfImport = state
        let importer = PDFImporter(charts: charts, local: localPatterns)
        do {
            let reading = try await importer.read(data, fileName: fileName)
            state.reading = reading
            state.preview = UIImage(data: reading.preview)
            state.stage = .found
        } catch let error as PDFImportError {
            state.stage = .failed(error.message)
        } catch {
            state.stage = .failed(PDFImportError.cannotOpen.message)
        }
    }

    /// "Add to library": the bundle importer's order, then the same landing as an opened bundle.
    func addImportedPDF() async {
        guard let state = pdfImport, let reading = state.reading else { return }
        let importer = PDFImporter(charts: charts, local: localPatterns)
        do {
            let manifest = try await importer.save(reading)
            manifests[manifest.id] = manifest
            for key in images.keys where key == "local:\(manifest.id)" || key.hasPrefix("\(manifest.id)/") { images[key] = nil }
            await loadLocalPatterns()
            scheduleReindex()
            pdfImport = nil
            tab = .patterns
            if let item = libraryItems.first(where: { $0.source == .local && $0.slug == manifest.id }) { libraryPath = [item] }
        } catch {
            state.stage = .failed("That pattern couldn't be saved.")
        }
    }

    func cancelPDFImport() { pdfImport = nil }
```

Then in the same file change `importBundle(at:)` to a one-line forwarder kept for the bundle tests (`func importBundle(at url: URL) async { await importFile(at: url) }`) with its body moved into `importFile(at:)` as above, and in `GraphghanApp.swift` replace both `model.importBundle(at: url)` calls with `model.importFile(at: url)`.

In `RootView.swift`, beside the existing `.alert("Couldn't open that pattern", ...)`, present the sheet:

```swift
        .sheet(isPresented: Binding(get: { model.pdfImport != nil }, set: { if !$0 { model.cancelPDFImport() } })) {
            if let state = model.pdfImport { PDFImportSheet(state: state) }
        }
```

- [ ] **Step 5: Run the tests**

Run: the Step 3 command, then the whole app suite: `xcodebuild test -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E '✘|Test run with|error:' | tail -5`
Expected: the four new tests pass and the existing `BundleImportTests` still pass (their `importBundle(at:)` calls forward). `PDFImportState` must be `@MainActor`; if the compiler objects to `Stage: Equatable` with an associated `String`, it does not (synthesised).

- [ ] **Step 6: Commit**

```bash
git add ios/project.yml ios/Graphghan ios/Tests
git commit -m "ios: a PDF opens from Files into an import sheet and, for our own PDFs, into the library (#112 PR 1)"
```

---

### Task 7: Docs, the launch argument, and the check

**Files:**
- Modify: `ios/README.md` (the "Opening a pattern" section, whichever paragraph describes `.graphghan` files and `--import`)
- Modify: `docs/superpowers/specs/2026-09-20-phone-pdf-import-design.md` §11 (tick the first criterion with the measured time)
- Modify: this plan (tick every box)

- [ ] **Step 1: README**

After the paragraph on opening a `.graphghan` file, add:

```markdown
A pattern PDF opens the same way (#112). One `graphghan export --format pdf` wrote is read exactly
from its text layer and lands in the library with the same chart id the Mac computed; any other PDF
gets the sentence "No chart or written rows were found in this PDF" until the written-row and grid
readers land (spec §8). `--import <path>.pdf` on the simulator drives the identical path:

    xcrun simctl launch booted com.tylervick.graphghan --import /path/to/pattern.pdf
```

- [ ] **Step 2: Time the own-PDF import on the simulator and record it**

Run: `cd ios && xcodebuild test -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:GraphghanTests/PDFImportTests/ourOwnPDFReadsToTheMacsChartAndSaves 2>&1 | grep -E 'passed|failed'`
Note the test's duration from the output line and write it into spec §11's first bullet as "(measured: N s on the iPhone 17 simulator)".

- [ ] **Step 3: The whole check**

Run: `mise run check` from the repo root (Python side unaffected, but the hook runs it), then `cd ios/Packages/GraphghanCore && swift test 2>&1 | grep 'Test run'`, then the full app suite from Task 6 Step 5.
Expected: all green.

- [ ] **Step 4: Commit and open the PR**

```bash
git add ios/README.md docs/superpowers
git commit -m "docs: opening a pattern PDF on the phone, PR 1 (#112)"
git push -u origin tylervick/phone-import
```

The PR body: what the three tasks' readers do, the chart-id equality, the sentences, `Closes` nothing (#112 closes with PR 3; say "Part 1 of #112"), and the Blink result.

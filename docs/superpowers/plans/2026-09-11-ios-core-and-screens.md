# iOS Core and Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native SwiftUI iOS app under `ios/` with a `GraphghanCore` Swift package that proves the chart format against the shared fixtures, SwiftData-backed projects, a pattern library fed from graphghan.milo.cat, and a full-screen Work screen with haptics.

**Architecture:** `GraphghanCore` is a UI-free Swift package (chart decoding and validation, content-hash ids, technique sequencing, the work engine, progress documents and pace math, site manifest models), tested with `swift test` on macOS against `fixtures/chart-format/`. The app target owns the stores: an actor `PatternStore` (site index and manifests, cached with ETags), an actor `ChartLibrary` (downloaded chart files, decoded once), and a `@MainActor` `ProjectService` over SwiftData (`Project`, `ProgressEvent`). Screens are thin SwiftUI over those. The Live Activity, intents, CI, and TestFlight are later plans; this plan leaves the seams for them (`ProjectService.apply` is the single mutation path; the SwiftData store lives in the App Group container).

**Tech Stack:** Swift 6.2 (Xcode 26.2), Swift 6 language mode, iOS 17.0 deployment target, SwiftUI, SwiftData, CryptoKit, Swift Testing (`import Testing`), xcodegen 2.46.0 via mise, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-10-graphghan-ios-app-design.md` (sections 6, 8.1, 8.2, 9, 10). This plan is "Plan 2: iOS core and screens" from section 10. The format the app reads is `docs/chart-format.md`; the conformance suite is `fixtures/chart-format/README.md`.

## Global Constraints

- Work on branch `feat/ios-core` in a worktree; never commit directly to `main`.
- Bundle id `com.tylervick.graphghan`, App Group `group.com.tylervick.graphghan`, development team `352UZEKYPP`, iOS 17.0 deployment target, `SWIFT_VERSION` 6.0 (language mode 6), strict concurrency complete.
- The core package imports Foundation and CryptoKit only. No UIKit, SwiftUI, or SwiftData in `Packages/GraphghanCore`.
- Every Swift test in this plan uses Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`), not XCTest.
- Format rules the Swift code must match exactly (from `docs/chart-format.md`): codes `^[A-Za-z]{1,3}$`; run strings `^(\d+[A-Za-z]{1,3})+$`; chart id = `"sha256:" + hex(sha256(canonical JSON of {"codes","rows","technique"} plus "passes" when present))` with keys sorted by code point, separators `,` and `:` only, non-ASCII unescaped; `rows` technique: pass k uses grid row `H-k` for start `bottom` else `k-1`, sides alternate from `first_side` (default `RS`), RS reads `rs_direction` (default `rtl`) and WS the opposite, runs reversed for `rtl`, `x0` is the leftmost grid column, label `Row k`; `rounds`: every pass is `first_side` reading `rs_direction`, label `Round k`; explicit `passes` override; any other type is unsupported. Progress: session gap 1200 s, session stitches = stitches-before(after last event) − stitches-before(before first event) clamped at 0, first "before" cursor is row 1 run 0, percent and stitches-per-hour rounded to one decimal, `null` rate with no active time.
- Cursor is `{row: 1-based pass index, run: 0-based run index}`; `run == runs.count` on the last pass means finished.
- Site base URL `https://graphghan.milo.cat/`; index at `patterns/index.json`; manifest and chart paths in a manifest are relative to `patterns/<slug>/`; the index's `preview` and `manifest` are relative to the site root.
- If a code block in this plan does not compile under Swift 6.2, make the smallest change that preserves the stated behaviour and record it in the task report; do not change interfaces named in an **Interfaces** block without saying so.
- Commands: `cd ios && mise run generate` (xcodegen), `mise run core-test` (`swift test` in the package), `mise run test` (xcodebuild on the iPhone 17 simulator). Each task ends with its named tests green.
- `git commit` must run with the Bash tool's sandbox disabled (1Password SSH signing); if signing fails, leave the tree staged and report. Commit messages end with:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_016acqd28TPss8NPKVWwzMxK`

---

## File structure

| path | responsibility |
|---|---|
| `ios/mise.toml` | xcodegen pin; `generate`, `build`, `test`, `core-test` tasks |
| `ios/project.yml` | xcodegen: app target, unit-test target, local package, entitlements, Info.plist |
| `ios/Assets.xcassets/` | AccentColor, AppIcon placeholder |
| `ios/Packages/GraphghanCore/Package.swift` | the core package |
| `…/Sources/GraphghanCore/JSONValue.swift` | generic JSON tree + canonical serializer |
| `…/Sources/GraphghanCore/ChartID.swift` | content-hash id |
| `…/Sources/GraphghanCore/ChartDocument.swift` | schema 2 decoding (raw) |
| `…/Sources/GraphghanCore/Chart.swift` | validated chart: cells, palette index, sizes |
| `…/Sources/GraphghanCore/RunString.swift` | run-string scanner |
| `…/Sources/GraphghanCore/WorkSequence.swift` | passes, runs, technique derivation, stitch prefix sums |
| `…/Sources/GraphghanCore/WorkEngine.swift` | cursor, actions, boundaries |
| `…/Sources/GraphghanCore/ProgressDocument.swift` | progress schema 1 codec |
| `…/Sources/GraphghanCore/Pace.swift` | sessions, rate, percent, finish estimate |
| `…/Sources/GraphghanCore/SiteModels.swift` | index entries and pattern manifests |
| `…/Tests/GraphghanCoreTests/Fixtures.swift` | fixture directory access |
| `…/Tests/GraphghanCoreTests/*Tests.swift` | one file per source file |
| `ios/Graphghan/GraphghanApp.swift` | `@main`, container, root tabs |
| `ios/Graphghan/AppModel.swift` | `@Observable` app state: stores, library state, navigation |
| `ios/Graphghan/Storage/AppGroup.swift` | container URLs |
| `ios/Graphghan/Storage/Project.swift`, `ProgressEvent.swift` | SwiftData models |
| `ios/Graphghan/Storage/ChartLibrary.swift` | downloaded chart files, decoded once |
| `ios/Graphghan/Network/HTTPClient.swift` | protocol + URLSession implementation |
| `ios/Graphghan/Network/PatternStore.swift` | index, manifests, previews, chart downloads |
| `ios/Graphghan/Services/ProjectService.swift` | start, apply, summary, finish, delete, version notice |
| `ios/Graphghan/UI/ChartImage.swift` | CGImage at 1 px per cell |
| `ios/Graphghan/UI/Haptics.swift` | run, row, new-color haptics |
| `ios/Graphghan/Patterns/LibraryView.swift`, `PatternDetailView.swift`, `ChartBrowserView.swift`, `StartProjectSheet.swift` | Patterns tab |
| `ios/Graphghan/Projects/ProjectListView.swift`, `ProjectDetailView.swift`, `JumpToRowSheet.swift` | Projects tab |
| `ios/Graphghan/Work/WorkView.swift`, `RowStripView.swift`, `RunChipsView.swift` | Work screen |
| `ios/Tests/*.swift` | app-target tests (in-memory SwiftData, stub HTTP) |
| `ios/README.md` | how to generate, build, test |

---

### Task 0: Branch and worktree

- [ ] **Step 1: Create the worktree**

From the repo root:
```bash
git worktree add .worktrees/ios-core -b feat/ios-core main
cd .worktrees/ios-core && mise trust -q && mise install -q && mise run setup
uv run pytest -q
```
Expected: 172 passed. All later commands run inside `.worktrees/ios-core`.

---

### Task 1: Scaffold the Xcode project and the core package

**Files:**
- Create: `ios/mise.toml`, `ios/project.yml`, `ios/Assets.xcassets/Contents.json`, `ios/Assets.xcassets/AccentColor.colorset/Contents.json`, `ios/Assets.xcassets/AppIcon.appiconset/Contents.json`, `ios/Graphghan/GraphghanApp.swift`, `ios/Tests/SmokeTests.swift`, `ios/Packages/GraphghanCore/Package.swift`, `ios/Packages/GraphghanCore/Sources/GraphghanCore/GraphghanCore.swift`, `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/Fixtures.swift`, `ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/FixturesTests.swift`, `ios/README.md`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `Fixtures.directory: URL` (the repo's `fixtures/chart-format`), `Fixtures.chartNames: [String]`, `Fixtures.data(_ name: String) throws -> Data`, `Fixtures.json(_ name: String) throws -> [String: Any]`; `GraphghanCore.formatSchema == 2`.

- [ ] **Step 1: Tooling and gitignore**

Create `ios/mise.toml`:
```toml
# iOS tooling. The repo-root mise.toml still applies here (uv, node, hk); this file adds what only
# ios/ needs. Run from ios/: `mise run generate && mise run test`.
[tools]
xcodegen = "2.46.0"

[tasks.generate]
description = "Generate Graphghan.xcodeproj from project.yml"
run = "xcodegen generate --quiet"

[tasks.core-test]
description = "swift test for the GraphghanCore package (macOS host, no simulator)"
dir = "Packages/GraphghanCore"
run = "swift test --quiet"

[tasks.build]
description = "Build the app for the iPhone 17 simulator"
depends = ["generate"]
run = "xcodebuild build -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData"

[tasks.test]
description = "Run the app target's unit tests on the iPhone 17 simulator"
depends = ["generate"]
run = "xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData"
```

Append to the repo-root `.gitignore`:
```
ios/*.xcodeproj
ios/Graphghan/Info.plist
ios/Graphghan/Graphghan.entitlements
ios/build/
ios/DerivedData/
ios/Packages/*/.build/
ios/TestResults*.xcresult
```

- [ ] **Step 2: project.yml**

Create `ios/project.yml`:
```yaml
name: Graphghan
options:
  bundleIdPrefix: com.tylervick
  deploymentTarget:
    iOS: "17.0"
  createIntermediateGroups: true
packages:
  GraphghanCore:
    path: Packages/GraphghanCore
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    TARGETED_DEVICE_FAMILY: "1"
    # Same team as Waddle; xcodegen regenerates the project, so the team lives here, not in Xcode's pane.
    DEVELOPMENT_TEAM: 352UZEKYPP
    CODE_SIGN_STYLE: Automatic
targets:
  Graphghan:
    type: application
    platform: iOS
    sources:
      - path: Graphghan
      - path: Assets.xcassets
    dependencies:
      - package: GraphghanCore
    entitlements:
      path: Graphghan/Graphghan.entitlements
      properties:
        com.apple.security.application-groups: [group.com.tylervick.graphghan]
    info:
      path: Graphghan/Info.plist
      properties:
        CFBundleDisplayName: Graphghan
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        UILaunchScreen: {}
        ITSAppUsesNonExemptEncryption: false
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tylervick.graphghan
        CURRENT_PROJECT_VERSION: 1
        MARKETING_VERSION: "0.1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
  GraphghanTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: Graphghan
schemes:
  Graphghan:
    build:
      targets:
        Graphghan: all
        GraphghanTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - GraphghanTests
```

- [ ] **Step 3: Asset catalog**

`ios/Assets.xcassets/Contents.json`:
```json
{ "info": { "author": "xcode", "version": 1 } }
```
`ios/Assets.xcassets/AccentColor.colorset/Contents.json` (the site's gold, `#D9A21B`):
```json
{
  "colors": [
    { "idiom": "universal",
      "color": { "color-space": "srgb", "components": { "red": "0.851", "green": "0.635", "blue": "0.106", "alpha": "1.000" } } }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```
`ios/Assets.xcassets/AppIcon.appiconset/Contents.json` (placeholder; artwork is a later task):
```json
{
  "images": [ { "idiom": "universal", "platform": "ios", "size": "1024x1024" } ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 4: App shell and smoke test**

`ios/Graphghan/GraphghanApp.swift`:
```swift
import SwiftUI
import GraphghanCore

@main
struct GraphghanApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Text("Patterns").tabItem { Label("Patterns", systemImage: "square.grid.3x3") }
                Text("Projects").tabItem { Label("Projects", systemImage: "checklist") }
            }
        }
    }
}
```
`ios/Tests/SmokeTests.swift`:
```swift
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct SmokeTests {
    @Test func coreIsLinked() {
        #expect(GraphghanCore.formatSchema == 2)
    }
}
```

- [ ] **Step 5: The package**

`ios/Packages/GraphghanCore/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GraphghanCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "GraphghanCore", targets: ["GraphghanCore"])],
    targets: [
        .target(name: "GraphghanCore"),
        .testTarget(name: "GraphghanCoreTests", dependencies: ["GraphghanCore"]),
    ],
    swiftLanguageModes: [.v6]
)
```
`ios/Packages/GraphghanCore/Sources/GraphghanCore/GraphghanCore.swift`:
```swift
/// The graphghan chart format, as read by this package. See docs/chart-format.md at the repo root.
public enum GraphghanCore {
    /// The chart document schema this package decodes.
    public static let formatSchema = 2
    /// The progress document schema this package reads and writes.
    public static let progressSchema = 1
}
```
`ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/Fixtures.swift`:
```swift
import Foundation

/// The shared conformance fixtures at <repo>/fixtures/chart-format, located relative to this file
/// so `swift test` and Xcode both find them without copying.
enum Fixtures {
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }  // GraphghanCoreTests, Tests, GraphghanCore, Packages, ios, <repo>
        return url.appendingPathComponent("fixtures/chart-format", isDirectory: true)
    }()

    static var chartNames: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".chart.json") }
            .map { String($0.dropLast(".chart.json".count)) }
            .sorted()
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func json(_ name: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data(name))
        guard let dict = object as? [String: Any] else { throw FixtureError.notAnObject(name) }
        return dict
    }

    enum FixtureError: Error { case notAnObject(String) }
}
```
`ios/Packages/GraphghanCore/Tests/GraphghanCoreTests/FixturesTests.swift`:
```swift
import Testing
@testable import GraphghanCore

@Suite struct FixturesTests {
    @Test func fixtureSetMatchesSpec() {
        #expect(Set(Fixtures.chartNames) == [
            "craigh-na-dun", "explicit-passes", "layers-stitch", "minimal-rounds",
            "minimal-rows", "two-letter-codes", "unknown-technique",
        ])
    }

    @Test func packageConstants() {
        #expect(GraphghanCore.formatSchema == 2)
        #expect(GraphghanCore.progressSchema == 1)
    }
}
```

- [ ] **Step 6: README**

`ios/README.md`:
```markdown
# Graphghan for iOS

SwiftUI app for working graphghan patterns published at https://graphghan.milo.cat/. The
`Packages/GraphghanCore` package reads the chart format (`../docs/chart-format.md`) and is tested
against `../fixtures/chart-format`.

    cd ios
    mise install            # xcodegen
    mise run generate       # Graphghan.xcodeproj (gitignored)
    mise run core-test      # swift test, macOS host
    mise run test           # app unit tests on the iPhone 17 simulator
    open Graphghan.xcodeproj

Bundle id `com.tylervick.graphghan`, App Group `group.com.tylervick.graphghan`, iOS 17.0+.
```

- [ ] **Step 7: Verify everything builds and tests run**

```bash
cd ios && mise install -q && mise run core-test && mise run test
```
Expected: `swift test` reports 2 tests passed; `xcodebuild test` ends with `** TEST SUCCEEDED **` (1 test). If xcodegen complains about the asset catalog or entitlements, fix the YAML and re-run; if the simulator name differs, use `xcrun simctl list devices available | grep iPhone` and pick one that exists, then correct `mise.toml`.

- [ ] **Step 8: Commit**

```bash
git add .gitignore ios
git commit -m "feat(ios): scaffold the Xcode project, GraphghanCore package, and fixture access"
```

---

### Task 2: JSON values, canonical serialization, and the chart id

**Files:**
- Create: `ios/Packages/GraphghanCore/Sources/GraphghanCore/JSONValue.swift`, `…/ChartID.swift`
- Test: `…/Tests/GraphghanCoreTests/JSONValueTests.swift`, `…/ChartIDTests.swift`

**Interfaces:**
- Produces: `public enum JSONValue: Equatable, Sendable, Codable { null, bool, int, double, string, array, object }` with `subscript(key: String) -> JSONValue?`, `var stringValue/intValue/boolValue/arrayValue/objectValue`; `public enum CanonicalJSON { static func encode(_ v: JSONValue) -> String }`; `public enum ChartID { static func compute(codes: [String], rows: [String], technique: JSONValue, passes: JSONValue?) -> String }`.

- [ ] **Step 1: Failing tests**

`JSONValueTests.swift`:
```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct JSONValueTests {
    @Test func decodesEveryKind() throws {
        let data = Data(#"{"a":null,"b":true,"c":7,"d":6.5,"e":"x","f":[1,"y"],"g":{"k":false}}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(v["a"] == .null)
        #expect(v["b"] == .bool(true))
        #expect(v["c"] == .int(7))
        #expect(v["d"] == .double(6.5))
        #expect(v["e"] == .string("x"))
        #expect(v["f"] == .array([.int(1), .string("y")]))
        #expect(v["g"]?["k"] == .bool(false))
    }

    @Test func canonicalMatchesPythonRules() {
        let v: JSONValue = .object([
            "zebra": .int(1), "apple": .array([.bool(true), .null]), "quote": .string("say \"hi\"\n"),
            "under_score": .string("é/ü"),
        ])
        // keys sorted by code point, no whitespace, control chars escaped, non-ASCII and "/" untouched
        #expect(CanonicalJSON.encode(v) == #"{"apple":[true,null],"quote":"say \"hi\"\n","under_score":"é/ü","zebra":1}"#)
    }

    @Test func canonicalSortsByCodePointNotLocale() {
        let v: JSONValue = .object(["b": .int(1), "B": .int(2), "_": .int(3), "a": .int(4)])
        #expect(CanonicalJSON.encode(v) == #"{"B":2,"_":3,"a":4,"b":1}"#)
    }
}
```
`ChartIDTests.swift`:
```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ChartIDTests {
    @Test func knownValue() {
        // Python: chart_id(["A","B"], ["2A2B","4A"], TECHNIQUE_ROWS) — recompute here with the same canonical form.
        let technique: JSONValue = .object([
            "type": .string("rows"), "start": .string("bottom"), "first_side": .string("RS"),
            "rs_direction": .string("rtl"), "turn": .bool(true),
        ])
        let id = ChartID.compute(codes: ["A", "B"], rows: ["2A2B", "4A"], technique: technique, passes: nil)
        #expect(id.hasPrefix("sha256:") && id.count == 7 + 64)
        // Names and hexes are not part of the id; passes are.
        #expect(ChartID.compute(codes: ["A", "B"], rows: ["2A2B", "4A"], technique: technique, passes: .array([])) != id)
    }

    @Test(arguments: Fixtures.chartNames)
    func matchesEveryFixture(name: String) throws {
        let doc = try Fixtures.json("\(name).chart.json")
        let raw = try Fixtures.data("\(name).chart.json")
        let tree = try JSONDecoder().decode(JSONValue.self, from: raw)
        let palette = try #require(doc["palette"] as? [[String: Any]])
        let codes = palette.compactMap { $0["code"] as? String }
        let rows = try #require(doc["rows"] as? [String])
        let technique = try #require(tree["technique"])
        let expected = try #require((doc["chart"] as? [String: Any])?["id"] as? String)
        #expect(ChartID.compute(codes: codes, rows: rows, technique: technique, passes: tree["passes"]) == expected)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ios && mise run core-test`
Expected: compile errors for `JSONValue`, `CanonicalJSON`, `ChartID`.

- [ ] **Step 3: Implement**

`JSONValue.swift`:
```swift
import Foundation

/// A generic JSON tree. Used wherever the format keeps a raw object we must hash or preserve
/// verbatim (`technique`, `passes`), and for canonical serialization.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d.rounded() == d && abs(d) < 9.0e15: return Int(d)
        default: return nil
        }
    }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// Python's `json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)`.
/// Keys sort by Unicode code point (UTF-8 byte order), only `"`, `\` and control characters are
/// escaped, `/` and non-ASCII pass through. Floats use Swift's shortest round-trip form, which
/// matches Python's repr for the values the format produces (the id never hashes floats).
public enum CanonicalJSON {
    public static func encode(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    private static func write(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d):
            if d.rounded() == d && abs(d) < 1e16 { out += String(Int(d)) + ".0" } else { out += "\(d)" }
        case .string(let s): writeString(s, into: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                write(v, into: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            let keys = o.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
            for (i, k) in keys.enumerated() {
                if i > 0 { out += "," }
                writeString(k, into: &out)
                out += ":"
                write(o[k]!, into: &out)
            }
            out += "}"
        }
    }

    private static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case let c where c.value < 0x20:
                out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}
```
`ChartID.swift`:
```swift
import CryptoKit
import Foundation

/// `chart.id`: SHA-256 over the canonical JSON of the codes, rows, technique and (when present)
/// passes. Names, hexes, yarn, instructions and stats never affect it. See docs/chart-format.md.
public enum ChartID {
    public static let prefix = "sha256:"

    public static func compute(codes: [String], rows: [String], technique: JSONValue, passes: JSONValue?) -> String {
        var object: [String: JSONValue] = [
            "codes": .array(codes.map(JSONValue.string)),
            "rows": .array(rows.map(JSONValue.string)),
            "technique": technique,
        ]
        if let passes { object["passes"] = passes }
        let canonical = CanonicalJSON.encode(.object(object))
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return prefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The 64 hex characters after the prefix, or nil if the id is not well-formed.
    public static func hex(_ id: String) -> String? {
        guard id.hasPrefix(prefix) else { return nil }
        let hex = String(id.dropFirst(prefix.count))
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return hex
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd ios && mise run core-test`
Expected: all pass, including `matchesEveryFixture` for all 7 fixtures (this is the Python/Swift id parity check).

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "feat(core): JSON values, canonical serialization, content-hash chart id"
```

---

### Task 3: Chart document decoding and the validated Chart

**Files:**
- Create: `…/Sources/GraphghanCore/RunString.swift`, `…/ChartDocument.swift`, `…/Chart.swift`
- Test: `…/Tests/GraphghanCoreTests/ChartDocumentTests.swift`, `…/ChartTests.swift`

**Interfaces:**
- Produces:
  - `public enum RunString { static func parse(_ s: String) -> [(code: String, count: Int)]? }` (nil when malformed), `static let codeMaxLength = 3`.
  - `public struct ChartDocument: Decodable, Sendable` with nested `PatternInfo`, `ChartInfo` (`id`, `variant?`, `gaugeKey?`, `width`, `height`), `GeneratorInfo?`, `PaletteEntry` (`code`, `name`, `hex`, `yarn: [String: String]?`, `thread: Thread?`, `use?`, `symbol?`), `Layer` (`legend`, `rows`), `Gauge` (`stitches: Double`, `rows: Double`, `over: Over(value: Double, unit: String)`, `stitch?`, `hook?`, `yarnWeight?`), `Instruction` (`title`, `text`); properties `schema`, `pattern`, `chart`, `generator`, `palette`, `rows`, `layers: [String: Layer]?`, `gauge`, `technique: JSONValue`, `passes: JSONValue?`, `instructions: [Instruction]`; `static func decode(_ data: Data) throws -> ChartDocument`; `var techniqueType: String`, `techniqueStart: String`, `techniqueFirstSide: String`, `techniqueRSDirection: String` (defaults `bottom`, `RS`, `rtl`).
  - `public struct GridRun: Equatable, Sendable { colorIndex: Int; count: Int; x0: Int }`.
  - `public struct Chart: Sendable` with `document`, `width`, `height`, `palette`, `cells: [UInt8]` (row-major, top row first), `runsByRow: [[GridRun]]`, `warnings: [String]`, `id`, `cellAspect: Double`, `finishedSize: FinishedSize` (`width`, `height`, `unit`), `func colorIndex(of code: String) -> Int?`, `func cell(x: Int, y: Int) -> Int`, `init(document:) throws`, `static func load(_ data: Data) throws -> Chart`.
  - `public enum ChartError: Error, Equatable { unsupportedSchema(Int), tooManyColors(Int), invalidCode(String), duplicateCode(String), invalidHex(code: String, hex: String), heightMismatch(rows: Int, height: Int), malformedRow(Int), unknownCode(row: Int, code: String), rowSum(row: Int, got: Int, expected: Int), idMismatch(expected: String, found: String) }`.

- [ ] **Step 1: Failing tests**

`ChartDocumentTests.swift`:
```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ChartDocumentTests {
    @Test(arguments: Fixtures.chartNames)
    func decodesEveryFixture(name: String) throws {
        let doc = try ChartDocument.decode(Fixtures.data("\(name).chart.json"))
        #expect(doc.schema == 2)
        #expect(doc.rows.count == doc.chart.height)
        #expect(!doc.palette.isEmpty)
        #expect(doc.gauge.over.unit == "in")
    }

    @Test func craighFields() throws {
        let doc = try ChartDocument.decode(Fixtures.data("craigh-na-dun.chart.json"))
        #expect(doc.pattern.title == "Craigh na Dun Blanket")
        #expect(doc.pattern.dedication == "For Meaghan")
        #expect(doc.chart.variant == "final" && doc.chart.gaugeKey == "sc")
        #expect(doc.chart.width == 189 && doc.chart.height == 184)
        #expect(doc.gauge.stitches == 14 && doc.gauge.rows == 16 && doc.gauge.hook == "5 mm (US H-8)")
        #expect(doc.palette[4].code == "Y" && doc.palette[4].yarn?["note"] == "Gold")
        #expect(doc.instructions.count == 2 && doc.instructions[0].title == "Setup")
        #expect(doc.techniqueType == "rows" && doc.techniqueStart == "bottom")
        #expect(doc.techniqueFirstSide == "RS" && doc.techniqueRSDirection == "rtl")
        #expect(doc.passes == nil)
    }

    @Test func unknownKeysAreIgnoredAndDefaultsApply() throws {
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"sha256:x","width":1,"height":1},
         "palette":[{"code":"A","name":"a","hex":"#000000","mystery":1}],"rows":["1A"],
         "gauge":{"stitches":10,"rows":10,"over":{"value":10,"unit":"cm"}},"technique":{"type":"rows"},"future":{}}
        """#
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(doc.instructions.isEmpty && doc.layers == nil && doc.generator == nil)
        #expect(doc.techniqueStart == "bottom" && doc.techniqueFirstSide == "RS" && doc.techniqueRSDirection == "rtl")
        #expect(doc.technique["type"] == .string("rows"))
    }

    @Test func layersDecode() throws {
        let doc = try ChartDocument.decode(Fixtures.data("layers-stitch.chart.json"))
        let stitch = try #require(doc.layers?["stitch"])
        #expect(stitch.legend["k"] == "knit" && stitch.rows == ["12k", "6k6p"])
    }
}
```
`ChartTests.swift`:
```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ChartTests {
    static func chart(_ name: String) throws -> Chart { try Chart.load(Fixtures.data("\(name).chart.json")) }

    static func doc(rows: [String], codes: [String] = ["A", "B"], hexes: [String]? = nil, width: Int? = nil, id: String? = nil) -> Data {
        let technique: JSONValue = .object(["type": .string("rows")])
        let chartID = id ?? ChartID.compute(codes: codes, rows: rows, technique: technique, passes: nil)
        let palette = codes.enumerated().map { i, c in
            #"{"code":"\#(c)","name":"n\#(i)","hex":"\#(hexes?[i] ?? String(format: "#%06x", i * 0x111111))"}"#
        }.joined(separator: ",")
        let w = width ?? (RunString.parse(rows[0])?.reduce(0) { $0 + $1.count } ?? 0)
        return Data(#"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\#(chartID)","width":\#(w),"height":\#(rows.count)},
         "palette":[\#(palette)],"rows":[\#(rows.map { "\"\($0)\"" }.joined(separator: ","))],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"}},"technique":{"type":"rows"}}
        """#.utf8)
    }

    @Test(arguments: Fixtures.chartNames)
    func everyFixtureLoads(name: String) throws {
        let chart = try Self.chart(name)
        #expect(chart.cells.count == chart.width * chart.height)
        #expect(chart.runsByRow.count == chart.height)
        #expect(chart.warnings.isEmpty)
    }

    @Test func cellsAndRuns() throws {
        let chart = try Chart(document: ChartDocument.decode(Self.doc(rows: ["2A2B", "4A"])))
        #expect(chart.width == 4 && chart.height == 2)
        #expect(Array(chart.cells) == [0, 0, 1, 1, 0, 0, 0, 0])
        #expect(chart.runsByRow[0] == [GridRun(colorIndex: 0, count: 2, x0: 0), GridRun(colorIndex: 1, count: 2, x0: 2)])
        #expect(chart.cell(x: 3, y: 0) == 1 && chart.cell(x: 3, y: 1) == 0)
        #expect(chart.colorIndex(of: "B") == 1 && chart.colorIndex(of: "Z") == nil)
    }

    @Test func multiLetterCodes() throws {
        let chart = try Self.chart("two-letter-codes")
        #expect(chart.colorIndex(of: "Gd") == 1)
        #expect(chart.runsByRow[0].map(\.count) == [7, 2, 3])
    }

    @Test func sizesFromGauge() throws {
        let chart = try Self.chart("craigh-na-dun")
        #expect(chart.cellAspect == 0.875)
        #expect(chart.finishedSize.width == 54 && chart.finishedSize.height == 46 && chart.finishedSize.unit == "in")
    }

    @Test func runStringScanner() {
        #expect(RunString.parse("7Gd2G3Y")?.map(\.code) == ["Gd", "G", "Y"])
        #expect(RunString.parse("7YB")?.count == 1)
        #expect(RunString.parse("") == nil)
        #expect(RunString.parse("A7") == nil)
        #expect(RunString.parse("7ABCD") == nil)
        #expect(RunString.parse("7A-") == nil)
    }

    @Test func rejectsMalformedDocuments() throws {
        func load(_ data: Data) -> ChartError? {
            do { _ = try Chart(document: ChartDocument.decode(data)); return nil } catch let e as ChartError { return e } catch { return nil }
        }
        #expect(load(Self.doc(rows: ["2A2B", "3A"])) == .rowSum(row: 1, got: 3, expected: 4))
        #expect(load(Self.doc(rows: ["2A2C"])) == .unknownCode(row: 0, code: "C"))
        #expect(load(Self.doc(rows: ["2A2B", "4A"], width: 5)) == .rowSum(row: 0, got: 4, expected: 5))
        #expect(load(Self.doc(rows: ["x"])) == .malformedRow(0))
        #expect(load(Self.doc(rows: ["4A"], codes: ["A", "A"])) == .duplicateCode("A"))
        #expect(load(Self.doc(rows: ["4A"], codes: ["ABCD"])) == .invalidCode("ABCD"))
        #expect(load(Self.doc(rows: ["4A"], hexes: ["red", "#000000"])) == .invalidHex(code: "A", hex: "red"))
        #expect(load(Self.doc(rows: ["4A"], id: "sha256:" + String(repeating: "0", count: 64)))
            == .idMismatch(expected: ChartID.compute(codes: ["A", "B"], rows: ["4A"], technique: .object(["type": .string("rows")]), passes: nil),
                           found: "sha256:" + String(repeating: "0", count: 64)))
    }

    @Test func heightMismatchAndSchema() throws {
        var bad = String(decoding: Self.doc(rows: ["4A"]), as: UTF8.self)
        bad = bad.replacingOccurrences(of: "\"height\":1", with: "\"height\":2")
        #expect(throws: ChartError.heightMismatch(rows: 1, height: 2)) { try Chart(document: ChartDocument.decode(Data(bad.utf8))) }
        let schema1 = String(decoding: Self.doc(rows: ["4A"]), as: UTF8.self).replacingOccurrences(of: "\"schema\":2", with: "\"schema\":1")
        #expect(throws: ChartError.unsupportedSchema(1)) { try Chart(document: ChartDocument.decode(Data(schema1.utf8))) }
    }

    @Test func caseOnlyDuplicatesWarn() throws {
        let chart = try Chart(document: ChartDocument.decode(Self.doc(rows: ["2a2A"], codes: ["a", "A"])))
        #expect(chart.warnings.count == 1 && chart.warnings[0].contains("differ only by case"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ios && mise run core-test` → compile errors for the new types.

- [ ] **Step 3: Implement**

`RunString.swift`:
```swift
/// The run-string encoding: a row is `(\d+[A-Za-z]{1,3})+`, e.g. `12C3K5C`. A run always starts
/// with digits, so `7YB` is one run of code `YB`.
public enum RunString {
    public static let codeMaxLength = 3

    /// The runs in order, or nil when the string is not a run string.
    public static func parse(_ s: String) -> [(code: String, count: Int)]? {
        var runs: [(code: String, count: Int)] = []
        var count = 0
        var digits = 0
        var code = ""
        for ch in s.unicodeScalars {
            if ch.value >= 0x30 && ch.value <= 0x39 {
                if !code.isEmpty {  // a new run begins: flush the previous one
                    runs.append((code, count))
                    count = 0; digits = 0; code = ""
                }
                count = count * 10 + Int(ch.value - 0x30)
                digits += 1
            } else if (ch.value >= 0x41 && ch.value <= 0x5A) || (ch.value >= 0x61 && ch.value <= 0x7A) {
                guard digits > 0, code.count < codeMaxLength else { return nil }
                code.unicodeScalars.append(ch)
            } else {
                return nil
            }
        }
        guard digits > 0, !code.isEmpty else { return nil }
        runs.append((code, count))
        return runs.allSatisfy { $0.count > 0 } ? runs : nil
    }

    public static func isValidCode(_ code: String) -> Bool {
        (1...codeMaxLength).contains(code.count) && code.unicodeScalars.allSatisfy {
            ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A)
        }
    }
}
```
`ChartDocument.swift`:
```swift
import Foundation

/// A chart document exactly as written (schema 2). Unknown keys are ignored; `technique` and
/// `passes` are kept raw because the chart id hashes them verbatim.
public struct ChartDocument: Decodable, Sendable {
    public struct PatternInfo: Decodable, Sendable {
        public let id: String
        public let title: String
        public let version: String
        public let author: String?
        public let license: String?
        public let dedication: String?
        public let quote: String?
        public let url: String?
    }

    public struct ChartInfo: Decodable, Sendable {
        public let id: String
        public let variant: String?
        public let gaugeKey: String?
        public let width: Int
        public let height: Int
        enum CodingKeys: String, CodingKey { case id, variant, gaugeKey = "gauge_key", width, height }
    }

    public struct GeneratorInfo: Decodable, Sendable {
        public let name: String?
        public let version: String?
    }

    public struct PaletteEntry: Decodable, Sendable, Equatable {
        public struct Thread: Decodable, Sendable, Equatable {
            public let system: String
            public let number: String
        }
        public let code: String
        public let name: String
        public let hex: String
        public let yarn: [String: String]?
        public let thread: Thread?
        public let use: String?
        public let symbol: String?
    }

    public struct Layer: Decodable, Sendable, Equatable {
        public let legend: [String: String]
        public let rows: [String]
    }

    public struct Gauge: Decodable, Sendable {
        public struct Over: Decodable, Sendable {
            public let value: Double
            public let unit: String
        }
        public let stitches: Double
        public let rows: Double
        public let over: Over
        public let stitch: String?
        public let hook: String?
        public let yarnWeight: String?
        enum CodingKeys: String, CodingKey { case stitches, rows, over, stitch, hook, yarnWeight = "yarn_weight" }
    }

    public struct Instruction: Decodable, Sendable, Equatable {
        public let title: String
        public let text: String
    }

    public let schema: Int
    public let pattern: PatternInfo
    public let chart: ChartInfo
    public let generator: GeneratorInfo?
    public let palette: [PaletteEntry]
    public let rows: [String]
    public let layers: [String: Layer]?
    public let gauge: Gauge
    public let technique: JSONValue
    public let passes: JSONValue?
    public let instructions: [Instruction]

    enum CodingKeys: String, CodingKey {
        case schema, pattern, chart, generator, palette, rows, layers, gauge, technique, passes, instructions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        pattern = try c.decode(PatternInfo.self, forKey: .pattern)
        chart = try c.decode(ChartInfo.self, forKey: .chart)
        generator = try c.decodeIfPresent(GeneratorInfo.self, forKey: .generator)
        palette = try c.decode([PaletteEntry].self, forKey: .palette)
        rows = try c.decode([String].self, forKey: .rows)
        layers = try c.decodeIfPresent([String: Layer].self, forKey: .layers)
        gauge = try c.decode(Gauge.self, forKey: .gauge)
        technique = try c.decode(JSONValue.self, forKey: .technique)
        let rawPasses = try c.decodeIfPresent(JSONValue.self, forKey: .passes)
        passes = rawPasses == .null ? nil : rawPasses
        instructions = try c.decodeIfPresent([Instruction].self, forKey: .instructions) ?? []
    }

    public static func decode(_ data: Data) throws -> ChartDocument {
        try JSONDecoder().decode(ChartDocument.self, from: data)
    }

    public var techniqueType: String { technique["type"]?.stringValue ?? "" }
    public var techniqueStart: String { technique["start"]?.stringValue ?? "bottom" }
    public var techniqueFirstSide: String { technique["first_side"]?.stringValue ?? "RS" }
    public var techniqueRSDirection: String { technique["rs_direction"]?.stringValue ?? "rtl" }
}
```
`Chart.swift`:
```swift
import Foundation

public enum ChartError: Error, Equatable {
    case unsupportedSchema(Int)
    case tooManyColors(Int)
    case invalidCode(String)
    case duplicateCode(String)
    case invalidHex(code: String, hex: String)
    case heightMismatch(rows: Int, height: Int)
    case malformedRow(Int)
    case unknownCode(row: Int, code: String)
    case rowSum(row: Int, got: Int, expected: Int)
    case idMismatch(expected: String, found: String)
}

/// One run of a grid row in left-to-right order: palette index, length, leftmost column.
public struct GridRun: Equatable, Sendable {
    public let colorIndex: Int
    public let count: Int
    public let x0: Int
    public init(colorIndex: Int, count: Int, x0: Int) {
        self.colorIndex = colorIndex; self.count = count; self.x0 = x0
    }
}

public struct FinishedSize: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let unit: String
}

/// A decoded, validated chart: the document plus its cells as palette indexes, top row first.
public struct Chart: Sendable {
    public let document: ChartDocument
    public let width: Int
    public let height: Int
    public let palette: [ChartDocument.PaletteEntry]
    public let cells: [UInt8]
    public let runsByRow: [[GridRun]]
    /// Non-fatal observations, e.g. codes that differ only by case.
    public let warnings: [String]
    private let index: [String: Int]

    public var id: String { document.chart.id }
    public var title: String { document.pattern.title }

    public var cellAspect: Double {
        (document.gauge.stitches / document.gauge.rows * 10000).rounded() / 10000
    }

    public var finishedSize: FinishedSize {
        let g = document.gauge
        let w = Double(width) / (g.stitches / g.over.value)
        let h = Double(height) / (g.rows / g.over.value)
        return FinishedSize(width: (w * 10).rounded() / 10, height: (h * 10).rounded() / 10, unit: g.over.unit)
    }

    public func colorIndex(of code: String) -> Int? { index[code] }

    public func cell(x: Int, y: Int) -> Int { Int(cells[y * width + x]) }

    public static func load(_ data: Data) throws -> Chart {
        try Chart(document: ChartDocument.decode(data))
    }

    public init(document: ChartDocument) throws {
        guard document.schema == 2 else { throw ChartError.unsupportedSchema(document.schema) }
        guard document.palette.count <= 255 else { throw ChartError.tooManyColors(document.palette.count) }
        var index: [String: Int] = [:]
        var folded: [String: String] = [:]
        var warnings: [String] = []
        for (i, entry) in document.palette.enumerated() {
            guard RunString.isValidCode(entry.code) else { throw ChartError.invalidCode(entry.code) }
            guard index[entry.code] == nil else { throw ChartError.duplicateCode(entry.code) }
            guard Chart.isHex(entry.hex) else { throw ChartError.invalidHex(code: entry.code, hex: entry.hex) }
            index[entry.code] = i
            if let other = folded[entry.code.lowercased()] {
                warnings.append("palette codes \(other) and \(entry.code) differ only by case; easy to misread at the hook")
            } else {
                folded[entry.code.lowercased()] = entry.code
            }
        }
        let width = document.chart.width
        let height = document.chart.height
        guard document.rows.count == height else { throw ChartError.heightMismatch(rows: document.rows.count, height: height) }
        var cells = [UInt8](repeating: 0, count: width * height)
        var runsByRow: [[GridRun]] = []
        runsByRow.reserveCapacity(height)
        for (y, row) in document.rows.enumerated() {
            guard let parsed = RunString.parse(row) else { throw ChartError.malformedRow(y) }
            var x = 0
            var runs: [GridRun] = []
            for (code, count) in parsed {
                guard let ci = index[code] else { throw ChartError.unknownCode(row: y, code: code) }
                guard x + count <= width else { throw ChartError.rowSum(row: y, got: parsed.reduce(0) { $0 + $1.count }, expected: width) }
                for i in 0..<count { cells[y * width + x + i] = UInt8(ci) }
                runs.append(GridRun(colorIndex: ci, count: count, x0: x))
                x += count
            }
            guard x == width else { throw ChartError.rowSum(row: y, got: x, expected: width) }
            runsByRow.append(runs)
        }
        let expected = ChartID.compute(codes: document.palette.map(\.code), rows: document.rows, technique: document.technique, passes: document.passes)
        guard expected == document.chart.id else { throw ChartError.idMismatch(expected: expected, found: document.chart.id) }
        self.document = document
        self.width = width
        self.height = height
        self.palette = document.palette
        self.cells = cells
        self.runsByRow = runsByRow
        self.warnings = warnings
        self.index = index
    }

    static func isHex(_ s: String) -> Bool {
        s.count == 7 && s.hasPrefix("#") && s.dropFirst().allSatisfy(\.isHexDigit)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd ios && mise run core-test` → all pass. If `rejectsMalformedDocuments`'s `rowSum` case for `["2A2B","3A"]` reports the wrong row, note that row indexes are 0-based grid rows (top first): `3A` is row 1.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "feat(core): decode chart schema 2 into a validated Chart with cells and runs"
```

---

### Task 4: Work sequence: passes, runs, technique derivation

**Files:**
- Create: `…/Sources/GraphghanCore/WorkSequence.swift`
- Test: `…/Tests/GraphghanCoreTests/WorkSequenceTests.swift`

**Interfaces:**
- Produces: `public struct Cursor: Equatable, Hashable, Codable, Sendable { row: Int; run: Int; static let start }`; `public enum Side: String { rs = "RS", ws = "WS"; var other }`; `public enum Direction: String { rtl, ltr; var flipped }`; `public struct Run: Equatable, Sendable, Hashable { code: String; count: Int; x0: Int? }`; `public struct Pass: Equatable, Sendable { label: String; side: Side?; direction: Direction?; gridRow: Int?; runs: [Run] }`; `public enum SequenceError: Error, Equatable { unsupportedTechnique(String), malformedPasses(String) }`; `public struct WorkSequence: Sendable { passes: [Pass]; totalStitches: Int; init(chart:) throws; init(passes:); func pass(at row: Int) -> Pass?; func isValid(_ cursor: Cursor) -> Bool; func stitchesBefore(_ cursor: Cursor) -> Int?; var isEmpty; var jsonValue: JSONValue }`.

- [ ] **Step 1: Failing tests**

`WorkSequenceTests.swift`:
```swift
import CryptoKit
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct WorkSequenceTests {
    struct ExpectedRun: Decodable, Equatable { let code: String; let count: Int; let x0: Int? }
    struct ExpectedPass: Decodable {
        let label: String; let side: String?; let direction: String?; let gridRow: Int?; let runs: [ExpectedRun]
        enum CodingKeys: String, CodingKey { case label, side, direction, gridRow = "grid_row", runs }
    }
    struct ExpectedSequence: Decodable { let passes: [ExpectedPass]?; let sha256: String? }

    static func sequence(_ name: String) throws -> WorkSequence {
        try WorkSequence(chart: Chart.load(Fixtures.data("\(name).chart.json")))
    }

    @Test(arguments: Fixtures.chartNames)
    func matchesFixture(name: String) throws {
        let path = Fixtures.directory.appendingPathComponent("\(name).sequence.json")
        guard FileManager.default.fileExists(atPath: path.path) else {
            #expect(throws: SequenceError.self) { try Self.sequence(name) }
            return
        }
        let expected = try JSONDecoder().decode(ExpectedSequence.self, from: Data(contentsOf: path))
        let seq = try Self.sequence(name)
        if let passes = expected.passes {
            #expect(seq.passes.count == passes.count)
            for (got, want) in zip(seq.passes, passes) {
                #expect(got.label == want.label)
                #expect(got.side?.rawValue == want.side)
                #expect(got.direction?.rawValue == want.direction)
                #expect(got.gridRow == want.gridRow)
                #expect(got.runs.map { ExpectedRun(code: $0.code, count: $0.count, x0: $0.x0) } == want.runs)
            }
        }
        if let sha = expected.sha256 {
            let canonical = CanonicalJSON.encode(seq.jsonValue)
            let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
            #expect(digest == sha)
        }
    }

    @Test func unknownTechniqueNames() throws {
        #expect(throws: SequenceError.unsupportedTechnique("tunisian")) { try Self.sequence("unknown-technique") }
    }

    @Test func stitchMath() throws {
        let seq = try Self.sequence("minimal-rows")  // 12 passes of 14 stitches; rows 3-10 have 3 runs
        #expect(seq.totalStitches == 168)
        #expect(seq.stitchesBefore(Cursor(row: 1, run: 0)) == 0)
        #expect(seq.stitchesBefore(Cursor(row: 3, run: 1)) == 30)
        #expect(seq.stitchesBefore(Cursor(row: 3, run: 3)) == 42)   // past the last run of row 3
        #expect(seq.stitchesBefore(Cursor(row: 13, run: 0)) == nil)
        #expect(seq.stitchesBefore(Cursor(row: 3, run: 4)) == nil)
        #expect(seq.isValid(Cursor(row: 12, run: 1)) && !seq.isValid(Cursor(row: 12, run: 2)))
        #expect(seq.pass(at: 1)?.label == "Row 1" && seq.pass(at: 0) == nil)
    }

    @Test func roundsLabelAndSides() throws {
        let seq = try Self.sequence("minimal-rounds")
        #expect(seq.passes[1].label == "Round 2" && seq.passes[1].side == .rs && seq.passes[1].direction == .rtl)
    }

    @Test func explicitPassesRejectUnknownCodes() throws {
        var json = String(decoding: Fixtures.data("explicit-passes.chart.json"), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"code\": \"B\"", with: "\"code\": \"Q\"")
        // The id no longer matches after editing passes, so build the document directly.
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(throws: SequenceError.self) { try WorkSequence(chart: try Chart.unchecked(document: doc)) }
    }
}
```
This last test needs an `unchecked` initializer that skips only the id check; add it (internal, `static func unchecked(document:) throws -> Chart`) by factoring the body of `Chart.init` into `init(document:verifyID:)` with `init(document:)` calling `verifyID: true`. Keep `init(document:)` public and the `verifyID` variant internal.

- [ ] **Step 2: Run to verify failure**

Run: `cd ios && mise run core-test` → compile errors.

- [ ] **Step 3: Implement**

`WorkSequence.swift`:
```swift
import Foundation

/// Where the crocheter is: the 1-based pass and the 0-based run within it.
/// `run == runs.count` on the last pass means the chart is finished.
public struct Cursor: Equatable, Hashable, Codable, Sendable {
    public var row: Int
    public var run: Int
    public init(row: Int, run: Int) { self.row = row; self.run = run }
    public static let start = Cursor(row: 1, run: 0)
}

public enum Side: String, Codable, Sendable, Equatable {
    case rs = "RS"
    case ws = "WS"
    public var other: Side { self == .rs ? .ws : .rs }
}

public enum Direction: String, Codable, Sendable, Equatable {
    case rtl, ltr
    public var flipped: Direction { self == .rtl ? .ltr : .rtl }
}

public struct Run: Equatable, Hashable, Sendable {
    public let code: String
    public let count: Int
    /// Leftmost grid column of the run regardless of reading direction; nil for explicit passes that omit it.
    public let x0: Int?
    public init(code: String, count: Int, x0: Int?) { self.code = code; self.count = count; self.x0 = x0 }
}

public struct Pass: Equatable, Sendable {
    public let label: String
    public let side: Side?
    public let direction: Direction?
    public let gridRow: Int?
    public let runs: [Run]
    public init(label: String, side: Side?, direction: Direction?, gridRow: Int?, runs: [Run]) {
        self.label = label; self.side = side; self.direction = direction; self.gridRow = gridRow; self.runs = runs
    }
    public var stitches: Int { runs.reduce(0) { $0 + $1.count } }
}

public enum SequenceError: Error, Equatable {
    case unsupportedTechnique(String)
    case malformedPasses(String)
}

/// The chart in working order. Explicit `passes` win; `rows` and `rounds` are derived; anything
/// else has no working order (display only). Mirrors graphghan.chartdoc.sequence.
public struct WorkSequence: Sendable {
    public let passes: [Pass]
    public let totalStitches: Int
    private let before: [Int]  // stitches before pass i (0-based)

    public init(passes: [Pass]) {
        self.passes = passes
        var before: [Int] = []
        var total = 0
        for p in passes { before.append(total); total += p.stitches }
        self.before = before
        self.totalStitches = total
    }

    public init(chart: Chart) throws {
        if let raw = chart.document.passes {
            self.init(passes: try WorkSequence.explicitPasses(raw, chart: chart))
            return
        }
        let doc = chart.document
        let type = doc.techniqueType
        guard type == "rows" || type == "rounds" else { throw SequenceError.unsupportedTechnique(type) }
        let firstSide = Side(rawValue: doc.techniqueFirstSide) ?? .rs
        let rsDirection = Direction(rawValue: doc.techniqueRSDirection) ?? .rtl
        let fromBottom = doc.techniqueStart != "top"
        let label = type == "rows" ? "Row" : "Round"
        var passes: [Pass] = []
        passes.reserveCapacity(chart.height)
        for k in 1...max(chart.height, 1) where chart.height > 0 {
            let y = fromBottom ? chart.height - k : k - 1
            let side: Side
            let direction: Direction
            if type == "rows" {
                side = k % 2 == 1 ? firstSide : firstSide.other
                direction = side == .rs ? rsDirection : rsDirection.flipped
            } else {
                side = firstSide
                direction = rsDirection
            }
            var runs = chart.runsByRow[y].map { Run(code: chart.palette[$0.colorIndex].code, count: $0.count, x0: $0.x0) }
            if direction == .rtl { runs.reverse() }
            passes.append(Pass(label: "\(label) \(k)", side: side, direction: direction, gridRow: y, runs: runs))
        }
        self.init(passes: passes)
    }

    private static func explicitPasses(_ raw: JSONValue, chart: Chart) throws -> [Pass] {
        guard let list = raw.arrayValue else { throw SequenceError.malformedPasses("passes is not a list") }
        return try list.enumerated().map { i, item in
            guard let o = item.objectValue else { throw SequenceError.malformedPasses("passes[\(i)] is not an object") }
            guard let runsRaw = o["runs"]?.arrayValue else { throw SequenceError.malformedPasses("passes[\(i)].runs is not a list") }
            let runs = try runsRaw.enumerated().map { j, r -> Run in
                guard let ro = r.objectValue, let code = ro["code"]?.stringValue, let count = ro["count"]?.intValue, count >= 1 else {
                    throw SequenceError.malformedPasses("passes[\(i)].runs[\(j)] is malformed")
                }
                guard chart.colorIndex(of: code) != nil else { throw SequenceError.malformedPasses("passes[\(i)].runs[\(j)] uses unknown code \(code)") }
                return Run(code: code, count: count, x0: ro["x0"]?.intValue)
            }
            let side = o["side"]?.stringValue.flatMap(Side.init(rawValue:))
            let direction = o["direction"]?.stringValue.flatMap(Direction.init(rawValue:))
            return Pass(label: o["label"]?.stringValue ?? "", side: side, direction: direction, gridRow: o["grid_row"]?.intValue, runs: runs)
        }
    }

    public var isEmpty: Bool { passes.isEmpty }

    public func pass(at row: Int) -> Pass? {
        guard row >= 1, row <= passes.count else { return nil }
        return passes[row - 1]
    }

    public func isValid(_ cursor: Cursor) -> Bool {
        guard let p = pass(at: cursor.row) else { return false }
        return cursor.run >= 0 && cursor.run <= p.runs.count
    }

    /// Stitches completed when the cursor sits at (row, run): every earlier pass plus the runs before `run`.
    public func stitchesBefore(_ cursor: Cursor) -> Int? {
        guard isValid(cursor) else { return nil }
        let p = passes[cursor.row - 1]
        return before[cursor.row - 1] + p.runs.prefix(cursor.run).reduce(0) { $0 + $1.count }
    }

    /// The pass list in the shape Python's `chartdoc.sequence` returns, for hashing against fixtures.
    public var jsonValue: JSONValue {
        .array(passes.map { p in
            .object([
                "label": .string(p.label),
                "side": p.side.map { .string($0.rawValue) } ?? .null,
                "direction": p.direction.map { .string($0.rawValue) } ?? .null,
                "grid_row": p.gridRow.map(JSONValue.int) ?? .null,
                "runs": .array(p.runs.map { r in
                    .object(["code": .string(r.code), "count": .int(r.count), "x0": r.x0.map(JSONValue.int) ?? .null])
                }),
            ])
        })
    }
}
```
In `Chart.swift`, change the initializer to:
```swift
    public init(document: ChartDocument) throws { try self.init(document: document, verifyID: true) }

    static func unchecked(document: ChartDocument) throws -> Chart { try Chart(document: document, verifyID: false) }

    init(document: ChartDocument, verifyID: Bool) throws {
        // ... existing body, with the id check wrapped in `if verifyID { ... }`
    }
```

- [ ] **Step 4: Run the tests**

Run: `cd ios && mise run core-test` → all pass, including the `craigh-na-dun` sha256 pin (proves the Swift sequencer matches Python's on 184 passes).

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "feat(core): work sequence with rows/rounds derivation, explicit passes, and stitch math"
```

---

### Task 5: Work engine: cursor actions at every boundary

**Files:**
- Create: `…/Sources/GraphghanCore/WorkEngine.swift`
- Test: `…/Tests/GraphghanCoreTests/WorkEngineTests.swift`

**Interfaces:**
- Produces: `public enum EventKind: String, Codable, Sendable { advance, back, jump }`; `public enum WorkAction: Equatable, Sendable { advance, back, jump(row: Int, run: Int = 0) }`; `public struct WorkStep: Equatable, Sendable { cursor: Cursor; kind: EventKind; startedNewRow: Bool; finished: Bool }`; `public enum WorkEngine { static func apply(_: WorkAction, to: Cursor, in: WorkSequence) -> WorkStep?; static func isFinished(_: Cursor, in: WorkSequence) -> Bool }`.

Semantics: `advance` from `(r, i)`: if `i + 1 < runs(r).count` → `(r, i+1)`; else if `r < passes.count` → `(r+1, 0)` with `startedNewRow`; else `(r, runs(r).count)` with `finished` (advancing a finished cursor returns nil). `back` from `(r, i)`: if `i > 0` → `(r, i-1)`; else if `r > 1` → `(r-1, runs(r-1).count - 1)`; else nil. `jump(row, run)` → `(row, run)` when `1...passes.count` contains `row` and `0 <= run < runs(row).count`, else nil; `startedNewRow` is true when `row` differs from the current row. `back` never reports `startedNewRow` (haptics only celebrate forward progress). Invalid input cursors return nil.

- [ ] **Step 1: Failing tests**

`WorkEngineTests.swift`:
```swift
import Testing
@testable import GraphghanCore

@Suite struct WorkEngineTests {
    // 12 passes; rows 1,2,11,12 have 1 run; rows 3-10 have 3 runs.
    static let seq = try! WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))

    @Test func advanceWithinRow() {
        let step = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 0), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 1), kind: .advance, startedNewRow: false, finished: false))
    }

    @Test func advanceAcrossRow() {
        let step = WorkEngine.apply(.advance, to: Cursor(row: 3, run: 2), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 4, run: 0), kind: .advance, startedNewRow: true, finished: false))
        #expect(WorkEngine.apply(.advance, to: .start, in: Self.seq)?.cursor == Cursor(row: 2, run: 0))
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
        let step = WorkEngine.apply(.back, to: Cursor(row: 4, run: 0), in: Self.seq)
        #expect(step == WorkStep(cursor: Cursor(row: 3, run: 2), kind: .back, startedNewRow: false, finished: false))
        #expect(WorkEngine.apply(.back, to: Cursor(row: 12, run: 1), in: Self.seq)?.cursor == Cursor(row: 12, run: 0))
    }

    @Test func backAtTheStartIsNoOp() {
        #expect(WorkEngine.apply(.back, to: .start, in: Self.seq) == nil)
    }

    @Test func jump() {
        #expect(WorkEngine.apply(.jump(row: 7), to: .start, in: Self.seq) == WorkStep(cursor: Cursor(row: 7, run: 0), kind: .jump, startedNewRow: true, finished: false))
        #expect(WorkEngine.apply(.jump(row: 0), to: .start, in: Self.seq) == nil)
        #expect(WorkEngine.apply(.jump(row: 13), to: .start, in: Self.seq) == nil)
        // jumping within the current row (tapping a chip) is not a new row
        #expect(WorkEngine.apply(.jump(row: 3, run: 2), to: Cursor(row: 3, run: 0), in: Self.seq)
            == WorkStep(cursor: Cursor(row: 3, run: 2), kind: .jump, startedNewRow: false, finished: false))
        #expect(WorkEngine.apply(.jump(row: 3, run: 3), to: .start, in: Self.seq) == nil)  // run == runs.count only via advance
    }

    @Test func invalidCursorIsRejected() {
        #expect(WorkEngine.apply(.advance, to: Cursor(row: 99, run: 0), in: Self.seq) == nil)
        #expect(WorkEngine.apply(.back, to: Cursor(row: 3, run: 9), in: Self.seq) == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** → compile errors.

- [ ] **Step 3: Implement**

`WorkEngine.swift`:
```swift
public enum EventKind: String, Codable, Sendable {
    case advance, back, jump
}

public enum WorkAction: Equatable, Sendable {
    case advance
    case back
    case jump(row: Int, run: Int = 0)
}

public struct WorkStep: Equatable, Sendable {
    public let cursor: Cursor
    public let kind: EventKind
    /// The step moved the cursor onto a different pass (advance across a row, or a jump).
    public let startedNewRow: Bool
    /// The step completed the last run of the last pass.
    public let finished: Bool
    public init(cursor: Cursor, kind: EventKind, startedNewRow: Bool, finished: Bool) {
        self.cursor = cursor; self.kind = kind; self.startedNewRow = startedNewRow; self.finished = finished
    }
}

/// The one place cursor movement is defined. Screens, intents and the Live Activity all call this.
public enum WorkEngine {
    public static func isFinished(_ cursor: Cursor, in seq: WorkSequence) -> Bool {
        guard let last = seq.passes.last else { return false }
        return cursor.row == seq.passes.count && cursor.run == last.runs.count
    }

    public static func apply(_ action: WorkAction, to cursor: Cursor, in seq: WorkSequence) -> WorkStep? {
        guard seq.isValid(cursor) else { return nil }
        switch action {
        case .advance:
            if isFinished(cursor, in: seq) { return nil }
            let runs = seq.passes[cursor.row - 1].runs.count
            if cursor.run + 1 < runs {
                return WorkStep(cursor: Cursor(row: cursor.row, run: cursor.run + 1), kind: .advance, startedNewRow: false, finished: false)
            }
            if cursor.row < seq.passes.count {
                return WorkStep(cursor: Cursor(row: cursor.row + 1, run: 0), kind: .advance, startedNewRow: true, finished: false)
            }
            return WorkStep(cursor: Cursor(row: cursor.row, run: runs), kind: .advance, startedNewRow: false, finished: true)
        case .back:
            if cursor.run > 0 {
                return WorkStep(cursor: Cursor(row: cursor.row, run: cursor.run - 1), kind: .back, startedNewRow: false, finished: false)
            }
            if cursor.row > 1 {
                let prevRuns = seq.passes[cursor.row - 2].runs.count
                return WorkStep(cursor: Cursor(row: cursor.row - 1, run: max(0, prevRuns - 1)), kind: .back, startedNewRow: false, finished: false)
            }
            return nil
        case .jump(let row, let run):
            guard let pass = seq.pass(at: row), run >= 0, run < pass.runs.count else { return nil }
            return WorkStep(cursor: Cursor(row: row, run: run), kind: .jump, startedNewRow: row != cursor.row, finished: false)
        }
    }
}
```
- [ ] **Step 4: Run the tests** → all pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "feat(core): work engine with advance, back, and jump at every boundary"
```

---

### Task 6: Progress document and pace

**Files:**
- Create: `…/Sources/GraphghanCore/ProgressDocument.swift`, `…/Pace.swift`
- Test: `…/Tests/GraphghanCoreTests/ProgressDocumentTests.swift`, `…/PaceTests.swift`

**Interfaces:**
- Produces: `public struct ProgressEventRecord: Codable, Equatable, Sendable { t: Date; row: Int; run: Int; kind: EventKind }`; `public struct ProgressDocument: Codable, Equatable, Sendable { schema: Int; patternID: String; chartID: String?; patternVersion: String?; cursor: Cursor; started: Date?; finished: Date?; events: [ProgressEventRecord]; static func decode(_: Data) throws -> ProgressDocument; func encode() throws -> Data; static func legacy(slug:row:run:) -> ProgressDocument }`; `public enum ProgressDates { static func parse(_: String) -> Date?; static func format(_: Date) -> String }`; `public struct Session: Equatable, Sendable { start: Date; end: Date; stitches: Int; var seconds: Int }`; `public struct ProgressSummary: Equatable, Sendable { percent: Double; stitchesDone: Int; totalStitches: Int; sessions: [Session]; activeSeconds: Int; stitchesPerHour: Double? }`; `public enum Pace { static let sessionGap: TimeInterval = 1200; static func summarize(events:cursor:sequence:gap:) -> ProgressSummary; static func estimatedFinish(remainingStitches:stitchesPerHour:sessions:now:windowDays:minimumSessions:) -> Date? }`.

- [ ] **Step 1: Failing tests**

`ProgressDocumentTests.swift`:
```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ProgressDocumentTests {
    @Test func decodesTheFixture() throws {
        let doc = try ProgressDocument.decode(Fixtures.data("progress-basic.progress.json"))
        #expect(doc.schema == 1 && doc.patternID == "minimal" && doc.patternVersion == "1.0.0")
        #expect(doc.cursor == Cursor(row: 5, run: 1) && doc.finished == nil)
        #expect(doc.events.count == 8 && doc.events[4].kind == .back && doc.events[6].kind == .jump)
        #expect(ProgressDates.format(doc.started!) == "2026-09-12T18:00:00Z")
    }

    @Test func roundTripsAndWritesNullChartID() throws {
        let doc = ProgressDocument.legacy(slug: "craigh-na-dun", row: 42, run: 3)
        let data = try doc.encode()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"chart_id\":null"))
        #expect(text.contains("\"pattern_id\":\"craigh-na-dun\""))
        #expect(try ProgressDocument.decode(data) == doc)
    }

    @Test func datesAcceptFractionalSeconds() {
        #expect(ProgressDates.parse("2026-09-12T18:00:00Z") != nil)
        #expect(ProgressDates.parse("2026-09-12T18:00:00.250Z") != nil)
        #expect(ProgressDates.parse("yesterday") == nil)
    }
}
```
`PaceTests.swift`:
```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct PaceTests {
    struct ExpectedSession: Decodable { let start: String; let end: String; let stitches: Int }
    struct Expected: Decodable {
        let percent: Double; let stitchesDone: Int; let totalStitches: Int; let sessions: [ExpectedSession]
        let activeSeconds: Int; let stitchesPerHour: Double?
        enum CodingKeys: String, CodingKey {
            case percent, stitchesDone = "stitches_done", totalStitches = "total_stitches", sessions
            case activeSeconds = "active_seconds", stitchesPerHour = "stitches_per_hour"
        }
    }

    @Test func matchesTheProgressFixture() throws {
        let doc = try ProgressDocument.decode(Fixtures.data("progress-basic.progress.json"))
        let raw = try Fixtures.json("progress-basic.progress.json")
        let chartName = try #require(((raw["ext"] as? [String: Any])?["fixture"] as? [String: Any])?["chart"] as? String)
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("\(chartName).chart.json")))
        let expected = try JSONDecoder().decode(Expected.self, from: Fixtures.data("progress-basic.progress.expected.json"))
        let s = Pace.summarize(events: doc.events, cursor: doc.cursor, sequence: seq)
        #expect(abs(s.percent - expected.percent) < 0.001)
        #expect(s.stitchesDone == expected.stitchesDone && s.totalStitches == expected.totalStitches)
        #expect(s.activeSeconds == expected.activeSeconds)
        #expect(s.sessions.map(\.stitches) == expected.sessions.map(\.stitches))
        #expect(s.sessions.map { ProgressDates.format($0.start) } == expected.sessions.map(\.start))
        #expect(s.sessions.map { ProgressDates.format($0.end) } == expected.sessions.map(\.end))
        let rate = try #require(s.stitchesPerHour)
        #expect(abs(rate - (expected.stitchesPerHour ?? -1)) < 0.001)
    }

    @Test func noEventsAndSingleEvent() throws {
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))
        let empty = Pace.summarize(events: [], cursor: .start, sequence: seq)
        #expect(empty == ProgressSummary(percent: 0, stitchesDone: 0, totalStitches: 168, sessions: [], activeSeconds: 0, stitchesPerHour: nil))
        let t = ProgressDates.parse("2026-09-12T18:00:00Z")!
        let one = Pace.summarize(events: [ProgressEventRecord(t: t, row: 2, run: 0, kind: .advance)], cursor: Cursor(row: 2, run: 0), sequence: seq)
        #expect(one.sessions == [Session(start: t, end: t, stitches: 14)] && one.activeSeconds == 0 && one.stitchesPerHour == nil)
    }

    @Test func backwardsSessionClampsToZeroAndEventsAreSorted() throws {
        let seq = try WorkSequence(chart: Chart.load(Fixtures.data("minimal-rows.chart.json")))
        let t0 = ProgressDates.parse("2026-09-12T18:00:00Z")!
        let events = [
            ProgressEventRecord(t: t0.addingTimeInterval(300), row: 2, run: 0, kind: .back),
            ProgressEventRecord(t: t0, row: 3, run: 2, kind: .jump),
        ]
        let s = Pace.summarize(events: events, cursor: Cursor(row: 2, run: 0), sequence: seq)
        #expect(s.sessions.count == 1 && s.sessions[0].stitches == 14)  // from (1,0) to (2,0) net
        let s2 = Pace.summarize(events: [
            ProgressEventRecord(t: t0, row: 3, run: 2, kind: .jump),
            ProgressEventRecord(t: t0.addingTimeInterval(3000), row: 2, run: 0, kind: .back),  // new session, goes backwards
        ], cursor: Cursor(row: 2, run: 0), sequence: seq)
        #expect(s2.sessions.map(\.stitches) == [40, 0])
    }

    @Test func estimateNeedsThreeSessionsAndSpreadsOverTheWindow() {
        let now = ProgressDates.parse("2026-09-20T12:00:00Z")!
        let day: TimeInterval = 86400
        let sessions = [
            Session(start: now.addingTimeInterval(-3 * day), end: now.addingTimeInterval(-3 * day + 600), stitches: 30),
            Session(start: now.addingTimeInterval(-2 * day), end: now.addingTimeInterval(-2 * day + 240), stitches: 10),
            Session(start: now.addingTimeInterval(-1 * day), end: now.addingTimeInterval(-1 * day + 900), stitches: 18),
        ]
        #expect(Pace.estimatedFinish(remainingStitches: 110, stitchesPerHour: 120, sessions: Array(sessions.prefix(2)), now: now) == nil)
        #expect(Pace.estimatedFinish(remainingStitches: 110, stitchesPerHour: nil, sessions: sessions, now: now) == nil)
        let finish = Pace.estimatedFinish(remainingStitches: 110, stitchesPerHour: 120, sessions: sessions, now: now)!
        // 110 st / 120 st/h = 0.9167 h; mean active hours per day over 14 days = (1740/3600)/14 = 0.03452 h/day
        // → 26.55 days
        #expect(abs(finish.timeIntervalSince(now) / day - 26.55) < 0.05)
        // sessions older than the window do not count toward the daily mean
        let old = Session(start: now.addingTimeInterval(-30 * day), end: now.addingTimeInterval(-30 * day + 36000), stitches: 999)
        let finish2 = Pace.estimatedFinish(remainingStitches: 110, stitchesPerHour: 120, sessions: sessions + [old], now: now)!
        #expect(abs(finish2.timeIntervalSince(now) - finish.timeIntervalSince(now)) < 1)
        #expect(Pace.estimatedFinish(remainingStitches: 0, stitchesPerHour: 120, sessions: sessions, now: now) == now)
    }
}
```

- [ ] **Step 2: Run to verify failure** → compile errors.

- [ ] **Step 3: Implement**

`ProgressDocument.swift`:
```swift
import Foundation

/// Dates in progress documents: `2026-09-12T18:31:12Z` on output; fractional seconds accepted on input.
public enum ProgressDates {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    public static func parse(_ s: String) -> Date? { plain.date(from: s) ?? fractional.date(from: s) }
    public static func format(_ d: Date) -> String { plain.string(from: d) }
}

public struct ProgressEventRecord: Codable, Equatable, Sendable {
    public let t: Date
    public let row: Int
    public let run: Int
    public let kind: EventKind
    public init(t: Date, row: Int, run: Int, kind: EventKind) { self.t = t; self.row = row; self.run = run; self.kind = kind }
}

/// Progress document, schema 1 (docs/chart-format.md). Every event records the cursor after the action.
public struct ProgressDocument: Codable, Equatable, Sendable {
    public var schema: Int
    public var patternID: String
    public var chartID: String?
    public var patternVersion: String?
    public var cursor: Cursor
    public var started: Date?
    public var finished: Date?
    public var events: [ProgressEventRecord]

    enum CodingKeys: String, CodingKey {
        case schema, cursor, started, finished, events
        case patternID = "pattern_id", chartID = "chart_id", patternVersion = "pattern_version"
    }

    public init(patternID: String, chartID: String?, patternVersion: String? = nil, cursor: Cursor, started: Date? = nil, finished: Date? = nil, events: [ProgressEventRecord] = []) {
        self.schema = GraphghanCore.progressSchema
        self.patternID = patternID; self.chartID = chartID; self.patternVersion = patternVersion
        self.cursor = cursor; self.started = started; self.finished = finished; self.events = events
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        patternID = try c.decode(String.self, forKey: .patternID)
        chartID = try c.decodeIfPresent(String.self, forKey: .chartID)
        patternVersion = try c.decodeIfPresent(String.self, forKey: .patternVersion)
        cursor = try c.decode(Cursor.self, forKey: .cursor)
        started = try c.decodeIfPresent(Date.self, forKey: .started)
        finished = try c.decodeIfPresent(Date.self, forKey: .finished)
        events = try c.decodeIfPresent([ProgressEventRecord].self, forKey: .events) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(patternID, forKey: .patternID)
        try c.encode(chartID, forKey: .chartID)  // nil encodes as null: the key is required by the schema
        try c.encodeIfPresent(patternVersion, forKey: .patternVersion)
        try c.encode(cursor, forKey: .cursor)
        try c.encodeIfPresent(started, forKey: .started)
        try c.encodeIfPresent(finished, forKey: .finished)
        try c.encode(events, forKey: .events)
    }

    public static func decode(_ data: Data) throws -> ProgressDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            guard let date = ProgressDates.parse(s) else {
                throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: "bad date \(s)")
            }
            return date
        }
        return try decoder.decode(ProgressDocument.self, from: data)
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, e in
            var c = e.singleValueContainer()
            try c.encode(ProgressDates.format(date))
        }
        return try encoder.encode(self)
    }

    /// A cursor-only document from the PWA's base64 `{slug,row,run}` code.
    public static func legacy(slug: String, row: Int, run: Int) -> ProgressDocument {
        ProgressDocument(patternID: slug, chartID: nil, cursor: Cursor(row: row, run: run))
    }
}
```
`Pace.swift`:
```swift
import Foundation

public struct Session: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let stitches: Int
    public init(start: Date, end: Date, stitches: Int) { self.start = start; self.end = end; self.stitches = stitches }
    public var seconds: Int { Int(end.timeIntervalSince(start).rounded(.down)) }
}

public struct ProgressSummary: Equatable, Sendable {
    public let percent: Double
    public let stitchesDone: Int
    public let totalStitches: Int
    public let sessions: [Session]
    public let activeSeconds: Int
    public let stitchesPerHour: Double?
    public init(percent: Double, stitchesDone: Int, totalStitches: Int, sessions: [Session], activeSeconds: Int, stitchesPerHour: Double?) {
        self.percent = percent; self.stitchesDone = stitchesDone; self.totalStitches = totalStitches
        self.sessions = sessions; self.activeSeconds = activeSeconds; self.stitchesPerHour = stitchesPerHour
    }
}

/// Sessions, rate and percent exactly as graphghan.progress.summarize computes them, plus the finish estimate.
public enum Pace {
    public static let sessionGap: TimeInterval = 1200

    private static func round1(_ x: Double) -> Double { (x * 10).rounded(.toNearestOrEven) / 10 }

    public static func summarize(events: [ProgressEventRecord], cursor: Cursor, sequence: WorkSequence, gap: TimeInterval = sessionGap) -> ProgressSummary {
        let total = sequence.totalStitches
        let done = sequence.stitchesBefore(cursor) ?? 0
        let sorted = events.sorted { $0.t < $1.t }
        var sessions: [Session] = []
        var start: Date?
        var end: Date?
        var fromCursor = Cursor.start
        var toCursor = Cursor.start
        var prevCursor = Cursor.start
        func close() {
            if let s = start, let e = end {
                let before = sequence.stitchesBefore(fromCursor) ?? 0
                let after = sequence.stitchesBefore(toCursor) ?? 0
                sessions.append(Session(start: s, end: e, stitches: max(0, after - before)))
            }
        }
        for e in sorted {
            if let last = end, e.t.timeIntervalSince(last) <= gap {
                end = e.t
            } else {
                close()
                start = e.t
                end = e.t
                fromCursor = prevCursor
            }
            toCursor = Cursor(row: e.row, run: e.run)
            prevCursor = toCursor
        }
        close()
        let active = sessions.reduce(0) { $0 + $1.seconds }
        let advanced = sessions.reduce(0) { $0 + $1.stitches }
        let rate: Double? = active > 0 ? round1(Double(advanced) / (Double(active) / 3600)) : nil
        return ProgressSummary(
            percent: total > 0 ? round1(100 * Double(done) / Double(total)) : 0,
            stitchesDone: done, totalStitches: total, sessions: sessions, activeSeconds: active, stitchesPerHour: rate
        )
    }

    /// Remaining stitches at the observed rate, spread over the mean active hours per calendar day
    /// across the last `windowDays`. Nil until `minimumSessions` sessions exist or with no rate.
    public static func estimatedFinish(remainingStitches: Int, stitchesPerHour: Double?, sessions: [Session], now: Date, windowDays: Int = 14, minimumSessions: Int = 3) -> Date? {
        guard sessions.count >= minimumSessions, let rate = stitchesPerHour, rate > 0 else { return nil }
        if remainingStitches <= 0 { return now }
        let windowStart = now.addingTimeInterval(-Double(windowDays) * 86400)
        var activeSeconds = 0.0
        for s in sessions {
            let start = max(s.start, windowStart)
            let end = min(s.end, now)
            if end > start { activeSeconds += end.timeIntervalSince(start) }
        }
        let hoursPerDay = activeSeconds / 3600 / Double(windowDays)
        guard hoursPerDay > 0 else { return nil }
        let hoursNeeded = Double(remainingStitches) / rate
        return now.addingTimeInterval(hoursNeeded / hoursPerDay * 86400)
    }
}
```

- [ ] **Step 4: Run the tests** → all pass (the fixture test is the Python parity check for the progress math).

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "feat(core): progress document codec, sessions and pace, finish estimate"
```

---

### Task 7: Site models: index entries and pattern manifests

**Files:**
- Create: `…/Sources/GraphghanCore/SiteModels.swift`
- Test: `…/Tests/GraphghanCoreTests/SiteModelsTests.swift`

**Interfaces:**
- Produces: `public struct IndexEntry: Decodable, Sendable, Identifiable, Equatable { slug, title, dedication, version, stitch: String; width, height: Int; sizeIn: [Double]; colors: Int; preview: String; manifest: String?; charts: Int?; var id: String }`; `public struct PatternManifest: Decodable, Sendable, Equatable { schema: Int; id, title, version, dedication, quote, author, license, preview: String; palette: [Swatch]; charts: [ManifestChart]; updated: String; var defaultChart: ManifestChart? }`; `public struct Swatch: Decodable, Sendable, Equatable { code, name, hex }`; `public struct ManifestChart: Decodable, Sendable, Identifiable, Equatable { id, variant, gaugeKey: String; isDefault: Bool; path, preview: String; width, height: Int; size: Size; stitch: String; colors, stitches: Int; changesPerRow: Changes; yardsEst: Int; var key: String }` with `Size { width, height: Double; unit: String }`, `Changes { mean, max: Double }`.

- [ ] **Step 1: Failing test**

`SiteModelsTests.swift`:
```swift
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct SiteModelsTests {
    static let index = #"""
    [{"slug":"craigh-na-dun","title":"Craigh na Dun Blanket","version":"1.0.0","stitch":"sc","width":189,"height":184,
      "size_in":[54.0,46.0],"dedication":"For Meaghan","colors":5,"preview":"patterns/craigh-na-dun/preview.png",
      "manifest":"patterns/craigh-na-dun/pattern.json","charts":2}]
    """#
    static let manifest = #"""
    {"schema":1,"id":"craigh-na-dun","title":"Craigh na Dun Blanket","version":"1.0.0","dedication":"For Meaghan",
     "quote":"Lord…","author":"Tyler Vick","license":"CC-BY-NC-SA-4.0","preview":"preview.png",
     "palette":[{"code":"C","name":"Cream","hex":"#f2e8d5"}],
     "charts":[
       {"id":"sha256:aaaa","variant":"final","gauge_key":"sc","default":true,"path":"charts/final-sc/chart.json",
        "preview":"charts/final-sc/preview.png","width":189,"height":184,"size":{"width":54.0,"height":46.0,"unit":"in"},
        "stitch":"sc","colors":5,"stitches":34776,"changes_per_row":{"mean":6.1,"max":23},"yards_est":3200},
       {"id":"sha256:bbbb","variant":"final","gauge_key":"hdc","default":false,"path":"charts/final-hdc/chart.json",
        "preview":"charts/final-hdc/preview.png","width":176,"height":115,"size":{"width":54.2,"height":46.0,"unit":"in"},
        "stitch":"hdc","colors":5,"stitches":20240,"changes_per_row":{"mean":5.0,"max":20},"yards_est":2100}],
     "updated":"2026-09-11T03:00:00Z"}
    """#

    @Test func decodesIndex() throws {
        let entries = try JSONDecoder().decode([IndexEntry].self, from: Data(Self.index.utf8))
        #expect(entries.count == 1 && entries[0].id == "craigh-na-dun" && entries[0].sizeIn == [54, 46])
        #expect(entries[0].manifest == "patterns/craigh-na-dun/pattern.json" && entries[0].charts == 2)
    }

    @Test func decodesManifest() throws {
        let m = try JSONDecoder().decode(PatternManifest.self, from: Data(Self.manifest.utf8))
        #expect(m.charts.count == 2 && m.defaultChart?.gaugeKey == "sc" && m.charts[1].isDefault == false)
        #expect(m.charts[0].key == "final-sc" && m.charts[1].size.width == 54.2 && m.charts[1].changesPerRow.max == 20)
        #expect(m.palette[0].hex == "#f2e8d5" && m.license == "CC-BY-NC-SA-4.0")
    }

    @Test func indexToleratesMissingNewKeys() throws {
        let old = Self.index.replacingOccurrences(of: #","manifest":"patterns/craigh-na-dun/pattern.json","charts":2"#, with: "")
        let entries = try JSONDecoder().decode([IndexEntry].self, from: Data(old.utf8))
        #expect(entries[0].manifest == nil && entries[0].charts == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** → compile errors.

- [ ] **Step 3: Implement**

`SiteModels.swift`:
```swift
import Foundation

/// One row of the site's `patterns/index.json`.
public struct IndexEntry: Decodable, Sendable, Identifiable, Equatable {
    public let slug: String
    public let title: String
    public let dedication: String
    public let version: String
    public let stitch: String
    public let width: Int
    public let height: Int
    public let sizeIn: [Double]
    public let colors: Int
    public let preview: String
    public let manifest: String?
    public let charts: Int?
    public var id: String { slug }
    enum CodingKeys: String, CodingKey {
        case slug, title, dedication, version, stitch, width, height, colors, preview, manifest, charts
        case sizeIn = "size_in"
    }
}

public struct Swatch: Decodable, Sendable, Equatable {
    public let code: String
    public let name: String
    public let hex: String
}

/// One published chart in a pattern manifest. Paths are relative to `patterns/<id>/` on the site.
public struct ManifestChart: Decodable, Sendable, Identifiable, Equatable {
    public struct Size: Decodable, Sendable, Equatable {
        public let width: Double
        public let height: Double
        public let unit: String
    }
    public struct Changes: Decodable, Sendable, Equatable {
        public let mean: Double
        public let max: Double
    }
    public let id: String
    public let variant: String
    public let gaugeKey: String
    public let isDefault: Bool
    public let path: String
    public let preview: String
    public let width: Int
    public let height: Int
    public let size: Size
    public let stitch: String
    public let colors: Int
    public let stitches: Int
    public let changesPerRow: Changes
    public let yardsEst: Int
    public var key: String { "\(variant)-\(gaugeKey)" }
    enum CodingKeys: String, CodingKey {
        case id, variant, path, preview, width, height, size, stitch, colors, stitches
        case gaugeKey = "gauge_key", isDefault = "default", changesPerRow = "changes_per_row", yardsEst = "yards_est"
    }
}

/// `patterns/<id>/pattern.json` (manifest schema 1).
public struct PatternManifest: Decodable, Sendable, Equatable {
    public let schema: Int
    public let id: String
    public let title: String
    public let version: String
    public let dedication: String
    public let quote: String
    public let author: String
    public let license: String
    public let preview: String
    public let palette: [Swatch]
    public let charts: [ManifestChart]
    public let updated: String
    public var defaultChart: ManifestChart? { charts.first(where: \.isDefault) ?? charts.first }
}
```

- [ ] **Step 4: Run the tests** → all pass.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GraphghanCore
git commit -m "feat(core): site index and pattern manifest models"
```

---

### Task 8: App storage: App Group paths, SwiftData models, chart library

**Files:**
- Create: `ios/Graphghan/Storage/AppGroup.swift`, `ios/Graphghan/Storage/Persistence.swift`, `ios/Graphghan/Storage/Project.swift`, `ios/Graphghan/Storage/ProgressEvent.swift`, `ios/Graphghan/Storage/ChartLibrary.swift`, `ios/Tests/TestSupport.swift`
- Test: `ios/Tests/ProjectModelTests.swift`, `ios/Tests/ChartLibraryTests.swift`
- Delete: `ios/Tests/SmokeTests.swift` (superseded)

**Interfaces:**
- Produces: `enum AppGroup { identifier; containerURL; supportURL; cachesURL; storeURL; chartsURL; patternsCacheURL }`; `enum Persistence { static func makeContainer(inMemory: Bool = false) throws -> ModelContainer }`; `@Model final class Project` (fields per spec 6.3 plus `chartVariant`, `chartGaugeKey`; `var cursor: Cursor`; `var eventRecords: [ProgressEventRecord]`; `var isFinished: Bool`); `@Model final class ProgressEvent { t, row, run, kindRaw, project?; var kind: EventKind }`; `actor ChartLibrary { init(directory:); func store(_ data: Data) throws -> Chart; func chart(id: String) throws -> Chart; func hasChart(id:) -> Bool; func remove(id:) throws }` with `ChartLibrary.LibraryError { missing(String), badID(String) }`; test helpers `TestFixtures.data(_:)`, `TestFixtures.directory`, `makeInMemoryContainer()`.

- [ ] **Step 1: Test support and failing tests**

`ios/Tests/TestSupport.swift`:
```swift
import Foundation
import SwiftData
@testable import Graphghan

enum TestFixtures {
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }  // Tests, ios, <repo>
        return url.appendingPathComponent("fixtures/chart-format", isDirectory: true)
    }()
    static func data(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
}

@MainActor
func makeInMemoryContainer() throws -> ModelContainer {
    try Persistence.makeContainer(inMemory: true)
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
```
`ios/Tests/ProjectModelTests.swift`:
```swift
import Foundation
import SwiftData
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct ProjectModelTests {
    @Test func cursorMapsToColumns() throws {
        let container = try makeInMemoryContainer()
        let p = Project(patternID: "x", chartID: "sha256:" + String(repeating: "a", count: 64), chartVariant: "final", chartGaugeKey: "sc", patternVersion: "1", title: "T", started: Date())
        container.mainContext.insert(p)
        p.cursor = Cursor(row: 4, run: 2)
        try container.mainContext.save()
        #expect(p.cursorRow == 4 && p.cursorRun == 2 && p.cursor == Cursor(row: 4, run: 2))
        #expect(!p.isFinished)
    }

    @Test func deletingAProjectCascadesToItsEvents() throws {
        let container = try makeInMemoryContainer()
        let ctx = container.mainContext
        let p = Project(patternID: "x", chartID: "sha256:" + String(repeating: "a", count: 64), chartVariant: "final", chartGaugeKey: "sc", patternVersion: "1", title: "T", started: Date())
        ctx.insert(p)
        for i in 0..<3 {
            let e = ProgressEvent(t: Date().addingTimeInterval(Double(i)), row: 1, run: i, kind: .advance)
            e.project = p
            ctx.insert(e)
        }
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<ProgressEvent>()) == 3)
        #expect(p.eventRecords.map(\.run) == [0, 1, 2])
        ctx.delete(p)
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<ProgressEvent>()) == 0)
    }
}
```
`ios/Tests/ChartLibraryTests.swift`:
```swift
import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct ChartLibraryTests {
    @Test func storesDecodesAndMemoizes() async throws {
        let dir = try temporaryDirectory()
        let lib = ChartLibrary(directory: dir)
        let data = try TestFixtures.data("two-letter-codes.chart.json")
        let chart = try await lib.store(data)
        #expect(chart.width == 12)
        #expect(await lib.hasChart(id: chart.id))
        let again = try await lib.chart(id: chart.id)
        #expect(again.id == chart.id)
        let fresh = ChartLibrary(directory: dir)  // reads the file back
        #expect(try await fresh.chart(id: chart.id).height == 2)
        try await lib.remove(id: chart.id)
        #expect(await !lib.hasChart(id: chart.id))
    }

    @Test func rejectsBadDataWithoutWriting() async throws {
        let dir = try temporaryDirectory()
        let lib = ChartLibrary(directory: dir)
        await #expect(throws: (any Error).self) { try await lib.store(Data("not json".utf8)) }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty ?? true)
        await #expect(throws: ChartLibrary.LibraryError.missing("sha256:" + String(repeating: "0", count: 64))) {
            try await lib.chart(id: "sha256:" + String(repeating: "0", count: 64))
        }
        await #expect(throws: ChartLibrary.LibraryError.badID("nope")) { try await lib.chart(id: "nope") }
    }
}
```
Delete `ios/Tests/SmokeTests.swift`.

- [ ] **Step 2: Run to verify failure**

Run: `cd ios && mise run test` → compile errors in the test target.

- [ ] **Step 3: Implement**

`AppGroup.swift`:
```swift
import Foundation

/// Where everything lives: the App Group container, so a widget extension and intents (later plans)
/// see the same store and chart files. Falls back to the app's own Application Support when the
/// group container is unavailable (e.g. a simulator build without the entitlement).
enum AppGroup {
    static let identifier = "group.com.tylervick.graphghan"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) { return url }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("graphghan-group", isDirectory: true)
    }

    static var supportURL: URL { containerURL.appendingPathComponent("Library/Application Support", isDirectory: true) }
    static var cachesURL: URL { containerURL.appendingPathComponent("Library/Caches", isDirectory: true) }
    static var storeURL: URL { supportURL.appendingPathComponent("graphghan.store") }
    static var chartsURL: URL { supportURL.appendingPathComponent("charts", isDirectory: true) }
    static var patternsCacheURL: URL { cachesURL.appendingPathComponent("patterns", isDirectory: true) }
}
```
`Persistence.swift`:
```swift
import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([Project.self, ProgressEvent.self])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            try FileManager.default.createDirectory(at: AppGroup.supportURL, withIntermediateDirectories: true)
            configuration = ModelConfiguration(schema: schema, url: AppGroup.storeURL)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```
`Project.swift`:
```swift
import Foundation
import SwiftData
import GraphghanCore

/// One instance of working a chart: which chart, where the crocheter is, and the event log.
@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var patternID: String
    var chartID: String
    var chartVariant: String
    var chartGaugeKey: String
    var patternVersion: String
    var title: String
    var started: Date
    var finished: Date?
    var notes: String
    var cursorRow: Int
    var cursorRun: Int
    var lastWorked: Date?
    @Relationship(deleteRule: .cascade, inverse: \ProgressEvent.project) var events: [ProgressEvent]

    init(patternID: String, chartID: String, chartVariant: String, chartGaugeKey: String, patternVersion: String, title: String, started: Date) {
        self.id = UUID()
        self.patternID = patternID
        self.chartID = chartID
        self.chartVariant = chartVariant
        self.chartGaugeKey = chartGaugeKey
        self.patternVersion = patternVersion
        self.title = title
        self.started = started
        self.finished = nil
        self.notes = ""
        self.cursorRow = 1
        self.cursorRun = 0
        self.lastWorked = nil
        self.events = []
    }

    var cursor: Cursor {
        get { Cursor(row: cursorRow, run: cursorRun) }
        set { cursorRow = newValue.row; cursorRun = newValue.run }
    }

    var isFinished: Bool { finished != nil }

    /// The event log as the core package's value type, oldest first.
    var eventRecords: [ProgressEventRecord] {
        events.map { ProgressEventRecord(t: $0.t, row: $0.row, run: $0.run, kind: $0.kind) }.sorted { $0.t < $1.t }
    }
}
```
`ProgressEvent.swift`:
```swift
import Foundation
import SwiftData
import GraphghanCore

@Model
final class ProgressEvent {
    var t: Date
    var row: Int
    var run: Int
    var kindRaw: String
    var project: Project?

    init(t: Date, row: Int, run: Int, kind: EventKind) {
        self.t = t; self.row = row; self.run = run; self.kindRaw = kind.rawValue; self.project = nil
    }

    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .advance }
}
```
`ChartLibrary.swift`:
```swift
import Foundation
import GraphghanCore

/// Downloaded chart files, one per chart id, decoded once per launch. A chart is stored only if it
/// decodes and validates, so nothing under `charts/` is ever unreadable.
actor ChartLibrary {
    enum LibraryError: Error, Equatable {
        case missing(String)
        case badID(String)
    }

    private let directory: URL
    private var cache: [String: Chart] = [:]

    init(directory: URL) { self.directory = directory }

    private func fileURL(for id: String) throws -> URL {
        guard let hex = ChartID.hex(id) else { throw LibraryError.badID(id) }
        return directory.appendingPathComponent("\(hex).json")
    }

    func store(_ data: Data) throws -> Chart {
        let chart = try Chart.load(data)
        let url = try fileURL(for: chart.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        cache[chart.id] = chart
        return chart
    }

    func chart(id: String) throws -> Chart {
        if let chart = cache[id] { return chart }
        let url = try fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.missing(id) }
        let chart = try Chart.load(Data(contentsOf: url))
        cache[id] = chart
        return chart
    }

    func hasChart(id: String) -> Bool {
        if cache[id] != nil { return true }
        guard let url = try? fileURL(for: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func remove(id: String) throws {
        cache[id] = nil
        let url = try fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd ios && mise run test` → `** TEST SUCCEEDED **` with the 4 new tests. If SwiftData complains that `ModelConfiguration(schema:url:)` needs a name, use `ModelConfiguration("graphghan", schema: schema, url: AppGroup.storeURL)`.

- [ ] **Step 5: Commit**

```bash
git add ios
git commit -m "feat(ios): App Group paths, SwiftData Project and ProgressEvent models, chart library"
```

---

### Task 9: HTTP client and the pattern store

**Files:**
- Create: `ios/Graphghan/Network/HTTPClient.swift`, `ios/Graphghan/Network/PatternStore.swift`
- Test: `ios/Tests/PatternStoreTests.swift` (plus `StubClient` appended to `ios/Tests/TestSupport.swift`)

**Interfaces:**
- Produces: `struct HTTPResponse: Sendable { status: Int; data: Data; etag: String? }`; `protocol HTTPClient: Sendable { func get(_ url: URL, ifNoneMatch: String?) async throws -> HTTPResponse }`; `struct URLSessionHTTPClient: HTTPClient`; `actor PatternStore { static let defaultBaseURL; init(baseURL:cacheDirectory:client:); func cachedIndex() -> [IndexEntry]?; func refreshIndex() async throws -> [IndexEntry]; func cachedManifest(for slug: String) -> PatternManifest?; func refreshManifest(for slug: String, path: String?) async throws -> PatternManifest; func preview(for slug: String, sitePath: String) async -> Data?; func chartPreview(for slug: String, path: String) async -> Data?; func chartData(for slug: String, path: String) async throws -> Data }` with `PatternStore.StoreError { http(Int), noCache }`; test helper `actor StubClient: HTTPClient { func respond(_ path: String, with: HTTPResponse); func fail(_ path: String, with: Error); func requests() -> [(path: String, ifNoneMatch: String?)] }`.

- [ ] **Step 1: Failing tests**

Append to `ios/Tests/TestSupport.swift`:
```swift
actor StubClient: HTTPClient {
    struct Recorded: Equatable { let path: String; let ifNoneMatch: String? }
    private var responses: [String: Result<HTTPResponse, Error>] = [:]
    private var log: [Recorded] = []

    func respond(_ path: String, status: Int = 200, body: String = "", etag: String? = nil) {
        responses[path] = .success(HTTPResponse(status: status, data: Data(body.utf8), etag: etag))
    }
    func respond(_ path: String, data: Data, etag: String? = nil) {
        responses[path] = .success(HTTPResponse(status: 200, data: data, etag: etag))
    }
    func fail(_ path: String) { responses[path] = .failure(URLError(.notConnectedToInternet)) }
    func requests() -> [Recorded] { log }

    func get(_ url: URL, ifNoneMatch: String?) async throws -> HTTPResponse {
        log.append(Recorded(path: url.path, ifNoneMatch: ifNoneMatch))
        guard let r = responses[url.path] else { throw URLError(.notConnectedToInternet) }
        return try r.get()
    }
}
```
`ios/Tests/PatternStoreTests.swift`:
```swift
import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct PatternStoreTests {
    static let index = #"[{"slug":"p","title":"P","version":"1","stitch":"sc","width":2,"height":1,"size_in":[1,1],"dedication":"","colors":1,"preview":"patterns/p/preview.png","manifest":"patterns/p/pattern.json","charts":1}]"#
    static let manifest = #"{"schema":1,"id":"p","title":"P","version":"1","dedication":"","quote":"","author":"","license":"","preview":"preview.png","palette":[],"charts":[],"updated":"2026-09-11T00:00:00Z"}"#

    func makeStore() async throws -> (PatternStore, StubClient) {
        let client = StubClient()
        let store = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        return (store, client)
    }

    @Test func freshFetchThenNotModified() async throws {
        let (store, client) = try await makeStore()
        #expect(await store.cachedIndex() == nil)
        await client.respond("/patterns/index.json", body: Self.index, etag: "\"v1\"")
        let first = try await store.refreshIndex()
        #expect(first.map(\.slug) == ["p"])
        #expect(await store.cachedIndex()?.count == 1)
        await client.respond("/patterns/index.json", status: 304)
        let second = try await store.refreshIndex()
        #expect(second == first)
        let log = await client.requests()
        #expect(log.map(\.ifNoneMatch) == [nil, "\"v1\""])
    }

    @Test func offlineWithCacheKeepsServingTheCache() async throws {
        let (store, client) = try await makeStore()
        await client.respond("/patterns/index.json", body: Self.index, etag: "\"v1\"")
        _ = try await store.refreshIndex()
        await client.fail("/patterns/index.json")
        await #expect(throws: URLError.self) { try await store.refreshIndex() }
        #expect(await store.cachedIndex()?.first?.slug == "p")
    }

    @Test func offlineWithoutCacheHasNothing() async throws {
        let (store, _) = try await makeStore()
        await #expect(throws: URLError.self) { try await store.refreshIndex() }
        #expect(await store.cachedIndex() == nil)
    }

    @Test func serverErrorsAreReported() async throws {
        let (store, client) = try await makeStore()
        await client.respond("/patterns/index.json", status: 500, body: "boom")
        await #expect(throws: PatternStore.StoreError.http(500)) { try await store.refreshIndex() }
        await client.respond("/patterns/index.json", status: 304)  // 304 with nothing cached
        await #expect(throws: PatternStore.StoreError.noCache) { try await store.refreshIndex() }
    }

    @Test func manifestsPreviewsAndCharts() async throws {
        let (store, client) = try await makeStore()
        await client.respond("/patterns/p/pattern.json", body: Self.manifest, etag: "\"m1\"")
        let m = try await store.refreshManifest(for: "p", path: "patterns/p/pattern.json")
        #expect(m.id == "p" && (await store.cachedManifest(for: "p"))?.id == "p")
        await client.respond("/patterns/p/preview.png", body: "PNG")
        #expect(await store.preview(for: "p", sitePath: "patterns/p/preview.png") == Data("PNG".utf8))
        await client.fail("/patterns/p/preview.png")
        #expect(await store.preview(for: "p", sitePath: "patterns/p/preview.png") == Data("PNG".utf8))  // cached
        await client.respond("/patterns/p/charts/final-sc/preview.png", body: "PNG2")
        #expect(await store.chartPreview(for: "p", path: "charts/final-sc/preview.png") == Data("PNG2".utf8))
        await client.respond("/patterns/p/charts/final-sc/chart.json", body: "{}")
        #expect(try await store.chartData(for: "p", path: "charts/final-sc/chart.json") == Data("{}".utf8))
        await client.fail("/patterns/p/charts/final-sc/chart.json")
        await #expect(throws: URLError.self) { try await store.chartData(for: "p", path: "charts/final-sc/chart.json") }
    }
}
```

- [ ] **Step 2: Run to verify failure** → compile errors.

- [ ] **Step 3: Implement**

`HTTPClient.swift`:
```swift
import Foundation

struct HTTPResponse: Sendable {
    let status: Int
    let data: Data
    let etag: String?
}

/// The one network seam. Tests substitute a stub; the app uses URLSession.
protocol HTTPClient: Sendable {
    func get(_ url: URL, ifNoneMatch: String?) async throws -> HTTPResponse
}

struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func get(_ url: URL, ifNoneMatch: String?) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData  // PatternStore manages its own cache with ETags
        if let ifNoneMatch { request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        return HTTPResponse(status: http?.statusCode ?? 0, data: data, etag: http?.value(forHTTPHeaderField: "ETag"))
    }
}
```
`PatternStore.swift`:
```swift
import Foundation
import GraphghanCore

/// The published library: `patterns/index.json`, each pattern's `pattern.json`, previews, and
/// chart downloads. Index and manifests are cached on disk with their ETags so a refresh that
/// returns 304 costs nothing and an offline launch still has a library.
actor PatternStore {
    enum StoreError: Error, Equatable {
        case http(Int)
        case noCache
    }

    static let defaultBaseURL = URL(string: "https://graphghan.milo.cat/")!

    let baseURL: URL
    private let cacheDirectory: URL
    private let client: HTTPClient

    init(baseURL: URL = PatternStore.defaultBaseURL, cacheDirectory: URL, client: HTTPClient) {
        self.baseURL = baseURL
        self.cacheDirectory = cacheDirectory
        self.client = client
    }

    // MARK: index

    private var indexFile: URL { cacheDirectory.appendingPathComponent("index.json") }

    func cachedIndex() -> [IndexEntry]? {
        guard let data = try? Data(contentsOf: indexFile) else { return nil }
        return try? JSONDecoder().decode([IndexEntry].self, from: data)
    }

    func refreshIndex() async throws -> [IndexEntry] {
        let data = try await conditionalGet(sitePath: "patterns/index.json", cacheFile: indexFile)
        return try JSONDecoder().decode([IndexEntry].self, from: data)
    }

    // MARK: manifests

    private func patternDirectory(_ slug: String) -> URL { cacheDirectory.appendingPathComponent(slug, isDirectory: true) }
    private func manifestFile(_ slug: String) -> URL { patternDirectory(slug).appendingPathComponent("pattern.json") }

    func cachedManifest(for slug: String) -> PatternManifest? {
        guard let data = try? Data(contentsOf: manifestFile(slug)) else { return nil }
        return try? JSONDecoder().decode(PatternManifest.self, from: data)
    }

    /// `path` is the index entry's `manifest` (site-relative); nil falls back to the conventional location.
    func refreshManifest(for slug: String, path: String?) async throws -> PatternManifest {
        let data = try await conditionalGet(sitePath: path ?? "patterns/\(slug)/pattern.json", cacheFile: manifestFile(slug))
        return try JSONDecoder().decode(PatternManifest.self, from: data)
    }

    // MARK: images and charts

    /// The pattern's site-relative preview (from the index). Cached forever; nil when unavailable.
    func preview(for slug: String, sitePath: String) async -> Data? {
        await cachedBytes(sitePath: sitePath, cacheFile: patternDirectory(slug).appendingPathComponent("preview.png"))
    }

    /// A chart preview by manifest-relative path (e.g. `charts/final-sc/preview.png`).
    func chartPreview(for slug: String, path: String) async -> Data? {
        let name = path.replacingOccurrences(of: "/", with: "_")
        return await cachedBytes(sitePath: "patterns/\(slug)/\(path)", cacheFile: patternDirectory(slug).appendingPathComponent(name))
    }

    /// A chart file by manifest-relative path. Not cached here: the ChartLibrary keeps what a project needs.
    func chartData(for slug: String, path: String) async throws -> Data {
        let response = try await client.get(url(for: "patterns/\(slug)/\(path)"), ifNoneMatch: nil)
        guard response.status == 200 else { throw StoreError.http(response.status) }
        return response.data
    }

    // MARK: plumbing

    private func url(for sitePath: String) -> URL { baseURL.appendingPathComponent(sitePath) }

    private func conditionalGet(sitePath: String, cacheFile: URL) async throws -> Data {
        let etagFile = cacheFile.appendingPathExtension("etag")
        let cached = try? Data(contentsOf: cacheFile)
        let etag = cached == nil ? nil : try? String(contentsOf: etagFile, encoding: .utf8)
        let response = try await client.get(url(for: sitePath), ifNoneMatch: etag)
        switch response.status {
        case 200:
            try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try response.data.write(to: cacheFile, options: .atomic)
            if let tag = response.etag { try tag.write(to: etagFile, atomically: true, encoding: .utf8) }
            else { try? FileManager.default.removeItem(at: etagFile) }
            return response.data
        case 304:
            guard let cached else { throw StoreError.noCache }
            return cached
        default:
            throw StoreError.http(response.status)
        }
    }

    private func cachedBytes(sitePath: String, cacheFile: URL) async -> Data? {
        if let data = try? Data(contentsOf: cacheFile) { return data }
        guard let response = try? await client.get(url(for: sitePath), ifNoneMatch: nil), response.status == 200 else { return nil }
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? response.data.write(to: cacheFile, options: .atomic)
        return response.data
    }
}
```

- [ ] **Step 4: Run the tests** → `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios
git commit -m "feat(ios): HTTP client seam and the ETag-cached pattern store"
```

---

### Task 10: ProjectService: start, apply, summary, finish, delete, version notice

**Files:**
- Create: `ios/Graphghan/Services/ProjectService.swift`
- Test: `ios/Tests/ProjectServiceTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class ProjectService { init(context: ModelContext, charts: ChartLibrary, patterns: PatternStore); var now: @Sendable () -> Date; var lastError: String?; func projects() throws -> [Project]; func startProject(manifest:chart:title:) async throws -> Project; func chart(for:) async throws -> Chart; func sequence(for:) async throws -> WorkSequence; @discardableResult func apply(_: WorkAction, to: Project, in: WorkSequence) throws -> WorkStep?; func summary(for:sequence:) -> ProgressSummary; func estimatedFinish(for:sequence:) -> Date?; func setNotes(_:for:) throws; func markFinished(_:) throws; func delete(_:) throws; func versionNotice(for:manifest:) -> VersionNotice?; func switchChart(_:to:manifest:) async throws; func exportDocument(for:) -> ProgressDocument }`; `enum VersionNotice: Equatable { case chartChanged(newChart: ManifestChart, newVersion: String, canSwitch: Bool) }`; `enum ServiceError: Error, Equatable { chartMismatch(expected: String, got: String), cursorNotAtStart, chartUnavailable(String) }`; test helper `TestManifest.make(chartID:variant:gaugeKey:version:) -> PatternManifest`.

- [ ] **Step 1: Failing tests**

Append to `ios/Tests/TestSupport.swift`:
```swift
enum TestManifest {
    static func make(chartID: String, variant: String = "final", gaugeKey: String = "sc", version: String = "1.0.0", path: String = "charts/final-sc/chart.json") -> PatternManifest {
        let json = """
        {"schema":1,"id":"two-letter-codes","title":"Two-letter codes","version":"\(version)","dedication":"","quote":"","author":"","license":"",
         "preview":"preview.png","palette":[],"charts":[{"id":"\(chartID)","variant":"\(variant)","gauge_key":"\(gaugeKey)","default":true,
         "path":"\(path)","preview":"charts/final-sc/preview.png","width":12,"height":2,"size":{"width":3.4,"height":0.5,"unit":"in"},
         "stitch":"sc","colors":4,"stitches":24,"changes_per_row":{"mean":2,"max":2},"yards_est":10}],"updated":"2026-09-11T00:00:00Z"}
        """
        return try! JSONDecoder().decode(PatternManifest.self, from: Data(json.utf8))
    }
}
```
`ios/Tests/ProjectServiceTests.swift`:
```swift
import Foundation
import SwiftData
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct ProjectServiceTests {
    struct Harness {
        let service: ProjectService
        let client: StubClient
        let context: ModelContext
        let chartData: Data
        let chartID: String
    }

    func makeHarness() async throws -> Harness {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        let service = ProjectService(context: container.mainContext, charts: charts, patterns: patterns)
        let data = try TestFixtures.data("two-letter-codes.chart.json")
        let id = try Chart.load(data).id
        await client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: data)
        return Harness(service: service, client: client, context: container.mainContext, chartData: data, chartID: id)
    }

    @Test func startPinsChartAndVersion() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID, version: "1.2.0")
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "Mine")
        #expect(p.chartID == h.chartID && p.patternVersion == "1.2.0" && p.patternID == "two-letter-codes")
        #expect(p.chartVariant == "final" && p.chartGaugeKey == "sc" && p.title == "Mine" && p.cursor == .start)
        #expect(try h.service.projects().count == 1)
        #expect(try await h.service.sequence(for: p).passes.count == 2)
    }

    @Test func failedDownloadOrDecodeLeavesNoProject() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        await h.client.fail("/patterns/two-letter-codes/charts/final-sc/chart.json")
        await #expect(throws: (any Error).self) { try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x") }
        #expect(try h.service.projects().isEmpty)
        await h.client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", body: "{\"schema\":2}")
        await #expect(throws: (any Error).self) { try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x") }
        #expect(try h.service.projects().isEmpty)
        // a manifest whose id disagrees with the downloaded chart is refused too
        let wrong = TestManifest.make(chartID: "sha256:" + String(repeating: "0", count: 64))
        await h.client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: h.chartData)
        await #expect(throws: ProjectService.ServiceError.chartMismatch(expected: wrong.charts[0].id, got: h.chartID)) {
            try await h.service.startProject(manifest: wrong, chart: wrong.charts[0], title: "x")
        }
        #expect(try h.service.projects().isEmpty)
    }

    @Test func applyWritesCursorAndEventTogether() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        h.service.now = { t }
        let step = try h.service.apply(.advance, to: p, in: seq)
        #expect(step?.cursor == Cursor(row: 1, run: 1))
        #expect(p.cursor == Cursor(row: 1, run: 1) && p.lastWorked == t)
        #expect(p.eventRecords == [ProgressEventRecord(t: t, row: 1, run: 1, kind: .advance)])
        #expect(try h.context.fetchCount(FetchDescriptor<ProgressEvent>()) == 1)
        #expect(try h.service.apply(.back, to: p, in: seq)?.cursor == .start)
        #expect(try h.service.apply(.back, to: p, in: seq) == nil)   // no-op at the start writes nothing
        #expect(try h.context.fetchCount(FetchDescriptor<ProgressEvent>()) == 2)
        // finishing the last run marks the project finished
        _ = try h.service.apply(.jump(row: 2), to: p, in: seq)
        for _ in 0..<3 { _ = try h.service.apply(.advance, to: p, in: seq) }
        #expect(p.isFinished && h.service.summary(for: p, sequence: seq).percent == 100)
    }

    @Test func summaryAndExport() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        h.service.now = { Date(timeIntervalSince1970: 1_800_000_000) }
        _ = try h.service.apply(.advance, to: p, in: seq)  // Kb 3 stitches done
        let s = h.service.summary(for: p, sequence: seq)
        #expect(s.stitchesDone == 3 && s.totalStitches == 24 && s.sessions.count == 1)
        #expect(h.service.estimatedFinish(for: p, sequence: seq) == nil)  // fewer than 3 sessions
        let doc = h.service.exportDocument(for: p)
        #expect(doc.patternID == "two-letter-codes" && doc.chartID == h.chartID && doc.cursor == Cursor(row: 1, run: 1) && doc.events.count == 1)
    }

    @Test func deleteCascadesAndNotesAndFinish() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        let seq = try await h.service.sequence(for: p)
        _ = try h.service.apply(.advance, to: p, in: seq)
        try h.service.setNotes("bobbin the gold", for: p)
        #expect(p.notes == "bobbin the gold")
        try h.service.markFinished(p)
        #expect(p.isFinished)
        try h.service.delete(p)
        #expect(try h.service.projects().isEmpty)
        #expect(try h.context.fetchCount(FetchDescriptor<ProgressEvent>()) == 0)
    }

    @Test func versionNoticeOnlyWhenTheChartChanged() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID, version: "1.0.0")
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        #expect(h.service.versionNotice(for: p, manifest: TestManifest.make(chartID: h.chartID, version: "1.1.0")) == nil)
        let changed = TestManifest.make(chartID: "sha256:" + String(repeating: "b", count: 64), version: "2.0.0")
        #expect(h.service.versionNotice(for: p, manifest: changed) == .chartChanged(newChart: changed.charts[0], newVersion: "2.0.0", canSwitch: true))
        let seq = try await h.service.sequence(for: p)
        _ = try h.service.apply(.advance, to: p, in: seq)
        #expect(h.service.versionNotice(for: p, manifest: changed) == .chartChanged(newChart: changed.charts[0], newVersion: "2.0.0", canSwitch: false))
        await #expect(throws: ProjectService.ServiceError.cursorNotAtStart) { try await h.service.switchChart(p, to: changed.charts[0], manifest: changed) }
        #expect(h.service.versionNotice(for: p, manifest: TestManifest.make(chartID: h.chartID, gaugeKey: "hdc")) == nil)  // no matching chart in the manifest: nothing to say
    }

    @Test func switchChartAtTheStart() async throws {
        let h = try await makeHarness()
        let manifest = TestManifest.make(chartID: h.chartID)
        let p = try await h.service.startProject(manifest: manifest, chart: manifest.charts[0], title: "x")
        // publish a "new" chart at the same variant/gauge: the minimal-rows fixture stands in for it
        let newData = try TestFixtures.data("minimal-rows.chart.json")
        let newID = try Chart.load(newData).id
        let changed = TestManifest.make(chartID: newID, version: "2.0.0", path: "charts/final-sc/chart.json")
        await h.client.respond("/patterns/two-letter-codes/charts/final-sc/chart.json", data: newData)
        try await h.service.switchChart(p, to: changed.charts[0], manifest: changed)
        #expect(p.chartID == newID && p.patternVersion == "2.0.0")
        #expect(try await h.service.sequence(for: p).passes.count == 12)
    }
}
```

- [ ] **Step 2: Run to verify failure** → compile errors.

- [ ] **Step 3: Implement**

`ProjectService.swift`:
```swift
import Foundation
import Observation
import SwiftData
import GraphghanCore

/// Every mutation of a project goes through here: the Work screen, and later the Live Activity
/// intents, call `apply`, so cursor and event are always written together.
@MainActor
@Observable
final class ProjectService {
    enum ServiceError: Error, Equatable {
        case chartMismatch(expected: String, got: String)
        case cursorNotAtStart
        case chartUnavailable(String)
    }

    enum VersionNotice: Equatable {
        case chartChanged(newChart: ManifestChart, newVersion: String, canSwitch: Bool)
    }

    private let context: ModelContext
    let charts: ChartLibrary
    let patterns: PatternStore
    /// Injected clock so tests control timestamps.
    var now: @Sendable () -> Date = { Date() }
    /// The last storage error, for a one-time banner. Never blocks advancing.
    var lastError: String?

    init(context: ModelContext, charts: ChartLibrary, patterns: PatternStore) {
        self.context = context
        self.charts = charts
        self.patterns = patterns
    }

    func projects() throws -> [Project] {
        var descriptor = FetchDescriptor<Project>()
        descriptor.sortBy = [SortDescriptor(\.lastWorked, order: .reverse), SortDescriptor(\.started, order: .reverse)]
        return try context.fetch(descriptor)
    }

    /// Downloads and validates the chart first; a project exists only once its chart is on disk.
    func startProject(manifest: PatternManifest, chart: ManifestChart, title: String) async throws -> Project {
        let data = try await patterns.chartData(for: manifest.id, path: chart.path)
        let decoded = try await charts.store(data)
        guard decoded.id == chart.id else {
            try? await charts.remove(id: decoded.id)
            throw ServiceError.chartMismatch(expected: chart.id, got: decoded.id)
        }
        let project = Project(patternID: manifest.id, chartID: chart.id, chartVariant: chart.variant, chartGaugeKey: chart.gaugeKey,
                              patternVersion: manifest.version, title: title.isEmpty ? manifest.title : title, started: now())
        context.insert(project)
        try save()
        return project
    }

    func chart(for project: Project) async throws -> Chart {
        do { return try await charts.chart(id: project.chartID) }
        catch { throw ServiceError.chartUnavailable(project.chartID) }
    }

    func sequence(for project: Project) async throws -> WorkSequence {
        try WorkSequence(chart: try await chart(for: project))
    }

    @discardableResult
    func apply(_ action: WorkAction, to project: Project, in sequence: WorkSequence) throws -> WorkStep? {
        guard let step = WorkEngine.apply(action, to: project.cursor, in: sequence) else { return nil }
        let t = now()
        project.cursor = step.cursor
        project.lastWorked = t
        if step.finished { project.finished = t }
        let event = ProgressEvent(t: t, row: step.cursor.row, run: step.cursor.run, kind: step.kind)
        event.project = project
        context.insert(event)
        try save()
        return step
    }

    func summary(for project: Project, sequence: WorkSequence) -> ProgressSummary {
        Pace.summarize(events: project.eventRecords, cursor: project.cursor, sequence: sequence)
    }

    func estimatedFinish(for project: Project, sequence: WorkSequence) -> Date? {
        let s = summary(for: project, sequence: sequence)
        return Pace.estimatedFinish(remainingStitches: s.totalStitches - s.stitchesDone, stitchesPerHour: s.stitchesPerHour, sessions: s.sessions, now: now())
    }

    func setNotes(_ text: String, for project: Project) throws {
        project.notes = text
        try save()
    }

    func markFinished(_ project: Project) throws {
        project.finished = now()
        try save()
    }

    func delete(_ project: Project) throws {
        context.delete(project)
        try save()
    }

    /// Spec 4.5: same chart id means nothing changed, whatever the version says.
    func versionNotice(for project: Project, manifest: PatternManifest) -> VersionNotice? {
        guard let published = manifest.charts.first(where: { $0.variant == project.chartVariant && $0.gaugeKey == project.chartGaugeKey }) else { return nil }
        guard published.id != project.chartID else { return nil }
        return .chartChanged(newChart: published, newVersion: manifest.version, canSwitch: project.cursor == .start)
    }

    func switchChart(_ project: Project, to chart: ManifestChart, manifest: PatternManifest) async throws {
        guard project.cursor == .start else { throw ServiceError.cursorNotAtStart }
        let data = try await patterns.chartData(for: manifest.id, path: chart.path)
        let decoded = try await charts.store(data)
        guard decoded.id == chart.id else { throw ServiceError.chartMismatch(expected: chart.id, got: decoded.id) }
        project.chartID = chart.id
        project.chartVariant = chart.variant
        project.chartGaugeKey = chart.gaugeKey
        project.patternVersion = manifest.version
        try save()
    }

    func exportDocument(for project: Project) -> ProgressDocument {
        ProgressDocument(patternID: project.patternID, chartID: project.chartID, patternVersion: project.patternVersion,
                         cursor: project.cursor, started: project.started, finished: project.finished, events: project.eventRecords)
    }

    private func save() throws {
        do {
            try context.save()
            lastError = nil
        } catch {
            context.rollback()
            lastError = error.localizedDescription
            throw error
        }
    }
}
```

- [ ] **Step 4: Run the tests** → `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios
git commit -m "feat(ios): ProjectService with atomic cursor and event writes, summaries, version notices"
```

---

### Task 11: App model and the Patterns tab

**Files:**
- Create: `ios/Graphghan/AppModel.swift`, `ios/Graphghan/RootView.swift`, `ios/Graphghan/UI/ChartImage.swift`, `ios/Graphghan/UI/PreviewImage.swift`, `ios/Graphghan/Patterns/LibraryView.swift`, `ios/Graphghan/Patterns/PatternDetailView.swift`, `ios/Graphghan/Patterns/ChartBrowserView.swift`, `ios/Graphghan/Patterns/StartProjectSheet.swift`
- Modify: `ios/Graphghan/GraphghanApp.swift`
- Test: `ios/Tests/ChartImageTests.swift`, `ios/Tests/AppModelTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class AppModel { enum Tab { patterns, projects }; init(context:patterns:charts:); static func live(context:) -> AppModel; var tab; var index: [IndexEntry]; var libraryBanner: String?; var libraryError: String?; var isLoadingLibrary: Bool; var workingProject: Project?; let patterns: PatternStore; let charts: ChartLibrary; let projects: ProjectService; func loadLibrary(force: Bool = false) async; func manifest(for slug: String, path: String?) async throws -> PatternManifest; func cachedManifest(for slug: String) -> PatternManifest?; func preview(for slug: String, sitePath: String) async -> UIImage?; func chartPreview(for slug: String, path: String) async -> UIImage?; func browseChart(manifest: PatternManifest, chart: ManifestChart) async throws -> Chart; func startProject(manifest:chart:title:) async throws }`; `enum ChartImage { static func make(_ chart: Chart) -> CGImage?; static func rgb(_ hex: String) -> (r: UInt8, g: UInt8, b: UInt8); static func color(_ hex: String) -> Color; static func isLight(_ hex: String) -> Bool }`; views `RootView`, `LibraryView`, `PatternDetailView(entry:)`, `ChartBrowserView(title:highlightRow:load:)`, `StartProjectSheet(manifest:)`, `PreviewImage(slug:sitePath:)`.

- [ ] **Step 1: Failing tests**

`ios/Tests/ChartImageTests.swift`:
```swift
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct ChartImageTests {
    @Test func onePixelPerCell() throws {
        let chart = try Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
        let image = try #require(ChartImage.make(chart))
        #expect(image.width == 12 && image.height == 2)
        #expect(ChartImage.rgb("#D9A21B") == (0xD9, 0xA2, 0x1B))
        #expect(ChartImage.isLight("#F2E8D5") && !ChartImage.isLight("#2B2F33"))
    }
}
```
`ios/Tests/AppModelTests.swift`:
```swift
import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct AppModelTests {
    static let index = #"[{"slug":"p","title":"P","version":"1","stitch":"sc","width":2,"height":1,"size_in":[1,1],"dedication":"","colors":1,"preview":"patterns/p/preview.png","manifest":"patterns/p/pattern.json","charts":1}]"#

    func makeModel() async throws -> (AppModel, StubClient) {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!, cacheDirectory: try temporaryDirectory(), client: client)
        let charts = ChartLibrary(directory: try temporaryDirectory())
        return (AppModel(context: container.mainContext, patterns: patterns, charts: charts), client)
    }

    @Test func offlineWithoutCacheShowsAnError() async throws {
        let (model, _) = try await makeModel()
        await model.loadLibrary()
        #expect(model.index.isEmpty && model.libraryError != nil && model.libraryBanner == nil)
    }

    @Test func refreshFailureKeepsTheCacheAndShowsABanner() async throws {
        let (model, client) = try await makeModel()
        await client.respond("/patterns/index.json", body: Self.index, etag: "\"1\"")
        await model.loadLibrary()
        #expect(model.index.count == 1 && model.libraryBanner == nil && model.libraryError == nil)
        await client.fail("/patterns/index.json")
        await model.loadLibrary(force: true)
        #expect(model.index.count == 1 && model.libraryBanner != nil && model.libraryError == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** → compile errors.

- [ ] **Step 3: Implement the model and image helpers**

`AppModel.swift`:
```swift
import Foundation
import Observation
import SwiftData
import UIKit
import GraphghanCore

/// App-wide state: the stores, the library as last loaded, navigation between tabs, and the
/// project currently open on the Work screen.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable { case patterns, projects }

    let patterns: PatternStore
    let charts: ChartLibrary
    let projects: ProjectService

    var tab: Tab = .patterns
    var index: [IndexEntry] = []
    /// A refresh failed but cached data is shown.
    var libraryBanner: String?
    /// Nothing to show at all (offline with no cache).
    var libraryError: String?
    var isLoadingLibrary = false
    var workingProject: Project?

    private var manifests: [String: PatternManifest] = [:]
    private var images: [String: UIImage] = [:]

    init(context: ModelContext, patterns: PatternStore, charts: ChartLibrary) {
        self.patterns = patterns
        self.charts = charts
        self.projects = ProjectService(context: context, charts: charts, patterns: patterns)
    }

    static func live(context: ModelContext) -> AppModel {
        AppModel(context: context,
                 patterns: PatternStore(cacheDirectory: AppGroup.patternsCacheURL, client: URLSessionHTTPClient()),
                 charts: ChartLibrary(directory: AppGroup.chartsURL))
    }

    // MARK: library

    func loadLibrary(force: Bool = false) async {
        if !force, !index.isEmpty { return }
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        let cached = await patterns.cachedIndex()
        if let cached, index.isEmpty { index = cached }
        do {
            index = try await patterns.refreshIndex()
            libraryBanner = nil
            libraryError = nil
        } catch {
            if index.isEmpty {
                libraryError = "Couldn't reach graphghan.milo.cat. Connect to the internet and try again."
            } else {
                libraryBanner = "Showing the last downloaded library; couldn't check for updates."
            }
        }
    }

    func cachedManifest(for slug: String) -> PatternManifest? {
        manifests[slug]
    }

    /// The cached manifest when there is one, refreshed in the background; otherwise fetched.
    func manifest(for slug: String, path: String?) async throws -> PatternManifest {
        if let m = manifests[slug] { return m }
        if let cached = await patterns.cachedManifest(for: slug) {
            manifests[slug] = cached
            Task { [weak self] in
                if let fresh = try? await self?.patterns.refreshManifest(for: slug, path: path) { self?.manifests[slug] = fresh }
            }
            return cached
        }
        let fresh = try await patterns.refreshManifest(for: slug, path: path)
        manifests[slug] = fresh
        return fresh
    }

    func preview(for slug: String, sitePath: String) async -> UIImage? {
        if let image = images[sitePath] { return image }
        guard let data = await patterns.preview(for: slug, sitePath: sitePath), let image = UIImage(data: data) else { return nil }
        images[sitePath] = image
        return image
    }

    func chartPreview(for slug: String, path: String) async -> UIImage? {
        let key = "\(slug)/\(path)"
        if let image = images[key] { return image }
        guard let data = await patterns.chartPreview(for: slug, path: path), let image = UIImage(data: data) else { return nil }
        images[key] = image
        return image
    }

    /// A chart for browsing: the library copy if a project already has it, else a download kept in memory.
    func browseChart(manifest: PatternManifest, chart: ManifestChart) async throws -> Chart {
        if await charts.hasChart(id: chart.id) { return try await charts.chart(id: chart.id) }
        return try Chart.load(await patterns.chartData(for: manifest.id, path: chart.path))
    }

    func startProject(manifest: PatternManifest, chart: ManifestChart, title: String) async throws {
        _ = try await projects.startProject(manifest: manifest, chart: chart, title: title)
        tab = .projects
    }
}
```
`RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            LibraryView()
                .tabItem { Label("Patterns", systemImage: "square.grid.3x3") }
                .tag(AppModel.Tab.patterns)
            ProjectListView()
                .tabItem { Label("Projects", systemImage: "checklist") }
                .tag(AppModel.Tab.projects)
        }
        .fullScreenCover(item: $model.workingProject) { project in
            WorkView(project: project)
        }
    }
}
```
Until Task 12 and 13 exist, add temporary placeholders so this task builds:
`ios/Graphghan/Projects/ProjectListView.swift` → `struct ProjectListView: View { var body: some View { Text("Projects") } }` and `ios/Graphghan/Work/WorkView.swift` → `struct WorkView: View { let project: Project; var body: some View { Text(project.title) } }`. Tasks 12 and 13 replace them.

`GraphghanApp.swift` (replace):
```swift
import SwiftData
import SwiftUI
import GraphghanCore

@main
struct GraphghanApp: App {
    private let container: ModelContainer
    private let model: AppModel

    init() {
        do {
            container = try Persistence.makeContainer()
        } catch {
            fatalError("Could not open the project store: \(error)")
        }
        model = AppModel.live(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(container)
        }
    }
}
```
`UI/ChartImage.swift`:
```swift
import CoreGraphics
import SwiftUI
import GraphghanCore

enum ChartImage {
    static func rgb(_ hex: String) -> (r: UInt8, g: UInt8, b: UInt8) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return (0x88, 0x88, 0x88) }
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    static func color(_ hex: String) -> Color {
        let c = rgb(hex)
        return Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
    }

    /// Same rule as the PWA: perceived luminance under 140 gets white text.
    static func isLight(_ hex: String) -> Bool {
        let c = rgb(hex)
        return (Double(c.r) * 299 + Double(c.g) * 587 + Double(c.b) * 114) / 1000 >= 140
    }

    /// One pixel per cell, RGBA, top row first. Scale it with nearest-neighbour to keep cells crisp.
    static func make(_ chart: Chart) -> CGImage? {
        let palette = chart.palette.map { rgb($0.hex) }
        var bytes = [UInt8](repeating: 255, count: chart.width * chart.height * 4)
        for (i, cell) in chart.cells.enumerated() {
            let c = palette[Int(cell)]
            bytes[i * 4] = c.r; bytes[i * 4 + 1] = c.g; bytes[i * 4 + 2] = c.b
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: chart.width, height: chart.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: chart.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
```
`UI/PreviewImage.swift`:
```swift
import SwiftUI

/// A pattern or chart preview from the site, loaded through the model's cache.
struct PreviewImage: View {
    @Environment(AppModel.self) private var model
    let slug: String
    var sitePath: String? = nil
    var chartPath: String? = nil
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                Rectangle().fill(.quaternary).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .task(id: sitePath ?? chartPath) {
            if let sitePath { image = await model.preview(for: slug, sitePath: sitePath) }
            else if let chartPath { image = await model.chartPreview(for: slug, path: chartPath) }
        }
    }
}
```

- [ ] **Step 4: Implement the Patterns tab views**

`Patterns/LibraryView.swift`:
```swift
import SwiftUI
import GraphghanCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.libraryError, model.index.isEmpty {
                    ContentUnavailableView {
                        Label("No patterns yet", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await model.loadLibrary(force: true) } }
                    }
                } else if model.index.isEmpty && model.isLoadingLibrary {
                    ProgressView("Loading patterns…")
                } else {
                    List(model.index) { entry in
                        NavigationLink(value: entry) { LibraryRow(entry: entry) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Patterns")
            .navigationDestination(for: IndexEntry.self) { PatternDetailView(entry: $0) }
            .refreshable { await model.loadLibrary(force: true) }
            .safeAreaInset(edge: .top) {
                if let banner = model.libraryBanner {
                    Text(banner)
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.yellow.opacity(0.25))
                }
            }
        }
        .task { await model.loadLibrary() }
    }
}

struct LibraryRow: View {
    let entry: IndexEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PreviewImage(slug: entry.slug, sitePath: entry.preview)
                .frame(width: 96, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.headline)
                if !entry.dedication.isEmpty { Text(entry.dedication).font(.subheadline).foregroundStyle(.secondary) }
                Text("\(entry.sizeIn[0].formatted()) × \(entry.sizeIn[1].formatted()) in · \(entry.stitch) · \(entry.colors) colors")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```
`Patterns/PatternDetailView.swift`:
```swift
import SwiftUI
import GraphghanCore

struct PatternDetailView: View {
    @Environment(AppModel.self) private var model
    let entry: IndexEntry
    @State private var manifest: PatternManifest?
    @State private var loadError: String?
    @State private var showStart = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PreviewImage(slug: entry.slug, sitePath: entry.preview)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if let manifest {
                    if !manifest.quote.isEmpty { Text("“\(manifest.quote)”").font(.title3.italic()) }
                    specs(manifest)
                    palette(manifest)
                    charts(manifest)
                    instructions
                } else if let loadError {
                    ContentUnavailableView("Couldn't load this pattern", systemImage: "wifi.slash", description: Text(loadError))
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let manifest {
                Button("Start project") { showStart = true }
                    .disabled(manifest.charts.isEmpty)
            }
        }
        .sheet(isPresented: $showStart) {
            if let manifest { StartProjectSheet(manifest: manifest) }
        }
        .task {
            do { manifest = try await model.manifest(for: entry.slug, path: entry.manifest) }
            catch { loadError = "Connect to the internet to open a pattern for the first time." }
        }
    }

    @ViewBuilder private func specs(_ m: PatternManifest) -> some View {
        let d = m.defaultChart
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow { Text("Chart").foregroundStyle(.secondary); Text(d.map { "\($0.width) × \($0.height) stitches × rows" } ?? "—") }
            GridRow { Text("Finished").foregroundStyle(.secondary); Text(d.map { "\($0.size.width.formatted()) × \($0.size.height.formatted()) \($0.size.unit)" } ?? "—") }
            GridRow { Text("Stitch").foregroundStyle(.secondary); Text(d?.stitch ?? entry.stitch) }
            GridRow { Text("Version").foregroundStyle(.secondary); Text(m.version) }
            if !m.dedication.isEmpty { GridRow { Text("For").foregroundStyle(.secondary); Text(m.dedication) } }
        }
        .font(.subheadline)
    }

    @ViewBuilder private func palette(_ m: PatternManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colors").font(.headline)
            ForEach(m.palette, id: \.code) { swatch in
                HStack {
                    RoundedRectangle(cornerRadius: 4).fill(ChartImage.color(swatch.hex)).frame(width: 28, height: 20)
                    Text(swatch.code).font(.system(.body, design: .monospaced)).bold()
                    Text(swatch.name)
                }
            }
        }
    }

    @ViewBuilder private func charts(_ m: PatternManifest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Published charts").font(.headline)
            ForEach(m.charts) { chart in
                NavigationLink {
                    ChartBrowserView(title: "\(m.title) · \(chart.key)", highlightRow: nil) {
                        try await model.browseChart(manifest: m, chart: chart)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(chart.variant) · \(chart.gaugeKey)").bold()
                            Text("\(chart.size.width.formatted()) × \(chart.size.height.formatted()) \(chart.size.unit) · \(chart.height) rows · \(chart.stitches.formatted()) stitches")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var instructions: some View {
        if let m = manifest, let chart = m.defaultChart {
            InstructionsView(slug: m.id, chart: chart)
        }
    }
}

/// Instruction sections live in the chart file, so they load on demand.
private struct InstructionsView: View {
    @Environment(AppModel.self) private var model
    let slug: String
    let chart: ManifestChart
    @State private var sections: [ChartDocument.Instruction] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sections, id: \.title) { section in
                Text(section.title).font(.headline)
                ForEach(section.text.split(separator: "\n").map(String.init), id: \.self) { line in
                    Text("• \(line)").font(.subheadline)
                }
            }
        }
        .task {
            if let manifest = model.cachedManifest(for: slug), let chart = try? await model.browseChart(manifest: manifest, chart: chart) {
                sections = chart.document.instructions
            }
        }
    }
}
```
`Patterns/ChartBrowserView.swift`:
```swift
import SwiftUI
import GraphghanCore

/// The whole chart at 1 pixel per cell, scaled without smoothing, with pinch zoom and row numbers.
struct ChartBrowserView: View {
    let title: String
    let highlightRow: Int?
    let load: @MainActor () async throws -> Chart
    @State private var chart: Chart?
    @State private var image: CGImage?
    @State private var scale: CGFloat = 4
    @State private var pinchBase: CGFloat = 4
    @State private var error: String?

    var body: some View {
        Group {
            if let chart, let image {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: CGFloat(chart.width) * scale, height: CGFloat(chart.height) * scale * chart.cellAspect)
                        rowNumbers(chart)
                        if let highlightRow, let y = gridRow(for: highlightRow, in: chart) {
                            Rectangle().stroke(Color.accentColor, lineWidth: 2)
                                .frame(width: CGFloat(chart.width) * scale, height: scale * chart.cellAspect)
                                .offset(y: CGFloat(y) * scale * chart.cellAspect)
                        }
                    }
                    .padding(24)
                }
                .gesture(MagnifyGesture().onChanged { scale = min(40, max(1, pinchBase * $0.magnification)) }.onEnded { _ in pinchBase = scale })
            } else if let error {
                ContentUnavailableView("Couldn't load the chart", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let c = try await load()
                chart = c
                image = ChartImage.make(c)
            } catch { self.error = String(describing: error) }
        }
    }

    private func gridRow(for row: Int, in chart: Chart) -> Int? {
        guard let seq = try? WorkSequence(chart: chart), let pass = seq.pass(at: row) else { return nil }
        return pass.gridRow
    }

    @ViewBuilder private func rowNumbers(_ chart: Chart) -> some View {
        let seq = try? WorkSequence(chart: chart)
        ForEach(Array(stride(from: 10, through: chart.height, by: 10)), id: \.self) { row in
            if let y = seq?.pass(at: row)?.gridRow {
                Text("\(row)")
                    .font(.system(size: 9, design: .monospaced))
                    .offset(x: -20, y: CGFloat(y) * scale * chart.cellAspect)
            }
        }
    }
}
```
`Patterns/StartProjectSheet.swift`:
```swift
import SwiftUI
import GraphghanCore

struct StartProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let manifest: PatternManifest
    @State private var chartID: String
    @State private var title: String
    @State private var starting = false
    @State private var error: String?

    init(manifest: PatternManifest) {
        self.manifest = manifest
        _chartID = State(initialValue: manifest.defaultChart?.id ?? "")
        _title = State(initialValue: manifest.title)
    }

    private var chart: ManifestChart? { manifest.charts.first { $0.id == chartID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chart") {
                    Picker("Chart", selection: $chartID) {
                        ForEach(manifest.charts) { c in
                            Text("\(c.variant) · \(c.gaugeKey): \(c.size.width.formatted()) × \(c.size.height.formatted()) \(c.size.unit), \(c.height) rows").tag(c.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Name") {
                    TextField("Project name", text: $title)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Start project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(starting ? "Starting…" : "Start") { start() }.disabled(chart == nil || starting)
                }
            }
        }
    }

    private func start() {
        guard let chart else { return }
        starting = true
        Task {
            do {
                try await model.startProject(manifest: manifest, chart: chart, title: title)
                dismiss()
            } catch {
                self.error = "Couldn't download the chart. Check your connection and try again."
                starting = false
            }
        }
    }
}
```

- [ ] **Step 5: Build, test, and look at it**

Run: `cd ios && mise run test` → `** TEST SUCCEEDED **`. Then launch it once to see real data:
```bash
cd ios && xcrun simctl boot "iPhone 17" 2>/dev/null; xcodebuild -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData build && xcrun simctl install "iPhone 17" build/DerivedData/Build/Products/Debug-iphonesimulator/Graphghan.app && xcrun simctl launch "iPhone 17" com.tylervick.graphghan && sleep 4 && xcrun simctl io "iPhone 17" screenshot build/library.png
```
Open `build/library.png`: the library should list Craigh na Dun with its preview. Tap through in the Simulator app (or trust the tests) to confirm the detail screen shows two published charts and Start project downloads and switches to the Projects tab (a placeholder for now). Note any failure in the report.

- [ ] **Step 6: Commit**

```bash
git add ios
git commit -m "feat(ios): app model, Patterns tab with library, detail, chart browser, and start project"
```

---

### Task 12: Projects tab

**Files:**
- Create: `ios/Graphghan/Projects/ProjectDetailView.swift`, `ios/Graphghan/Projects/JumpToRowSheet.swift`, `ios/Graphghan/Projects/ProjectRow.swift`
- Replace: `ios/Graphghan/Projects/ProjectListView.swift`

**Interfaces:**
- Produces: views `ProjectListView`, `ProjectRow(project:)`, `ProjectDetailView(project:)`, `JumpToRowSheet(rowCount:current:onJump:)`. `ProjectDetailView` uses `AppModel.projects` for every mutation and `AppModel.manifest(for:path:)` for the version notice.

- [ ] **Step 1: Implement**

`Projects/ProjectListView.swift`:
```swift
import SwiftData
import SwiftUI

struct ProjectListView: View {
    @Query(sort: [SortDescriptor(\Project.lastWorked, order: .reverse), SortDescriptor(\Project.started, order: .reverse)])
    private var projects: [Project]

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView("No projects", systemImage: "checklist", description: Text("Start one from a pattern."))
                } else {
                    List(projects) { project in
                        NavigationLink(value: project.id) { ProjectRow(project: project) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: UUID.self) { id in
                if let project = projects.first(where: { $0.id == id }) { ProjectDetailView(project: project) }
            }
        }
    }
}
```
`Projects/ProjectRow.swift`:
```swift
import SwiftUI
import GraphghanCore

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var sequence: WorkSequence?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PreviewImage(slug: project.patternID, sitePath: "patterns/\(project.patternID)/preview.png")
                .frame(width: 96, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title).font(.headline)
                if let sequence {
                    let summary = model.projects.summary(for: project, sequence: sequence)
                    ProgressView(value: summary.percent, total: 100)
                    Text(project.isFinished ? "Finished" : "Row \(project.cursor.row) of \(sequence.passes.count) · \(summary.percent.formatted())%")
                        .font(.caption).foregroundStyle(.secondary)
                    if let finish = model.projects.estimatedFinish(for: project, sequence: sequence), !project.isFinished {
                        Text("Done around \(finish.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let last = project.lastWorked {
                    Text("Last worked \(last.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .task(id: project.chartID) { sequence = try? await model.projects.sequence(for: project) }
    }
}
```
`Projects/JumpToRowSheet.swift`:
```swift
import SwiftUI

struct JumpToRowSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rowCount: Int
    let current: Int
    let onJump: (Int) -> Void
    @State private var row: Int

    init(rowCount: Int, current: Int, onJump: @escaping (Int) -> Void) {
        self.rowCount = rowCount
        self.current = current
        self.onJump = onJump
        _row = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper(value: $row, in: 1...max(1, rowCount)) { Text("Row \(row) of \(rowCount)") }
                TextField("Row", value: $row, format: .number).keyboardType(.numberPad)
            }
            .navigationTitle("Jump to row")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Jump") { onJump(min(max(1, row), rowCount)); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```
`Projects/ProjectDetailView.swift`:
```swift
import SwiftUI
import GraphghanCore

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var sequence: WorkSequence?
    @State private var loadError: String?
    @State private var manifest: PatternManifest?
    @State private var notes: String = ""
    @State private var showJump = false
    @State private var confirmDelete = false
    @State private var switching = false

    var body: some View {
        List {
            if let sequence {
                let summary = model.projects.summary(for: project, sequence: sequence)
                Section {
                    ProgressView(value: summary.percent, total: 100)
                    LabeledContent("Row", value: project.isFinished ? "Finished" : "\(project.cursor.row) of \(sequence.passes.count)")
                    LabeledContent("Stitches", value: "\(summary.stitchesDone.formatted()) of \(summary.totalStitches.formatted())")
                    if let rate = summary.stitchesPerHour { LabeledContent("Pace", value: "\(rate.formatted()) stitches per hour") }
                    if let finish = model.projects.estimatedFinish(for: project, sequence: sequence) {
                        LabeledContent("Estimated finish", value: finish.formatted(date: .long, time: .omitted))
                    }
                }
                Section {
                    Button { model.workingProject = project } label: { Label("Work", systemImage: "play.fill") }
                        .disabled(project.isFinished)
                    NavigationLink {
                        ChartBrowserView(title: project.title, highlightRow: project.cursor.row) { try await model.projects.chart(for: project) }
                    } label: { Label("Browse chart at row \(project.cursor.row)", systemImage: "square.grid.3x3") }
                    Button { showJump = true } label: { Label("Jump to row", systemImage: "arrow.turn.down.right") }
                }
                if let notice = manifest.flatMap({ model.projects.versionNotice(for: project, manifest: $0) }) {
                    Section("Pattern updated") { versionNotice(notice) }
                }
                Section("Notes") {
                    TextField("Yarn lots, hook, reminders…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: notes) { _, new in try? model.projects.setNotes(new, for: project) }
                }
                if !summary.sessions.isEmpty {
                    Section("Sessions") {
                        ForEach(Array(summary.sessions.suffix(10).reversed().enumerated()), id: \.offset) { _, s in
                            LabeledContent(s.start.formatted(date: .abbreviated, time: .shortened),
                                           value: "\(s.stitches) stitches · \(max(1, s.seconds / 60)) min")
                        }
                    }
                }
                Section {
                    if !project.isFinished {
                        Button("Mark finished") { try? model.projects.markFinished(project) }
                    }
                    Button("Delete project", role: .destructive) { confirmDelete = true }
                }
            } else if let loadError {
                Section {
                    ContentUnavailableView("Chart missing", systemImage: "exclamationmark.triangle", description: Text(loadError))
                    Button("Download again") { Task { await redownload() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showJump) {
            if let sequence {
                JumpToRowSheet(rowCount: sequence.passes.count, current: project.cursor.row) { row in
                    try? model.projects.apply(.jump(row: row), to: project, in: sequence)
                }
            }
        }
        .confirmationDialog("Delete this project and its progress?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? model.projects.delete(project)
                dismiss()
            }
        }
        .task { await load() }
    }

    private func load() async {
        notes = project.notes
        do { sequence = try await model.projects.sequence(for: project) }
        catch { loadError = "This project's chart could not be read. Download it again to continue." }
        manifest = try? await model.manifest(for: project.patternID, path: nil)
    }

    private func redownload() async {
        guard let manifest = manifest ?? (try? await model.manifest(for: project.patternID, path: nil)),
              let chart = manifest.charts.first(where: { $0.id == project.chartID }) else { return }
        if let data = try? await model.patterns.chartData(for: manifest.id, path: chart.path), (try? await model.charts.store(data)) != nil {
            loadError = nil
            await load()
        }
    }

    @ViewBuilder private func versionNotice(_ notice: ProjectService.VersionNotice) -> some View {
        switch notice {
        case .chartChanged(let newChart, let newVersion, let canSwitch):
            Text("Version \(newVersion) of this pattern changed the \(newChart.variant) · \(newChart.gaugeKey) chart. This project keeps the chart it started with.")
                .font(.footnote)
            if canSwitch, let manifest {
                Button(switching ? "Switching…" : "Switch to the new chart") {
                    switching = true
                    Task {
                        try? await model.projects.switchChart(project, to: newChart, manifest: manifest)
                        switching = false
                        await load()
                    }
                }
                .disabled(switching)
            } else {
                Text("Switching is only offered before the first row is worked.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: Build and test**

Run: `cd ios && mise run test` → `** TEST SUCCEEDED **` (no new automated tests; the service tests already cover every mutation this screen makes). Launch as in Task 11 Step 5, start a project from Craigh na Dun, open it, jump to row 5, add a note, and screenshot to `build/project.png`.

- [ ] **Step 3: Commit**

```bash
git add ios
git commit -m "feat(ios): Projects tab with progress, sessions, notes, jump, finish, delete, and version notices"
```

---

### Task 13: Work screen with haptics

**Files:**
- Create: `ios/Graphghan/UI/Haptics.swift`, `ios/Graphghan/Work/RowStripView.swift`, `ios/Graphghan/Work/RunChipsView.swift`, `ios/Graphghan/Work/WorkFeedback.swift`
- Replace: `ios/Graphghan/Work/WorkView.swift`
- Test: `ios/Tests/WorkFeedbackTests.swift`

**Interfaces:**
- Produces: `enum WorkFeedback { case run, row, newColor, finished }`; `enum WorkFeedbackRule { static func feedback(for step: WorkStep, from previous: Cursor, in seq: WorkSequence) -> WorkFeedback? }` (pure, tested); `@MainActor enum Haptics { static func play(_ feedback: WorkFeedback) }`; views `WorkView(project:)`, `RowStripView(chart:sequence:cursor:)`, `RunChipsView(chart:pass:cursor:onSelect:)`.

Feedback rule: `back` → nil; `finished` → `.finished`; `startedNewRow` → `.newColor` when the new current run's code does not appear in the previous pass's runs, else `.row`; otherwise → `.newColor` if the new current run's code does not appear in the previous pass's runs, else `.run`. ("The next run introduces a color the previous row did not use.")

- [ ] **Step 1: Failing test**

`ios/Tests/WorkFeedbackTests.swift`:
```swift
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct WorkFeedbackTests {
    // two-letter-codes: Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3
    static let seq = try! WorkSequence(chart: Chart.load(TestFixtures.data("two-letter-codes.chart.json")))

    @Test func runWithinRow() {
        let step = WorkEngine.apply(.advance, to: .start, in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: step, from: .start, in: Self.seq) == .run)   // Gd: row 1 has no previous row → plain run
    }

    @Test func rowBoundaryAndNewColor() {
        let toRow2 = WorkEngine.apply(.advance, to: Cursor(row: 1, run: 2), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: toRow2, from: Cursor(row: 1, run: 2), in: Self.seq) == .row)  // Gd was used in row 1
        let toY = WorkEngine.apply(.advance, to: Cursor(row: 2, run: 1), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: toY, from: Cursor(row: 2, run: 1), in: Self.seq) == .newColor)  // Y not in row 1
    }

    @Test func backAndFinished() {
        let back = WorkEngine.apply(.back, to: Cursor(row: 2, run: 1), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: back, from: Cursor(row: 2, run: 1), in: Self.seq) == nil)
        let done = WorkEngine.apply(.advance, to: Cursor(row: 2, run: 2), in: Self.seq)!
        #expect(WorkFeedbackRule.feedback(for: done, from: Cursor(row: 2, run: 2), in: Self.seq) == .finished)
    }
}
```

- [ ] **Step 2: Run to verify failure** → compile errors.

- [ ] **Step 3: Implement**

`Work/WorkFeedback.swift`:
```swift
import GraphghanCore

enum WorkFeedback: Equatable {
    case run, row, newColor, finished
}

/// Which haptic a step deserves. Pure so it is testable; Haptics plays it.
enum WorkFeedbackRule {
    static func feedback(for step: WorkStep, from previous: Cursor, in seq: WorkSequence) -> WorkFeedback? {
        if step.kind == .back { return nil }
        if step.finished { return .finished }
        guard let pass = seq.pass(at: step.cursor.row), step.cursor.run < pass.runs.count else { return nil }
        let code = pass.runs[step.cursor.run].code
        let previousRowCodes = Set(seq.pass(at: step.cursor.row - 1)?.runs.map(\.code) ?? [])
        let introducesColor = seq.pass(at: step.cursor.row - 1) != nil && !previousRowCodes.contains(code)
        if introducesColor { return .newColor }
        return step.startedNewRow ? .row : .run
    }
}
```
`UI/Haptics.swift`:
```swift
import UIKit

@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    static func prepare() { light.prepare(); medium.prepare(); rigid.prepare() }

    static func play(_ feedback: WorkFeedback) {
        switch feedback {
        case .run: light.impactOccurred()
        case .row: medium.impactOccurred()
        case .newColor:
            rigid.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { rigid.impactOccurred() }
        case .finished: notify.notificationOccurred(.success)
        }
    }
}
```
`Work/RowStripView.swift`:
```swift
import SwiftUI
import GraphghanCore

/// The grid rows around the current pass, current row outlined, a marker on the edge you start from.
struct RowStripView: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    var rowsAround = 2

    var body: some View {
        Canvas { context, size in
            guard let pass = sequence.pass(at: cursor.row), let y = pass.gridRow else { return }
            let y0 = max(0, y - rowsAround)
            let y1 = min(chart.height - 1, y + rowsAround)
            let rows = y1 - y0 + 1
            let cw = size.width / CGFloat(chart.width)
            let ch = size.height / CGFloat(rows)
            for gy in y0...y1 {
                for run in chart.runsByRow[gy] {
                    let rect = CGRect(x: CGFloat(run.x0) * cw, y: CGFloat(gy - y0) * ch, width: CGFloat(run.count) * cw, height: ch)
                    context.fill(Path(rect), with: .color(ChartImage.color(chart.palette[run.colorIndex].hex)))
                }
                if gy != y {
                    context.fill(Path(CGRect(x: 0, y: CGFloat(gy - y0) * ch, width: size.width, height: ch)), with: .color(.black.opacity(0.35)))
                }
            }
            let current = CGRect(x: 1, y: CGFloat(y - y0) * ch + 1, width: size.width - 2, height: ch - 2)
            context.stroke(Path(current), with: .color(.accentColor), lineWidth: 2)
            let marker = pass.direction == .ltr
                ? CGRect(x: 0, y: CGFloat(y - y0) * ch, width: 8, height: ch)
                : CGRect(x: size.width - 8, y: CGFloat(y - y0) * ch, width: 8, height: ch)
            context.fill(Path(marker), with: .color(.accentColor))
        }
        .frame(height: 56)
        .accessibilityHidden(true)
    }
}
```
`Work/RunChipsView.swift`:
```swift
import SwiftUI
import GraphghanCore

/// The current row's runs in working order: done runs dimmed, current highlighted, tap to jump.
struct RunChipsView: View {
    let chart: Chart
    let pass: Pass
    let cursor: Cursor
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(pass.runs.enumerated()), id: \.offset) { i, run in
                        let hex = chart.palette[chart.colorIndex(of: run.code) ?? 0].hex
                        Button { onSelect(i) } label: {
                            Text("\(run.count) \(run.code)")
                                .font(.system(.subheadline, design: .monospaced).bold())
                                .foregroundStyle(ChartImage.isLight(hex) ? .black : .white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(ChartImage.color(hex), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == cursor.run ? Color.accentColor : .clear, lineWidth: 3))
                                .opacity(i < cursor.run ? 0.35 : 1)
                        }
                        .buttonStyle(.plain)
                        .id(i)
                        .accessibilityLabel("\(run.count) \(chart.palette[chart.colorIndex(of: run.code) ?? 0].name)\(i == cursor.run ? ", current" : i < cursor.run ? ", done" : "")")
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: cursor, initial: true) { _, new in withAnimation { proxy.scrollTo(min(new.run, max(0, pass.runs.count - 1)), anchor: .center) } }
        }
    }
}
```
`Work/WorkView.swift` (replace):
```swift
import SwiftUI
import GraphghanCore

/// Full-screen working mode: the current run, the rows around it, one big Done target.
struct WorkView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var chart: Chart?
    @State private var sequence: WorkSequence?
    @State private var cursor: Cursor = .start
    @State private var showJump = false
    @State private var error: String?

    var body: some View {
        Group {
            if let chart, let sequence, let pass = sequence.pass(at: cursor.row) {
                content(chart: chart, sequence: sequence, pass: pass)
            } else if let error {
                VStack(spacing: 16) {
                    Text(error)
                    Button("Close") { dismiss() }
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .task {
            cursor = project.cursor
            do {
                chart = try await model.projects.chart(for: project)
                sequence = try await model.projects.sequence(for: project)
                Haptics.prepare()
            } catch {
                self.error = "This project's chart could not be read. Open the project and download it again."
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private func content(chart: Chart, sequence: WorkSequence, pass: Pass) -> some View {
        let finished = WorkEngine.isFinished(cursor, in: sequence)
        let current: Run? = cursor.run < pass.runs.count ? pass.runs[cursor.run] : nil
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                Button("Close") { dismiss() }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(pass.label) of \(sequence.passes.count)").font(.title2.bold())
                        .onLongPressGesture { showJump = true }
                        .accessibilityHint("Long press to jump to a row")
                    Text(sideText(pass)).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Back") { perform(.back, sequence: sequence) }
                    .disabled(cursor == .start)
            }
            .padding(.horizontal)

            RowStripView(chart: chart, sequence: sequence, cursor: cursor).padding(.horizontal)

            RunChipsView(chart: chart, pass: pass, cursor: cursor) { run in
                perform(.jump(row: cursor.row, run: run), sequence: sequence)
            }

            if finished {
                VStack(spacing: 8) {
                    Text("Finished").font(.largeTitle.bold())
                    Text("Every row is done. Block it, weave in the ends, and take a picture.").multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else if let current {
                currentRun(current, chart: chart, sequence: sequence, pass: pass)
                Spacer(minLength: 0)
                Button {
                    perform(.advance, sequence: sequence)
                } label: {
                    Text("Done").font(.largeTitle.bold()).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxHeight: .infinity)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityLabel("Done with \(current.count) \(colorName(current.code, chart))")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 60).onEnded { value in
                if value.translation.width > 80, abs(value.translation.height) < 80 { perform(.back, sequence: sequence) }
            }
        )
        .sheet(isPresented: $showJump) {
            JumpToRowSheet(rowCount: sequence.passes.count, current: cursor.row) { row in perform(.jump(row: row), sequence: sequence) }
        }
    }

    @ViewBuilder
    private func currentRun(_ run: Run, chart: Chart, sequence: WorkSequence, pass: Pass) -> some View {
        let hex = chart.palette[chart.colorIndex(of: run.code) ?? 0].hex
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(run.count)").font(.system(size: 72, weight: .heavy, design: .rounded))
                Text(run.code).font(.system(size: 40, weight: .bold, design: .monospaced))
            }
            Text(colorName(run.code, chart)).font(.title3)
        }
        .foregroundStyle(ChartImage.isLight(hex) ? .black : .white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(ChartImage.color(hex), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        Text(nextText(chart: chart, sequence: sequence, pass: pass)).font(.headline).foregroundStyle(.secondary)
    }

    private func nextText(chart: Chart, sequence: WorkSequence, pass: Pass) -> String {
        if cursor.run + 1 < pass.runs.count {
            let next = pass.runs[cursor.run + 1]
            return "then \(next.count) \(colorName(next.code, chart))"
        }
        if let nextPass = sequence.pass(at: cursor.row + 1), let first = nextPass.runs.first {
            return "last run in this row · next row starts in \(colorName(first.code, chart))"
        }
        return "last run of the last row"
    }

    private func sideText(_ pass: Pass) -> String {
        let side = pass.side == .ws ? "Wrong side" : "Right side"
        let dir = pass.direction == .ltr ? "read left → right" : "read right → left"
        return "\(side) · \(dir)"
    }

    private func colorName(_ code: String, _ chart: Chart) -> String {
        chart.palette[chart.colorIndex(of: code) ?? 0].name
    }

    private func perform(_ action: WorkAction, sequence: WorkSequence) {
        let previous = cursor
        do {
            guard let step = try model.projects.apply(action, to: project, in: sequence) else { return }
            cursor = step.cursor
            if let feedback = WorkFeedbackRule.feedback(for: step, from: previous, in: sequence) { Haptics.play(feedback) }
        } catch {
            // The store keeps lastError for the banner; the screen stays usable.
        }
    }
}
```

- [ ] **Step 4: Build, test, and use it**

Run: `cd ios && mise run test` → `** TEST SUCCEEDED **`. Launch as in Task 11 Step 5, open the Craigh na Dun project, tap Work, tap Done through Row 1 into Row 2 (the strip should move, the chips should reset), swipe right to go back, long-press the row title and jump to row 40, rotate the simulator (`xcrun simctl` has no rotate; use the Simulator app's Device menu) and confirm the layout survives, then close. Screenshot to `build/work.png`.

- [ ] **Step 5: Commit**

```bash
git add ios
git commit -m "feat(ios): Work screen with row strip, run chips, big Done target, swipe back, jump, and haptics"
```

---

### Task 14: Docs and repo wiring

**Files:**
- Modify: `README.md`, `ios/README.md`, `.claude/skills/graphghan/SKILL.md`

- [ ] **Step 1: README**

In the root `README.md`, add after the "Chart format" section:
```markdown
## iOS app

`ios/` holds a SwiftUI app for working a published pattern on an iPhone (see `ios/README.md`):
a Patterns tab fed from this site, a Projects tab with per-project progress, and a full-screen
Work screen. `ios/Packages/GraphghanCore` is the Swift reader for the chart format and passes the
same conformance fixtures as the Python package.
```
In `ios/README.md`, add a "Layout" section listing `Graphghan/` (app: `Storage/`, `Network/`, `Services/`, `Patterns/`, `Projects/`, `Work/`, `UI/`), `Packages/GraphghanCore/` (format reader), `Tests/` (app unit tests, Swift Testing, in-memory SwiftData and a stub HTTP client), and a "Data" section: SwiftData store and chart files under the App Group container (`group.com.tylervick.graphghan`), pattern cache under its `Library/Caches/patterns`.

In `.claude/skills/graphghan/SKILL.md`, append under "Publishing and export":
```markdown
- The iOS app (`ios/`) reads the published manifest and charts; anything the site publishes is
  what the app can start a project from. `ios/Packages/GraphghanCore` must keep passing
  `fixtures/chart-format` (run `cd ios && mise run core-test`).
```

- [ ] **Step 2: Final checks and commit**

Run from `ios/`: `mise run core-test && mise run test`. Run from the repo root: `mise run check` (the Python side is untouched; hk's whitespace/newline checks cover the new files). Commit:
```bash
git add README.md ios/README.md .claude/skills/graphghan/SKILL.md
git commit -m "docs: iOS app overview and skill note"
```

- [ ] **Step 3: Finish the branch**

Push `feat/ios-core` and open a pull request against `main` titled "iOS app: core package, projects, and Work screen" summarizing Tasks 1–14, with the session attribution footer. CI does not yet build the iOS project (Plan 4 adds that job); state in the PR that `mise run core-test` and `mise run test` were run locally.

---

## Self-review notes

Spec coverage. §6.1 structure: Tasks 1–7 (core), 8–13 (app); the widget target is Plan 3. §6.2 pattern data: Task 9 (ETag cache under `Library/Caches/patterns/<id>/`, charts under `Application Support/charts/<id>.json`, decoded once per launch via `ChartLibrary`'s memo). §6.3 models: Task 8 (plus `chartVariant`/`chartGaugeKey`, needed for the version notice's chart lookup). `WorkEngine.apply` + single save: Task 10. §6.4 pace and estimate: Task 6. §6.5 screens: Task 11 (library list with pull-to-refresh, banner, empty state; detail with quote, specs, palette, instructions, published charts; chart browser at 1 px per cell with nearest-neighbour scaling, pinch, row numbers; start project with variant/gauge picker, name, and no project on download failure), Task 12 (project list with percent, row of total, last worked, estimate; detail with overview, sessions, pace, notes, Work, browse at current row, jump, finish, delete, version notice with switch only at row 1 run 0), Task 13 (full screen, idle timer, orientations via Info.plist, header with row/side/direction, strip, chips, current run with next-run text, lower-half Done, swipe-right Back, long-press jump, Close, haptics light/medium/double, every action through the service). §6.6 errors: storage errors recorded in `lastError` and never block (Task 10, Task 13's `perform`); undecodable chart → project marked needing re-download with a button (Task 12); offline as a state (Task 11). §8.1/8.2: Task 1. §9 Swift core tests: decoder edge cases, engine boundaries, progress round trip, pace from a known log, chart id parity for every fixture — Tasks 2–6. §9 app tests: start pins, atomic advance, delete cascade, version notice, PatternStore fresh/304/offline-with-cache/offline-without-cache, failed download leaves no project — Tasks 8–10.

Interface consistency: `WorkAction.jump(row:run:)` (Task 5) is used by Task 13's chip tap and by Task 12's sheet with the default `run: 0`; `Chart.unchecked(document:)` (Task 4) is internal to the core package; `ProjectService.apply` returns `WorkStep?` everywhere; `AppModel.manifest(for:path:)` takes the index entry's `manifest` path or nil.

Known simplifications, deliberate: no CloudKit; the Work screen's Back button is an accessibility affordance beside the swipe; the chart browser's row numbers are every 10 rows; instruction sections load from the default chart file rather than a separate fetch.

# iOS Design Language ("Heather") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the Heather design language to every screen of the iOS app, the Live Activity, and the app icon, light theme only, with snapshot coverage.

**Architecture:** Seven semantic colors live in a shared asset catalog compiled into both the app and the widget extension; fonts and text styles live in the app target. Small shared views (card, chip, banner, button styles, yarn surface, weave) replace ad hoc styling, and the Work screen is rebuilt around a stateless `WorkScreen` view so it can be snapshotted without the model.

**Tech Stack:** SwiftUI, iOS 17, Swift 6 strict concurrency, XcodeGen (`project.yml`), Swift Testing, the repo's `ImageRenderer` snapshot harness (`ios/Tests/Snapshots.swift`), Pillow (already a project dependency through `site/build.py`) for the icon.

**Spec:** `docs/superpowers/specs/2026-09-11-ios-design-language-design.md`

## Global Constraints

- iOS 17.0 deployment target; Swift 6, `SWIFT_STRICT_CONCURRENCY: complete` (from `ios/project.yml`).
- Every command below runs from `ios/` unless stated. Regenerate the project after touching `project.yml`: `mise run generate`. Tests: `mise run test` (iPhone 17 simulator). A single test: `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -only-testing:GraphghanTests/<Suite>/<test>`.
- Snapshot references live in `ios/Tests/__Snapshots__/`. A missing reference is recorded and the test fails once; re-run to compare; commit the PNG. To re-record, delete the PNG.
- Colors: only the tokens in Task 1 (`Color.ground`, `.panel`, `.ink`, `.ink2`, `.line`, `.heather`, `.moss`, `.mossDeep`, `.cream`, `.brick`). No view names a hex except through `YarnSurface` (Task 2) for yarn colors from a chart.
- Fonts: only `Font.Heather.*` styles from Task 1. Live Activity views use system faces only (the widget bundles no fonts).
- Yarn-colored surfaces (swatch, chip, palette entry, strip cell) get foreground and hairline from `YarnSurface` (Task 2), never from `ChartImage.isLight` or `HexColor.isLight` directly.
- The weave is painted on Ground and on the Work screen's Moss field only. Panels are flat. Only the Work card has a shadow.
- PR #24 (iOS CI and TestFlight) merges before this plan starts. Rebase `tylervick/style` on `main` first (`git rebase origin/main`); the branch holds only the spec and this plan, so nothing conflicts.
- Snapshots: locally `mise run test` compares (and records a missing reference); CI's `ios` job runs the same tests in `render` mode and uploads the PNGs as the `ios-snapshots` artifact, so a drifted reference fails locally, not in CI. To re-record every reference in one run: `TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record mise run test`.
- Commit after every task with a conventional message; branch `tylervick/style`; finish with a PR (never a local merge).
- Copy stays as it is today unless the spec changes it: "then N Name", "next row starts in Name", "Finished", "Every row is done. Block it, weave in the ends, and take a picture."

---

## File structure

Create:
- `ios/Shared/Tokens.xcassets/` — the seven token color sets plus `MossDeep`, compiled into app and widget.
- `ios/Shared/Theme.swift` — `Color` token accessors and the `weave` modifier.
- `ios/Shared/YarnSurface.swift` — fill, foreground, hairline for yarn colors; `yarnSurface(_:radius:)` modifier.
- `ios/Fonts/` — Literata (SemiBold, MediumItalic), Atkinson Hyperlegible (Regular, Bold), Nunito (variable), `OFL-*.txt`.
- `ios/Graphghan/UI/Typography.swift` — `Font.Heather` text styles; `Theme.installAppearance()` for navigation and tab bars.
- `ios/Graphghan/UI/Card.swift`, `Chip.swift`, `Banner.swift`, `ButtonStyles.swift` — shared components.
- `ios/Graphghan/Projects/ProjectCardView.swift` — stateless project row.
- `ios/Graphghan/Patterns/PatternDetailContent.swift` — stateless pattern detail body.
- `ios/Graphghan/Work/WorkScreen.swift`, `SwatchStack.swift`, `DoneField.swift`, `OnDeckRule.swift` — the Work screen.
- `ios/Scripts/make_icon.py` — writes the 1024 pt icon.
- `ios/Tests/ThemeTests.swift`, `YarnSurfaceTests.swift`, `ComponentSnapshotTests.swift`, `ProjectCardTests.swift`, `PatternDetailTests.swift`, `WorkScreenTests.swift`, `OnDeckRuleTests.swift`.

Modify:
- `ios/project.yml` (fonts, shared catalog, icon), `ios/mise.toml` (icon task), `ios/Assets.xcassets/AccentColor.colorset/Contents.json`, `ios/Assets.xcassets/AppIcon.appiconset/`.
- `ios/Graphghan/GraphghanApp.swift`, `RootView.swift`, `Patterns/LibraryView.swift`, `Patterns/PatternDetailView.swift`, `Patterns/StartProjectSheet.swift`, `Patterns/ChartBrowserView.swift`, `Projects/ProjectListView.swift`, `Projects/ProjectRow.swift`, `Projects/ProjectDetailView.swift`, `Work/WorkView.swift`, `Work/RowStripView.swift`, `Work/RunChipsView.swift`, `UI/ChartImage.swift`.
- `ios/Shared/WorkActivityViews.swift`, `ios/Tests/WorkActivityViewsTests.swift` (references re-recorded).
- `ios/README.md`, `ios/docs/qa.md`.

---

### Task 1: Tokens, fonts, and text styles

**Files:**
- Create: `ios/Shared/Tokens.xcassets/Contents.json` and eight `*.colorset/Contents.json`
- Create: `ios/Shared/Theme.swift`
- Create: `ios/Fonts/*.ttf`, `ios/Fonts/OFL-Literata.txt`, `OFL-AtkinsonHyperlegible.txt`, `OFL-Nunito.txt`
- Create: `ios/Graphghan/UI/Typography.swift`
- Modify: `ios/project.yml`, `ios/Assets.xcassets/AccentColor.colorset/Contents.json`
- Test: `ios/Tests/ThemeTests.swift`

**Interfaces:**
- Produces: `Color.ground, .panel, .ink, .ink2, .line, .heather, .moss, .mossDeep, .cream, .brick` (static, in `Shared/Theme.swift`); `View.weave(_ color: Color = .ink, opacity: Double = 0.045)`; `Font.Heather.title, .heading, .rowNumber, .done, .quote, .body, .label, .caption, .count, .code`; `Theme.installAppearance()`.

- [ ] **Step 1: Write the failing tests**

`ios/Tests/ThemeTests.swift`:

```swift
import SwiftUI
import Testing
import UIKit
@testable import Graphghan

@MainActor
@Suite struct ThemeTests {
    /// Every token resolves from the shared catalog (a missing set resolves to clear, which is what this catches).
    @Test func tokensResolve() {
        for name in ["Ground", "Panel", "Ink", "Ink2", "Line", "Heather", "Moss", "MossDeep"] {
            #expect(UIColor(named: name) != nil, "missing color set \(name)")
        }
        #expect(UIColor(Color.ground).cgColor.components?.first != nil)
    }

    /// The bundled faces register under the PostScript names Typography.swift uses. If one is nil,
    /// dump `UIFont.familyNames.flatMap(UIFont.fontNames(forFamilyName:))` and fix the name.
    @Test func fontsRegister() {
        for name in ["Literata-SemiBold", "Literata-MediumItalic", "AtkinsonHyperlegible-Regular", "AtkinsonHyperlegible-Bold", "Nunito-Black"] {
            #expect(UIFont(name: name, size: 17) != nil, "font \(name) not registered")
        }
    }

    @Test func weaveRenders() throws {
        #expect(try Snapshots.assert(Color.ground.weave().frame(width: 60, height: 60), named: "weave", size: CGSize(width: 60, height: 60)))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mise run generate && xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -only-testing:GraphghanTests/ThemeTests`
Expected: compile failure (`Color.ground`, `weave` undefined).

- [ ] **Step 3: Generate the shared color catalog**

Run from `ios/`:

```bash
python3 - <<'EOF'
import json, os
tokens = {  # name: (light, dark)
    "Ground": ("EEEBE4", "1B1917"), "Panel": ("F8F6F1", "262320"), "Ink": ("1F2A24", "F1ECE2"),
    "Ink2": ("5B675F", "A39C90"), "Line": ("D3D0C6", "3A352F"), "Heather": ("7C5E8C", "C9A8DC"),
    "Moss": ("1E4D3A", "2E7D5B"), "MossDeep": ("163B2D", "245F48"),
}
def comp(h): return {"red": f"0x{h[0:2]}", "green": f"0x{h[2:4]}", "blue": f"0x{h[4:6]}", "alpha": "1.000"}
root = "Shared/Tokens.xcassets"
os.makedirs(root, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(f"{root}/Contents.json", "w"), indent=2)
for name, (light, dark) in tokens.items():
    d = f"{root}/{name}.colorset"; os.makedirs(d, exist_ok=True)
    json.dump({"colors": [
        {"idiom": "universal", "color": {"color-space": "srgb", "components": comp(light)}},
        {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}],
         "color": {"color-space": "srgb", "components": comp(dark)}}],
        "info": {"author": "xcode", "version": 1}}, open(f"{d}/Contents.json", "w"), indent=2)
print("wrote", len(tokens), "color sets")
EOF
```

Then repoint the app tint. Replace `ios/Assets.xcassets/AccentColor.colorset/Contents.json` with:

```json
{
  "colors": [
    { "idiom": "universal",
      "color": { "color-space": "srgb", "components": { "red": "0x1E", "green": "0x4D", "blue": "0x3A", "alpha": "1.000" } } },
    { "idiom": "universal", "appearances": [ { "appearance": "luminosity", "value": "dark" } ],
      "color": { "color-space": "srgb", "components": { "red": "0x2E", "green": "0x7D", "blue": "0x5B", "alpha": "1.000" } } }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 4: Fetch the fonts**

Run from `ios/` (all OFL; the license texts ride along):

```bash
mkdir -p Fonts
L=https://raw.githubusercontent.com/googlefonts/literata/main
curl -sSLf -o Fonts/Literata-SemiBold.ttf    "$L/fonts/ttf/Literata-SemiBold.ttf"
curl -sSLf -o Fonts/Literata-MediumItalic.ttf "$L/fonts/ttf/Literata-MediumItalic.ttf"
curl -sSLf -o Fonts/OFL-Literata.txt          "$L/OFL.txt"
cp ../site/src/fonts/AtkinsonHyperlegible-Regular.ttf ../site/src/fonts/AtkinsonHyperlegible-Bold.ttf Fonts/
cp ../site/src/fonts/OFL.txt Fonts/OFL-AtkinsonHyperlegible.txt
G=https://raw.githubusercontent.com/google/fonts/main/ofl/nunito
curl -sSLf -o "Fonts/Nunito[wght].ttf" "$G/Nunito%5Bwght%5D.ttf"
curl -sSLf -o Fonts/OFL-Nunito.txt "$G/OFL.txt"
ls -la Fonts
```

Expected: five `.ttf` files (each between 50 KB and 400 KB) and three OFL texts. If the Atkinson OFL in `site/src/fonts` covers several faces, that is fine; it is the same license text.

- [ ] **Step 5: Register fonts and the shared catalog in `project.yml`**

In `ios/project.yml`, under `targets.Graphghan.sources` add `Fonts` and the shared catalog, and under `targets.GraphghanWidgets.sources` add the shared catalog:

```yaml
  Graphghan:
    type: application
    platform: iOS
    sources:
      - path: Graphghan
      - path: Shared
      - path: Assets.xcassets
      - path: Fonts
```

```yaml
  GraphghanWidgets:
    type: app-extension
    platform: iOS
    sources:
      - path: GraphghanWidgets
      - path: Shared
```

`Shared/Tokens.xcassets` sits inside `Shared`, which both targets already list, so it compiles into both. Then add the font list to the app's Info.plist properties (same block as `NSSupportsLiveActivities`):

```yaml
        UIAppFonts:
          - Literata-SemiBold.ttf
          - Literata-MediumItalic.ttf
          - AtkinsonHyperlegible-Regular.ttf
          - AtkinsonHyperlegible-Bold.ttf
          - Nunito[wght].ttf
```

- [ ] **Step 6: Write `Shared/Theme.swift`**

```swift
import SwiftUI

/// The Heather tokens (spec §3). Named sets live in Shared/Tokens.xcassets so the widget gets them too.
extension Color {
    static let ground = Color("Ground")
    static let panel = Color("Panel")
    static let ink = Color("Ink")
    static let ink2 = Color("Ink2")
    static let line = Color("Line")
    static let heather = Color("Heather")
    static let moss = Color("Moss")
    static let mossDeep = Color("MossDeep")
    /// Text on Moss (#F4F5F0). Not a set: it does not change with the theme.
    static let cream = Color(red: 0xF4 / 255, green: 0xF5 / 255, blue: 0xF0 / 255)
    /// The save-failure rule (#9C3B3B).
    static let brick = Color(red: 0x9C / 255, green: 0x3B / 255, blue: 0x3B / 255)
}

/// The tweed weave (spec §4): 1pt hairlines at 135°, 5pt pitch. Painted behind the content, never over it.
struct Weave: ViewModifier {
    var color: Color = .ink
    var opacity: Double = 0.045

    func body(content: Content) -> some View {
        content.background {
            Canvas { context, size in
                let step: CGFloat = 5 * 2.0.squareRoot()
                var path = Path()
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += step
                }
                context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: 1)
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func weave(_ color: Color = .ink, opacity: Double = 0.045) -> some View {
        modifier(Weave(color: color, opacity: opacity))
    }
}
```

- [ ] **Step 7: Write `Graphghan/UI/Typography.swift`**

```swift
import SwiftUI
import UIKit

extension Font {
    /// The Heather type ramp (spec §5.2). Every style scales with Dynamic Type except `done`.
    enum Heather {
        static let title = Font.custom("Literata-SemiBold", size: 28, relativeTo: .largeTitle)
        static let heading = Font.custom("Literata-SemiBold", size: 22, relativeTo: .title2)
        static let rowNumber = Font.custom("Literata-SemiBold", size: 26, relativeTo: .title)
        static let done = Font.custom("Literata-SemiBold", fixedSize: 48)
        static let quote = Font.custom("Literata-MediumItalic", size: 17, relativeTo: .body)
        static let body = Font.custom("AtkinsonHyperlegible-Regular", size: 17, relativeTo: .body)
        static let label = Font.custom("AtkinsonHyperlegible-Bold", size: 15, relativeTo: .subheadline)
        static let caption = Font.custom("AtkinsonHyperlegible-Regular", size: 13, relativeTo: .footnote)
        static let count = Font.custom("Nunito-Black", size: 84, relativeTo: .largeTitle)
        static let code = Font.custom("AtkinsonHyperlegible-Bold", size: 34, relativeTo: .title)
    }
}

enum Theme {
    /// Navigation and tab bars are UIKit underneath (spec §6.5): Ground behind both, Literata titles, Moss tint.
    @MainActor static func installAppearance() {
        let ground = UIColor(named: "Ground") ?? .systemBackground
        let ink = UIColor(named: "Ink") ?? .label
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = ground
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: ink, .font: UIFont(name: "Literata-SemiBold", size: 17) ?? .preferredFont(forTextStyle: .headline)]
        nav.largeTitleTextAttributes = [.foregroundColor: ink, .font: UIFont(name: "Literata-SemiBold", size: 34) ?? .preferredFont(forTextStyle: .largeTitle)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = ground
        tab.shadowColor = UIColor(named: "Line")
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
```

- [ ] **Step 8: Call the appearance from the app**

In `ios/Graphghan/GraphghanApp.swift`, at the top of `init()` (before the container code) add:

```swift
        Theme.installAppearance()
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `mise run generate && xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -only-testing:GraphghanTests/ThemeTests`
Expected: first run records `weave.png` and fails once with "Recorded new snapshot"; second run: 3 tests pass. Open `Tests/__Snapshots__/weave.png`: a stone square with faint diagonal hairlines.

If `fontsRegister` fails only for `Nunito-Black`, print the registered names once (`print(UIFont.fontNames(forFamilyName: "Nunito"))` in the test) and use the instance name it lists (it will be one of `Nunito-Black` or `NunitoBlack`); update `Typography.swift` and the test to match.

- [ ] **Step 10: Commit**

```bash
git add project.yml Shared/Tokens.xcassets Shared/Theme.swift Fonts Graphghan/UI/Typography.swift Graphghan/GraphghanApp.swift Assets.xcassets/AccentColor.colorset Tests/ThemeTests.swift Tests/__Snapshots__/weave.png
git commit -m "feat(ios): Heather tokens, fonts, text ramp, and the weave"
```

---

### Task 2: Yarn surfaces

**Files:**
- Create: `ios/Shared/YarnSurface.swift`
- Modify: `ios/Graphghan/UI/ChartImage.swift`
- Test: `ios/Tests/YarnSurfaceTests.swift`

**Interfaces:**
- Consumes: `HexColor.rgb/color/isLight` (`Shared/HexColor.swift`).
- Produces: `YarnSurface.fill(_ hex: String) -> Color`, `YarnSurface.foreground(_ hex: String) -> Color`, `YarnSurface.hairline: Color`, `View.yarnSurface(_ hex: String, radius: CGFloat)`, `View.yarnSurface(_ hex: String, shape: some InsettableShape)`.

- [ ] **Step 1: Write the failing test**

`ios/Tests/YarnSurfaceTests.swift`:

```swift
import SwiftUI
import Testing
import UIKit
@testable import Graphghan

@MainActor
@Suite struct YarnSurfaceTests {
    private func luminance(_ color: Color) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Cream yarn gets dark text, charcoal yarn gets light text; the split is the PWA's 140/255 rule.
    @Test func foregroundFollowsLuminance() {
        #expect(luminance(YarnSurface.foreground("#F2E8D5")) < 0.3)
        #expect(luminance(YarnSurface.foreground("#2B2F33")) > 0.8)
        #expect(luminance(YarnSurface.foreground("#D9A21B")) < 0.3)   // gold is light by the rule
        #expect(luminance(YarnSurface.foreground("#1E4D3A")) > 0.8)
    }

    /// The hairline is what keeps cream on cream visible: 14% black.
    @Test func hairlineIsFourteenPercentBlack() {
        var a: CGFloat = 0
        UIColor(YarnSurface.hairline).getRed(nil, green: nil, blue: nil, alpha: &a)
        #expect(abs(a - 0.14) < 0.01)
    }

    /// A cream swatch on the cream ground still shows its edge.
    @Test func creamOnCream() throws {
        let view = Text("51 C").font(Font.Heather.label).padding(12).yarnSurface("#F2E8D5", radius: 18)
            .padding(12).background(Color(red: 0xF2 / 255, green: 0xE8 / 255, blue: 0xD5 / 255))
        #expect(try Snapshots.assert(view, named: "yarn-cream-on-cream", size: CGSize(width: 120, height: 70)))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -only-testing:GraphghanTests/YarnSurfaceTests`
Expected: compile failure (`YarnSurface` undefined).

- [ ] **Step 3: Write `Shared/YarnSurface.swift`**

```swift
import SwiftUI

/// Every surface painted in a yarn color from a chart goes through here (spec §3): the fill, the
/// foreground that reads on it, and the hairline that keeps cream visible on cream.
enum YarnSurface {
    static let hairline = Color.black.opacity(0.14)
    /// Dark ink for light yarn (#2B2723), warm cream for dark yarn (#F4EFE6).
    private static let darkText = Color(red: 0x2B / 255, green: 0x27 / 255, blue: 0x23 / 255)
    private static let lightText = Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255)

    static func fill(_ hex: String) -> Color { HexColor.color(hex) }
    static func foreground(_ hex: String) -> Color { HexColor.isLight(hex) ? darkText : lightText }
}

struct YarnSurfaceModifier<S: InsettableShape>: ViewModifier {
    let hex: String
    let shape: S

    func body(content: Content) -> some View {
        content
            .foregroundStyle(YarnSurface.foreground(hex))
            .background(YarnSurface.fill(hex), in: shape)
            .overlay(shape.strokeBorder(YarnSurface.hairline, lineWidth: 1))
    }
}

extension View {
    func yarnSurface(_ hex: String, radius: CGFloat) -> some View {
        modifier(YarnSurfaceModifier(hex: hex, shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }
    func yarnSurface<S: InsettableShape>(_ hex: String, shape: S) -> some View {
        modifier(YarnSurfaceModifier(hex: hex, shape: shape))
    }
}
```

- [ ] **Step 4: Point `ChartImage` at `HexColor`**

In `ios/Graphghan/UI/ChartImage.swift` delete the `color(_:)` and `isLight(_:)` functions and the `rgb` variant is kept only for `make`. Replace the three functions with:

```swift
    static func rgb(_ hex: String) -> (r: UInt8, g: UInt8, b: UInt8) {
        let c = HexColor.rgb(hex)
        return (UInt8(c.r * 255), UInt8(c.g * 255), UInt8(c.b * 255))
    }

    static func color(_ hex: String) -> Color { HexColor.color(hex) }
```

Then grep for the removed function: `grep -rn "ChartImage.isLight" Graphghan Shared` and change each use to `YarnSurface.foreground(hex)` where it picked a text color (`WorkView.swift:155`, `RunChipsView.swift:20`), i.e. `.foregroundStyle(ChartImage.isLight(hex) ? .black : .white)` becomes `.foregroundStyle(YarnSurface.foreground(hex))`. (Both views are rewritten in Task 6; this keeps the build green until then.) `Tests/ChartImageTests.swift` may reference `isLight`; if so change that assertion to `HexColor.isLight`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -only-testing:GraphghanTests/YarnSurfaceTests -only-testing:GraphghanTests/ChartImageTests`
Expected: `yarn-cream-on-cream.png` recorded on the first run; then all pass. The PNG shows a cream pill with a visible edge on a cream field.

- [ ] **Step 6: Commit**

```bash
git add Shared/YarnSurface.swift Graphghan/UI/ChartImage.swift Graphghan/Work Tests/YarnSurfaceTests.swift Tests/ChartImageTests.swift Tests/__Snapshots__/yarn-cream-on-cream.png
git commit -m "feat(ios): one helper for every yarn-colored surface"
```

---

### Task 3: Shared components: card, chip, banner, button styles

**Files:**
- Create: `ios/Graphghan/UI/Card.swift`, `ios/Graphghan/UI/Chip.swift`, `ios/Graphghan/UI/Banner.swift`, `ios/Graphghan/UI/ButtonStyles.swift`
- Test: `ios/Tests/ComponentSnapshotTests.swift`

**Interfaces:**
- Consumes: tokens and `Font.Heather` (Task 1), `yarnSurface` (Task 2).
- Produces: `Card { content }` with `padding: CGFloat = 12`; `Chip(text:hex:state:)` with `Chip.State { case plain, upcoming, current, done }`; `Banner(text:kind:action:)` with `Banner.Kind { case info, failure }` and `action: Banner.Action?` (`Action(label: String, run: () -> Void)`); `ButtonStyle.primary`, `.secondary`.

- [ ] **Step 1: Write the failing snapshot test**

`ios/Tests/ComponentSnapshotTests.swift`:

```swift
import SwiftUI
import Testing
@testable import Graphghan

@MainActor
@Suite struct ComponentSnapshotTests {
    @Test func componentsSheet() throws {
        let sheet = VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 6) {
                Chip(text: "2 G", hex: "#1E4D3A", state: .done)
                Chip(text: "4 Y", hex: "#D9A21B", state: .done)
                Chip(text: "51 C", hex: "#F2E8D5", state: .current)
                Chip(text: "4 K", hex: "#2B2F33", state: .upcoming)
                Chip(text: "P", hex: "#6B2D5C", state: .plain)
            }
            Button("Start project") {}.buttonStyle(.primary)
            Button("Browse chart") {}.buttonStyle(.secondary)
            Banner(text: "Showing saved patterns. The site could not be reached.", kind: .info, action: .init(label: "Retry") {})
            Banner(text: "Couldn't save your progress: disk full.", kind: .failure, action: .init(label: "Dismiss") {})
            Card { Text("Craigh na Dun Blanket").font(Font.Heather.heading) }
        }
        .padding(16)
        .background(Color.ground.weave())
        #expect(try Snapshots.assert(sheet, named: "components", size: CGSize(width: 390, height: 420)))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -only-testing:GraphghanTests/ComponentSnapshotTests`
Expected: compile failure (`Chip`, `Banner`, `Card`, `.primary` undefined).

- [ ] **Step 3: Write the four component files**

`ios/Graphghan/UI/Card.swift`:

```swift
import SwiftUI

/// Panel, 14pt radius, one Line hairline, no shadow (spec §6.2).
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
    }
}
```

`ios/Graphghan/UI/Chip.swift`:

```swift
import SwiftUI

/// A run or a palette entry in its yarn color (spec §6.3).
struct Chip: View {
    enum State { case plain, upcoming, current, done }
    let text: String
    let hex: String
    var state: State = .plain

    var body: some View {
        Text(text)
            .font(Font.Heather.label)
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: 52, minHeight: 36)
            .yarnSurface(hex, shape: Capsule())
            .background {
                if state == .current { Capsule().stroke(Color.heather, lineWidth: 3).padding(-3) }
            }
            .opacity(state == .done ? 0.35 : 1)
    }
}
```

`ios/Graphghan/UI/Banner.swift`:

```swift
import SwiftUI

/// A Panel card with a 4pt leading rule: Heather for information, Brick for a failure (spec §6.6).
struct Banner: View {
    enum Kind { case info, failure }
    struct Action {
        let label: String
        let run: () -> Void
        init(label: String, run: @escaping () -> Void) { self.label = label; self.run = run }
    }
    let text: String
    var kind: Kind = .info
    var action: Action?

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(kind == .info ? Color.heather : Color.brick).frame(width: 4)
            HStack(spacing: 10) {
                Text(text).font(Font.Heather.caption).foregroundStyle(Color.ink)
                Spacer(minLength: 0)
                if let action {
                    Button(action.label, action: action.run).font(Font.Heather.label).tint(.moss)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
```

`ios/Graphghan/UI/ButtonStyles.swift`:

```swift
import SwiftUI

/// Moss fill, Cream text, pill, 50pt (spec §6.4).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.Heather.label)
            .foregroundStyle(Color.cream)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.moss.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

/// Panel fill, Line border, Moss text.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.Heather.label)
            .foregroundStyle(Color.moss)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.panel.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var secondary: SecondaryButtonStyle { .init() } }
```

- [ ] **Step 4: Run the test to verify it passes**

Run the same command. Expected: `components.png` recorded, then passes. Check the PNG: five pills (two dimmed, the cream one ringed in heather), a moss pill button, a bordered panel button, two banners with rules, and a card.

- [ ] **Step 5: Commit**

```bash
git add Graphghan/UI/Card.swift Graphghan/UI/Chip.swift Graphghan/UI/Banner.swift Graphghan/UI/ButtonStyles.swift Tests/ComponentSnapshotTests.swift Tests/__Snapshots__/components.png
git commit -m "feat(ios): card, chip, banner, and button styles"
```

---

### Task 4: Navigation chrome and the two lists

**Files:**
- Create: `ios/Graphghan/Projects/ProjectCardView.swift`
- Modify: `ios/Graphghan/RootView.swift`, `ios/Graphghan/Patterns/LibraryView.swift`, `ios/Graphghan/Projects/ProjectListView.swift`, `ios/Graphghan/Projects/ProjectRow.swift`
- Test: `ios/Tests/ProjectCardTests.swift`

**Interfaces:**
- Consumes: `Card`, `Banner`, tokens, `Font.Heather`, `weave`.
- Produces: `ProjectCardView(title:percent:line:estimate:lastWorked:finished:preview:)` (all `String`/`Double?`/`Bool`/`UIImage?`), used by `ProjectRow`; `LibraryRow` restyled in place.

- [ ] **Step 1: Write the failing snapshot test**

`ios/Tests/ProjectCardTests.swift`:

```swift
import SwiftUI
import Testing
@testable import Graphghan

@MainActor
@Suite struct ProjectCardTests {
    @Test func activeAndFinished() throws {
        let list = VStack(spacing: 12) {
            ProjectCardView(title: "Craigh na Dun Blanket", percent: 23, line: "Row 42 of 184 · 23%",
                            estimate: "Done around Nov 3", lastWorked: "Last worked yesterday", finished: false, preview: nil)
            ProjectCardView(title: "Craigh na Dun Blanket", percent: 100, line: "Finished",
                            estimate: nil, lastWorked: "Last worked Aug 30", finished: true, preview: nil)
        }
        .padding(16)
        .background(Color.ground.weave())
        #expect(try Snapshots.assert(list, named: "project-cards", size: CGSize(width: 390, height: 280)))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -quiet ... -only-testing:GraphghanTests/ProjectCardTests`
Expected: compile failure (`ProjectCardView` undefined).

- [ ] **Step 3: Write `ProjectCardView` and use it from `ProjectRow`**

`ios/Graphghan/Projects/ProjectCardView.swift`:

```swift
import SwiftUI

/// The project row as a card (spec §6.2). Stateless so it can be snapshotted; `ProjectRow` feeds it.
struct ProjectCardView: View {
    let title: String
    let percent: Double?
    let line: String
    let estimate: String?
    let lastWorked: String?
    let finished: Bool
    let preview: UIImage?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                PreviewFrame(image: preview)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(Font.Heather.heading).foregroundStyle(Color.ink).lineLimit(2)
                    if !finished, let percent {
                        ProgressView(value: percent, total: 100).tint(.heather)
                    }
                    Text(line).font(Font.Heather.caption).foregroundStyle(Color.ink2).monospacedDigit()
                    if let estimate { Text(estimate).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                    if let lastWorked { Text(lastWorked).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Font.Heather.label).foregroundStyle(Color.ink2).padding(.top, 4)
            }
        }
    }
}

/// 96 × 80 preview with the yarn hairline; a Panel placeholder until the image arrives.
struct PreviewFrame: View {
    let image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFill()
            } else {
                Color.panel.overlay(Image(systemName: "photo").foregroundStyle(Color.ink2))
            }
        }
        .frame(width: 96, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(YarnSurface.hairline, lineWidth: 1))
    }
}
```

Replace the body of `ios/Graphghan/Projects/ProjectRow.swift` with:

```swift
import SwiftUI
import GraphghanCore

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var sequence: WorkSequence?
    @State private var preview: UIImage?

    var body: some View {
        let summary = sequence.map { model.projects.summary(for: project, sequence: $0) }
        ProjectCardView(
            title: project.title,
            percent: summary?.percent,
            line: line(summary),
            estimate: sequence.flatMap { seq in
                project.isFinished ? nil : model.projects.estimatedFinish(for: project, sequence: seq).map { "Done around \($0.formatted(date: .abbreviated, time: .omitted))" }
            },
            lastWorked: project.lastWorked.map { "Last worked \($0.formatted(.relative(presentation: .named)))" },
            finished: project.isFinished,
            preview: preview)
        .task(id: project.chartID) { sequence = try? await model.projects.sequence(for: project) }
        .task { preview = await model.preview(for: project.patternID, sitePath: "patterns/\(project.patternID)/preview.png") }
    }

    private func line(_ summary: ProjectService.Summary?) -> String {
        guard let sequence, let summary else { return "" }
        return project.isFinished ? "Finished" : "Row \(project.cursor.row) of \(sequence.passes.count) · \(summary.percent.formatted())%"
    }
}
```

If `ProjectService.summary(for:sequence:)` returns a type not named `Summary`, use its actual name (`grep -n "func summary" Graphghan/Services/ProjectService.swift`).

- [ ] **Step 4: Restyle the Projects list**

In `ios/Graphghan/Projects/ProjectListView.swift` replace the `List(ordered) { ... }.listStyle(.plain)` block with:

```swift
                    List(ordered) { project in
                        NavigationLink(value: project.id) { ProjectRow(project: project) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
```

Wrap the `Group { ... }` in a `.background(Color.ground.weave().ignoresSafeArea())` and `.tint(.moss)`, and replace the `safeAreaInset` banner with:

```swift
            .safeAreaInset(edge: .top) {
                if let error = model.projects.lastError {
                    Banner(text: "Couldn't save your progress: \(error)", kind: .failure, action: .init(label: "Dismiss") { model.projects.lastError = nil })
                }
            }
```

The `ContentUnavailableView("No projects", ...)` stays; give it `.tint(.moss)` (inherited from the Group).

- [ ] **Step 5: Restyle the Patterns list**

In `ios/Graphghan/Patterns/LibraryView.swift`, the same three changes: list rows `listRowBackground(Color.clear)`, `listRowSeparator(.hidden)`, `listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))`, `.scrollContentBackground(.hidden)`; `.background(Color.ground.weave().ignoresSafeArea())` and `.tint(.moss)` on the Group; the top banner becomes:

```swift
                if let banner = model.libraryBanner {
                    Banner(text: banner, kind: .info, action: .init(label: "Retry") { Task { await model.loadLibrary(force: true) } })
                }
```

And `LibraryRow` becomes a card:

```swift
struct LibraryRow: View {
    @Environment(AppModel.self) private var model
    let entry: IndexEntry
    @State private var preview: UIImage?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                PreviewFrame(image: preview)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title).font(Font.Heather.heading).foregroundStyle(Color.ink).lineLimit(2)
                    if !entry.dedication.isEmpty { Text(entry.dedication).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                    Text("\(entry.sizeIn[0].formatted()) × \(entry.sizeIn[1].formatted()) in · \(entry.stitch) · \(entry.colors) colors")
                        .font(Font.Heather.caption).foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Font.Heather.label).foregroundStyle(Color.ink2).padding(.top, 4)
            }
        }
        .task(id: entry.preview) { preview = await model.preview(for: entry.slug, sitePath: entry.preview) }
    }
}
```

- [ ] **Step 6: Root chrome**

In `ios/Graphghan/RootView.swift` add after the `TabView` closing brace, before `.fullScreenCover`:

```swift
        .tint(.moss)
        .font(Font.Heather.body)
        .foregroundStyle(Color.ink)
```

- [ ] **Step 7: Build, run the test, and eyeball the simulator**

Run: `mise run test`
Expected: `project-cards.png` recorded then all tests pass (the Live Activity snapshots are untouched so far). Then `mise run build` and launch in the simulator (`xcrun simctl boot "iPhone 17"; open -a Simulator; xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/Graphghan.app; xcrun simctl launch booted com.tylervick.graphghan`): both tabs show cards on the stone weave, Literata large titles, Moss tab icons.

- [ ] **Step 8: Commit**

```bash
git add Graphghan/Projects/ProjectCardView.swift Graphghan/Projects/ProjectRow.swift Graphghan/Projects/ProjectListView.swift Graphghan/Patterns/LibraryView.swift Graphghan/RootView.swift Tests/ProjectCardTests.swift Tests/__Snapshots__/project-cards.png
git commit -m "feat(ios): Heather chrome on the Patterns and Projects lists"
```

---

### Task 5: Pattern detail, project detail, sheets, chart browser

**Files:**
- Create: `ios/Graphghan/Patterns/PatternDetailContent.swift`
- Modify: `ios/Graphghan/Patterns/PatternDetailView.swift`, `ios/Graphghan/Projects/ProjectDetailView.swift`, `ios/Graphghan/Patterns/StartProjectSheet.swift`, `ios/Graphghan/Patterns/ChartBrowserView.swift`
- Test: `ios/Tests/PatternDetailTests.swift`

**Interfaces:**
- Consumes: `Card`, `Chip`, `.primary`, tokens, `Font.Heather`, `YarnLabel.text(for:)`, `PatternManifest`, `Chart`, `ManifestChart`.
- Produces: `PatternDetailContent(manifest:chart:preview:onStart:onBrowse:)` where `onBrowse: (ManifestChart) -> Void`.

- [ ] **Step 1: Write the failing snapshot test**

`ios/Tests/PatternDetailTests.swift`:

```swift
import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct PatternDetailTests {
    @Test func content() throws {
        let manifest = TestManifest.make(chartID: "final-sc")
        let chart = try Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
        let view = PatternDetailContent(manifest: manifest, chart: chart, preview: nil, onStart: {}, onBrowse: { _ in })
            .background(Color.ground.weave())
        #expect(try Snapshots.assert(view, named: "pattern-detail", size: CGSize(width: 390, height: 760)))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -quiet ... -only-testing:GraphghanTests/PatternDetailTests`
Expected: compile failure.

- [ ] **Step 3: Write `PatternDetailContent`**

`ios/Graphghan/Patterns/PatternDetailContent.swift`:

```swift
import SwiftUI
import GraphghanCore

/// The pattern detail body (spec §6.7), stateless: `PatternDetailView` loads and hands over.
struct PatternDetailContent: View {
    let manifest: PatternManifest
    /// The default chart once loaded; until then the manifest's plain palette shows.
    let chart: Chart?
    let preview: UIImage?
    let onStart: () -> Void
    let onBrowse: (ManifestChart) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewImage
            VStack(alignment: .leading, spacing: 4) {
                Text(manifest.title).font(Font.Heather.title).foregroundStyle(Color.ink)
                if !manifest.dedication.isEmpty { Text("For \(manifest.dedication)").font(Font.Heather.body).foregroundStyle(Color.ink2) }
                if !manifest.quote.isEmpty { Text("“\(manifest.quote)”").font(Font.Heather.quote).foregroundStyle(Color.ink).padding(.top, 4) }
            }
            specs
            colors
            if let chart, !chart.document.instructions.isEmpty { instructions(chart) }
            charts
            Button("Start project", action: onStart).buttonStyle(.primary).disabled(manifest.charts.isEmpty)
        }
        .padding(16)
    }

    private var previewImage: some View {
        Group {
            if let preview { Image(uiImage: preview).resizable().interpolation(.none).scaledToFill() }
            else { Color.panel.overlay(Image(systemName: "photo").foregroundStyle(Color.ink2)) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
    }

    private var specs: some View {
        let d = manifest.defaultChart
        return Card(padding: 14) {
            VStack(spacing: 8) {
                specRow("Chart", d.map { "\($0.width) × \($0.height) stitches × rows" } ?? "—")
                specRow("Finished", d.map { "\($0.size.width.formatted()) × \($0.size.height.formatted()) \($0.size.unit)" } ?? "—")
                specRow("Stitch", d?.stitch ?? "—")
                specRow("Version", manifest.version)
            }
        }
    }

    private func specRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(Font.Heather.body).foregroundStyle(Color.ink2)
            Spacer()
            Text(value).font(Font.Heather.body).foregroundStyle(Color.ink).monospacedDigit()
        }
    }

    private var colors: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Colors").font(Font.Heather.heading).foregroundStyle(Color.ink)
                if let chart {
                    ForEach(chart.document.palette, id: \.code) { entry in
                        paletteRow(code: entry.code, name: entry.name, hex: entry.hex, note: YarnLabel.text(for: entry))
                    }
                } else {
                    ForEach(manifest.palette, id: \.code) { swatch in
                        paletteRow(code: swatch.code, name: swatch.name, hex: swatch.hex, note: nil)
                    }
                }
            }
        }
    }

    private func paletteRow(code: String, name: String, hex: String, note: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Chip(text: code, hex: hex)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Font.Heather.label).foregroundStyle(Color.ink)
                if let note { Text(note).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
            }
        }
    }

    private func instructions(_ chart: Chart) -> some View {
        ForEach(chart.document.instructions, id: \.title) { section in
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title).font(Font.Heather.heading).foregroundStyle(Color.ink)
                    ForEach(section.text.split(separator: "\n").map(String.init), id: \.self) { line in
                        Text("• \(line)").font(Font.Heather.body).foregroundStyle(Color.ink)
                    }
                }
            }
        }
    }

    private var charts: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Published charts").font(Font.Heather.heading).foregroundStyle(Color.ink)
                ForEach(manifest.charts) { chart in
                    Button { onBrowse(chart) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(chart.variant) · \(chart.gaugeKey)").font(Font.Heather.label).foregroundStyle(Color.ink)
                                Text("\(chart.size.width.formatted()) × \(chart.size.height.formatted()) \(chart.size.unit) · \(chart.height) rows · \(chart.stitches.formatted()) stitches")
                                    .font(Font.Heather.caption).foregroundStyle(Color.ink2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.ink2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Rewrite `PatternDetailView` around it**

Replace `ios/Graphghan/Patterns/PatternDetailView.swift` entirely (this removes the private `palette(_:)` and `ChartDetailsView`):

```swift
import SwiftUI
import GraphghanCore

struct PatternDetailView: View {
    @Environment(AppModel.self) private var model
    let entry: IndexEntry
    @State private var manifest: PatternManifest?
    @State private var chart: Chart?
    @State private var preview: UIImage?
    @State private var loadError: String?
    @State private var showStart = false
    @State private var browsing: ManifestChart?

    var body: some View {
        ScrollView {
            if let manifest {
                PatternDetailContent(manifest: manifest, chart: chart, preview: preview,
                                     onStart: { showStart = true }, onBrowse: { browsing = $0 })
            } else if let loadError {
                ContentUnavailableView("Couldn't load this pattern", systemImage: "wifi.slash", description: Text(loadError))
                    .padding(.top, 80)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(Color.ground.weave().ignoresSafeArea())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $browsing) { chart in
            if let manifest {
                ChartBrowserView(title: "\(manifest.title) · \(chart.key)", highlightRow: nil) {
                    try await model.browseChart(manifest: manifest, chart: chart)
                }
            }
        }
        .sheet(isPresented: $showStart) {
            if let manifest { StartProjectSheet(manifest: manifest) }
        }
        .task {
            preview = await model.preview(for: entry.slug, sitePath: entry.preview)
            do {
                let m = try await model.manifest(for: entry.slug, path: entry.manifest)
                manifest = m
                if let c = m.defaultChart { chart = try? await model.browseChart(manifest: m, chart: c) }
            } catch { loadError = "Connect to the internet to open a pattern for the first time." }
        }
    }
}
```

`ManifestChart` must be `Hashable` for `navigationDestination(item:)`; check `grep -n "struct ManifestChart" Packages/GraphghanCore/Sources/GraphghanCore/SiteModels.swift` and add `Hashable` to its conformances if it only has `Identifiable, Codable, Sendable` (its stored properties are all value types, so synthesis works). The core package tests must still pass: `mise run core-test`.

- [ ] **Step 5: Project detail, sheets, chart browser**

`ios/Graphghan/Projects/ProjectDetailView.swift`: keep the grouped `List`, and add after `.navigationBarTitleDisplayMode(.inline)`:

```swift
        .scrollContentBackground(.hidden)
        .background(Color.ground.weave().ignoresSafeArea())
        .listRowBackgroundPanel()
```

with this helper appended to `ios/Graphghan/UI/Card.swift`:

```swift
extension View {
    /// Grouped lists keep their sections; rows sit on Panel with a Line hairline instead of the system gray.
    func listRowBackgroundPanel() -> some View {
        environment(\.defaultMinListRowHeight, 44)
            .listRowBackground(Color.panel)
            .listSectionSeparatorTint(Color.line)
    }
}
```

Replace the `ProgressView(value: summary.percent, total: 100)` with `ProgressView(value: summary.percent, total: 100).tint(.heather)`, and the whole `safeAreaInset` block with:

```swift
        .safeAreaInset(edge: .top) {
            if let error = model.projects.lastError {
                Banner(text: "Couldn't save your progress: \(error)", kind: .failure, action: .init(label: "Dismiss") { model.projects.lastError = nil })
            }
        }
``` `StartProjectSheet.swift`: replace `Text(error).foregroundStyle(.red)` with `Text(error).foregroundStyle(Color.brick)`, and give the `Form` `.scrollContentBackground(.hidden).background(Color.ground.weave().ignoresSafeArea())`. `JumpToRowSheet.swift`: the `Form` gets `.scrollContentBackground(.hidden).background(Color.ground.weave().ignoresSafeArea())` as well. `ChartBrowserView.swift`: the highlight `Rectangle().stroke(Color.accentColor, lineWidth: 2)` becomes `Color.heather`, and the row numbers get `.foregroundStyle(Color.ink2)`; the ScrollView gets `.background(Color.panel)`.

- [ ] **Step 6: Run the tests and the app**

Run: `mise run core-test && mise run test`
Expected: `pattern-detail.png` recorded, then all pass. In the simulator: the pattern detail shows the preview, title, quote in italic Literata, specs and colors cards, chart list, and a Moss "Start project" pill; the project detail sits on the weave with Panel rows.

- [ ] **Step 7: Commit**

```bash
git add Graphghan/Patterns Graphghan/Projects/ProjectDetailView.swift Graphghan/UI/Card.swift Packages/GraphghanCore Tests/PatternDetailTests.swift Tests/__Snapshots__/pattern-detail.png
git commit -m "feat(ios): Heather pattern detail, project detail, sheets, and chart browser"
```

---

### Task 6: The Work screen

**Files:**
- Create: `ios/Graphghan/Work/OnDeckRule.swift`, `ios/Graphghan/Work/SwatchStack.swift`, `ios/Graphghan/Work/DoneField.swift`, `ios/Graphghan/Work/WorkScreen.swift`
- Modify: `ios/Graphghan/Work/WorkView.swift`, `ios/Graphghan/Work/RowStripView.swift`, `ios/Graphghan/Work/RunChipsView.swift`
- Test: `ios/Tests/OnDeckRuleTests.swift`, `ios/Tests/WorkScreenTests.swift`

**Interfaces:**
- Consumes: `Chart` (`palette`, `colorIndex(of:)`), `WorkSequence` (`pass(at:)`, `passes`), `Pass` (`label`, `runs`, `side`, `direction`), `Run` (`code`, `count`), `Cursor`, `WorkEngine.isFinished(_:in:)`, `Chip`, `YarnSurface`, tokens, `Font.Heather`.
- Produces: `OnDeck` (`text: String`, `hex: String`) and `OnDeckRule.onDeck(cursor:chart:sequence:) -> OnDeck?`; `WorkScreen(chart:sequence:cursor:onDone:onBack:onClose:onJump:onSelectRun:)`; `SwatchStack(chart:sequence:cursor:)`; `DoneField(finished:canGoBack:onDone:onBack:)`.

- [ ] **Step 1: Write the failing rule test**

`ios/Tests/OnDeckRuleTests.swift`:

```swift
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct OnDeckRuleTests {
    // two-letter-codes: Row 1 = Kb 3, Gd 7, G 2 ; Row 2 = Gd 7, G 2, Y 3
    static let chart = try! Chart.load(TestFixtures.data("two-letter-codes.chart.json"))
    static let seq = try! WorkSequence(chart: chart)
    static func name(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].name }
    static func hex(_ code: String) -> String { chart.palette[chart.colorIndex(of: code)!].hex }

    @Test func nextRunInRow() {
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 0), chart: Self.chart, sequence: Self.seq)
        #expect(d?.text == "then 7 \(Self.name("Gd"))")
        #expect(d?.hex == Self.hex("Gd"))
    }

    @Test func lastRunInRowNamesNextRowsColor() {
        let d = OnDeckRule.onDeck(cursor: Cursor(row: 1, run: 2), chart: Self.chart, sequence: Self.seq)
        #expect(d?.text == "next row starts in \(Self.name("Gd"))")
        #expect(d?.hex == Self.hex("Gd"))
    }

    @Test func lastRunOfPatternHasNothingOnDeck() {
        #expect(OnDeckRule.onDeck(cursor: Cursor(row: 2, run: 2), chart: Self.chart, sequence: Self.seq) == nil)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -quiet ... -only-testing:GraphghanTests/OnDeckRuleTests`
Expected: compile failure (`OnDeckRule` undefined).

- [ ] **Step 3: Write `OnDeckRule.swift`**

```swift
import GraphghanCore

/// What sits under the current swatch (spec §6.1): the next run, the next row's first color, or nothing.
struct OnDeck: Hashable {
    let text: String
    let hex: String
}

enum OnDeckRule {
    static func onDeck(cursor: Cursor, chart: Chart, sequence: WorkSequence) -> OnDeck? {
        guard let pass = sequence.pass(at: cursor.row) else { return nil }
        func entry(_ code: String) -> (name: String, hex: String) {
            let e = chart.palette[chart.colorIndex(of: code) ?? 0]
            return (e.name, e.hex)
        }
        if cursor.run + 1 < pass.runs.count {
            let next = pass.runs[cursor.run + 1]
            let e = entry(next.code)
            return OnDeck(text: "then \(next.count) \(e.name)", hex: e.hex)
        }
        if let nextPass = sequence.pass(at: cursor.row + 1), let first = nextPass.runs.first {
            let e = entry(first.code)
            return OnDeck(text: "next row starts in \(e.name)", hex: e.hex)
        }
        return nil
    }
}
```

- [ ] **Step 4: Run the rule test to verify it passes**

Run the same command. Expected: 3 pass.

- [ ] **Step 5: Write the failing screen snapshots**

`ios/Tests/WorkScreenTests.swift`:

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

    private func screen(_ cursor: Cursor) -> some View {
        WorkScreen(chart: Self.chart, sequence: Self.seq, cursor: cursor, onDone: {}, onBack: {}, onClose: {}, onJump: {}, onSelectRun: { _ in })
    }

    @Test func midRow() throws {
        #expect(try Snapshots.assert(screen(Cursor(row: 42, run: 8)), named: "work-mid-row", size: Self.phone))
    }

    @Test func lastRunInRow() throws {
        let runs = Self.seq.pass(at: 42)!.runs.count
        #expect(try Snapshots.assert(screen(Cursor(row: 42, run: runs - 1)), named: "work-last-in-row", size: Self.phone))
    }

    @Test func finished() throws {
        let end = Cursor(row: Self.seq.passes.count, run: Self.seq.passes.last!.runs.count)
        #expect(try Snapshots.assert(screen(end), named: "work-finished", size: Self.phone))
    }

    /// At the largest accessibility size the count may cap; nothing may clip or overlap the Done field.
    @Test func accessibilitySize() throws {
        let view = screen(Cursor(row: 42, run: 8)).environment(\.dynamicTypeSize, .accessibility5)
        #expect(try Snapshots.assert(view, named: "work-mid-row-ax5", size: Self.phone))
    }
}
```

- [ ] **Step 6: Run them to verify they fail**

Run: `xcodebuild test -quiet ... -only-testing:GraphghanTests/WorkScreenTests`
Expected: compile failure (`WorkScreen` undefined).

- [ ] **Step 7: Restyle the strip and chips**

`ios/Graphghan/Work/RowStripView.swift`: change the two `.color(.accentColor)` to `.color(.heather)`, and the dimming fill on rows other than the current one from `.color(.black.opacity(0.35))` to `.color(.black.opacity(0.45))`. Wrap the Canvas so the strip sits in its own panel:

```swift
        .frame(height: 56)
        .padding(8)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.line, lineWidth: 1))
        .accessibilityHidden(true)
```

`ios/Graphghan/Work/RunChipsView.swift`: replace the chip label with the shared `Chip`:

```swift
                        Button { onSelect(i) } label: {
                            Chip(text: "\(run.count) \(run.code)", hex: hex, state: i < cursor.run ? .done : i == cursor.run ? .current : .upcoming)
                        }
```

and change `.padding(.horizontal)` on the HStack to `.padding(.horizontal, 4)` (the card supplies the inset). Keep the `ScrollViewReader`, `.id(i)`, and accessibility label as they are.

- [ ] **Step 8: Write `SwatchStack.swift`**

```swift
import SwiftUI
import GraphghanCore

/// The current run on its yarn color with the next run on deck beneath it (spec §6.1).
struct SwatchStack: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let pass = sequence.pass(at: cursor.row), cursor.run < pass.runs.count {
            let run = pass.runs[cursor.run]
            let entry = chart.palette[chart.colorIndex(of: run.code) ?? 0]
            let onDeck = OnDeckRule.onDeck(cursor: cursor, chart: chart, sequence: sequence)
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(run.count)").font(Font.Heather.count).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        Text(run.code).font(Font.Heather.code).lineLimit(1)
                    }
                    Text(entry.name).font(Font.Heather.heading).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 16)
                .yarnSurface(entry.hex, radius: 16)
                .zIndex(1)
                .id(cursor)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(run.count) \(entry.name)")
                if let onDeck {
                    Text(onDeck.text)
                        .font(Font.Heather.label)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)
                        .padding(.bottom, 10)
                        .yarnSurface(onDeck.hex, shape: UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous))
                        .padding(.top, -12)
                        .id(onDeck)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .clipped()
        }
    }
}
```

- [ ] **Step 9: Write `DoneField.swift`**

```swift
import SwiftUI

/// Everything below the card: the Back rail on the leading edge, Done (or Close) filling the rest (spec §6.1).
struct DoneField: View {
    let finished: Bool
    let canGoBack: Bool
    let onDone: () -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if !finished {
                Button(action: onBack) {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 26, weight: .semibold))
                        Text("Back").font(Font.Heather.label)
                    }
                    .padding(.bottom, 40)
                    .frame(width: 84, maxHeight: .infinity)
                    .foregroundStyle(Color.cream.opacity(canGoBack ? 0.85 : 0.35))
                    .background(Color.mossDeep, in: UnevenRoundedRectangle(topTrailingRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .accessibilityLabel("Back one run")
            }
            Button(action: onDone) {
                Text(finished ? "Close" : "Done")
                    .font(Font.Heather.done)
                    .foregroundStyle(Color.cream)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 10: Write `WorkScreen.swift`**

```swift
import SwiftUI
import GraphghanCore

/// The Work screen without the model (spec §6.1): Moss is the ground and the Done target; the work
/// floats on one stone card. `WorkView` owns state and haptics and feeds this.
struct WorkScreen: View {
    let chart: Chart
    let sequence: WorkSequence
    let cursor: Cursor
    let onDone: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let onJump: () -> Void
    let onSelectRun: (Int) -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var finished: Bool { WorkEngine.isFinished(cursor, in: sequence) }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                HStack(spacing: 0) {
                    VStack(spacing: 14) { header; card }.frame(maxWidth: .infinity)
                    field.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 14) { header; card; field }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.moss.weave(.cream, opacity: 0.05).ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.cream.opacity(0.75))
            .accessibilityLabel("Close")
            Spacer()
            VStack(spacing: 4) {
                if let pass = sequence.pass(at: cursor.row) {
                    (Text("\(pass.label) ") + Text("of").fontWeight(.medium).foregroundStyle(Color.cream.opacity(0.7)) + Text(" \(sequence.passes.count)"))
                        .font(Font.Heather.rowNumber).monospacedDigit()
                        .onLongPressGesture(perform: onJump)
                        .accessibilityHint("Long press to jump to a row")
                        .accessibilityAction(named: "Jump to row", onJump)
                    Text(finished ? "Every row worked" : sideText(pass)).font(Font.Heather.caption).foregroundStyle(Color.cream.opacity(0.75))
                }
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(Color.cream)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var card: some View {
        VStack(spacing: 12) {
            RowStripView(chart: chart, sequence: sequence, cursor: cursor)
            if finished {
                VStack(spacing: 8) {
                    Text("Finished").font(Font.Heather.title)
                    Text("Every row is done. Block it, weave in the ends, and take a picture.")
                        .font(Font.Heather.body).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .yarnSurface("#F2E8D5", radius: 16)
            } else {
                RunChipsView(chart: chart, pass: sequence.pass(at: cursor.row)!, cursor: cursor, onSelect: onSelectRun)
                SwatchStack(chart: chart, sequence: sequence, cursor: cursor)
            }
        }
        .padding(12)
        .background(Color.ground.weave().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        .padding(.horizontal, 12)
        .foregroundStyle(Color.ink)
        .contentShape(Rectangle())
        .onTapGesture {}  // the card swallows taps: nothing inside advances by accident
    }

    private var field: some View {
        DoneField(finished: finished, canGoBack: cursor != .start, onDone: finished ? onClose : onDone, onBack: onBack)
            .frame(maxHeight: .infinity)
    }

    private func sideText(_ pass: Pass) -> String {
        let dir = pass.direction.map { $0 == .ltr ? "read left to right" : "read right to left" } ?? "read direction not specified"
        guard let side = pass.side else { return dir }
        return "\(side == .ws ? "Wrong side" : "Right side") · \(dir)"
    }
}
```

- [ ] **Step 11: Rewrite `WorkView` to use it**

Replace the `content(chart:sequence:pass:)` function and `currentRun`, `nextText`, `sideText`, `colorName` in `ios/Graphghan/Work/WorkView.swift` with:

```swift
    @ViewBuilder
    private func content(chart: Chart, sequence: WorkSequence, pass: Pass) -> some View {
        WorkScreen(chart: chart, sequence: sequence, cursor: cursor,
                   onDone: { perform(.advance, sequence: sequence) },
                   onBack: { perform(.back, sequence: sequence) },
                   onClose: { dismiss() },
                   onJump: { showJump = true },
                   onSelectRun: { run in perform(.jump(row: cursor.row, run: run), sequence: sequence) })
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                if let saveError = model.projects.lastError {
                    Banner(text: "Couldn't save your progress: \(saveError)", kind: .failure, action: .init(label: "Dismiss") { model.projects.lastError = nil })
                }
                if let hint = model.liveActivity.settingsHint {
                    Banner(text: hint, kind: .info, action: .init(label: "Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        model.liveActivity.dismissHint()
                    })
                }
            }
            .padding(.top, 60)
        }
        .gesture(
            DragGesture(minimumDistance: 60).onEnded { value in
                if value.translation.width > 80, abs(value.translation.height) < 80 { perform(.back, sequence: sequence) }
            }
        )
        .sheet(isPresented: $showJump) {
            JumpToRowSheet(rowCount: sequence.passes.count, current: cursor.row) { row in perform(.jump(row: row), sequence: sequence) }
        }
    }
```

and in `perform(_:sequence:)` wrap the cursor assignment so the swatch animates:

```swift
        withAnimation(.spring(duration: 0.25)) { cursor = step.cursor }
```

The `Body` `if let chart, let sequence, let pass = sequence.pass(at: cursor.row)` guard stays. Delete the now-unused `body` pieces (`Text("Finished")…`, the `Button { perform(.advance…) }`), and remove `import` lines only if unused.

- [ ] **Step 12: Run the tests to verify they pass**

Run: `mise run test`
Expected: four Work snapshots recorded on the first run, then all green. Inspect each PNG against the canvas: `work-mid-row.png` shows the green weave, the stone card with strip, chips (done dimmed, current ringed), the cream "51 C Cream" swatch with a charcoal "then 4 Charcoal" bar tucked beneath, and a Done field with the Back rail; `work-last-in-row.png` reads "next row starts in …"; `work-finished.png` shows the cream Finished panel and "Close"; `work-mid-row-ax5.png` shows nothing overlapping the field.

- [ ] **Step 13: Try it in the simulator**

`mise run build`, install and launch as in Task 4, open a project, tap Work: tapping the green advances with the swatch sliding; tapping the card does nothing; the rail steps back; rotate to landscape: card on the left, field on the right; Settings › Accessibility › Motion › Reduce Motion on: the swatch crossfades.

- [ ] **Step 14: Commit**

```bash
git add Graphghan/Work Tests/OnDeckRuleTests.swift Tests/WorkScreenTests.swift Tests/__Snapshots__/work-*.png
git commit -m "feat(ios): the Work screen with Done as the ground and the next run on deck"
```

---

### Task 7: Live Activity in the new look

**Files:**
- Modify: `ios/Shared/WorkActivityViews.swift`
- Test: `ios/Tests/WorkActivityViewsTests.swift` (re-record all nine references)

**Interfaces:**
- Consumes: `Color.moss`, `.cream`, `YarnSurface` (both in `Shared`, compiled into the widget), system fonts only.
- Produces: unchanged view names and initializers.

- [ ] **Step 1: Confirm the current references still pass**

Run: `xcodebuild test -quiet ... -only-testing:GraphghanTests/WorkActivityViewsTests`
Expected: all pass (nothing has touched these views yet; this proves the baseline before the restyle).

- [ ] **Step 2: Restyle `WorkActivityViews.swift`**

Apply these edits (spec §6.8):

`RunSwatch`:

```swift
        Text("\(count)")
            .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .frame(minWidth: size * 1.3, minHeight: size)
            .padding(.horizontal, 6)
            .yarnSurface(hex, radius: size * 0.22)
            .accessibilityLabel("\(count) \(info.swatch(for: code)?.name ?? code)")
```

`RunRow` name and next line:

```swift
                    Text(info.swatch(for: code)?.name ?? code).font(.system(.title3, design: .serif).weight(.semibold)).lineLimit(1)
                    Text(nextText).font(.footnote).foregroundStyle(Color.cream.opacity(0.75)).lineLimit(1)
```

`RunButtons`: the Back button gets `.buttonStyle(.bordered).tint(Color.cream.opacity(0.7))` and `.clipShape(Capsule())`; the Done button `.buttonStyle(.borderedProminent).tint(.moss).clipShape(Capsule())`, and `doneFont` becomes `.system(.title3, design: .default).weight(.bold)` on the lock screen and `.body.bold()` on the island.

`WorkLockScreenView` and `WorkExpandedCenterView` headers: title `.font(.system(.headline, design: .serif).weight(.semibold))`; "Row … of …" `.font(.subheadline.bold()).monospacedDigit().foregroundStyle(Color.cream.opacity(0.75))`; "Finished" `.font(.system(.title2, design: .serif).weight(.semibold))`. The lock screen's `.foregroundStyle(.white)` becomes `.foregroundStyle(Color.cream)`. Compact and minimal views are unchanged apart from `RunSwatch`.

- [ ] **Step 3: Record, then compare**

Run once in record mode, then once in compare mode:

```bash
TEST_RUNNER_GRAPHGHAN_SNAPSHOTS=record xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -only-testing:GraphghanTests/WorkActivityViewsTests
xcodebuild test -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData -only-testing:GraphghanTests/WorkActivityViewsTests
```

Expected: the first run overwrites the nine lock-screen, island, and minimal PNGs (the three render-mode tests PR #24 added pass their own environment and are unaffected); the second run passes. `git status` shows exactly nine modified PNGs. Inspect `lock-midway.png`: cream serif title, the swatch with its hairline, a capsule Back and a Moss Done. Confirm the card is still inside Apple's 160pt budget (the layout heights did not change: 44pt swatch, 40pt buttons, 12pt padding).

- [ ] **Step 4: Widget target builds**

Run: `xcodebuild build -quiet -project Graphghan.xcodeproj -scheme Graphghan -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData`
Expected: succeeds (the widget links `Shared/Theme.swift`, `YarnSurface.swift`, and the token catalog).

- [ ] **Step 5: Commit**

```bash
git add Shared/WorkActivityViews.swift Tests/__Snapshots__
git commit -m "feat(ios): Live Activity in Heather colors and system faces"
```

---

### Task 8: App icon

**Files:**
- Create: `ios/Scripts/make_icon.py`, `ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
- Modify: `ios/Assets.xcassets/AppIcon.appiconset/Contents.json`, `ios/mise.toml`

**Interfaces:**
- Produces: `python ios/Scripts/make_icon.py [--out PATH] [--size N]` writing a PNG; the `mise run icon` task in `ios/`.

- [ ] **Step 1: Write the script**

`ios/Scripts/make_icon.py`:

```python
"""The app icon (spec §7): moss sky with the weave, a gold moon, the hill band, and a crocheted
chain along the horizon. Geometry is in fractions of the side so the PWA icon can share it later."""
import argparse
from PIL import Image, ImageDraw

MOSS, MOSS_DEEP, CREAM, GOLD = (30, 77, 58), (22, 59, 45), (244, 245, 240), (217, 162, 27)


def polyline(draw, points, fill, width):
    """A stroked path with round joins and caps (Pillow's line() has neither)."""
    draw.line(points, fill=fill, width=width, joint="curve")
    r = width / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def make_icon(size: int) -> Image.Image:
    s = size / 100  # one percent
    img = Image.new("RGB", (size, size), MOSS)
    # the weave: hairlines at 135°, 2.8% pitch, 5% cream
    weave = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    wd = ImageDraw.Draw(weave)
    pitch = int(2.8 * s * 2 ** 0.5)
    for x in range(-size, size, max(1, pitch)):
        wd.line([(x, size), (x + size, 0)], fill=(*CREAM, 13), width=max(1, int(0.6 * s)))
    img.paste(Image.alpha_composite(img.convert("RGBA"), weave).convert("RGB"))
    d = ImageDraw.Draw(img)
    # hill band from 62% down, then the moon
    d.rectangle([0, 62 * s, size, size], fill=MOSS_DEEP)
    d.ellipse([(74 - 9) * s, (30 - 9) * s, (74 + 9) * s, (30 + 9) * s], fill=GOLD)
    # eight chevrons along the horizon, tips leading (the chain travels right), halo in the hill color
    n, step, y = 8, 9.5, 62
    x0 = 50 - step * (n - 1) / 2
    for i in range(n):
        cx = x0 + step * i
        pts = [((cx + 9.5) * s, (y - 8.5) * s), ((cx - 3.5) * s, y * s), ((cx + 9.5) * s, (y + 8.5) * s)]
        polyline(d, pts, MOSS_DEEP, int(10 * s))
        polyline(d, pts, CREAM, int(6 * s))
    return img


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="Assets.xcassets/AppIcon.appiconset/icon-1024.png")
    ap.add_argument("--size", type=int, default=1024)
    a = ap.parse_args()
    make_icon(a.size).save(a.out)
    print("wrote", a.out)
```

- [ ] **Step 2: Add the task and the icon set entry**

`ios/mise.toml`, append after the `ci-test` task PR #24 added:

```toml
[tasks.icon]
description = "Regenerate the app icon PNG from Scripts/make_icon.py"
run = "uv run --project .. python Scripts/make_icon.py"
```

`ios/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images": [ { "filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" } ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 3: Generate and look**

Run from `ios/`: `mise run icon && open Assets.xcassets/AppIcon.appiconset/icon-1024.png`
Expected: a 1024 square, moss sky with a faint weave, gold moon upper right, darker hill from 62% down, eight cream chevrons along the horizon reading as a chain. Also render at 58 (`uv run --project .. python Scripts/make_icon.py --size 58 --out /tmp/icon-58.png`) and confirm the chain still reads.

- [ ] **Step 4: Build and check the home screen**

Run: `mise run generate && mise run build`, install to the simulator, and confirm the icon shows on the home screen (the simulator applies the mask).

- [ ] **Step 5: Commit**

```bash
git add Scripts/make_icon.py mise.toml Assets.xcassets/AppIcon.appiconset
git commit -m "feat(ios): app icon, the chain on the horizon"
```

---

### Task 9: Docs, full verification, PR

**Files:**
- Modify: `ios/README.md`, `ios/docs/qa.md`

- [ ] **Step 1: README**

In `ios/README.md`, under "Layout", change the `UI/` bullet to:

```markdown
  - `UI/` — shared components (card, chip, banner, button styles), the type ramp (`Typography.swift`), preview images
- `Shared/` — compiles into the app and the widget: the color tokens (`Tokens.xcassets`, `Theme.swift`), yarn surfaces, Live Activity views and intents
- `Fonts/` — Literata, Atkinson Hyperlegible, Nunito (all OFL), registered in `project.yml`
- `Scripts/make_icon.py` — the app icon; `mise run icon` regenerates it
```

and add a section before "## Device build" (PR #24 added that section and "## CI and releases"):

```markdown
## Design language

The spec is `../docs/superpowers/specs/2026-09-11-ios-design-language-design.md` ("Heather"). Colors are the
named sets in `Shared/Tokens.xcassets` and nothing else; fonts are `Font.Heather.*`; every yarn-colored
surface goes through `YarnSurface`. Screen snapshots live under `Tests/__Snapshots__` (delete a PNG to
re-record it on the iPhone 17 simulator). Dark values are declared in the catalog but not yet tuned.
```

- [ ] **Step 2: QA checklist**

In `ios/docs/qa.md`, add before "## Offline":

```markdown
## Looks right
- [ ] Home screen: the icon shows the moon, hill, and chain; it reads at the settings size too.
- [ ] Patterns and Projects: cards on the stone weave, Literata titles, Moss tab tint, no system blue anywhere.
- [ ] Pattern detail: quote in italic, palette chips with a visible edge on the cream chip, a Moss "Start project" pill.
- [ ] Work: green ground, the card does not advance when tapped, the on-deck bar shows the next run in its color, "next row starts in …" on the last run, Back rail steps back, Done slides the swatch.
- [ ] Work at Settings › Accessibility › Larger Text (max): nothing overlaps the Done field.
- [ ] Reduce Motion on: the swatch crossfades instead of sliding.
- [ ] Lock screen activity: cream serif title, the swatch with its edge, capsule Back, Moss Done.
```

- [ ] **Step 3: Full verification**

Run from `ios/`: `mise run core-test && mise run test`
Expected: everything passes with no new recordings. Then from the repo root: `mise run check` (ruff and pytest still pass; the icon script is under `ios/` so ruff should either skip it or pass; fix any lint it reports).

- [ ] **Step 4: Commit and open the PR**

```bash
git add README.md docs/qa.md
git commit -m "docs(ios): design language notes and the looks-right checklist"
git push -u origin tylervick/style
gh pr create --title "iOS design language: Heather" --body "$(cat <<'EOF'
Applies the Heather design language (spec: docs/superpowers/specs/2026-09-11-ios-design-language-design.md) to every screen, the Live Activity, and the app icon. Light theme only; dark tokens declared, untuned.

- Shared color tokens in `Shared/Tokens.xcassets`, fonts under `Fonts/`, type ramp in `Typography.swift`
- Card, chip, banner, button styles; every yarn-colored surface through `YarnSurface`
- Work screen: Done is the ground, the work floats on one card, the next run sits on deck
- Live Activity in the new colors with system faces; icon generated by `Scripts/make_icon.py`
- Snapshots for the components, project cards, pattern detail, four Work states, and the re-recorded activity views

Canvas: https://claude.ai/code/artifact/ab079b20-bc2f-4deb-a529-08175ee12c85

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01WCvaK6fT94CWMp1n6zGXFW
EOF
)"
```

Every commit message in this plan also ends with:

```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WCvaK6fT94CWMp1n6zGXFW
```

import Foundation
import Testing

/// Guards the tokens rule (spec §3/§5.2): no raw hex, no `Color(red:`/`Color(white:`, no
/// `.accentColor`, no system `.secondary`/`.tertiary`/`.white`/`.black` foreground, no raw
/// `GraphicsContext.Shading.color(.black)`/`.color(.white)` in a `Canvas`, and no system
/// text-style or `.font(.system(` font outside the shared token files. Everything under
/// `Graphghan/` and `Shared/` goes through `Color.*` (Shared/Theme.swift) and `Font.Heather.*`
/// (Graphghan/UI/Typography.swift) instead.
@Suite struct DesignRulesTests {
    /// Resolves `ios/` from this file's own path (see Tests/TestSupport.swift:7-12): delete the
    /// file name, then the `Tests` directory.
    private static let iosDirectory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }()

    /// Directories under `ios/` this test enumerates. Not `Tests/` itself (this file's own
    /// strings would otherwise match the very patterns it looks for) and not `GraphghanWidgets/`
    /// or the `GraphghanCore` package, which the brief doesn't ask this guard to cover.
    private static let scannedRoots = ["Graphghan", "Shared"]

    /// Skip the whole file: these are the token/typography definitions themselves.
    private static let fullyAllowlisted: Set<String> = [
        "Shared/Theme.swift",
        "Shared/YarnSurface.swift",
        "Shared/HexColor.swift",
        "Graphghan/UI/Typography.swift",
    ]
    /// Skip both font rules only: the Live Activity views intentionally match the system's own
    /// lock screen / Dynamic Island type instead of the Heather ramp.
    private static let fontRulesAllowlisted: Set<String> = ["Shared/WorkActivityViews.swift"]
    /// Skip the `.font(.system(` rule only: 9pt axis numerals on the chart browser.
    private static let systemFontRuleAllowlisted: Set<String> = ["Graphghan/Patterns/ChartBrowserView.swift"]

    // Built from pieces (concatenation, not a literal) so this file's own description of the
    // rules never itself matches what it is checking for.
    private static let hexLiteral = try! NSRegularExpression(pattern: "\"" + "#[0-9A-Fa-f]{6}" + "\"")
    private static let systemTextStyleFont = try! NSRegularExpression(
        pattern: "\\" + ".font\\(\\" + ".(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)\\b"
    )

    private struct Violation: CustomStringConvertible, Sendable {
        let path: String
        let line: Int
        let text: String
        var description: String { "\(path):\(line): \(text.trimmingCharacters(in: .whitespaces))" }
    }

    @Test func noRawColorsOrSystemFontsOutsideTheTokens() throws {
        var violations: [Violation] = []
        for path in try Self.swiftFiles() {
            if Self.fullyAllowlisted.contains(path) { continue }
            let url = Self.iosDirectory.appendingPathComponent(path)
            let text = try String(contentsOf: url, encoding: .utf8)
            for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
                Self.check(line: line, path: path, lineNumber: offset + 1, into: &violations)
            }
        }
        let message = Comment(rawValue: "\n" + violations.map(\.description).joined(separator: "\n"))
        #expect(violations.isEmpty, message)
    }

    private static func check(line: String, path: String, lineNumber: Int, into violations: inout [Violation]) {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        var flagged = false

        if hexLiteral.firstMatch(in: line, range: range) != nil { flagged = true }
        if line.contains("Color(red:") || line.contains("Color(white:") { flagged = true }
        if line.contains(".accentColor") { flagged = true }
        for token in ["secondary", "tertiary", "white", "black"] {
            if line.contains("foregroundStyle(." + token + ")") { flagged = true }
        }
        // GraphicsContext.Shading.color(_:), a Canvas fill/stroke, not a SwiftUI foregroundStyle.
        for token in ["black", "white"] {
            if line.contains(".color(." + token) { flagged = true }
        }
        if !fontRulesAllowlisted.contains(path) {
            if systemTextStyleFont.firstMatch(in: line, range: range) != nil { flagged = true }
        }
        if !fontRulesAllowlisted.contains(path), !systemFontRuleAllowlisted.contains(path) {
            if line.contains(".font(.system(") && !line.contains("Image(systemName:") { flagged = true }
        }

        if flagged { violations.append(Violation(path: path, line: lineNumber, text: line)) }
    }

    private static func swiftFiles() throws -> [String] {
        var results: [String] = []
        for root in scannedRoots {
            let rootURL = iosDirectory.appendingPathComponent(root, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                let relative = fileURL.path.replacingOccurrences(of: iosDirectory.path + "/", with: "")
                results.append(relative)
            }
        }
        return results.sorted()
    }
}

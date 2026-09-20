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
        public struct Over: Sendable, Equatable {
            public let value: Double
            public let unit: String
        }
        public var stitches: Double
        public var rows: Double
        public var over: Over
        public var hook: String? = nil
        public var yarnWeight: String? = nil
        public var stitchName: String? = nil
        /// The turning chain the rows print ("ch 1, turn"), nil when the rows print none.
        public var chain: Int? = nil
    }
    public struct FinishedSize: Sendable, Equatable {
        public let width: Double
        public let height: Double
        public let unit: String
    }
    public struct KeyEntry: Sendable, Equatable {
        public let code: String
        public let name: String
        public let hex: String
        public let yarnNote: String?
    }
    public struct Run: Sendable, Equatable {
        public let code: String
        public let count: Int
    }
    public struct WrittenRow: Sendable, Equatable {
        public let row: Int
        public let side: String
        public let page: Int
        public let runs: [Run]
        public let total: Int
    }

    static let keyTitle = "Key"
    static let rowsTitle = "Written rows"
    static let metaRe = try! NSRegularExpression(pattern: #"^(?:(.+?) - )?(?:([A-Za-z0-9.+-]+) - )?version (\S+)$"#)
    static let gaugeRe = try! NSRegularExpression(pattern: #"^Gauge: ([\d.]+) sts and ([\d.]+) rows = ([\d.]+) (in|cm)(?: \((.*)\))?$"#)
    static let sizeRe = try! NSRegularExpression(pattern: #"^Finished size: ([\d.]+) x ([\d.]+) (in|cm)$"#)
    static let keyRe = try! NSRegularExpression(pattern: #"^([A-Za-z]{1,3}) +(.+?) +(#[0-9a-fA-F]{6})(?: +(.*))?$"#)
    static let headerRe = try! NSRegularExpression(pattern: #"^Chart (\d+) of (\d+): columns (\d+)-(\d+) of (\d+), rows (\d+)-(\d+) of (\d+)"#)
    static let rowHeadRe = try! NSRegularExpression(pattern: #"^Row \d+ \((?:RS|WS)\):"#)
    static let rowRe = try! NSRegularExpression(pattern: #"^Row (\d+) \((RS|WS)\): (?:ch (\d+), turn, |turn, )?(.*?) ?\((\d+) sts\)$"#)
    static let runRe = try! NSRegularExpression(pattern: #"^(\d+) ([A-Za-z]{1,3})$"#)

    /// A page's lines, trimmed; `\r\n`, `\n` and `\r` all end a line (PDFKit and pdfium differ).
    static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The capture groups of the first match, nil for no match; a group that did not take part is nil.
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
        var width: Int? = nil
        var height: Int? = nil
        for text in pageTexts {
            if let g = groups(headerRe, lines(text).first ?? ""), let w = Int(g[4] ?? ""), let h = Int(g[7] ?? "") {
                width = w
                height = h
            }
        }
        guard let width, let height else { throw OwnPDFError.noChartHeader }
        let (rows, chain) = try writtenRows(pageTexts, title: title)
        if let chain, gauge != nil { gauge?.chain = chain }
        if pattern.title.isEmpty { pattern.title = title }
        guard rows.count == height, rows.enumerated().allSatisfy({ $0.element.row == $0.offset + 1 }) else {
            throw OwnPDFError.rowsDoNotMatch("\(rows.count) written rows for a chart of \(height)")
        }
        if let bad = rows.first(where: { $0.total != width || $0.runs.reduce(0, { $0 + $1.count }) != width }) {
            throw OwnPDFError.rowsDoNotMatch("row \(bad.row) does not sum to \(width)")
        }
        return OwnPDFReading(pattern: pattern, gauge: gauge, finishedSize: size, palette: palette, width: width, height: height, rows: rows)
    }

    static func number(_ s: String?) -> Double? { s.flatMap(Double.init) }

    /// pattern, gauge and finished size from the cover page's text.
    static func cover(_ text: String, title: String) -> (PatternInfo, Gauge?, FinishedSize?) {
        let l = lines(text).filter { !$0.isEmpty }
        var pattern = PatternInfo(title: title)
        var gauge: Gauge? = nil
        var hook: String? = nil
        var yarn: String? = nil
        var size: FinishedSize? = nil
        var i = (l.first == title) ? 1 : 0
        // dedication, quote and the author line sit between the title and the Materials heading
        while i < l.count, l[i] != "Materials" {
            let ln = l[i]
            if let g = groups(metaRe, ln), g[0] != nil || g[1] != nil || ln.contains("version") {
                pattern.author = g[0]
                pattern.license = g[1]
                pattern.version = g[2] ?? pattern.version
            } else if ln.hasPrefix("\""), ln.hasSuffix("\""), ln.count >= 2 {
                pattern.quote = String(ln.dropFirst().dropLast())
            } else if pattern.dedication == nil {
                pattern.dedication = ln
            }
            i += 1
        }
        for ln in l[i...] {
            if ln.hasPrefix("Yarn: ") {
                yarn = String(ln.dropFirst(6))
            } else if ln.hasPrefix("Hook: ") {
                hook = String(ln.dropFirst(6))
            } else if let g = groups(gaugeRe, ln), let st = number(g[0]), let rows = number(g[1]), let over = number(g[2]), let unit = g[3] {
                gauge = Gauge(stitches: st, rows: rows, over: Over(value: over, unit: unit))
                for d in (g[4] ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !d.isEmpty {
                    if d.hasSuffix(" terms") { pattern.terms = String(d.dropLast(6)) } else { gauge?.stitchName = d }
                }
            } else if let g = groups(sizeRe, ln), let w = number(g[0]), let h = number(g[1]), let unit = g[2] {
                size = FinishedSize(width: w, height: h, unit: unit)
            } else if ln == "Colours" {
                break
            }
        }
        gauge?.hook = hook
        gauge?.yarnWeight = yarn
        return (pattern, gauge, size)
    }

    typealias Over = Gauge.Over

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

    static let rowHeadInsideRe = try! NSRegularExpression(pattern: #"\s+(?=Row \d+ \((?:RS|WS)\):)"#)

    /// Written rows from the rows pages: wrapped lines rejoined, the running footer removed
    /// wherever PDFKit put it (it joins the footer's title to the last line of a column and the
    /// page number to the last line of the page), in page order.
    static func writtenRows(_ texts: [String], title: String) throws -> ([WrittenRow], Int?) {
        let footer = try NSRegularExpression(
            pattern: #"(?:\s*(?:"# + NSRegularExpression.escapedPattern(for: title) + #"|Page \d+))+\s*$"#)
        var rows: [WrittenRow] = []
        var chain: Int? = nil
        var started = false
        for (index, text) in texts.enumerated() {
            let page = index + 1
            var l = lines(text)
            if !started {
                guard l.first == rowsTitle else { continue }
                started = true
                l = Array(l.dropFirst())
            } else if !(l.first ?? "").hasPrefix("Row ") {
                break  // a page after the rows that is not rows
            }
            var joined: [String] = []
            for raw in l where !raw.isEmpty {
                // Cut a line wherever another row head begins inside it, then drop footer fragments.
                let pieces = rowHeadInsideRe.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "\n")
                    .split(separator: "\n").map { String($0) }
                for piece in pieces {
                    var ln = footer.stringByReplacingMatches(in: piece, range: NSRange(piece.startIndex..., in: piece), withTemplate: "")
                    ln = ln.trimmingCharacters(in: .whitespaces)
                    if ln.isEmpty { continue }
                    if rowHeadRe.firstMatch(in: ln, range: NSRange(ln.startIndex..., in: ln)) != nil {
                        joined.append(ln)
                    } else if !joined.isEmpty {
                        joined[joined.count - 1] += " " + ln
                    }
                }
            }
            for ln in joined {
                guard let g = groups(rowRe, ln), let row = Int(g[0] ?? ""), let side = g[1], let total = Int(g[4] ?? "") else {
                    throw OwnPDFError.badRow(page: page, text: ln)
                }
                var runs: [Run] = []
                for part in (g[3] ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                    guard let r = groups(runRe, part), let n = Int(r[0] ?? ""), let code = r[1] else {
                        throw OwnPDFError.badRow(page: page, text: ln)
                    }
                    runs.append(Run(code: code, count: n))
                }
                rows.append(WrittenRow(row: row, side: side, page: page, runs: runs, total: total))
                if chain == nil, let c = g[2], let n = Int(c) { chain = n }
            }
        }
        return (rows, chain)
    }
}

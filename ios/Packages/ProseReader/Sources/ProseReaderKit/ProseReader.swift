// The reading loop: which model, how the text is cut, what is kept. The same loop a phone would run.

import Foundation
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
public enum ReaderModel: String, Sendable {
    case onDevice = "ondevice"
    case cloud = "cloud"
}

/// How the rows are handed to the model: one row per prompt (what the 4k on-device window can
/// hold), or one page per prompt (what a 32k window can).
public enum RowBatching: String, Sendable {
    case row, page
}

public struct ReaderOptions: Sendable {
    public var batching: RowBatching
    public var reuseSession: Bool
    /// Rows longer than this many runs are read in parts (0 turns it off): the on-device model
    /// cannot hold a 40-run braid row in one answer.
    public var chunkRuns: Int
    /// Worked examples of the grammars patterns use, added to the instructions (spec §9, step 3
    /// of the on-device plan): what an increase is, that a colour named before its runs applies
    /// to them, that a bracketed total is not a run.
    public var examples: Bool
    public init(batching: RowBatching = .row, reuseSession: Bool = false, chunkRuns: Int = 8, examples: Bool = false) {
        self.batching = batching
        self.reuseSession = reuseSession
        self.chunkRuns = chunkRuns
        self.examples = examples
    }
}

public struct ReaderProgress: Sendable {
    public let page: Int
    public let rowsSoFar: Int
    public let seconds: Double
}

@available(macOS 26.0, iOS 26.0, *)
public struct ProseReader: Sendable {
    public let model: ReaderModel
    public let options: ReaderOptions

    public init(model: ReaderModel, options: ReaderOptions = ReaderOptions()) {
        self.model = model
        self.options = options
    }

    /// Why the chosen model cannot answer here, or nil when it can.
    public func unavailableReason() -> String? {
        switch model {
        case .onDevice:
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(let why): return "on-device model unavailable: \(why)"
            }
        case .cloud:
            if #available(macOS 27.0, iOS 27.0, *) {
                switch PrivateCloudComputeLanguageModel().availability {
                case .available: return nil
                case .unavailable(let why): return "Private Cloud Compute model unavailable: \(why)"
                }
            }
            return "Private Cloud Compute needs macOS 27 or iOS 27"
        }
    }

    private static let rowInstructions =
        "You transcribe written crochet rows into structured data exactly as printed. "
        + "A run is a count and a colour; a turning chain (ch 1, turn) is not a run. Never correct a number."

    /// The grammars the corpus found, each with the answer it should produce. Short enough to leave
    /// the 4k window room for a chunk of eight runs and the answer.
    public static let grammarExamples = """
        Rules the patterns use:
        - A colour in parentheses applies to every run after it until the next colour in parentheses: "(Black) 5 sc, 3 sc, (White) 2 sc" is Black 8, White 2.
        - "N inc" makes 2 stitches for each of the N, in the colour in force: "1 inc" is 2 stitches; "N dec" makes 1 stitch for each of the N: "1 dec" is 1 stitch. Both are runs of the current colour, and neighbours of one colour merge.
        - A count in square brackets at the end, like [29], is the row's total, not a run. "(29 sts)" likewise.
        - "(agave) x 85" is 85 stitches of agave. "8sc in c1" is 8 stitches of c1. "sc across" with no count means the whole row in that colour.
        Examples:
        - "R 2 [→]: (Black) ch 1, turn, 1 inc, 7 sc, (White) 1 inc [11]" → row 2, runs Black 9, White 2, total 11.
        - "R 57 [←]: (Black) ch 1, turn, 9 sc, (White) 15 sc, 1 dec [25]" → row 57, runs Black 9, White 16, total 25.
        - "Row 3 RS: (agave) x 85, (terra) x 19" → row 3, runs agave 85, terra 19, total 0.
        - "Row 5: 7sc in c1, 3sc in c2, 7sc in c1." → row 5, runs c1 7, c2 3, c1 7, total 0.
        - "Row 12 (WS): ch 1, turn, 8 A, 14 B, 8 A (30 sts)" → row 12, runs A 8, B 14, A 8, total 30.
        """

    private static let frontInstructions =
        "You read a crochet pattern's front matter and answer only from what the text says; "
        + "leave what it does not say empty or 0."

    private var rowInstructionsInUse: String {
        options.examples ? Self.rowInstructions + "\n" + Self.grammarExamples : Self.rowInstructions
    }

    private func makeSession(instructions: String) -> LanguageModelSession {
        switch model {
        case .onDevice:
            return LanguageModelSession(model: .default, instructions: instructions)
        case .cloud:
            if #available(macOS 27.0, iOS 27.0, *) {
                return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
            }
            return LanguageModelSession(model: .default, instructions: instructions)
        }
    }

    /// Read a pattern whose pages are already text (PDFKit, or the importer's staged pNN.txt).
    public func read(pages: [String], progress: (@Sendable (ReaderProgress) -> Void)? = nil) async -> ProseDocument {
        let started = Date()
        var doc = await readFront(pages: pages)
        let key = Dictionary(
            (doc.palette ?? []).compactMap { p in p.key_label.map { ($0.lowercased(), p.code) } },
            uniquingKeysWith: { a, _ in a })
        var rows: [ProseDocument.Row] = []
        var session: LanguageModelSession? = nil
        for (index, text) in pages.enumerated() {
            let pageNo = index + 1
            let blocks = RowText.blocks(in: text)
            if blocks.isEmpty { continue }
            if options.batching == .page {
                if session == nil || !options.reuseSession {
                    session = makeSession(instructions: rowInstructionsInUse)
                }
                let prompt = "Transcribe every row in this text:\n" + blocks.joined(separator: "\n")
                do {
                    let got = try await session!.respond(to: prompt, generating: RowsPageOut.self)
                    for (i, r) in got.content.rows.enumerated() {
                        let source = i < blocks.count ? blocks[i] : blocks.last ?? ""
                        rows.append(
                            ProseDocument.Row(
                                row: r.row, page: pageNo, text: source,
                                runs: RowText.cleanRuns(r.runs, key: key),
                                total: r.total > 0 ? r.total : nil, error: nil))
                    }
                } catch {
                    for source in blocks {
                        rows.append(
                            ProseDocument.Row(
                                row: 0, page: pageNo, text: source, runs: [], total: nil,
                                error: String(describing: error).prefix(200).description))
                    }
                    session = nil
                }
                progress?(ReaderProgress(page: pageNo, rowsSoFar: rows.count, seconds: Date().timeIntervalSince(started)))
                continue
            }
            for block in blocks {
                // One row per prompt, in parts when the row is long: each part is one answer the
                // model can hold, and the parts join in order. The row number comes from the text's
                // own head (the model once answered 189 for "Row 1 (RS): 189 Y"), and increases and
                // decreases are rewritten into plain stitch counts first, a rule the model does not
                // keep however it is told.
                let parts = RowText.chunks(of: RowText.normalized(block), maxRuns: options.chunkRuns)
                var rowNo = RowText.rowNumber(of: block) ?? 0
                var runs: [[ProseDocument.RunValue]] = []
                var total: Int? = nil
                var failure: String? = nil
                for (k, part) in parts.enumerated() {
                    if session == nil || !options.reuseSession {
                        session = makeSession(instructions: rowInstructionsInUse)
                    }
                    let label = parts.count > 1 ? " (part \(k + 1) of \(parts.count) of one row)" : ""
                    do {
                        let got = try await session!.respond(to: "Transcribe this row\(label):\n" + part, generating: WrittenRowOut.self)
                        if rowNo == 0 { rowNo = got.content.row }  // only when the head carried none
                        runs = RowText.join(runs, RowText.cleanRuns(got.content.runs, key: key))
                        if got.content.total > 0 { total = got.content.total }
                    } catch {
                        failure = String(describing: error).prefix(200).description
                        session = nil
                        break
                    }
                }
                rows.append(ProseDocument.Row(row: failure == nil ? rowNo : 0, page: pageNo, text: block, runs: failure == nil ? runs : [], total: total, error: failure))
                progress?(ReaderProgress(page: pageNo, rowsSoFar: rows.count, seconds: Date().timeIntervalSince(started)))
            }
        }
        if !rows.isEmpty { doc.written_rows = rows }
        doc.uncertain = (doc.uncertain ?? []) + [
            "read by Apple's \(model == .cloud ? "Private Cloud Compute" : "on-device") model (FoundationModels, \(options.batching == .page ? "a page" : "a row") per prompt\(options.examples ? ", with grammar examples" : "")); numbers were transcribed, not checked, by the model"
        ]
        return doc
    }

    private func readFront(pages: [String]) async -> ProseDocument {
        var doc = ProseDocument()
        let session = makeSession(instructions: Self.frontInstructions)
        for text in pages.prefix(3) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let clipped = String(text.prefix(5000))
            guard let got = try? await session.respond(to: "Read this page:\n" + clipped, generating: FrontOut.self).content
            else { continue }
            var pattern = doc.pattern ?? [:]
            if !got.title.isEmpty, pattern["title"] == nil { pattern["title"] = got.title }
            if !got.author.isEmpty, pattern["author"] == nil { pattern["author"] = got.author }
            if !pattern.isEmpty { doc.pattern = pattern }
            var gauge = doc.gauge ?? ProseDocument.Gauge()
            if got.gaugeStitches > 0, got.gaugeRows > 0, got.gaugeOver > 0, !got.gaugeUnit.isEmpty, gauge.stitches == nil {
                gauge.stitches = got.gaugeStitches
                gauge.rows = got.gaugeRows
                gauge.over = .init(value: got.gaugeOver, unit: got.gaugeUnit)
            }
            if !got.hook.isEmpty, gauge.hook == nil { gauge.hook = got.hook }
            if !got.yarnWeight.isEmpty, gauge.yarn_weight == nil { gauge.yarn_weight = got.yarnWeight }
            if !got.stitch.isEmpty, gauge.stitch == nil { gauge.stitch = got.stitch }
            doc.gauge = gauge
            var chart = doc.chart ?? ProseDocument.Chart()
            if got.width > 0, got.height > 0, chart.width == nil {
                chart.width = got.width
                chart.height = got.height
            }
            doc.chart = chart
            if !got.colours.isEmpty, doc.palette == nil {
                // Codes are A, B, C... in key order unless the key itself prints 1-3 letter codes
                // that the rows use: the model invents a letter per colour otherwise, and its
                // choice drifts from run to run, so a code counts only when the pages contain it
                // as a token beside a count.
                let corpus = pages.joined(separator: "\n")
                let printed = got.colours.allSatisfy { c in
                    RowText.isCode(c.code) && c.code != c.name
                        && corpus.range(of: "\\b\\d+ ?\(c.code)\\b", options: .regularExpression) != nil
                }
                doc.palette = got.colours.enumerated().map { i, c in
                    let code = printed ? c.code : String(UnicodeScalar(65 + i) ?? "A")
                    let hex = c.hex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil ? c.hex.lowercased() : nil
                    let name = c.name.isEmpty ? c.code : c.name
                    return ProseDocument.Palette(code: code, name: name, hex: hex, key_label: name)
                }
            }
        }
        if let g = doc.gauge, g.stitches == nil, g.hook == nil, g.yarn_weight == nil, g.stitch == nil { doc.gauge = nil }
        return doc
    }
}

/// Text handling that needs no model: finding the rows on a page, tidying what the model returns.
public enum RowText {
    /// The head of a written row in every spelling the corpus uses (#146): "Row 12 (WS):",
    /// "R 3 [←]:", "Row 4 WS:", "Row1:"; "Row 1." and "Row 3 -" with a period or a dash for the
    /// colon; "Rows 1-10:" and "Row 2 & 3:", a range the model is left to read; "1st row:"; and a
    /// bare numbered list, "7. 2G, 3R, 2G", when what follows the number looks like a run. The
    /// punctuation that ends the head is what keeps "Row 1 starts at the bottom right" out.
    /// Groups: 1 and 2 are the number (with any range) and the side marker of the "Row" form,
    /// 3 and 4 the same for the ordinal form, 5 the number of a numbered list.
    static let headPattern: String = {
        let ending = #"(?::|\.(?=\s)|\s[-–—](?=\s))"#
        let marker = #"([^:.\-–—\n]{0,14}?)"#
        let range = #"(\d+(?:\s*(?:[-–]|&|and)\s*\d+)?)"#
        let run = #"(?:\d+\s*(?!(?:sc|dc|hdc|tr|ch|sts?|sl)\b)[A-Za-z]{1,3}\b|\([A-Za-z][A-Za-z ]*\))"#
        return "(?:(?:Rows?|ROWS?|R)\\s*\\.?\\s*" + range + marker + ending
            + "|(\\d+)(?:st|nd|rd|th)\\s+[Rr]ow" + marker + ending
            + "|(\\d+)\\.(?=\\s+" + run + "))"
    }()
    static let rowStart = try! NSRegularExpression(pattern: "^\\s*" + headPattern)
    /// The same head inside a line: PDFKit joins the last row of one column with the first of the next.
    static let rowInside = try! NSRegularExpression(pattern: "\\s(?=" + headPattern + ")")

    /// A block's head taken apart: its number (with any range, as printed), its side marker, whether
    /// it was already the "Row N …:" form the model reads best, and where the row's text starts.
    struct Head {
        let number: String
        let marker: String
        let verbatim: Bool
        let end: String.Index
    }

    static func head(of block: String) -> Head? {
        let range = NSRange(block.startIndex..., in: block)
        guard let m = rowStart.firstMatch(in: block, range: range), let end = Range(m.range, in: block)?.upperBound else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: block) else { return nil }
            return String(block[r])
        }
        if let number = group(1) {
            let matched = block[..<end]
            let verbatim = matched.hasSuffix(":") && !matched.contains("Rows") && !matched.contains("ROWS")
            return Head(number: number, marker: (group(2) ?? "").trimmingCharacters(in: .whitespaces), verbatim: verbatim, end: end)
        }
        if let number = group(3) { return Head(number: number, marker: (group(4) ?? "").trimmingCharacters(in: .whitespaces), verbatim: false, end: end) }
        if let number = group(5) { return Head(number: number, marker: "", verbatim: false, end: end) }
        return nil
    }

    /// The block with its head in the one form the model reads best, "Row N (marker): text", and
    /// one space between head and text; a head already in that form is kept as printed.
    static func canonicalHead(_ block: String) -> String {
        guard let h = head(of: block) else { return block }
        let rest = block[h.end...].trimmingCharacters(in: .whitespaces)
        let head = h.verbatim ? String(block[..<h.end]).trimmingCharacters(in: .whitespaces)
                              : "Row " + h.number + (h.marker.isEmpty ? "" : " " + h.marker) + ":"
        return head + " " + rest
    }
    static let notARun: Set<String> = ["ch", "turn", "sl", "st", "sts", "fsc", "fdc", "sc", "hdc", "dc"]

    /// Each written row's text on a page, wrapped continuation lines rejoined (a continuation
    /// starts with a count or carries a comma-separated list; a footer does neither).
    public static func blocks(in text: String) -> [String] {
        var blocks: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let whole = raw.trimmingCharacters(in: .whitespaces)
            if whole.isEmpty { continue }
            // Cut a line wherever another row head begins inside it.
            let pieces = rowInside.stringByReplacingMatches(in: whole, range: NSRange(whole.startIndex..., in: whole), withTemplate: "\n")
                .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            for line in pieces where !line.isEmpty {
                let range = NSRange(line.startIndex..., in: line)
                if rowStart.firstMatch(in: line, range: range) != nil {
                    blocks.append(line)
                } else if let last = blocks.last, line.contains(where: \.isLetter),
                          (line.first?.isNumber == true || line.contains(", ")), !last.hasSuffix("."), !last.hasSuffix(":"),
                          line.range(of: #"^\d+\.\s"#, options: .regularExpression) == nil {
                    // A wrapped row continues with a count and a colour ("4 Y (9 sts)"); a bare
                    // number is a chart-page label, a footer has no leading count, and "1. You
                    // will use…" is a numbered instruction, not a continuation.
                    blocks[blocks.count - 1] = last + " " + line
                }
            }
        }
        return blocks
    }

    /// A long row cut into parts of at most `maxRuns` comma-separated items after its head (the one
    /// `rowStart` matched, whatever its punctuation), each part carrying the head so the model
    /// knows what it is reading. 0 means never cut.
    public static func chunks(of block: String, maxRuns: Int) -> [String] {
        guard maxRuns > 0, let h = head(of: block) else { return [block] }
        let head = String(block[..<h.end]).trimmingCharacters(in: .whitespaces)
        let items = block[h.end...].trimmingCharacters(in: .whitespaces).components(separatedBy: ", ")
        if items.count <= maxRuns { return [block] }
        var parts: [String] = []
        var i = 0
        while i < items.count {
            let slice = items[i..<min(i + maxRuns, items.count)]
            parts.append(head + " " + slice.joined(separator: ", "))
            i += maxRuns
        }
        return parts
    }

    /// Runs from two parts of one row joined, merging a run that straddles the cut.
    static func join(_ a: [[ProseDocument.RunValue]], _ b: [[ProseDocument.RunValue]]) -> [[ProseDocument.RunValue]] {
        guard let last = a.last, let first = b.first, case .code(let c1) = last[0], case .code(let c2) = first[0], c1 == c2,
              case .count(let n1) = last[1], case .count(let n2) = first[1]
        else { return a + b }
        return a.dropLast() + [[.code(c1), .count(n1 + n2)]] + b.dropFirst()
    }

    static let incRe = try! NSRegularExpression(pattern: #"\b(\d+)\s*inc\b"#)
    static let decRe = try! NSRegularExpression(pattern: #"\b(\d+)\s*dec\b"#)

    /// The row number printed in a block's head: the first number of a range ("Rows 1-10" is row 1).
    public static func rowNumber(of block: String) -> Int? {
        guard let h = head(of: block) else { return nil }
        return Int(h.number.prefix { $0.isNumber })
    }

    static let foundationRe = try! NSRegularExpression(
        pattern: #"\bch\s*\d+,?\s*(?:from the \w+ (?:stitch|chain|ch) from the hook,?\s*)?(?:turn,?\s*)?"#, options: .caseInsensitive)
    static let adjacentRe = try! NSRegularExpression(pattern: #"\b(\d+) sc, (\d+) sc\b"#)

    /// The head in one form, increases and decreases as the stitches they make ("1 inc" is 2
    /// stitches of the colour in force, "2 dec" is 2 stitches), chains and turning phrases removed,
    /// and two plain counts of one colour added together, all before the model sees the row: it
    /// keeps none of these rules however it is told, and each is a regular expression.
    public static func normalized(_ block: String) -> String {
        var out = canonicalHead(block)
        for (re, factor) in [(incRe, 2), (decRe, 1)] {
            for m in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let whole = Range(m.range, in: out), let num = Range(m.range(at: 1), in: out), let n = Int(out[num]) else { continue }
                out.replaceSubrange(whole, with: "\(n * factor) sc")
            }
        }
        out = foundationRe.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        while let m = adjacentRe.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
              let whole = Range(m.range, in: out), let a = Range(m.range(at: 1), in: out), let b = Range(m.range(at: 2), in: out),
              let x = Int(out[a]), let y = Int(out[b]) {
            out.replaceSubrange(whole, with: "\(x + y) sc")
        }
        return out
    }

    public static func isCode(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z]{1,3}$", options: .regularExpression) != nil
    }

    @available(macOS 26.0, iOS 26.0, *)
    static func cleanRuns(_ runs: [RunOut], key: [String: String]) -> [[ProseDocument.RunValue]] {
        var out: [(String, Int)] = []
        for r in runs {
            var code = r.code.trimmingCharacters(in: .whitespaces)
            if notARun.contains(code.lowercased()) || r.count <= 0 { continue }
            if let mapped = key[code.lowercased()] { code = mapped }
            if !isCode(code) {
                code = String(code.filter { $0.isLetter }.prefix(3))
                if code.isEmpty { continue }  // a bracketed total or a stray number, not a colour
            }
            if let last = out.last, last.0 == code {
                out[out.count - 1].1 += r.count
            } else {
                out.append((code, r.count))
            }
        }
        return out.map { [.code($0.0), .count($0.1)] }
    }
}

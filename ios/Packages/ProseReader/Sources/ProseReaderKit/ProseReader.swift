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
    /// cannot hold a 40-run braid row in one answer, and four a part reads a 17-run pillow row
    /// where eight lost most of them (#149: bee pillow 10 → 71 of 75, daisy 39 → 52 of 52, the
    /// c2c squares level or better).
    public var chunkRuns: Int
    /// Worked examples of the grammars patterns use, added to the instructions (spec §9, step 3
    /// of the on-device plan): what an increase is, that a colour named before its runs applies
    /// to them, that a bracketed total is not a run.
    public var examples: Bool
    public init(batching: RowBatching = .row, reuseSession: Bool = false, chunkRuns: Int = 4, examples: Bool = false) {
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
    /// the 4k window room for a chunk of runs and the answer.
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
        // Codes the page prints as "bl= Black" lines become their palette letters in the row text
        // before the prompt: the model is told a chain is not a run, so "ch = Charcoal" would
        // vanish from every row otherwise. A printed code that names no palette entry stays as
        // written and survives the stitch-word filter.
        let printed = RowText.printedKey(in: pages)
        let palette = doc.palette ?? []
        var printedMap: [String: String] = [:]
        for (code, name) in printed where printedMap[code] == nil {
            printedMap[code] = palette.first { ($0.key_label ?? $0.name).lowercased().hasPrefix(name) }?.code ?? code
        }
        let printedCodes = Set(printed.map(\.code))
        var rows: [ProseDocument.Row] = []
        var lastWidth: Int? = nil  // the last read row's stitch count, for "repeat from * across" and plain rows
        var pendingPlain: [(index: Int, colour: String)] = []  // plain rows read before any width was known
        var widthVotes: [Int: Int] = [:]  // a plain row's width is one two counted rows agree on
        var fillCode: ProseDocument.RunValue? = nil  // the first counted row's first run, for a plain row that names no colour
        func fillPending(width: Int) {
            for (index, colour) in pendingPlain {
                let code: ProseDocument.RunValue = colour.isEmpty ? (fillCode ?? .code("A")) : .code(key[colour.lowercased()] ?? colour)
                let waiting = rows[index]
                rows[index] = ProseDocument.Row(row: waiting.row, page: waiting.page, text: waiting.text, runs: [[code, .count(width)]], total: width, error: nil)
            }
            pendingPlain.removeAll()
        }
        // A row printed on its own beats one derived from a range head or a "repeat row N", whichever
        // comes first: "Rows 4-25: repeat Row 3 using the chart" is a summary, and the explicit rows follow.
        var spellings: [String: String] = [:]  // code lowercased → the spelling first seen in this document
        var explicit = Set<Int>()
        var derived: [Int: Int] = [:]  // row number → index in rows
        func emit(_ row: ProseDocument.Row, derivedFrom numbers: [Int]) {
            let isDerived = numbers.count > 1
            if isDerived {
                if explicit.contains(row.row) { return }
                if let i = derived[row.row] { rows[i] = row; return }
                derived[row.row] = rows.count
            } else if row.row > 0 {
                explicit.insert(row.row)
                if let i = derived.removeValue(forKey: row.row) { rows[i] = row; return }
            }
            rows.append(row)
        }
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
                                runs: RowText.cleanRuns(r.runs, key: key, printed: printedCodes, spellings: &spellings),
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
                // keep however it is told. A head that covers several rows ("Rows 2-4") yields one
                // row per number, and a row that repeats an earlier one copies it without a prompt (#147).
                let numbers = RowText.rowNumbers(of: block)
                if let ref = RowText.repeatedRow(in: block), let src = rows.last(where: { $0.row == ref && $0.error == nil && !$0.runs.isEmpty }) {
                    for n in numbers.isEmpty ? [0] : numbers {
                        emit(ProseDocument.Row(row: n, page: pageNo, text: block, runs: src.runs, total: src.total, error: nil), derivedFrom: numbers + [0])
                    }
                    progress?(ReaderProgress(page: pageNo, rowsSoFar: rows.count, seconds: Date().timeIntervalSince(started)))
                    continue
                }
                let normalizedBlock = RowText.normalized(block, printed: printedMap, width: lastWidth)
                if let colour = RowText.plainRowColour(of: normalizedBlock) {
                    // A plain row, no counts, never goes to the model (with nothing to count it
                    // generates until the context is full): it is the previous row's width in the
                    // colour it names, or in the colour in force. Before any width is known it
                    // waits, and the first counted row fills it in.
                    let code: ProseDocument.RunValue? = colour.isEmpty ? rows.last(where: { $0.error == nil && !$0.runs.isEmpty })?.runs.first?.first : .code(key[colour.lowercased()] ?? colour)
                    for n in numbers.isEmpty ? [0] : numbers {
                        if let width = lastWidth, let code {
                            emit(ProseDocument.Row(row: n, page: pageNo, text: block, runs: [[code, .count(width)]], total: width, error: nil), derivedFrom: numbers)
                        } else if !explicit.contains(n) {
                            pendingPlain.append((rows.count, colour))
                            rows.append(ProseDocument.Row(row: n, page: pageNo, text: block, runs: [], total: nil, error: "plain row before any counted row: width unknown"))
                            if numbers.count > 1 { derived[n] = rows.count - 1 } else if n > 0 { explicit.insert(n) }
                        }
                    }
                    progress?(ReaderProgress(page: pageNo, rowsSoFar: rows.count, seconds: Date().timeIntervalSince(started)))
                    continue
                }
                let parts = RowText.chunks(of: normalizedBlock, maxRuns: options.chunkRuns)
                var rowNo = RowText.rowNumber(of: block) ?? 0
                var runs: [[ProseDocument.RunValue]] = []
                var total: Int? = RowText.printedTotal(of: block)
                var failure: String? = nil
                var invented = 0  // runs the model answered with codes this row never printed
                for (k, part) in parts.enumerated() {
                    if session == nil || !options.reuseSession {
                        session = makeSession(instructions: rowInstructionsInUse)
                    }
                    let label = parts.count > 1 ? " (part \(k + 1) of \(parts.count) of one row)" : ""
                    do {
                        let got = try await session!.respond(to: "Transcribe this row\(label):\n" + part, generating: WrittenRowOut.self)
                        if rowNo == 0 { rowNo = got.content.row }  // only when the head carried none
                        let cleaned = RowText.cleanRuns(got.content.runs, key: key, printed: printedCodes, spellings: &spellings, text: part)
                        if cleaned.isEmpty, !got.content.runs.isEmpty { invented += got.content.runs.count }
                        runs = RowText.join(runs, cleaned)
                        if total == nil, got.content.total > 0 { total = got.content.total }
                    } catch {
                        failure = String(describing: error).prefix(200).description
                        session = nil
                        break
                    }
                }
                if failure == nil, runs.isEmpty, invented > 0 {
                    failure = "the model answered with \(invented) run(s) naming colours this row does not print"
                }
                if failure == nil, !runs.isEmpty {
                    let width = runs.reduce(0) { sum, run in
                        sum + run.compactMap { v -> Int? in if case .count(let n) = v { return n } else { return nil } }.reduce(0, +)
                    }
                    lastWidth = width
                    widthVotes[width, default: 0] += 1
                    if fillCode == nil { fillCode = runs[0][0] }
                    if !pendingPlain.isEmpty, widthVotes[width] == 2 { fillPending(width: width) }  // two counted rows agree
                }
                let covered = numbers.count > 1 ? numbers : [failure == nil ? rowNo : 0]
                for n in covered {
                    emit(ProseDocument.Row(row: failure == nil ? n : 0, page: pageNo, text: block, runs: failure == nil ? runs : [], total: total, error: failure), derivedFrom: numbers)
                }
                progress?(ReaderProgress(page: pageNo, rowsSoFar: rows.count, seconds: Date().timeIntervalSince(started)))
            }
        }
        if !pendingPlain.isEmpty, let width = widthVotes.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key {
            fillPending(width: width)  // no two rows agreed: the commonest width, the smaller on a tie
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
    /// punctuation that ends the head, right after the number or its side marker, is what keeps
    /// "Row 1 starts at the bottom right" and "Row 1 starts here. Continue" out.
    /// Groups: 1 and 2 are the number (with any range) and the side marker of the "Row" form,
    /// 3 and 4 the same for the ordinal form, 5 the number of a numbered list.
    static let headPattern: String = {
        let ending = #"(?::|\.(?=\s)|\s[-–—](?=\s(?!\d)))"#  // "Row 3 - Sc"; not "Rows 1 – 25 you will"
        // A side marker is a bracketed or parenthesised group or a bare RS/WS/LR/RL: any other text
        // between the number and the period is a sentence ("Row 1 starts here. Continue").
        let marker = #"((?:\s*\([^()\n]{1,24}\)|\s*\[[^\[\]\n]{1,12}\]|\s+(?:RS|WS|LR|RL))?)"#
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
            let plain = number.allSatisfy(\.isNumber)
            let spaced = matched.range(of: #"^\s*(?:Row|ROW|R)\s+\d"#, options: .regularExpression) != nil  // "Row1:" is rewritten
            let verbatim = plain && spaced && matched.hasSuffix(":") && !matched.contains("Rows") && !matched.contains("ROWS")
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
        let first = String(h.number.prefix { $0.isNumber })  // a range head prompts as its first row (#147)
        let head = h.verbatim ? String(block[..<h.end]).trimmingCharacters(in: .whitespaces)
                              : "Row " + first + (h.marker.isEmpty ? "" : " " + h.marker) + ":"
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

    /// Every row a block's head covers (#147): "Rows 1-10" is ten rows, "Rows 2 & 3" two, "Row 5"
    /// one. A range wider than 300 rows is a misprint and counts as its first row alone.
    public static func rowNumbers(of block: String) -> [Int] {
        guard let h = head(of: block) else { return [] }
        let numbers = h.number.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let first = numbers.first else { return [] }
        guard numbers.count == 2, let last = numbers.last, last >= first, last - first <= 300 else { return [first] }
        if h.number.contains("&") || h.number.contains("and") { return [first, last] }
        return Array(first...last)
    }

    static let repeatRowRe = try! NSRegularExpression(pattern: #"\brep(?:eat)?\.?\s+rows?\s+(\d+)\b"#, options: .caseInsensitive)
    /// The row this block says to repeat ("Row 6: repeat row 5"), if it is written that way.
    public static func repeatedRow(in block: String) -> Int? {
        guard let h = head(of: block) else { return nil }
        let rest = String(block[h.end...])
        guard let m = repeatRowRe.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)), let r = Range(m.range(at: 1), in: rest) else { return nil }
        return Int(rest[r])
    }

    static let foundationRe = try! NSRegularExpression(
        pattern: #"\bch\s*\d+,?\s*(?:from the \w+ (?:stitch|chain|ch) from the hook,?\s*)?(?:turn,?\s*)?"#, options: .caseInsensitive)
    static let adjacentRe = try! NSRegularExpression(pattern: #"\b(\d+) sc, (\d+) sc\b"#)
    /// #148, the run spellings the model mishandles. A count glued to a colour code ("c2", "gh3")
    /// but not to a stitch word ("ch2", "dc2tog"); a colour named by its number after "in", "with",
    /// "of" or the word colour ("in c1", "with C2", "color 2"; a bare "c2" is two stitches of c),
    /// which is the key's first, second… code; "8sc in c1" / "9sc with C2" /
    /// "sc 8 in white" / "(green) sc 10", all "count colour" with the stitch word in the way; and a
    /// bare parenthesised name meaning one stitch ("(Pale Rose), (White) x 13").
    static let gluedRe = try! NSRegularExpression(pattern: #"\b(?!(?:sc|dc|hdc|tr|ch|st|sts|sl|fsc|fdc|tog|Row|ROW|R)\d)([A-Za-z]{1,3})(\d+)\b(?!tog)"#)
    static let numberedColourRe = try! NSRegularExpression(pattern: #"(?:(?<=\bin |\bwith |\bof )[cC]|\b[cC]olou?r\s?)([1-9])\b"#)
    static let countStitchNameRe = try! NSRegularExpression(pattern: #"\b(\d+)\s*sc\s+(?:in|with|of)\s+((?:[A-Z]\b)|[A-Za-z][A-Za-z ]*?)(?=[,.]|\s*$)"#)
    static let stitchCountNameRe = try! NSRegularExpression(pattern: #"\bsc\s+(\d+)\s+in\s+([A-Za-z][A-Za-z ]*?)(?=[,.]|\s*$)"#)
    static let nameStitchCountRe = try! NSRegularExpression(pattern: #"\(([^()]+)\)\s*sc\s*(\d+)"#)
    static let bareNameRe = try! NSRegularExpression(pattern: #"\(([A-Za-z][A-Za-z ]*)\)(?=\s*(?:,|$))"#)
    /// A bare code standing as a run item ("c, a, (lb) x 3") is one stitch; said so, a chunk that
    /// starts with it is not guessed at (#149).
    static let bareCodeRe = try! NSRegularExpression(pattern: #"(?<=[,:]\s)(?!(?:sc|dc|hdc|tr|ch|st|sts|sl|RS|WS)\b)([A-Za-z]{1,3})(?=\s*(?:,|\.?\s*$))"#)

    /// The head in one form, increases and decreases as the stitches they make ("1 inc" is 2
    /// stitches of the colour in force, "2 dec" is 2 stitches), chains and turning phrases removed,
    /// and two plain counts of one colour added together, all before the model sees the row: it
    /// keeps none of these rules however it is told, and each is a regular expression.
    static let groupRe = try! NSRegularExpression(pattern: #"[\(\[]([^()\[\]]+)[\)\]]\s*(?:(\d+)\s*(?:times|x)\b|(twice)\b)"#)
    static let starRe = try! NSRegularExpression(
        pattern: #"\*\s*(.*?)\s*;?\s*\brep(?:eat)?\.?\s+from\s+\*(?:\s+(?:(\d+)\s+(more\s+)?times|across|to\s+(?:the\s+)?end|to\s+last\b[^,.;]*))?"#, options: .caseInsensitive)
    static let numberRe = try! NSRegularExpression(pattern: #"\d+"#)

    /// The integers in a piece of row text, added up: a run count however it is spelled.
    static func stitchSum(_ text: String) -> Int {
        numberRe.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }.compactMap { Int(text[$0]) }.reduce(0, +)
    }

    /// A bracketed group with a count expanded in place ("(14 CC, 24 MC) 3 times"), and a starred
    /// group repeated a stated number of times or, for "repeat from * across", as many times as
    /// fill the row's width (the previous row's) exactly; otherwise it is left for the model (#147).
    static func expandedRepeats(_ block: String, width: Int?) -> String {
        var out = block
        for m in groupRe.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
            guard let whole = Range(m.range, in: out), let g = Range(m.range(at: 1), in: out) else { continue }
            let n = Range(m.range(at: 2), in: out).flatMap { Int(out[$0]) } ?? 2
            out.replaceSubrange(whole, with: Array(repeating: String(out[g]), count: max(1, min(n, 200))).joined(separator: ", "))
        }
        guard let m = starRe.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
              let whole = Range(m.range, in: out), let g = Range(m.range(at: 1), in: out) else { return out }
        let group = String(out[g])
        var times: Int? = nil
        if let n = Range(m.range(at: 2), in: out).flatMap({ Int(out[$0]) }) {
            times = m.range(at: 3).location != NSNotFound ? n + 1 : n
        } else if let width, let h = head(of: out) {
            let before = String(out[h.end..<whole.lowerBound]), after = String(out[whole.upperBound...])
            let unit = stitchSum(group), rest = width - stitchSum(before) - stitchSum(after)
            if unit > 0, rest > 0, rest % unit == 0 { times = rest / unit }
        }
        guard let times, times > 0, times <= 200 else { return out }
        out.replaceSubrange(whole, with: Array(repeating: group, count: times).joined(separator: ", "))
        return out
    }

    /// A printed code standing as a run item (no letter on either side; a comma, a full stop, a
    /// bracket, an "x N" or the end after it, so "a" in "Join in a new colour" is left alone)
    /// replaced by its palette letter.
    static func substitutePrinted(_ text: String, printed: [String: String]) -> String {
        var out = text
        for (code, letter) in printed.sorted(by: { $0.key.count > $1.key.count }) where code != letter {
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: code) + #"(?![A-Za-z])(?=\s*[,.)]|\s+x\s*\d|\s*$)"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: NSRegularExpression.escapedTemplate(for: letter))
        }
        return out
    }

    public static func normalized(_ block: String, printed: [String: String] = [:], width: Int? = nil) -> String {
        var out = canonicalHead(block)
        // The printed total is read by `printedTotal`; alone in a chunk the model reads "(14 boxes)" as runs (#149).
        out = totalRe.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        for (re, factor) in [(incRe, 2), (decRe, 1)] {
            for m in re.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
                guard let whole = Range(m.range, in: out), let num = Range(m.range(at: 1), in: out), let n = Int(out[num]) else { continue }
                out.replaceSubrange(whole, with: "\(n * factor) sc")
            }
        }
        out = foundationRe.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        out = expandedRepeats(out, width: width)
        for m in numberedColourRe.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
            guard let whole = Range(m.range, in: out), let d = Range(m.range(at: 1), in: out), let n = Int(out[d]), let letter = UnicodeScalar(64 + n) else { continue }
            out.replaceSubrange(whole, with: String(letter))  // "in c1", "color 2" → the key's first, second… code
        }
        // Printed codes become palette letters before the rewrites (so "ch = Charcoal" is a code, not
        // a chain, when the bare-code rule sees it) and again after ("c2" is "2 c" only afterwards).
        out = substitutePrinted(out, printed: printed)
        for (re, template) in [(gluedRe, "$2 $1"), (countStitchNameRe, "$1 $2"), (stitchCountNameRe, "$1 $2"), (nameStitchCountRe, "$2 $1"), (bareNameRe, "($1) x 1"), (bareCodeRe, "1 $1")] {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        out = substitutePrinted(out, printed: printed)
        while let m = adjacentRe.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
              let whole = Range(m.range, in: out), let a = Range(m.range(at: 1), in: out), let b = Range(m.range(at: 2), in: out),
              let x = Int(out[a]), let y = Int(out[b]) {
            out.replaceSubrange(whole, with: "\(x + y) sc")
        }
        return out
    }

    /// A key the page prints one code per line, "bl= Black", "c = Carrot - this is the background",
    /// "w= (Soft) White": the code (lowercased) and the name up to its first dash, slash or comma,
    /// brackets removed.
    static let keyLineRe = try! NSRegularExpression(pattern: #"^\s*([A-Za-z]{1,3})\s*=\s*(\(?[A-Za-z][A-Za-z ()]*?)\s*(?:[-/,.].*)?$"#)
    public static func printedKey(in pages: [String]) -> [(code: String, name: String)] {
        var out: [(code: String, name: String)] = []
        for page in pages {
            for line in page.split(whereSeparator: \.isNewline) {
                let l = String(line)
                guard let m = keyLineRe.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)),
                      let c = Range(m.range(at: 1), in: l), let n = Range(m.range(at: 2), in: l) else { continue }
                let name = String(l[n]).lowercased().replacingOccurrences(of: #"[()]"#, with: "", options: .regularExpression)
                out.append((String(l[c]).lowercased(), name.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out
    }

    static let plainRowRe = try! NSRegularExpression(
        pattern: #"\b(?:across|each st|every st|to (?:the )?end)\b|^\s*(?:sc|dc|hdc|tr)\s+(?:in|with)\s+[A-Za-z]{1,3}\.?\s*$"#, options: .caseInsensitive)
    /// Digits that are not counts: a bracketed total, a turning chain, a row reference.
    static let notACountRe = try! NSRegularExpression(pattern: #"\(\d+\)|\bch\s*\d+|\bRows?\s*\d+(?:\s*-\s*\d+)?"#, options: .caseInsensitive)
    static let codeTokenRe = try! NSRegularExpression(pattern: #"(?<![A-Za-z])([A-Z]{1,3})(?![A-Za-z])"#)
    /// A plain row ("sc across in A", "sc in each st across", "sc in A"), after `normalized`: the
    /// one code it names, "" when it names none, nil when the row carries counts and is not plain.
    public static func plainRowColour(of block: String) -> String? {
        guard let h = head(of: block) else { return nil }
        var body = String(block[h.end...])
        body = notACountRe.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body), withTemplate: "")
        let range = NSRange(body.startIndex..., in: body)
        guard numberRe.firstMatch(in: body, range: range) == nil, plainRowRe.firstMatch(in: body, range: range) != nil else { return nil }
        let codes = codeTokenRe.matches(in: body, range: range).compactMap { Range($0.range(at: 1), in: body) }.map { String(body[$0]) }
            .filter { !notARun.contains($0.lowercased()) && $0 != "RS" && $0 != "WS" }
        return codes.count == 1 ? codes[0] : ""
    }

    /// A total printed at the row's end: "(14 boxes)", "(189 sts)", "(52 squares)", "[25]".
    static let totalRe = try! NSRegularExpression(pattern: #"\s*(?:\(\s*(\d+)\s*(?:boxes?|squares?|sts?|stitches|sc|dc|hdc|tiles?)?\s*\)|\[\s*(\d+)\s*\])\s*\.?\s*$"#)
    public static func printedTotal(of block: String) -> Int? {
        guard let m = totalRe.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)) else { return nil }
        for i in 1...2 { if let r = Range(m.range(at: i), in: block), let n = Int(block[r]) { return n } }
        return nil
    }

    public static func isCode(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z]{1,3}$", options: .regularExpression) != nil
    }

    @available(macOS 26.0, iOS 26.0, *)
    /// With `text` (the row as prompted), a code the model made up is dropped (#150): what the
    /// model has no answer for, it fills from the example grammars ("aga", "Bla"), so a run's code
    /// must be a palette code, a printed code, or a token of the row's own text.
    static func cleanRuns(_ runs: [RunOut], key: [String: String], printed: Set<String> = [], spellings: inout [String: String], text: String? = nil) -> [[ProseDocument.RunValue]] {
        var out: [(String, Int)] = []
        let palette = Set(key.values.map { $0.lowercased() })
        let tokens: Set<String>? = text.map { t in
            Set(t.split(whereSeparator: { !$0.isLetter }).map { $0.lowercased() })
        }
        for r in runs {
            var code = r.code.trimmingCharacters(in: .whitespaces)
            if r.count <= 0 || (notARun.contains(code.lowercased()) && !printed.contains(code.lowercased())) { continue }
            if let tokens {
                let lower = code.lowercased()
                let known = palette.contains(lower) || key[lower] != nil || printed.contains(lower) || tokens.contains(lower)
                if !known { continue }  // neither a colour of this document nor a word of this row: an invention
            }
            // The model's casing drifts ("w" once, "W" another time): one spelling per code, the first seen.
            if let seen = spellings[code.lowercased()] { code = seen } else { spellings[code.lowercased()] = code }
            if code.count == 2, code.first?.lowercased() == "c", let n = Int(String(code.last!)), n > 0, let letter = UnicodeScalar(64 + n) {
                code = String(letter)  // "c1", "C2": the key's first, second… colour (#148)
            }
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

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
    public init(batching: RowBatching = .row, reuseSession: Bool = false, chunkRuns: Int = 8) {
        self.batching = batching
        self.reuseSession = reuseSession
        self.chunkRuns = chunkRuns
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

    private static let frontInstructions =
        "You read a crochet pattern's front matter and answer only from what the text says; "
        + "leave what it does not say empty or 0."

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
                    session = makeSession(instructions: Self.rowInstructions)
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
                // model can hold, and the parts join in order.
                let parts = RowText.chunks(of: block, maxRuns: options.chunkRuns)
                var rowNo = 0
                var runs: [[ProseDocument.RunValue]] = []
                var total: Int? = nil
                var failure: String? = nil
                for (k, part) in parts.enumerated() {
                    if session == nil || !options.reuseSession {
                        session = makeSession(instructions: Self.rowInstructions)
                    }
                    let label = parts.count > 1 ? " (part \(k + 1) of \(parts.count) of one row)" : ""
                    do {
                        let got = try await session!.respond(to: "Transcribe this row\(label):\n" + part, generating: WrittenRowOut.self)
                        if rowNo == 0 { rowNo = got.content.row }
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
            "read by Apple's \(model == .cloud ? "Private Cloud Compute" : "on-device") model (FoundationModels, \(options.batching == .page ? "a page" : "a row") per prompt); numbers were transcribed, not checked, by the model"
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
                doc.palette = got.colours.enumerated().map { i, c in
                    let code = RowText.isCode(c.code) ? c.code : String(UnicodeScalar(65 + i) ?? "A")
                    let hex = c.hex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil ? c.hex.lowercased() : nil
                    return ProseDocument.Palette(code: code, name: c.name.isEmpty ? c.code : c.name, hex: hex, key_label: c.name.isEmpty ? c.code : c.name)
                }
            }
        }
        if let g = doc.gauge, g.stitches == nil, g.hook == nil, g.yarn_weight == nil, g.stitch == nil { doc.gauge = nil }
        return doc
    }
}

/// Text handling that needs no model: finding the rows on a page, tidying what the model returns.
public enum RowText {
    static let rowStart = try! NSRegularExpression(pattern: #"^\s*(?:Row|ROW|R)\s*\.?\s*\d+\b"#)
    static let notARun: Set<String> = ["ch", "turn", "sl", "st", "sts", "fsc", "fdc", "sc", "hdc", "dc"]

    /// Each written row's text on a page, wrapped continuation lines rejoined (a continuation
    /// starts with a count or carries a comma-separated list; a footer does neither).
    public static func blocks(in text: String) -> [String] {
        var blocks: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let range = NSRange(line.startIndex..., in: line)
            if rowStart.firstMatch(in: line, range: range) != nil {
                blocks.append(line)
            } else if let last = blocks.last, (line.first?.isNumber == true || line.contains(", ")), !last.hasSuffix("."), !last.hasSuffix(":") {
                blocks[blocks.count - 1] = last + " " + line
            }
        }
        return blocks
    }

    /// A long row cut into parts of at most `maxRuns` comma-separated items after its "Row N:" head,
    /// each part carrying the head so the model knows what it is reading. 0 means never cut.
    public static func chunks(of block: String, maxRuns: Int) -> [String] {
        guard maxRuns > 0, let colon = block.range(of: ": ") else { return [block] }
        let head = String(block[..<colon.lowerBound])
        let items = block[colon.upperBound...].components(separatedBy: ", ")
        if items.count <= maxRuns { return [block] }
        var parts: [String] = []
        var i = 0
        while i < items.count {
            let slice = items[i..<min(i + maxRuns, items.count)]
            parts.append(head + ": " + slice.joined(separator: ", "))
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
                if code.isEmpty { code = "X" }
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

import Foundation
import GraphghanCore
import PDFKit
import ProseReaderKit

/// A pattern PDF, from bytes to a pattern the library shows (phone import spec §5.1, §5.3). PDFKit
/// turns the pages into text here; every decision about that text is `GraphghanCore`'s or the
/// row reader's. Reading and saving are two steps because the sheet shows the chart before "Add
/// to library" saves it, and a read writes nothing.
struct PDFImporter: Sendable {
    let charts: ChartLibrary
    let local: LocalPatternStore
    /// The written-row reader (spec §4.3), nil when this iPhone has no model to run it on; then
    /// `modelUnavailable` says why, for the log.
    let rowReader: (any RowReading)?
    let modelUnavailable: String?

    /// A pattern PDF is a few MB; the Orca bag, all photos, is 18 MB.
    static let maximumBytes = 20 << 20
    /// A page with fewer characters than this holds a page number and a title at most: its rows,
    /// if any, are a picture (spec §4.4). A page of prose is well past it.
    static let pictureTextLimit = 40
    /// Seconds one row takes on the on-device model (spec §4.3, measured on Orca), for the estimate.
    static let secondsPerRow = 3.0

    func read(_ data: Data, fileName: String, progress: (@Sendable (PDFImportProgress) -> Void)? = nil) async throws(PDFImportError) -> PDFImportReading {
        guard data.count <= Self.maximumBytes else { throw .tooBig }
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw .cannotOpen }
        var texts: [String] = []
        var thinPages = 0
        for i in 0..<document.pageCount {
            let text = document.page(at: i)?.string ?? ""
            texts.append(text)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < Self.pictureTextLimit { thinPages += 1 }
            progress?(.pages(done: i + 1, of: document.pageCount))
        }
        let title = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if OwnPDFReader.isOwn(pageTexts: texts) {
            return try await assembleOwn(texts: texts, title: title, fileName: fileName)
        }
        if let grid = try await readGrid(document, texts: texts, title: title, fileName: fileName, progress: progress) { return grid }
        guard RowText.rowCount(in: texts) >= 2 else {
            // Every page nearly empty of text: the rows are printed as a picture (§4.4).
            throw thinPages == document.pageCount ? .rowsArePictures : .nothingFound
        }
        guard let rowReader else { throw .needsAppleIntelligence }
        return try await assembleRows(texts: texts, reader: rowReader, title: title, fileName: fileName, progress: progress)
    }

    // MARK: our own PDF (spec §4.1)

    func assembleOwn(texts: [String], title: String, fileName: String) async throws(PDFImportError) -> PDFImportReading {
        let reading: OwnPDFReading
        do {
            reading = try OwnPDFReader.read(pageTexts: texts, title: title.isEmpty ? Self.stem(fileName) : title)
        } catch let error as OwnPDFError {
            throw .badRow(error)  // the reader's own error travels with the sentence
        } catch {
            throw .invalidChart("\(error)")
        }
        let patternTitle = reading.pattern.title.isEmpty ? Self.stem(fileName) : reading.pattern.title
        let draft = ChartWriter.draft(from: reading, id: "")
        return try await assemble(draft: draft, title: patternTitle, version: reading.pattern.version, fileName: fileName, texts: texts, source: .ownPDF, warnings: [])
    }

    // MARK: written rows alone (spec §4.3)

    func assembleRows(texts: [String], reader: any RowReading, title: String, fileName: String,
                      progress: (@Sendable (PDFImportProgress) -> Void)?) async throws(PDFImportError) -> PDFImportReading {
        let started = Date()
        // The sheet moves to the rows state before the first row is read, so the estimate and
        // Cancel are there while the model warms up.
        progress?(.rows(done: 0, of: RowText.rowCount(in: texts), secondsElapsed: 0))
        let doc = await reader.read(pages: texts) { p in
            progress?(.rows(done: p.rowsSoFar, of: p.rowsTotal, secondsElapsed: Int(Date().timeIntervalSince(started))))
        }
        if Task.isCancelled { throw .cancelled }
        let all = doc.written_rows ?? []
        // A row the reader could not read is named, never dropped: dropping the last one would
        // shrink the height inferred below and pass a truncated chart off as whole.
        let unread = all.compactMap { r -> String? in
            if let error = r.error { return "row \(r.row): \(error)" }
            return r.runs.isEmpty ? "row \(r.row): no runs read" : nil
        }
        guard unread.isEmpty else { throw .rowsDoNotAssemble(unread) }
        guard !all.isEmpty else { throw .rowsDoNotAssemble(["no written rows were read"]) }
        let rows = all.map { RowsChart.Row(row: $0.row, runs: $0.runs.map(Self.run), total: $0.total) }
        // Width and height are what the front matter says, else the widest row and the highest
        // number; either way within what the app works (§5.1) before any grid is allocated.
        let width = doc.chart?.width.flatMap { $0 > 0 ? $0 : nil } ?? rows.map { $0.runs.reduce(0) { $0 + $1.count } }.max() ?? 0
        let height = doc.chart?.height.flatMap { $0 > 0 ? $0 : nil } ?? rows.map(\.row).max() ?? 0
        guard width >= 1, height >= 1 else { throw .rowsDoNotAssemble(["the chart would be \(width) × \(height)"]) }
        guard width <= OwnPDFReader.maximumSide, height <= OwnPDFReader.maximumSide else { throw .badRow(.tooLarge(width: width, height: height)) }
        // Every code the rows use is in the palette; a key colour with no hex gets a placeholder.
        var palette = (doc.palette ?? []).map { ChartDraft.Palette(code: $0.code, name: $0.name.isEmpty ? $0.code : $0.name, hex: $0.hex ?? "") }
        let used = Set(rows.flatMap { $0.runs.map(\.code) })
        for code in used.sorted() where !palette.contains(where: { $0.code == code }) {
            palette.append(ChartDraft.Palette(code: code, name: code, hex: ""))
        }
        for i in palette.indices where !Self.isHex(palette[i].hex) {
            let taken = palette.map(\.hex).filter(Self.isHex)
            palette[i] = ChartDraft.Palette(code: palette[i].code, name: palette[i].name, hex: RowsChart.placeholderHex(avoiding: taken))
        }
        let strings: [String]
        switch RowsChart.rowStrings(rows: rows, codes: palette.map(\.code), width: width, height: height, row1: doc.chart?.row1 ?? "bottom-right") {
        case .success(let s): strings = s
        case .failure(let problems): throw .rowsDoNotAssemble(problems.sentences)
        }
        let patternTitle = doc.pattern?["title"].flatMap { $0.isEmpty ? nil : $0 } ?? (title.isEmpty ? Self.stem(fileName) : title)
        var gauge = ChartDraft.Gauge()
        var gaugePrinted = false
        if let g = doc.gauge, let st = g.stitches, let rws = g.rows, let over = g.over,
           st > 0, rws > 0, over.value > 0, over.unit == "in" || over.unit == "cm" {
            gauge.stitches = Double(st)
            gauge.rows = Double(rws)
            gauge.overValue = Double(over.value)
            gauge.overUnit = over.unit
            gaugePrinted = true
        }
        gauge.stitch = doc.gauge?.stitch.flatMap { $0.isEmpty ? nil : $0 } ?? "sc"
        gauge.hook = doc.gauge?.hook.flatMap { $0.isEmpty ? nil : $0 }
        gauge.yarnWeight = doc.gauge?.yarn_weight.flatMap { $0.isEmpty ? nil : $0 }
        let record = ImportRecord(grid: false, check: .noRows, rowsChecked: 0, rowsTotal: 0, rowsDisagree: [], gaugePrinted: gaugePrinted, problem: nil)
        let draft = ChartDraft(pattern: .init(id: "", title: patternTitle, version: "0.1.0"), palette: palette, rows: strings,
                               width: width, height: height, gauge: gauge, ext: record.json())
        return try await assemble(draft: draft, title: patternTitle, version: "0.1.0", fileName: fileName, texts: texts,
                                  source: .writtenRows(count: rows.count, gaugePrinted: gaugePrinted), warnings: [])
    }

    /// `["A", 3]` from the reader's document as a run.
    static func run(_ pair: [ProseDocument.RunValue]) -> (code: String, count: Int) {
        var code = ""
        var count = 0
        for v in pair {
            switch v {
            case .code(let s): code = s
            case .count(let n): count = n
            }
        }
        return (code, count)
    }

    // MARK: a chart on a page (spec §4.2, §5.1 step 2)

    /// The smallest grid that counts as a chart (spec §5.1).
    static let minimumGridSide = 8

    func readGrid(_ document: PDFDocument, texts: [String], title: String, fileName: String,
                  progress: (@Sendable (PDFImportProgress) -> Void)?) async throws(PDFImportError) -> PDFImportReading? {
        var best: (page: Int, region: Region)?
        var warnings: [String] = []
        for i in 0..<document.pageCount {
            if Task.isCancelled { throw .cancelled }
            guard let page = document.page(at: i) else { continue }
            guard let image = PageRenderer.image(page) else { warnings.append("page \(i + 1) is too large to read"); continue }
            let regions = (try? GridReader.findRegions(image)) ?? []  // tooLarge cannot happen under the budget
            for r in regions where r.cols >= Self.minimumGridSide && r.rows >= Self.minimumGridSide {
                if best == nil || r.cells > best!.region.cells { best = (i, r) }
            }
            progress?(.pages(done: i + 1, of: document.pageCount))
        }
        guard let best, let page = document.page(at: best.page), let image = PageRenderer.image(page) else { return nil }
        let patternTitle = title.isEmpty ? Self.stem(fileName) : title
        let (draft, _, gridWarnings) = GridChart.draft(image: image, region: best.region, title: patternTitle)
        return try await assemble(draft: draft, title: patternTitle, version: "0.1.0", fileName: fileName, texts: texts,
                                  source: .grid(page: best.page + 1, rowsToCheck: RowText.rowCount(in: texts)), warnings: warnings + gridWarnings)
    }

    /// The written rows read and compared with the chart (spec §4.2): the outcome as the record
    /// the chart carries. Cancelling stops the reader between rows; what was read is compared.
    func check(_ reading: PDFImportReading, progress: (@Sendable (PDFImportProgress) -> Void)?) async -> ImportRecord {
        var record = ImportRecord(json: reading.draft.ext) ?? ImportRecord(grid: true, check: .noRows, rowsChecked: 0, rowsTotal: 0, rowsDisagree: [], gaugePrinted: false, problem: nil)
        guard case .grid(_, let total) = reading.source, total > 0 else { record.check = .noRows; return record }
        record.rowsTotal = total
        guard let rowReader else { record.check = .unavailable; return record }
        progress?(.checking(done: 0, of: total))
        let doc = await rowReader.read(pages: reading.pageTexts) { p in progress?(.checking(done: p.rowsSoFar, of: p.rowsTotal)) }
        let stopped = Task.isCancelled
        let all = (doc.written_rows ?? []).filter { $0.error == nil && !$0.runs.isEmpty }
        let rows = all.map { RowsChart.Row(row: $0.row, runs: $0.runs.map(Self.run), total: $0.total) }
        var codes = (doc.palette ?? []).map(\.code)
        if codes.isEmpty { for r in rows { for run in r.runs where !codes.contains(run.code) { codes.append(run.code) } } }
        record.check = stopped ? .stopped : .finished
        record.rowsChecked = rows.map(\.row).max() ?? 0
        let chart = reading.bundle.charts[0].chart
        if let w = doc.chart?.width, let h = doc.chart?.height, w > 0, h > 0, (w, h) != (chart.width, chart.height) {
            record.problem = "written rows give \(w)x\(h), the chart reads \(chart.width)x\(chart.height)"
            return record
        }
        guard !rows.isEmpty else {
            // Stopped before the first row is simply stopped at row 0; finished with nothing read is a problem.
            if !stopped { record.problem = "no written rows could be read" }
            return record
        }
        switch RowsChart.crossCheck(rows: rows, codes: codes, grid: chart.cells, width: chart.width, height: chart.height, row1: doc.chart?.row1 ?? "bottom-right") {
        case .compared(let disagree, _): record.rowsDisagree = disagree
        case .incomparable(let why): record.problem = why
        }
        return record
    }

    // MARK: the tail every reader shares (spec §5.3)

    func assemble(draft: ChartDraft, title: String, version: String, fileName: String, texts: [String],
                  source: PDFImportSource, warnings: [String]) async throws(PDFImportError) -> PDFImportReading {
        var draft = draft
        draft.pattern.id = await Self.uniqueSlug(Self.slug(title), in: local)
        let (bundle, preview, chart) = try Self.bundle(for: draft, title: title, version: version, fileName: fileName)
        return PDFImportReading(bundle: bundle, preview: preview, width: chart.width, height: chart.height, colours: chart.palette.count,
                                source: source, draft: draft, title: title, version: version, fileName: fileName, pageTexts: texts, warnings: warnings)
    }

    /// The chart, its preview and its manifest from a draft whose id is the slug; `save` rebuilds
    /// them when the check's record goes into the draft.
    static func bundle(for draft: ChartDraft, title: String, version: String, fileName: String) throws(PDFImportError) -> (PatternBundle, Data, Chart) {
        let slug = draft.pattern.id
        let (chartData, chartID) = ChartWriter.encode(draft)
        let chart: Chart
        do { chart = try Chart.load(chartData) } catch { throw .invalidChart("\(error)") }
        guard let preview = ChartPreview.png(chart) else { throw .invalidChart("no preview") }
        let gaugeKey = draft.gauge.stitch ?? "sc"
        let dedication = "Imported from \(fileName) on \(today())"
        let manifestData = ManifestWriter.encode(id: slug, title: title, version: version, dedication: dedication,
                                                 chart: chart, chartID: chartID, variant: "final", gaugeKey: gaugeKey, palette: draft.palette)
        let manifest: PatternManifest
        do { manifest = try JSONDecoder().decode(PatternManifest.self, from: manifestData) } catch { throw .invalidChart("manifest: \(error)") }
        let entry = manifest.charts[0]
        let bundle = PatternBundle(manifest: manifest, manifestData: manifestData,
                                   charts: [BundleChart(entry: entry, chart: chart, data: chartData)],
                                   previews: ["preview.png": preview, entry.preview: preview])
        return (bundle, preview, chart)
    }

    /// The bundle importer's order (bundle design §6.2): charts, then the pattern directory whole.
    /// With a record, the check's outcome goes into the chart first (spec §6.3).
    func save(_ reading: PDFImportReading, record: ImportRecord? = nil) async throws -> PatternManifest {
        var bundle = reading.bundle
        if let record {
            var draft = reading.draft
            draft.ext = record.json()
            bundle = try Self.bundle(for: draft, title: reading.title, version: reading.version, fileName: reading.fileName).0
        }
        for chart in bundle.charts { _ = try await charts.store(chart.data) }
        try await local.save(bundle)
        return bundle.manifest
    }

    static func isHex(_ s: String) -> Bool {
        s.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
    }

    static func stem(_ fileName: String) -> String { (fileName as NSString).deletingPathExtension }

    /// `site/build.py`'s slug rule, which `PatternBundle.slugCharacters` enforces on the phone: ASCII
    /// lowercase letters and digits, runs of anything else one dash. Diacritics fold first ("Café" →
    /// "cafe"); a title with no ASCII letters at all becomes "pattern", made unique by `uniqueSlug`.
    static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = ""
        var dash = false
        for ch in folded.unicodeScalars {
            if (ch.value >= 0x61 && ch.value <= 0x7a) || (ch.value >= 0x30 && ch.value <= 0x39) {
                out.unicodeScalars.append(ch)
                dash = false
            } else if !dash, !out.isEmpty {
                out += "-"
                dash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "pattern" : out
    }

    static func uniqueSlug(_ base: String, in store: LocalPatternStore) async -> String {
        var slug = base
        var n = 2
        while await store.has(id: slug) {
            slug = "\(base)-\(n)"
            n += 1
        }
        return slug
    }

    static func today() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "en_GB")
        return f.string(from: Date())
    }

    static func describe(_ error: OwnPDFError) -> String {
        switch error {
        case .noChartHeader: return "no chart header"
        case .badRow(let page, let text): return "page \(page), \"\(text.prefix(40))\""
        case .rowsDoNotMatch(let why): return why
        case .tooLarge(let w, let h): return "\(w) × \(h) is bigger than the app can work"
        }
    }
}

/// How far a read has got, for the sheet (spec §5.2): pages while PDFKit extracts text, rows while
/// the model reads them.
enum PDFImportProgress: Sendable, Equatable {
    case pages(done: Int, of: Int)
    case rows(done: Int, of: Int, secondsElapsed: Int)
    case checking(done: Int, of: Int)
}

/// Which reader made the chart, for the sheet's and the detail screen's sentences.
enum PDFImportSource: Sendable, Equatable {
    case ownPDF
    /// A chart read off a page's grid (1-based page); `rowsToCheck` written rows follow, or none.
    case grid(page: Int, rowsToCheck: Int)
    case writtenRows(count: Int, gaugePrinted: Bool)
}

struct PDFImportReading: Sendable {
    let bundle: PatternBundle
    let preview: Data
    let width: Int
    let height: Int
    let colours: Int
    let source: PDFImportSource
    /// What was assembled, so "Add to library" can write the check's record into it (§6.3).
    let draft: ChartDraft
    let title: String
    let version: String
    let fileName: String
    let pageTexts: [String]
    let warnings: [String]
}

/// Why a PDF was refused; `message` is the sentence the sheet shows (phone import spec §5.4).
enum PDFImportError: Error, Equatable {
    case tooBig
    case cannotOpen
    case nothingFound
    case rowsArePictures
    case needsAppleIntelligence
    case rowsDoNotAssemble([String])
    case invalidChart(String)
    case badRow(OwnPDFError)
    case cancelled

    var message: String {
        switch self {
        case .tooBig: return "That file is too big to be a pattern."
        case .cannotOpen: return "That PDF couldn't be opened."
        case .nothingFound: return "No chart or written rows were found in this PDF."
        case .rowsArePictures: return "This pattern's rows are printed as a picture; the app can't read that yet."
        case .needsAppleIntelligence:
            return "Reading written rows needs Apple Intelligence on this iPhone. Open the PDF on a Mac with graphghan, or send a .graphghan file instead."
        case .rowsDoNotAssemble(let why): return "The written rows in this PDF don't add up: \(why.joined(separator: "; "))."
        case .invalidChart(let why): return "The chart in this PDF isn't one the app can work: \(why)."
        case .badRow(.tooLarge(let w, let h)): return "The chart in this PDF is too big for the app: \(w) × \(h) stitches."
        case .badRow(let error): return "A written row in this PDF couldn't be read (\(PDFImporter.describe(error)))."
        case .cancelled: return ""
        }
    }
}

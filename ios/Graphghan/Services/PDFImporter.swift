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
        // PR 2 and 3 of the phone import add the written-row and grid readers here.
        guard OwnPDFReader.isOwn(pageTexts: texts) else { throw .nothingFound }
        let reading: OwnPDFReading
        do {
            reading = try OwnPDFReader.read(pageTexts: texts, title: title.isEmpty ? Self.stem(fileName) : title)
        } catch let error as OwnPDFError {
            throw .badRow(error)  // the reader's own error travels with the sentence
        } catch {
            throw .invalidChart("\(error)")
        }
        let title2 = reading.pattern.title.isEmpty ? Self.stem(fileName) : reading.pattern.title
        let slug = await Self.uniqueSlug(Self.slug(title2), in: local)
        let draft = ChartWriter.draft(from: reading, id: slug)
        let (chartData, chartID) = ChartWriter.encode(draft)
        let chart: Chart
        do { chart = try Chart.load(chartData) } catch { throw .invalidChart("\(error)") }
        guard let preview = ChartPreview.png(chart) else { throw .invalidChart("no preview") }
        let gaugeKey = draft.gauge.stitch ?? "sc"
        let dedication = "Imported from \(fileName) on \(Self.today())"
        let manifestData = ManifestWriter.encode(id: slug, title: title2, version: reading.pattern.version, dedication: dedication,
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
    case badRow(OwnPDFError)

    var message: String {
        switch self {
        case .tooBig: return "That file is too big to be a pattern."
        case .cannotOpen: return "That PDF couldn't be opened."
        case .nothingFound: return "No chart or written rows were found in this PDF."
        case .invalidChart(let why): return "The chart in this PDF isn't one the app can work: \(why)."
        case .badRow(let error): return "A written row in this PDF couldn't be read (\(PDFImporter.describe(error)))."
        }
    }
}

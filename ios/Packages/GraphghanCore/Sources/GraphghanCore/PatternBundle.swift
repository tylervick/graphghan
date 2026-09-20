import Foundation

/// A `.graphghan` file: a whole pattern as one document, read and validated in memory.
///
/// The format is `docs/chart-format.md` §Bundle — a zip with `pattern.json` at the root plus the
/// chart files and previews it references at their relative paths, which are the same relative
/// paths the site serves. Nothing here knows how the file arrived.
///
/// `read` is all-or-nothing on purpose: the importer stores charts and writes a pattern directory
/// only after this has succeeded, which is what makes a broken bundle leave the library untouched
/// (design spec §6.2).
public struct PatternBundle: Sendable {
    public let manifest: PatternManifest
    /// The manifest's bytes exactly as the bundle carried them. A local pattern's `pattern.json`
    /// is written back from these rather than re-encoded, so the copy on the phone is the file
    /// that arrived -- `PatternManifest` is `Decodable` only, and a hand-written encoder beside
    /// it would be a second definition of the manifest to keep in step.
    public let manifestData: Data
    /// In the order the manifest lists them, default first.
    public let charts: [BundleChart]
    /// Manifest-relative path to PNG bytes: the pattern preview and each chart's.
    public let previews: [String: Data]

    public init(manifest: PatternManifest, manifestData: Data, charts: [BundleChart], previews: [String: Data]) {
        self.manifest = manifest
        self.manifestData = manifestData
        self.charts = charts
        self.previews = previews
    }

    public static let manifestName = "pattern.json"

    /// A slug becomes a directory name on the phone, so it is checked the way `site/build.py`
    /// checks it before making a directory out of one: refused, never sanitised.
    static let slugCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")

    public static func read(_ data: Data) throws -> PatternBundle {
        let archive: ZipArchive
        do { archive = try ZipArchive(data) } catch let error as ZipArchive.ZipError {
            throw BundleError.badArchive(error)
        }

        guard archive.contains(manifestName) else { throw BundleError.noManifest }
        let manifestData = try read(manifestName, from: archive)
        let manifest: PatternManifest
        do { manifest = try JSONDecoder().decode(PatternManifest.self, from: manifestData) } catch {
            throw BundleError.badManifest("\(error)")
        }

        guard manifest.schema == 1 else { throw BundleError.unsupportedManifestSchema(manifest.schema) }
        guard !manifest.id.isEmpty,
              manifest.id.unicodeScalars.allSatisfy(slugCharacters.contains) else {
            throw BundleError.badPatternID(manifest.id)
        }
        guard !manifest.charts.isEmpty else { throw BundleError.noCharts }
        var seen = Set<String>()
        for entry in manifest.charts where !seen.insert(entry.path).inserted {
            throw BundleError.duplicateChartPath(entry.path)
        }

        var charts: [BundleChart] = []
        for entry in manifest.charts {
            let chartData = try read(entry.path, from: archive)
            let chart: Chart
            // The same decode and validation a downloaded chart gets -- an imported chart is not
            // trusted more for having arrived as a file.
            do { chart = try Chart.load(chartData) } catch {
                throw BundleError.invalidChart(path: entry.path, reason: describe(error))
            }
            guard chart.id == entry.id else {
                throw BundleError.chartIDMismatch(path: entry.path, expected: entry.id, found: chart.id)
            }
            charts.append(BundleChart(entry: entry, chart: chart, data: chartData))
        }

        var previews: [String: Data] = [:]
        for path in [manifest.preview] + manifest.charts.map(\.preview) where !path.isEmpty {
            previews[path] = try read(path, from: archive)
        }

        return PatternBundle(manifest: manifest, manifestData: manifestData, charts: charts, previews: previews)
    }

    private static func read(_ name: String, from archive: ZipArchive) throws -> Data {
        do { return try archive.data(named: name) } catch ZipArchive.ZipError.notFound {
            throw BundleError.missingFile(name)
        } catch let error as ZipArchive.ZipError {
            throw BundleError.badArchive(error)
        }
    }

    private static func describe(_ error: any Error) -> String {
        (error as? ChartError).map(String.init(describing:)) ?? String(describing: error)
    }
}

/// One chart out of a bundle: what the manifest says about it, the validated chart, and the exact
/// bytes, which is what `ChartLibrary` stores (a re-encode would change the file, not the id).
public struct BundleChart: Sendable {
    public let entry: ManifestChart
    public let chart: Chart
    public let data: Data

    public init(entry: ManifestChart, chart: Chart, data: Data) {
        self.entry = entry
        self.chart = chart
        self.data = data
    }
}

/// Why a bundle was refused. `message` is the sentence the app shows: about the file, not about
/// the parser. It lives here, beside the condition, so "a broken bundle reports why" is testable
/// without a screen.
public enum BundleError: Error, Equatable {
    case badArchive(ZipArchive.ZipError)
    case noManifest
    case badManifest(String)
    case unsupportedManifestSchema(Int)
    case badPatternID(String)
    case noCharts
    case duplicateChartPath(String)
    case missingFile(String)
    case invalidChart(path: String, reason: String)
    case chartIDMismatch(path: String, expected: String, found: String)

    public var message: String {
        switch self {
        case .badArchive(let error):
            switch error {
            case .notAZip:
                return "That file isn't a Graphghan pattern."
            case .entryTooLarge, .archiveTooLarge, .tooManyEntries:
                return "That pattern is far too big to be a chart. It wasn't opened."
            case .encrypted:
                return "That pattern file is password-protected, which Graphghan can't open."
            case .zip64, .multiDisk, .dataDescriptor, .unsupportedMethod:
                return "That pattern file was packed in a way Graphghan can't read."
            case .unsafeName(let name), .malformedName(let name):
                return "That pattern file contains a suspicious entry (\(name)) and wasn't opened."
            case .truncated, .corrupt, .notFound:
                return "That pattern file is damaged."
            }
        case .noManifest:
            return "That file isn't a Graphghan pattern: it has no pattern.json."
        case .badManifest:
            return "This pattern's details couldn't be read."
        case .unsupportedManifestSchema(let schema):
            return "This pattern was made by a newer version of Graphghan (format \(schema))."
        case .badPatternID(let id):
            return "This pattern has an invalid name (\(id))."
        case .noCharts:
            return "This pattern has no charts in it."
        case .duplicateChartPath(let path):
            return "This pattern lists \(path) twice."
        case .missingFile(let path):
            return "This pattern is missing the file it lists as \(path)."
        case .invalidChart(let path, let reason):
            return "This pattern's chart \(path) isn't usable: \(reason)."
        case .chartIDMismatch(let path, _, _):
            return "This pattern's chart \(path) doesn't match what the pattern says it is."
        }
    }
}

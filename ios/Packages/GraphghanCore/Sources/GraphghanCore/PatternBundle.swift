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
    /// Each written piece's rows document, in the manifest's order. Empty for a manifest without
    /// pieces, or a pieced manifest whose pieces are all charts.
    public let rows: [BundleRows]

    public init(manifest: PatternManifest, manifestData: Data, charts: [BundleChart], previews: [String: Data], rows: [BundleRows] = []) {
        self.manifest = manifest
        self.manifestData = manifestData
        self.charts = charts
        self.previews = previews
        self.rows = rows
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

        try validate(manifest)

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

        var rows: [BundleRows] = []
        for piece in manifest.pieces ?? [] where piece.rows != nil {
            let path = piece.rows!
            let rowsData = try read(path, from: archive)
            let document: RowsDocument
            do { document = try RowsDocument.load(rowsData) } catch {
                throw BundleError.invalidRows(path: path, reason: describe(error))
            }
            guard document.id == piece.rowsID else {
                throw BundleError.rowsIDMismatch(path: path, expected: piece.rowsID ?? "", found: document.id)
            }
            rows.append(BundleRows(piece: piece, document: document, data: rowsData))
        }

        var previews: [String: Data] = [:]
        for path in [manifest.preview] + manifest.charts.map(\.preview) where !path.isEmpty {
            previews[path] = try read(path, from: archive)
        }

        return PatternBundle(manifest: manifest, manifestData: manifestData, charts: charts, previews: previews, rows: rows)
    }

    /// The manifest-level checks `read` makes before it opens any file the manifest names: the
    /// schema, the pattern id, the pieces and the paths. Public so the phone's own pieced save
    /// refuses, before writing anything, a manifest `read` would later refuse.
    public static func validate(_ manifest: PatternManifest) throws {
        guard GraphghanCore.manifestSchemas.contains(manifest.schema) else {
            throw BundleError.unsupportedManifestSchema(manifest.schema)
        }
        if manifest.pieces != nil, manifest.schema != 2 { throw BundleError.piecedNeedsSchema2 }
        guard !manifest.id.isEmpty,
              manifest.id.unicodeScalars.allSatisfy(slugCharacters.contains) else {
            throw BundleError.badPatternID(manifest.id)
        }
        if manifest.isPieced {
            guard !(manifest.pieces ?? []).isEmpty else { throw BundleError.noPieces }
        } else {
            guard !manifest.charts.isEmpty else { throw BundleError.noCharts }
        }
        var seen = Set<String>()
        for entry in manifest.charts where !seen.insert(entry.path).inserted {
            throw BundleError.duplicateChartPath(entry.path)
        }

        // A piece is exactly one of a chart (naming a `charts[]` entry) or written rows (with its
        // id); checked before the paths are, so its rows files join the paths every entry needs.
        var rowsPaths: [String] = []
        if let pieces = manifest.pieces {
            let chartIDs = Set(manifest.charts.map(\.id))
            var pieceIDs = Set<String>()
            var namedCharts = Set<String>()
            var firstChartPiece: String?
            for piece in pieces {
                guard pieceIDs.insert(piece.id).inserted else { throw BundleError.duplicatePiece(piece: piece.id) }
                guard piece.make >= 1 else { throw BundleError.pieceMakeCount(piece: piece.id, make: piece.make) }
                switch (piece.chart, piece.rows) {
                case (let chartID?, nil):
                    guard chartIDs.contains(chartID) else { throw BundleError.pieceNamesMissingChart(piece: piece.id) }
                    // Spec §5.3: each chart once. The same grid twice is one piece made twice.
                    guard namedCharts.insert(chartID).inserted else { throw BundleError.pieceSharesChart(piece: piece.id) }
                    if firstChartPiece == nil { firstChartPiece = chartID }
                case (nil, let path?):
                    guard piece.rowsID != nil else { throw BundleError.pieceKind(piece: piece.id) }
                    rowsPaths.append(path)
                default:
                    throw BundleError.pieceKind(piece: piece.id)
                }
            }
            // Spec §5.3, as `validate_manifest` has it (#228): `charts` lists only the charts the
            // pieces name, and the default is the first chart piece's, so a reader that knows
            // nothing of pieces opens on the first piece.
            if let unnamed = manifest.charts.first(where: { !namedCharts.contains($0.id) }) {
                throw BundleError.chartNamedByNoPiece(path: unnamed.path)
            }
            if let first = firstChartPiece, let def = manifest.charts.first(where: \.isDefault), def.id != first {
                throw BundleError.defaultNotFirstChartPiece
            }
        }

        // An absent manifest-level `preview` decodes to "" (schema 1 and 2 both allow omitting
        // it); every other path here is still required by its owner (a chart, a written piece)
        // and an empty one is a lie about that file, not "no file" -- it stays checked.
        try checkPaths([manifestName] + (manifest.preview.isEmpty ? [] : [manifest.preview])
            + manifest.charts.map(\.path) + manifest.charts.map(\.preview) + rowsPaths)
    }

    /// Every referenced path has to be writable as a file under one directory, because that is
    /// what the app does with them. The zip reader has already refused traversal; what is left is
    /// a path that cannot become a file *here*: an empty or `.` component, which a store would
    /// silently skip, and a path nested under another referenced path, which would need
    /// `pattern.json` to be a file and a directory at once — that one fails halfway through the
    /// write, after the charts are already stored.
    private static func checkPaths(_ paths: [String]) throws {
        for path in paths {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty, !parts.contains(where: { $0.isEmpty || $0 == "." }) else {
                throw BundleError.unusablePath(path)
            }
        }
        for path in paths {
            for other in paths where other != path && other.hasPrefix(path + "/") {
                throw BundleError.unusablePath(other)
            }
        }
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

/// A written piece's document in a pieced bundle.
public struct BundleRows: Sendable {
    public let piece: ManifestPiece
    public let document: RowsDocument
    public let data: Data
    public init(piece: ManifestPiece, document: RowsDocument, data: Data) { self.piece = piece; self.document = document; self.data = data }
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
    /// A referenced path that cannot be written as a file under the pattern's directory.
    case unusablePath(String)
    case invalidChart(path: String, reason: String)
    case chartIDMismatch(path: String, expected: String, found: String)
    /// A manifest whose `pieces` is present but whose `schema` is not 2.
    case piecedNeedsSchema2
    /// A pieced manifest (`pieces` present) that lists none.
    case noPieces
    /// A chart piece names a `charts[].id` the manifest doesn't carry.
    case pieceNamesMissingChart(piece: String)
    /// A piece with neither `chart` nor `rows`, both, or a written piece with no `rows_id`.
    case pieceKind(piece: String)
    /// Two pieces share an id: progress keys a piece copy by it.
    case duplicatePiece(piece: String)
    /// A chart piece names a chart an earlier piece already names (spec §5.3: each chart once).
    case pieceSharesChart(piece: String)
    /// A piece whose `make` is below 1.
    case pieceMakeCount(piece: String, make: Int)
    /// A pieced manifest lists a chart no piece names (spec §5.3).
    case chartNamedByNoPiece(path: String)
    /// A pieced manifest's default chart is not the first chart piece's (spec §5.3).
    case defaultNotFirstChartPiece
    case invalidRows(path: String, reason: String)
    case rowsIDMismatch(path: String, expected: String, found: String)

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
            case .unsafeName(let name), .malformedName(let name), .duplicateName(let name):
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
        case .unusablePath(let path):
            return "This pattern lists a file at a path that can't be saved (\(path))."
        case .invalidChart(let path, let reason):
            return "This pattern's chart \(path) isn't usable: \(reason)."
        case .chartIDMismatch(let path, _, _):
            return "This pattern's chart \(path) doesn't match what the pattern says it is."
        case .piecedNeedsSchema2:
            return "This pattern lists its pieces in a format this version of Graphghan doesn't recognise."
        case .noPieces:
            return "This pattern says it is made of pieces but lists none."
        case .pieceNamesMissingChart(let piece):
            return "The piece “\(piece)” names a chart this file doesn't contain."
        case .pieceKind(let piece):
            return "The piece “\(piece)” is neither a chart nor written rows."
        case .duplicatePiece(let piece):
            return "Two pieces are both called “\(piece)”."
        case .pieceSharesChart(let piece):
            return "The piece “\(piece)” names the same chart as another piece."
        case .pieceMakeCount(let piece, let make):
            return "The piece “\(piece)” is to be made \(make) times."
        case .chartNamedByNoPiece(let path):
            return "This pattern lists the chart \(path), but no piece uses it."
        case .defaultNotFirstChartPiece:
            return "This pattern opens on a chart that isn't its first piece's."
        case .invalidRows(let path, let reason):
            return "The written rows in \(path) can't be used: \(reason)."
        case .rowsIDMismatch(let path, _, _):
            return "The written rows in \(path) don't match what the pattern lists."
        }
    }
}

import Foundation

/// One row of the site's `patterns/index.json`.
public struct IndexEntry: Decodable, Sendable, Identifiable, Hashable {
    public let slug: String
    public let title: String
    public let dedication: String
    public let version: String
    public let stitch: String
    public let width: Int
    public let height: Int
    public let sizeIn: [Double]
    public let colors: Int
    public let preview: String
    public let manifest: String?
    public let charts: Int?
    public var id: String { slug }
    enum CodingKeys: String, CodingKey {
        case slug, title, dedication, version, stitch, width, height, colors, preview, manifest, charts
        case sizeIn = "size_in"
    }

    public init(slug: String, title: String, dedication: String, version: String, stitch: String,
                width: Int, height: Int, sizeIn: [Double], colors: Int, preview: String,
                manifest: String?, charts: Int?) {
        self.slug = slug
        self.title = title
        self.dedication = dedication
        self.version = version
        self.stitch = stitch
        self.width = width
        self.height = height
        self.sizeIn = sizeIn
        self.colors = colors
        self.preview = preview
        self.manifest = manifest
        self.charts = charts
    }

    /// The row a pattern would have in the site's `index.json`, computed from its manifest — the
    /// same projection `site/build.py`'s `index_entry` makes, so a pattern opened from a file
    /// reads like one from the feed. `preview` is the manifest-relative path, not a site path:
    /// a local pattern's previews are resolved against its own directory.
    public init(manifest: PatternManifest) {
        let chart = manifest.defaultChart
        // The index always quotes inches, whatever unit the gauge is stated in (#48).
        let inches: [Double] = if let size = chart?.size {
            size.unit == "cm" ? [(size.width / 2.54 * 10).rounded() / 10, (size.height / 2.54 * 10).rounded() / 10]
                              : [size.width, size.height]
        } else { [] }
        self.init(slug: manifest.id, title: manifest.title, dedication: manifest.dedication,
                  version: manifest.version, stitch: chart?.stitch ?? "",
                  width: chart?.width ?? 0, height: chart?.height ?? 0, sizeIn: inches,
                  colors: chart.map { $0.colors } ?? manifest.palette.count,
                  preview: manifest.preview, manifest: nil, charts: manifest.charts.count)
    }
}

public struct Swatch: Decodable, Sendable, Equatable {
    public let code: String
    public let name: String
    public let hex: String
}

/// One published chart in a pattern manifest. Paths are relative to `patterns/<id>/` on the site.
public struct ManifestChart: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public struct Size: Decodable, Sendable, Equatable, Hashable {
        public let width: Double
        public let height: Double
        public let unit: String
    }
    public struct Changes: Decodable, Sendable, Equatable, Hashable {
        public let mean: Double
        public let max: Double
    }
    public let id: String
    public let variant: String
    public let gaugeKey: String
    public let isDefault: Bool
    public let path: String
    public let preview: String
    public let width: Int
    public let height: Int
    /// Absent, not a placeholder, when the chart's gauge and cell kind do not count the same
    /// thing (#48) -- `manifest.py` omits the key entirely, so a reader that demands it refuses a
    /// manifest this repo's own exporter validly produces.
    public let size: Size?
    public let stitch: String
    public let colors: Int
    public let stitches: Int
    public let changesPerRow: Changes
    public let yardsEst: Int
    public var key: String { "\(variant)-\(gaugeKey)" }
    /// "54 × 46 in", or nil when the chart has no stated finished size.
    public var sizeLabel: String? {
        guard let size else { return nil }
        return "\(size.width.formatted()) × \(size.height.formatted()) \(size.unit)"
    }
    enum CodingKeys: String, CodingKey {
        case id, variant, path, preview, width, height, size, stitch, colors, stitches
        case gaugeKey = "gauge_key", isDefault = "default", changesPerRow = "changes_per_row", yardsEst = "yards_est"
    }
}

/// One piece of a pieced pattern (manifest schema 2, spec 2026-09-25 §5.3): a chart, or a
/// written-rows document for a piece that is not a grid. Worked `make` times.
public struct ManifestPiece: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let make: Int
    /// A `charts[].id`, for a chart piece.
    public let chart: String?
    /// The rows document's path in the bundle, and its id, for a written piece.
    public let rows: String?
    public let rowsID: String?
    /// Pages of the source PDF this piece comes from.
    public let pages: [Int]
    public var isWritten: Bool { rows != nil }

    enum CodingKeys: String, CodingKey { case id, title, make, chart, rows, pages; case rowsID = "rows_id" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        make = try c.decodeIfPresent(Int.self, forKey: .make) ?? 1
        chart = try c.decodeIfPresent(String.self, forKey: .chart)
        rows = try c.decodeIfPresent(String.self, forKey: .rows)
        rowsID = try c.decodeIfPresent(String.self, forKey: .rowsID)
        pages = try c.decodeIfPresent([Int].self, forKey: .pages) ?? []
    }
}

/// One step of putting the pieces together. A step with only pages points into the source PDF.
public struct AssemblyStep: Decodable, Sendable, Equatable, Hashable {
    public let title: String
    public let text: String?
    public let pages: [Int]
    enum CodingKeys: String, CodingKey { case title, text, pages }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        pages = try c.decodeIfPresent([Int].self, forKey: .pages) ?? []
    }
}

/// `patterns/<id>/pattern.json` (manifest schema 1, or 2 with pieces).
public struct PatternManifest: Decodable, Sendable, Equatable {
    public let schema: Int
    public let id: String
    public let title: String
    public let version: String
    public let dedication: String
    public let quote: String
    public let author: String
    public let license: String
    public let preview: String
    public let palette: [Swatch]
    public let charts: [ManifestChart]
    public let updated: String
    /// Manifest schema 2's pieces, in the pattern's order; nil for a manifest without them, which
    /// is one piece: the default chart.
    public let pieces: [ManifestPiece]?
    /// Putting the pieces together; empty when the manifest has none.
    public let assembly: [AssemblyStep]
    public var isPieced: Bool { pieces != nil }
    /// Piece copies to make: the sum of `make`, or 1 for a manifest without pieces.
    public var piecesTotal: Int { pieces?.reduce(0) { $0 + $1.make } ?? 1 }
    public var defaultChart: ManifestChart? { charts.first(where: \.isDefault) ?? charts.first }

    enum CodingKeys: String, CodingKey {
        case schema, id, title, version, dedication, quote, author, license, preview, palette, charts, updated
        case pieces, assembly
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        version = try c.decode(String.self, forKey: .version)
        dedication = try c.decode(String.self, forKey: .dedication)
        quote = try c.decode(String.self, forKey: .quote)
        author = try c.decode(String.self, forKey: .author)
        license = try c.decode(String.self, forKey: .license)
        preview = try c.decode(String.self, forKey: .preview)
        palette = try c.decode([Swatch].self, forKey: .palette)
        charts = try c.decode([ManifestChart].self, forKey: .charts)
        updated = try c.decode(String.self, forKey: .updated)
        pieces = try c.decodeIfPresent([ManifestPiece].self, forKey: .pieces)
        assembly = try c.decodeIfPresent([AssemblyStep].self, forKey: .assembly) ?? []
    }

    public init(schema: Int, id: String, title: String, version: String, dedication: String, quote: String,
                author: String, license: String, preview: String, palette: [Swatch], charts: [ManifestChart],
                updated: String, pieces: [ManifestPiece]? = nil, assembly: [AssemblyStep] = []) {
        self.schema = schema
        self.id = id
        self.title = title
        self.version = version
        self.dedication = dedication
        self.quote = quote
        self.author = author
        self.license = license
        self.preview = preview
        self.palette = palette
        self.charts = charts
        self.updated = updated
        self.pieces = pieces
        self.assembly = assembly
    }
}

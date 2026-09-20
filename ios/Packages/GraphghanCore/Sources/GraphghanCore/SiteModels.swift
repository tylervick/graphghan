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

/// `patterns/<id>/pattern.json` (manifest schema 1).
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
    public var defaultChart: ManifestChart? { charts.first(where: \.isDefault) ?? charts.first }
}

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

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.slug = try container.decode(String.self, forKey: .slug)
        self.title = try container.decode(String.self, forKey: .title)
        self.dedication = try container.decode(String.self, forKey: .dedication)
        self.version = try container.decode(String.self, forKey: .version)
        self.stitch = try container.decode(String.self, forKey: .stitch)
        self.width = try container.decode(Int.self, forKey: .width)
        self.height = try container.decode(Int.self, forKey: .height)
        self.sizeIn = try container.decode([Double].self, forKey: .sizeIn)
        self.colors = try container.decode(Int.self, forKey: .colors)
        self.preview = try container.decode(String.self, forKey: .preview)
        self.manifest = try container.decodeIfPresent(String.self, forKey: .manifest)
        self.charts = try container.decodeIfPresent(Int.self, forKey: .charts)
    }
}

public struct Swatch: Decodable, Sendable, Equatable {
    public let code: String
    public let name: String
    public let hex: String
}

/// One published chart in a pattern manifest. Paths are relative to `patterns/<id>/` on the site.
public struct ManifestChart: Decodable, Sendable, Identifiable, Equatable {
    public struct Size: Decodable, Sendable, Equatable {
        public let width: Double
        public let height: Double
        public let unit: String
    }
    public struct Changes: Decodable, Sendable, Equatable {
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
    public let size: Size
    public let stitch: String
    public let colors: Int
    public let stitches: Int
    public let changesPerRow: Changes
    public let yardsEst: Int
    public var key: String { "\(variant)-\(gaugeKey)" }
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

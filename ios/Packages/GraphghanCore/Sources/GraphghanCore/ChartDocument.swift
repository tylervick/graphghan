import Foundation

/// A chart document exactly as written (schema 2). Unknown keys are ignored; `technique` and
/// `passes` are kept raw because the chart id hashes them verbatim.
public struct ChartDocument: Decodable, Sendable {
    public struct PatternInfo: Decodable, Sendable {
        public let id: String
        public let title: String
        public let version: String
        public let author: String?
        public let license: String?
        public let dedication: String?
        public let quote: String?
        public let url: String?
        public let craft: String?
        public let language: String?
    }

    public struct ChartInfo: Decodable, Sendable {
        public let id: String
        public let variant: String?
        public let gaugeKey: String?
        public let width: Int
        public let height: Int
        enum CodingKeys: String, CodingKey { case id, variant, gaugeKey = "gauge_key", width, height }
    }

    public struct GeneratorInfo: Decodable, Sendable {
        public let name: String?
        public let version: String?
    }

    public struct PaletteEntry: Decodable, Sendable, Equatable {
        public struct Thread: Decodable, Sendable, Equatable {
            public let system: String
            public let number: String
        }
        public let code: String
        public let name: String
        public let hex: String
        public let yarn: [String: String]?
        public let thread: Thread?
        public let use: String?
        public let symbol: String?
    }

    public struct Layer: Decodable, Sendable, Equatable {
        public let legend: [String: String]
        public let rows: [String]
    }

    public struct Gauge: Decodable, Sendable {
        public struct Over: Decodable, Sendable {
            public let value: Double
            public let unit: String
        }
        public let stitches: Double
        public let rows: Double
        public let over: Over
        public let stitch: String?
        public let hook: String?
        public let yarnWeight: String?
        public let unit: String?
        public let stitchName: String?
        public let terms: Terms?
        public let termsAlso: Terms?
        /// nil when absent — and when present but not understood (an unknown `kind`, a missing
        /// `chain`), so a future kind reads as "no boundary" instead of failing the chart.
        public let boundary: Boundary?

        enum CodingKeys: String, CodingKey {
            case stitches, rows, over, stitch, hook, yarnWeight = "yarn_weight"
            case unit, stitchName = "stitch_name", terms, termsAlso = "terms_also", boundary
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            stitches = try c.decode(Double.self, forKey: .stitches)
            rows = try c.decode(Double.self, forKey: .rows)
            over = try c.decode(Over.self, forKey: .over)
            stitch = try c.decodeIfPresent(String.self, forKey: .stitch)
            hook = try c.decodeIfPresent(String.self, forKey: .hook)
            yarnWeight = try c.decodeIfPresent(String.self, forKey: .yarnWeight)
            unit = try c.decodeIfPresent(String.self, forKey: .unit)
            stitchName = try c.decodeIfPresent(String.self, forKey: .stitchName)
            terms = (try? c.decodeIfPresent(Terms.self, forKey: .terms)) ?? nil
            termsAlso = (try? c.decodeIfPresent(Terms.self, forKey: .termsAlso)) ?? nil
            boundary = (try? c.decodeIfPresent(Boundary.self, forKey: .boundary)) ?? nil
        }
    }

    public struct Instruction: Decodable, Sendable, Equatable {
        public let title: String
        public let text: String
    }

    /// Top-level `foundation`: authored, never cross-checked against `chart.width`.
    public struct Foundation: Decodable, Sendable, Equatable {
        public let chain: Int
        public let firstStitchIn: Int?
        public let note: String?
        enum CodingKeys: String, CodingKey { case chain, firstStitchIn = "first_stitch_in", note }
    }

    public let schema: Int
    public let pattern: PatternInfo
    public let chart: ChartInfo
    public let generator: GeneratorInfo?
    public let palette: [PaletteEntry]
    public let rows: [String]
    public let layers: [String: Layer]?
    public let gauge: Gauge
    public let technique: JSONValue
    public let passes: JSONValue?
    public let instructions: [Instruction]
    public let foundation: Foundation?

    enum CodingKeys: String, CodingKey {
        case schema, pattern, chart, generator, palette, rows, layers, gauge, technique, passes, instructions, foundation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        pattern = try c.decode(PatternInfo.self, forKey: .pattern)
        chart = try c.decode(ChartInfo.self, forKey: .chart)
        generator = try c.decodeIfPresent(GeneratorInfo.self, forKey: .generator)
        palette = try c.decode([PaletteEntry].self, forKey: .palette)
        rows = try c.decode([String].self, forKey: .rows)
        layers = try c.decodeIfPresent([String: Layer].self, forKey: .layers)
        gauge = try c.decode(Gauge.self, forKey: .gauge)
        technique = try c.decode(JSONValue.self, forKey: .technique)
        let rawPasses = try c.decodeIfPresent(JSONValue.self, forKey: .passes)
        passes = rawPasses == .null ? nil : rawPasses
        instructions = try c.decodeIfPresent([Instruction].self, forKey: .instructions) ?? []
        foundation = try c.decodeIfPresent(Foundation.self, forKey: .foundation)
    }

    public static func decode(_ data: Data) throws -> ChartDocument {
        try JSONDecoder().decode(ChartDocument.self, from: data)
    }

    public var techniqueType: String { technique["type"]?.stringValue ?? "" }
    public var techniqueStart: String { technique["start"]?.stringValue ?? "bottom" }
    public var techniqueFirstSide: String { technique["first_side"]?.stringValue ?? "RS" }
    public var techniqueRSDirection: String { technique["rs_direction"]?.stringValue ?? "rtl" }
}

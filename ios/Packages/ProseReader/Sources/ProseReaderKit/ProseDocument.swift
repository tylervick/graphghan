// The graphghan-import/1 document (schema/import-prose.schema.json) as the model produces it.
// Every field is optional in the schema; the reader fills what the text says and nothing else.

import Foundation
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "One run of stitches in a written crochet row")
public struct RunOut: Sendable {
    @Guide(description: "the number of stitches in this run")
    public var count: Int
    @Guide(description: "the colour exactly as the row names it: a code such as A, or a name such as White")
    public var code: String
}

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "One written row of a crochet chart, transcribed exactly as printed")
public struct WrittenRowOut: Sendable {
    @Guide(description: "the row number")
    public var row: Int
    @Guide(description: "every run in the order printed; a turning chain (ch 1, turn) is not a run; never add, merge or correct any")
    public var runs: [RunOut]
    @Guide(description: "the stitch count the row prints at its end, or 0 when it prints none")
    public var total: Int
}

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "The written rows found on one page of a crochet pattern")
public struct RowsPageOut: Sendable {
    @Guide(description: "every written row on the page, in the order printed; an empty list when the page has none")
    public var rows: [WrittenRowOut]
}

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "One colour of a pattern's key")
public struct ColourOut: Sendable {
    @Guide(description: "the letter or short code the pattern uses, or the name when it uses none")
    public var code: String
    @Guide(description: "the colour's name as printed")
    public var name: String
    @Guide(description: "the hex colour as #rrggbb when the key prints one, else empty")
    public var hex: String
}

@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "A crochet pattern's front matter: what it is, what it needs, how big")
public struct FrontOut: Sendable {
    @Guide(description: "the pattern's title, or empty") public var title: String
    @Guide(description: "the designer, or empty") public var author: String
    @Guide(description: "the hook size as printed, or empty") public var hook: String
    @Guide(description: "the yarn weight or yarn named, or empty") public var yarnWeight: String
    @Guide(description: "stitches in the gauge, or 0") public var gaugeStitches: Int
    @Guide(description: "rows in the gauge, or 0") public var gaugeRows: Int
    @Guide(description: "the length the gauge is measured over, or 0") public var gaugeOver: Int
    @Guide(description: "in, cm, or empty", .anyOf(["in", "cm", ""])) public var gaugeUnit: String
    @Guide(description: "the stitch the chart is worked in as its abbreviation, such as sc, or empty") public var stitch: String
    @Guide(description: "the chart's width in stitches when stated, or 0") public var width: Int
    @Guide(description: "the chart's height in rows when stated, or 0") public var height: Int
    @Guide(description: "the colour key in the order printed; empty when the page has none") public var colours: [ColourOut]
}

/// The JSON the Python importer consumes: `graphghan-import/1`.
public struct ProseDocument: Codable, Sendable {
    public struct Gauge: Codable, Sendable {
        public struct Over: Codable, Sendable { public var value: Int; public var unit: String }
        public var stitches: Int?
        public var rows: Int?
        public var over: Over?
        public var stitch: String?
        public var hook: String?
        public var yarn_weight: String?
    }
    public struct Palette: Codable, Sendable {
        public var code: String
        public var name: String
        public var hex: String?
        public var key_label: String?
    }
    public struct Chart: Codable, Sendable {
        public var width: Int?
        public var height: Int?
        public var row1: String = "bottom-right"
    }
    public struct Row: Codable, Sendable {
        public var row: Int
        public var page: Int
        public var text: String
        public var runs: [[RunValue]]
        public var total: Int?
        public var error: String?
    }
    /// A run is `[code, count]` in the schema: a two-element array of a string and an integer.
    public enum RunValue: Codable, Sendable {
        case code(String), count(Int)
        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Int.self) { self = .count(n) } else { self = .code(try c.decode(String.self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self { case .code(let s): try c.encode(s); case .count(let n): try c.encode(n) }
        }
    }
    public var schema = "graphghan-import/1"
    public var pattern: [String: String]?
    public var gauge: Gauge?
    public var palette: [Palette]?
    public var chart: Chart?
    public var written_rows: [Row]?
    public var uncertain: [String]?
}

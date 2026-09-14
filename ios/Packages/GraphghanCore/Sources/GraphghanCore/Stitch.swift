import Foundation

/// Terminology system of the abbreviations (docs/chart-format.md §Gauge). `dc`, `tr` and `htr`
/// collide between the two, so a reader never spells out without knowing which one applies.
public enum Terms: String, Codable, Sendable {
    case us = "US"
    case uk = "UK"
}

/// What happens at the end of a pass. Phase 1 readers act on `turn` and show nothing for the rest.
public enum BoundaryKind: String, Codable, Sendable {
    case turn, join, rejoin, spiral
    case `return`
}

public enum ChainColor: String, Codable, Sendable {
    case next, current
}

/// What one grid cell is. Absent from a document means `.stitch`.
///
/// A kind that is in this enum but not yet implemented (everything but `.stitch`) still opens the
/// chart: the stitch-derived numbers are withheld rather than computed wrongly. A kind *outside*
/// this enum is a different case and refuses the document — an unrecognised cardinality is one this
/// repo's writers did not produce and cannot reason about, so every number in it is suspect
/// (docs/superpowers/specs/2026-09-14-cell-cardinality-design.md §4.1, and the #50 tenet).
public enum CellKind: String, Codable, Sendable {
    case stitch, block, tile, motif, pair
}

/// `gauge.boundary`, exactly as authored. Never derived from the stitch: published patterns split
/// on the number (dc is ch 3 in 7 of 12 corpus patterns and ch 2 in the other 5).
public struct Boundary: Codable, Equatable, Sendable {
    public let kind: BoundaryKind
    public let chain: Int
    public let countsAsStitch: Bool
    public let color: ChainColor?

    public init(kind: BoundaryKind, chain: Int, countsAsStitch: Bool = false, color: ChainColor? = nil) {
        self.kind = kind; self.chain = chain; self.countsAsStitch = countsAsStitch; self.color = color
    }

    enum CodingKeys: String, CodingKey { case kind, chain, countsAsStitch = "counts_as_stitch", color }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(BoundaryKind.self, forKey: .kind)
        chain = try c.decode(Int.self, forKey: .chain)
        countsAsStitch = try c.decodeIfPresent(Bool.self, forKey: .countsAsStitch) ?? false
        color = try c.decodeIfPresent(ChainColor.self, forKey: .color)
    }
}

/// The stitch a chart is worked in, resolved from `gauge.stitch`, `gauge.terms`, `gauge.stitch_name`
/// and `gauge.boundary`. `name` is nil for an abbreviation the tables do not know and the chart
/// did not name; the UI then shows the abbreviation alone.
public struct Stitch: Equatable, Sendable {
    public let code: String
    public let terms: Terms
    public let boundary: Boundary?
    public let name: String?

    public init(code: String, terms: Terms, stitchName: String?, boundary: Boundary?) {
        self.code = code
        self.terms = terms
        self.boundary = boundary
        // The CYC table wins over stitch_name so a chart cannot rename `sc` (spec §6.1).
        self.name = StitchNames.name(code, terms: terms) ?? stitchName
    }
}

/// The Craft Yarn Council master abbreviation list, one table per terminology system.
public enum StitchNames {
    static let us: [String: String] = [
        "ch": "chain", "sl st": "slip stitch", "sc": "single crochet", "hdc": "half double crochet",
        "dc": "double crochet", "tr": "treble crochet", "dtr": "double treble crochet",
        "trtr": "triple treble crochet", "sc2tog": "single crochet 2 together",
        "dc2tog": "double crochet 2 together", "hdc2tog": "half double crochet 2 together",
        "fsc": "foundation single crochet", "fdc": "foundation double crochet",
    ]
    static let uk: [String: String] = [
        "ch": "chain", "ss": "slip stitch", "sl st": "slip stitch", "dc": "double crochet", "htr": "half treble",
        "tr": "treble", "dtr": "double treble", "trtr": "triple treble", "qtr": "quadruple treble",
        "dc2tog": "double crochet 2 together", "tr2tog": "treble 2 together",
    ]

    public static func name(_ code: String, terms: Terms) -> String? {
        let key = code.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        switch terms {
        case .us: return us[key]
        case .uk: return uk[key]
        }
    }
}

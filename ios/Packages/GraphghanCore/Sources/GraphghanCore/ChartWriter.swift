import Foundation

/// A chart document the phone assembles (phone import spec §5.3). Encoded with `CanonicalJSON`
/// so the bytes are the same every time and `chart.id` is the id `ChartID.compute` hashes, the
/// way the Mac computed it: codes, rows, technique and (when present) cell.
public struct ChartDraft: Sendable, Equatable {
    public struct Pattern: Sendable, Equatable {
        public var id: String
        public var title: String
        public var version: String
        public var author: String? = nil
        public var license: String? = nil
        public var dedication: String? = nil
        public var quote: String? = nil
        public init(id: String, title: String, version: String) {
            self.id = id
            self.title = title
            self.version = version
        }
    }
    public struct Palette: Sendable, Equatable {
        public let code: String
        public let name: String
        public let hex: String
        public var yarnNote: String? = nil
        /// What the colour is for, as the format's `use`; `noStitch` for a background (#205).
        public var use: String? = nil
        /// The `use` of a colour that is not a yarn: a shaped piece's background, which stays in the
        /// palette so the grid stays rectangular (the Python's `chart.no_stitch`).
        public static let noStitch = "no stitch"
        public init(code: String, name: String, hex: String, yarnNote: String? = nil, use: String? = nil) {
            self.code = code
            self.name = name
            self.hex = hex
            self.yarnNote = yarnNote
            self.use = use
        }
    }
    public struct Gauge: Sendable, Equatable {
        public var stitches: Double = 14
        public var rows: Double = 16
        public var overValue: Double = 4
        public var overUnit: String = "in"
        public var stitch: String? = nil
        public var hook: String? = nil
        public var yarnWeight: String? = nil
        public var stitchName: String? = nil
        public var terms: String? = nil
        public var chain: Int? = nil
        public init() {}
    }
    public var pattern: Pattern
    public var palette: [Palette]
    /// Top to bottom as displayed, the format's order; a written row 1 is the last of these.
    public var rows: [String]
    public var width: Int
    public var height: Int
    public var gauge: Gauge
    /// `ext.graphghan.import` and the like; nil for none. The id ignores it.
    public var ext: JSONValue? = nil
    public init(pattern: Pattern, palette: [Palette], rows: [String], width: Int, height: Int, gauge: Gauge, ext: JSONValue? = nil) {
        self.pattern = pattern
        self.palette = palette
        self.rows = rows
        self.width = width
        self.height = height
        self.gauge = gauge
        self.ext = ext
    }
}

public enum ChartWriter {
    /// The one technique the phone writes: rows from the bottom, RS first, right to left, turning.
    public static let techniqueRows: JSONValue = .object([
        "type": .string("rows"), "start": .string("bottom"), "first_side": .string("RS"),
        "rs_direction": .string("rtl"), "turn": .bool(true),
    ])

    public static func runString(_ runs: [(code: String, count: Int)]) -> String {
        runs.map { "\($0.count)\($0.code)" }.joined()
    }

    static func num(_ d: Double) -> JSONValue { d.rounded() == d && abs(d) < 1e15 ? .int(Int(d)) : .double(d) }

    public static func encode(_ draft: ChartDraft) -> (data: Data, id: String) {
        let codes = draft.palette.map(\.code)
        let id = ChartID.compute(codes: codes, rows: draft.rows, technique: techniqueRows, passes: nil)
        var pattern: [String: JSONValue] = [
            "id": .string(draft.pattern.id), "title": .string(draft.pattern.title), "version": .string(draft.pattern.version),
        ]
        if let a = draft.pattern.author { pattern["author"] = .string(a) }
        if let l = draft.pattern.license { pattern["license"] = .string(l) }
        if let d = draft.pattern.dedication { pattern["dedication"] = .string(d) }
        if let q = draft.pattern.quote { pattern["quote"] = .string(q) }
        var gauge: [String: JSONValue] = [
            "stitches": num(draft.gauge.stitches), "rows": num(draft.gauge.rows),
            "over": .object(["value": num(draft.gauge.overValue), "unit": .string(draft.gauge.overUnit)]),
        ]
        if let s = draft.gauge.stitch { gauge["stitch"] = .string(s) }
        if let h = draft.gauge.hook { gauge["hook"] = .string(h) }
        if let y = draft.gauge.yarnWeight { gauge["yarn_weight"] = .string(y) }
        if let n = draft.gauge.stitchName { gauge["stitch_name"] = .string(n) }
        if let t = draft.gauge.terms { gauge["terms"] = .string(t) }
        if let c = draft.gauge.chain {
            gauge["boundary"] = .object([
                "kind": .string("turn"), "chain": .int(c), "counts_as_stitch": .bool(false), "color": .string("next"),
            ])
        }
        var doc: [String: JSONValue] = [
            "schema": .int(2),
            "pattern": .object(pattern),
            "chart": .object(["id": .string(id), "width": .int(draft.width), "height": .int(draft.height)]),
            "generator": .object(["name": .string("graphghan-ios"), "version": .string("0.1.0")]),
            "palette": .array(draft.palette.map { p in
                var e: [String: JSONValue] = ["code": .string(p.code), "name": .string(p.name), "hex": .string(p.hex)]
                if let n = p.yarnNote { e["yarn"] = .object(["note": .string(n)]) }
                if let u = p.use { e["use"] = .string(u) }
                return .object(e)
            }),
            "rows": .array(draft.rows.map(JSONValue.string)),
            "gauge": .object(gauge),
            "technique": techniqueRows,
        ]
        if let ext = draft.ext { doc["ext"] = ext }
        return (Data(CanonicalJSON.encode(.object(doc)).utf8), id)
    }

    /// The draft an own PDF describes, under the library id it will have. The written rows are
    /// numbered from the bottom (`DIRECTION`: "Row 1 starts at the bottom right"), and the format
    /// stores rows top to bottom, so row 1 goes last; and an odd (RS) row is written in the order
    /// it is worked, right to left, so its runs are reversed back (`export.py` `written_rows`).
    public static func draft(from r: OwnPDFReading, id slug: String) -> ChartDraft {
        var pattern = ChartDraft.Pattern(id: slug, title: r.pattern.title, version: r.pattern.version)
        pattern.author = r.pattern.author
        pattern.license = r.pattern.license
        pattern.dedication = r.pattern.dedication
        pattern.quote = r.pattern.quote
        var gauge = ChartDraft.Gauge()
        if let g = r.gauge {
            gauge.stitches = g.stitches
            gauge.rows = g.rows
            gauge.overValue = g.over.value
            gauge.overUnit = g.over.unit
            gauge.hook = g.hook
            gauge.yarnWeight = g.yarnWeight
            gauge.stitchName = g.stitchName
            gauge.chain = g.chain
            gauge.stitch = stitchKey(for: g.stitchName)
        }
        gauge.terms = r.pattern.terms
        let rows = r.rows.sorted { $0.row > $1.row }.map { row -> String in
            let runs = row.runs.map { (code: $0.code, count: $0.count) }
            return runString(row.row % 2 == 1 ? runs.reversed() : runs)
        }
        return ChartDraft(
            pattern: pattern,
            palette: r.palette.map { ChartDraft.Palette(code: $0.code, name: $0.name, hex: $0.hex, yarnNote: $0.yarnNote) },
            rows: rows, width: r.width, height: r.height, gauge: gauge)
    }

    /// "single crochet" → "sc": the stitch key the format uses, from the name the cover prints.
    static func stitchKey(for name: String?) -> String? {
        switch name {
        case "single crochet": return "sc"
        case "half double crochet": return "hdc"
        case "double crochet": return "dc"
        case "treble crochet": return "tr"
        default: return nil
        }
    }
}

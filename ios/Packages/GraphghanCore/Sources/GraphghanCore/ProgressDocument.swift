import Foundation

/// Dates in progress documents: `2026-09-12T18:31:12Z` on output; fractional seconds accepted on input.
public enum ProgressDates {
    // Configured once below and never mutated again; concurrent reads (`.date(from:)`/`.string(from:)`)
    // are safe, so `nonisolated(unsafe)` is the smallest fix for Swift 6's global-actor-isolation check.
    private nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    public static func parse(_ s: String) -> Date? { plain.date(from: s) ?? fractional.date(from: s) }
    public static func format(_ d: Date) -> String { plain.string(from: d) }
}

public struct ProgressEventRecord: Codable, Equatable, Sendable {
    public let t: Date
    public let row: Int
    public let run: Int
    public let stitch: Int
    public let kind: EventKind
    public init(t: Date, row: Int, run: Int, stitch: Int = 0, kind: EventKind) { self.t = t; self.row = row; self.run = run; self.stitch = stitch; self.kind = kind }
    public var cursor: Cursor { Cursor(row: row, run: run, stitch: stitch) }

    enum CodingKeys: String, CodingKey { case t, row, run, stitch, kind }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Date.self, forKey: .t)
        row = try c.decode(Int.self, forKey: .row)
        run = try c.decode(Int.self, forKey: .run)
        stitch = try c.decodeIfPresent(Int.self, forKey: .stitch) ?? 0
        kind = try c.decode(EventKind.self, forKey: .kind)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t)
        try c.encode(row, forKey: .row)
        try c.encode(run, forKey: .run)
        if stitch != 0 { try c.encode(stitch, forKey: .stitch) }
        try c.encode(kind, forKey: .kind)
    }
}

/// Progress document, schema 1 (docs/chart-format.md). Every event records the cursor after the action.
public struct ProgressDocument: Codable, Equatable, Sendable {
    public var schema: Int
    public var patternID: String
    public var chartID: String?
    public var patternVersion: String?
    public var cursor: Cursor
    public var started: Date?
    public var finished: Date?
    public var events: [ProgressEventRecord]

    enum CodingKeys: String, CodingKey {
        case schema, cursor, started, finished, events
        case patternID = "pattern_id", chartID = "chart_id", patternVersion = "pattern_version"
    }

    public init(patternID: String, chartID: String?, patternVersion: String? = nil, cursor: Cursor, started: Date? = nil, finished: Date? = nil, events: [ProgressEventRecord] = []) {
        self.schema = GraphghanCore.progressSchema
        self.patternID = patternID; self.chartID = chartID; self.patternVersion = patternVersion
        self.cursor = cursor; self.started = started; self.finished = finished; self.events = events
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        patternID = try c.decode(String.self, forKey: .patternID)
        chartID = try c.decodeIfPresent(String.self, forKey: .chartID)
        patternVersion = try c.decodeIfPresent(String.self, forKey: .patternVersion)
        cursor = try c.decode(Cursor.self, forKey: .cursor)
        started = try c.decodeIfPresent(Date.self, forKey: .started)
        finished = try c.decodeIfPresent(Date.self, forKey: .finished)
        events = try c.decodeIfPresent([ProgressEventRecord].self, forKey: .events) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(patternID, forKey: .patternID)
        try c.encode(chartID, forKey: .chartID)  // nil encodes as null: the key is required by the schema
        try c.encodeIfPresent(patternVersion, forKey: .patternVersion)
        try c.encode(cursor, forKey: .cursor)
        try c.encodeIfPresent(started, forKey: .started)
        try c.encodeIfPresent(finished, forKey: .finished)
        try c.encode(events, forKey: .events)
    }

    public static func decode(_ data: Data) throws -> ProgressDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            guard let date = ProgressDates.parse(s) else {
                throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: "bad date \(s)")
            }
            return date
        }
        return try decoder.decode(ProgressDocument.self, from: data)
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, e in
            var c = e.singleValueContainer()
            try c.encode(ProgressDates.format(date))
        }
        return try encoder.encode(self)
    }

    /// A cursor-only document from the PWA's base64 `{slug,row,run}` code.
    public static func legacy(slug: String, row: Int, run: Int) -> ProgressDocument {
        ProgressDocument(patternID: slug, chartID: nil, cursor: Cursor(row: row, run: run))
    }
}

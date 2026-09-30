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

/// Which copy of which piece: a pieced project's unit of progress (spec 2026-09-25 §5.4).
public struct PieceKey: Hashable, Sendable, Codable {
    public let piece: String
    public let copy: Int
    public init(piece: String, copy: Int) { self.piece = piece; self.copy = copy }
}

public struct PieceProgressRecord: Codable, Equatable, Sendable {
    public let piece: String
    public let copy: Int
    public let docID: String
    public let cursor: Cursor
    public let finished: Date?
    public var key: PieceKey { PieceKey(piece: piece, copy: copy) }
    public init(piece: String, copy: Int, docID: String, cursor: Cursor, finished: Date?) {
        self.piece = piece; self.copy = copy; self.docID = docID; self.cursor = cursor; self.finished = finished
    }
    enum CodingKeys: String, CodingKey { case piece, copy, cursor, finished; case docID = "doc_id" }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(piece, forKey: .piece); try c.encode(copy, forKey: .copy); try c.encode(docID, forKey: .docID)
        try c.encode(cursor, forKey: .cursor); try c.encode(finished, forKey: .finished)  // null, not absent
    }
}

public struct PiecedEventRecord: Codable, Equatable, Sendable {
    public let t: Date
    public let piece: String
    public let copy: Int
    public let row: Int
    public let run: Int
    public let stitch: Int
    public let kind: EventKind
    public var key: PieceKey { PieceKey(piece: piece, copy: copy) }
    public var cursor: Cursor { Cursor(row: row, run: run, stitch: stitch) }
    public init(t: Date, piece: String, copy: Int, row: Int, run: Int, stitch: Int = 0, kind: EventKind) {
        self.t = t; self.piece = piece; self.copy = copy; self.row = row; self.run = run; self.stitch = stitch; self.kind = kind
    }
    enum CodingKeys: String, CodingKey { case t, piece, copy, row, run, stitch, kind }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Date.self, forKey: .t); piece = try c.decode(String.self, forKey: .piece); copy = try c.decode(Int.self, forKey: .copy)
        row = try c.decode(Int.self, forKey: .row); run = try c.decode(Int.self, forKey: .run)
        stitch = try c.decodeIfPresent(Int.self, forKey: .stitch) ?? 0; kind = try c.decode(EventKind.self, forKey: .kind)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t); try c.encode(piece, forKey: .piece); try c.encode(copy, forKey: .copy)
        try c.encode(row, forKey: .row); try c.encode(run, forKey: .run)
        if stitch != 0 { try c.encode(stitch, forKey: .stitch) }
        try c.encode(kind, forKey: .kind)
    }
}

/// Progress document, schema 2: a pieced project (spec 2026-09-25 §5.4).
public struct ProjectProgressDocument: Codable, Equatable, Sendable {
    public var schema: Int = 2
    public var patternID: String
    public var patternVersion: String?
    public var pieces: [PieceProgressRecord]
    public var current: PieceKey?
    public var assemblyDone: [Int]
    public var started: Date?
    public var finished: Date?
    public var events: [PiecedEventRecord]
    public init(patternID: String, patternVersion: String?, pieces: [PieceProgressRecord], current: PieceKey?, assemblyDone: [Int],
                started: Date?, finished: Date?, events: [PiecedEventRecord]) {
        self.patternID = patternID; self.patternVersion = patternVersion; self.pieces = pieces; self.current = current
        self.assemblyDone = assemblyDone; self.started = started; self.finished = finished; self.events = events
    }
    enum CodingKeys: String, CodingKey {
        case schema, pieces, current, started, finished, events
        case patternID = "pattern_id", patternVersion = "pattern_version", assemblyDone = "assembly_done"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        patternID = try c.decode(String.self, forKey: .patternID)
        patternVersion = try c.decodeIfPresent(String.self, forKey: .patternVersion)
        pieces = try c.decode([PieceProgressRecord].self, forKey: .pieces)
        current = try c.decodeIfPresent(PieceKey.self, forKey: .current)
        assemblyDone = try c.decodeIfPresent([Int].self, forKey: .assemblyDone) ?? []
        started = try c.decodeIfPresent(Date.self, forKey: .started)
        finished = try c.decodeIfPresent(Date.self, forKey: .finished)
        events = try c.decodeIfPresent([PiecedEventRecord].self, forKey: .events) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema)
        try c.encode(patternID, forKey: .patternID)
        try c.encodeIfPresent(patternVersion, forKey: .patternVersion)
        try c.encode(pieces, forKey: .pieces)
        try c.encodeIfPresent(current, forKey: .current)
        try c.encode(assemblyDone, forKey: .assemblyDone)
        try c.encodeIfPresent(started, forKey: .started)
        try c.encodeIfPresent(finished, forKey: .finished)
        try c.encode(events, forKey: .events)
    }

    /// Dates as the schema-1 document writes them (`ProgressDocument.decode`/`encode`'s date
    /// strategy, copied verbatim, so both documents write dates identically).
    public static func decode(_ data: Data) throws -> ProjectProgressDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            guard let date = ProgressDates.parse(s) else {
                throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: "bad date \(s)")
            }
            return date
        }
        return try decoder.decode(ProjectProgressDocument.self, from: data)
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
}

import CryptoKit
import Foundation

public enum RowsError: Error, Equatable {
    case unsupportedSchema(Int)
    case empty
    /// Row `row` is missing or printed twice where the entries should tile 1...N.
    case gap(row: Int)
    /// Only the last entry may be open-ended.
    case openNotLast(entry: Int)
    /// An entry with neither `to` nor `repeat`.
    case noEnd(entry: Int)
    case badRange(entry: Int)
    case badCount(entry: Int)
    case unknownCode(entry: Int, code: String)
    case idMismatch(expected: String, found: String)
    case malformed(String)
}

/// A written-rows document (schema 1, spec 2026-09-25 §5.2): a piece that is not a grid. Each
/// entry is one printed line whose rows share its text. Mirrors graphghan.rowsdoc.
public struct RowsDocument: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Decodable {
        public let label: String
        public let from: Int
        public let to: Int?
        public let text: String
        public let count: Int?
        public let code: String?
        public let repeatText: String?
        public init(label: String, from: Int, to: Int?, text: String, count: Int?, code: String?, repeatText: String?) {
            self.label = label; self.from = from; self.to = to; self.text = text; self.count = count; self.code = code; self.repeatText = repeatText
        }
        enum CodingKeys: String, CodingKey { case label, from, to, text, count, code; case repeatText = "repeat" }
    }
    public struct Note: Sendable, Equatable, Decodable { public let title: String; public let text: String }

    public let id: String
    public let title: String
    public let palette: [Swatch]
    public let entries: [Entry]
    public let pages: [Int]
    public let notes: [Note]

    private struct Raw: Decodable {
        struct Piece: Decodable { let title: String }
        struct Source: Decodable { let pages: [Int]? }
        let schema: Int
        let id: String
        let piece: Piece
        let palette: [Swatch]?
        let rows: [Entry]
        let source: Source?
        let notes: [Note]?
    }

    /// Decodes and validates: refuses what cannot be worked as written (gaps, a misplaced open end).
    public static func load(_ data: Data) throws -> RowsDocument {
        let raw: Raw
        do { raw = try JSONDecoder().decode(Raw.self, from: data) } catch { throw RowsError.malformed("\(error)") }
        guard raw.schema == GraphghanCore.rowsSchema else { throw RowsError.unsupportedSchema(raw.schema) }
        guard !raw.rows.isEmpty else { throw RowsError.empty }
        let codes = Set((raw.palette ?? []).map(\.code))
        // Two passes: the tiling shape (gaps, ranges, the open end) is checked in full before any
        // entry's count or code, so a document with both kinds of problem is refused for the
        // structural one -- the fixtures pin this (a gap fixture's first entry also uses a code
        // absent from its missing palette, but still refuses as a gap, not an unknown code).
        var expected = 1
        for (i, e) in raw.rows.enumerated() {
            guard e.from == expected else { throw RowsError.gap(row: expected) }
            if let to = e.to {
                guard to >= e.from else { throw RowsError.badRange(entry: i) }
                expected = to + 1
            } else {
                guard e.repeatText != nil else { throw RowsError.noEnd(entry: i) }
                guard i == raw.rows.count - 1 else { throw RowsError.openNotLast(entry: i) }
            }
        }
        for (i, e) in raw.rows.enumerated() {
            if let n = e.count, n < 1 { throw RowsError.badCount(entry: i) }
            if let code = e.code, !RunString.isValidCode(code) || !codes.contains(code) { throw RowsError.unknownCode(entry: i, code: code) }
        }
        let computed = computeID(raw.rows)
        guard computed == raw.id else { throw RowsError.idMismatch(expected: computed, found: raw.id) }
        return RowsDocument(id: raw.id, title: raw.piece.title, palette: raw.palette ?? [], entries: raw.rows,
                            pages: raw.source?.pages ?? [], notes: raw.notes ?? [])
    }

    /// `"sha256:" + hex(sha256(canonical))` over `{"rows": [from, to, text, count, code, repeat]}`:
    /// the rows, not the titles; an absent key stays absent. Mirrors graphghan.rowsdoc.rows_id.
    public static func computeID(_ entries: [Entry]) -> String {
        let rows: [JSONValue] = entries.map { e in
            var o: [String: JSONValue] = ["from": .int(e.from), "text": .string(e.text)]
            if let to = e.to { o["to"] = .int(to) }
            if let n = e.count { o["count"] = .int(n) }
            if let c = e.code { o["code"] = .string(c) }
            if let r = e.repeatText { o["repeat"] = .string(r) }
            return .object(o)
        }
        let canonical = CanonicalJSON.encode(.object(["rows": .array(rows)]))
        return ChartID.prefix + SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

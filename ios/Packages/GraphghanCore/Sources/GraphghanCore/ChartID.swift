import CryptoKit
import Foundation

/// `chart.id`: SHA-256 over the canonical JSON of the codes, rows, technique and (when present)
/// passes. Names, hexes, yarn, instructions and stats never affect it. See docs/chart-format.md.
public enum ChartID {
    public static let prefix = "sha256:"

    public static func compute(codes: [String], rows: [String], technique: JSONValue, passes: JSONValue?) -> String {
        var object: [String: JSONValue] = [
            "codes": .array(codes.map(JSONValue.string)),
            "rows": .array(rows.map(JSONValue.string)),
            "technique": technique,
        ]
        if let passes { object["passes"] = passes }
        let canonical = CanonicalJSON.encode(.object(object))
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return prefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The 64 hex characters after the prefix, or nil if the id is not well-formed.
    public static func hex(_ id: String) -> String? {
        guard id.hasPrefix(prefix) else { return nil }
        let hex = String(id.dropFirst(prefix.count))
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return hex
    }
}

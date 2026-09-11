import Foundation

/// A generic JSON tree. Used wherever the format keeps a raw object we must hash or preserve
/// verbatim (`technique`, `passes`), and for canonical serialization.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d) where d.rounded() == d && abs(d) < 9.0e15: return Int(d)
        default: return nil
        }
    }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

/// Python's `json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)`.
/// Keys sort by Unicode code point (UTF-8 byte order), only `"`, `\` and control characters are
/// escaped, `/` and non-ASCII pass through. Floats use Swift's shortest round-trip form, which
/// matches Python's repr for the values the format produces (the id never hashes floats).
public enum CanonicalJSON {
    public static func encode(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    private static func write(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d):
            if d.rounded() == d && abs(d) < 1e16 { out += String(Int(d)) + ".0" } else { out += "\(d)" }
        case .string(let s): writeString(s, into: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                write(v, into: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            let keys = o.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
            for (i, k) in keys.enumerated() {
                if i > 0 { out += "," }
                writeString(k, into: &out)
                out += ":"
                write(o[k]!, into: &out)
            }
            out += "}"
        }
    }

    private static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case let c where c.value < 0x20:
                out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}

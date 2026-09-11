import Foundation
import Testing
@testable import GraphghanCore

@Suite struct JSONValueTests {
    @Test func decodesEveryKind() throws {
        let data = Data(#"{"a":null,"b":true,"c":7,"d":6.5,"e":"x","f":[1,"y"],"g":{"k":false}}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(v["a"] == .null)
        #expect(v["b"] == .bool(true))
        #expect(v["c"] == .int(7))
        #expect(v["d"] == .double(6.5))
        #expect(v["e"] == .string("x"))
        #expect(v["f"] == .array([.int(1), .string("y")]))
        #expect(v["g"]?["k"] == .bool(false))
    }

    @Test func canonicalMatchesPythonRules() {
        let v: JSONValue = .object([
            "zebra": .int(1), "apple": .array([.bool(true), .null]), "quote": .string("say \"hi\"\n"),
            "under_score": .string("é/ü"),
        ])
        // keys sorted by code point, no whitespace, control chars escaped, non-ASCII and "/" untouched
        #expect(CanonicalJSON.encode(v) == #"{"apple":[true,null],"quote":"say \"hi\"\n","under_score":"é/ü","zebra":1}"#)
    }

    @Test func canonicalSortsByCodePointNotLocale() {
        let v: JSONValue = .object(["b": .int(1), "B": .int(2), "_": .int(3), "a": .int(4)])
        #expect(CanonicalJSON.encode(v) == #"{"B":2,"_":3,"a":4,"b":1}"#)
    }
}

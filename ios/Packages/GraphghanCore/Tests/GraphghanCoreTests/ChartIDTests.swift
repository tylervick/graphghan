import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ChartIDTests {
    @Test func knownValue() {
        // Python: chart_id(["A","B"], ["2A2B","4A"], TECHNIQUE_ROWS) — recompute here with the same canonical form.
        let technique: JSONValue = .object([
            "type": .string("rows"), "start": .string("bottom"), "first_side": .string("RS"),
            "rs_direction": .string("rtl"), "turn": .bool(true),
        ])
        let id = ChartID.compute(codes: ["A", "B"], rows: ["2A2B", "4A"], technique: technique, passes: nil)
        #expect(id.hasPrefix("sha256:") && id.count == 7 + 64)
        // Names and hexes are not part of the id; passes are.
        #expect(ChartID.compute(codes: ["A", "B"], rows: ["2A2B", "4A"], technique: technique, passes: .array([])) != id)
    }

    @Test(arguments: Fixtures.chartNames)
    func matchesEveryFixture(name: String) throws {
        let doc = try Fixtures.json("\(name).chart.json")
        let raw = try Fixtures.data("\(name).chart.json")
        let tree = try JSONDecoder().decode(JSONValue.self, from: raw)
        let palette = try #require(doc["palette"] as? [[String: Any]])
        let codes = palette.compactMap { $0["code"] as? String }
        let rows = try #require(doc["rows"] as? [String])
        let technique = try #require(tree["technique"])
        let expected = try #require((doc["chart"] as? [String: Any])?["id"] as? String)
        #expect(ChartID.compute(codes: codes, rows: rows, technique: technique, passes: tree["passes"]) == expected)
    }
}

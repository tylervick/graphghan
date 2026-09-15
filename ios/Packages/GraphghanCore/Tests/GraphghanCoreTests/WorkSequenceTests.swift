import CryptoKit
import Foundation
import Testing
@testable import GraphghanCore

@Suite struct WorkSequenceTests {
    struct ExpectedRun: Decodable, Equatable { let code: String; let count: Int; let x0: Int? }
    struct ExpectedPass: Decodable {
        let label: String; let side: String?; let direction: String?; let gridRow: Int?; let runs: [ExpectedRun]
        enum CodingKeys: String, CodingKey { case label, side, direction, gridRow = "grid_row", runs }
    }
    struct ExpectedSequence: Decodable { let passes: [ExpectedPass]?; let sha256: String? }

    static func sequence(_ name: String) throws -> WorkSequence {
        try WorkSequence(chart: Chart.load(Fixtures.data("\(name).chart.json")))
    }

    /// A chart with no explicit passes, so the working order comes from `technique`.
    static func derived(technique: JSONValue, rows: [String], codes: [String] = ["A", "B"]) throws -> WorkSequence {
        let id = ChartID.compute(codes: codes, rows: rows, technique: technique, passes: nil)
        let palette = codes.enumerated().map { i, c in
            #"{"code":"\#(c)","name":"n\#(i)","hex":"\#(String(format: "#%06x", i * 0x111111))"}"#
        }.joined(separator: ",")
        let width = RunString.parse(rows[0])?.reduce(0) { $0 + $1.count } ?? 0
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\#(id)","width":\#(width),"height":\#(rows.count)},
         "palette":[\#(palette)],"rows":[\#(rows.map { "\"\($0)\"" }.joined(separator: ","))],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"}},"technique":\#(CanonicalJSON.encode(technique))}
        """#
        return try WorkSequence(chart: Chart.load(Data(json.utf8)))
    }

    @Test(arguments: Fixtures.chartNames)
    func matchesFixture(name: String) throws {
        let path = Fixtures.directory.appendingPathComponent("\(name).sequence.json")
        guard FileManager.default.fileExists(atPath: path.path) else {
            #expect(throws: SequenceError.self) { try Self.sequence(name) }
            return
        }
        let expected = try JSONDecoder().decode(ExpectedSequence.self, from: Data(contentsOf: path))
        let seq = try Self.sequence(name)
        if let passes = expected.passes {
            #expect(seq.passes.count == passes.count)
            for (got, want) in zip(seq.passes, passes) {
                #expect(got.label == want.label)
                #expect(got.side?.rawValue == want.side)
                #expect(got.direction?.rawValue == want.direction)
                #expect(got.gridRow == want.gridRow)
                #expect(got.runs.map { ExpectedRun(code: $0.code, count: $0.count, x0: $0.x0) } == want.runs)
            }
        }
        if let sha = expected.sha256 {
            let canonical = CanonicalJSON.encode(seq.jsonValue)
            let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
            #expect(digest == sha)
        }
    }

    @Test func unknownTechniqueNames() throws {
        #expect(throws: SequenceError.unsupportedTechnique("tunisian")) { try Self.sequence("unknown-technique") }
    }

    @Test func stitchMath() throws {
        let seq = try Self.sequence("minimal-rows")  // 12 passes of 14 stitches; rows 3-10 have 3 runs
        #expect(seq.totalCells == 168)
        #expect(seq.cellsBefore(Cursor(row: 1, run: 0)) == 0)
        #expect(seq.cellsBefore(Cursor(row: 3, run: 1)) == 30)
        #expect(seq.cellsBefore(Cursor(row: 3, run: 3)) == 42)   // past the last run of row 3
        #expect(seq.cellsBefore(Cursor(row: 13, run: 0)) == nil)
        #expect(seq.cellsBefore(Cursor(row: 3, run: 4)) == nil)
        #expect(seq.isValid(Cursor(row: 12, run: 1)) && !seq.isValid(Cursor(row: 12, run: 2)))
        #expect(seq.pass(at: 1)?.label == "Row 1" && seq.pass(at: 0) == nil)
    }

    @Test func totalCellsIsTheDenominatorAndStitchesFollowTheKind() throws {
        let seq = try Self.sequence("minimal-rows")
        #expect(seq.totalCells == 168)
        #expect(seq.totalStitches == 168)

        let filet = try Self.sequence("filet-blocks")
        #expect(filet.totalCells > 0)
        #expect(filet.totalStitches == nil)
    }

    @Test func roundsLabelAndSides() throws {
        let seq = try Self.sequence("minimal-rounds")
        #expect(seq.passes[1].label == "Round 2" && seq.passes[1].side == .rs && seq.passes[1].direction == .rtl)
    }

    /// Python: `y = h - k if start == "bottom" else k - 1`, and the sides alternate from
    /// `first_side`, so a top-down chart whose first row is the wrong side reads row 1 left to right.
    @Test func topDownFromTheWrongSide() throws {
        let seq = try Self.derived(technique: .object(["type": .string("rows"), "start": .string("top"), "first_side": .string("WS")]),
                                   rows: ["2A2B", "4A"])
        #expect(seq.passes.count == 2)
        #expect(seq.passes[0].label == "Row 1" && seq.passes[0].gridRow == 0)
        #expect(seq.passes[0].side == .ws && seq.passes[0].direction == .ltr)
        #expect(seq.passes[0].runs.map(\.code) == ["A", "B"])   // ltr: grid order
        #expect(seq.passes[1].label == "Row 2" && seq.passes[1].gridRow == 1)
        #expect(seq.passes[1].side == .rs && seq.passes[1].direction == .rtl)
    }

    /// Python checks `isinstance(doc["passes"], list)`; anything else derives from the technique.
    @Test func nonListPassesFallBackToTheTechnique() throws {
        var json = try String(decoding: Fixtures.data("minimal-rows.chart.json"), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"instructions\": []", with: "\"instructions\": [], \"passes\": \"soon\"")
        let seq = try WorkSequence(chart: Chart.load(Data(json.utf8)))  // the id ignores non-list passes
        #expect(seq.passes.count == 12 && seq.passes[0].label == "Row 1")
    }

    @Test func explicitPassesRejectGridRowsOutsideTheChart() throws {
        let json = try String(decoding: Fixtures.data("explicit-passes.chart.json"), as: UTF8.self)
        for badRow in ["5", "-1"] {
            // The chart is 2 rows tall, so the second pass's grid_row 1 becomes out of range.
            let edited = json.replacingOccurrences(of: "\"grid_row\": 1", with: "\"grid_row\": \(badRow)")
            let doc = try ChartDocument.decode(Data(edited.utf8))  // the id no longer matches
            #expect(throws: SequenceError.malformedPasses("passes[1].grid_row out of range")) {
                try WorkSequence(chart: try Chart.unchecked(document: doc))
            }
        }
    }

    @Test func explicitPassesRejectUnknownCodes() throws {
        var json = try String(decoding: Fixtures.data("explicit-passes.chart.json"), as: UTF8.self)
        // Only the pass run's code changes (the one followed by "count"); a plain string
        // replace would also rename the palette entry "B", which is not what this test checks.
        let codeInRun = try NSRegularExpression(pattern: "\"code\": \"B\"(?=,\\s*\"count\")")
        let fullRange = NSRange(json.startIndex..., in: json)
        json = codeInRun.stringByReplacingMatches(in: json, range: fullRange, withTemplate: "\"code\": \"Q\"")
        // The id no longer matches after editing passes, so build the document directly.
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(throws: SequenceError.self) { try WorkSequence(chart: try Chart.unchecked(document: doc)) }
    }

    @Test func explicitPassesRejectEmptyRuns() throws {
        var json = try String(decoding: Fixtures.data("explicit-passes.chart.json"), as: UTF8.self)
        // Empty the second pass's runs array; runs entries contain no "]" so this is unambiguous.
        let runsInSecondPass = try NSRegularExpression(pattern: "(\"label\": \"Row 2\"[^\\]]*\"runs\":\\s*\\[)[^\\]]*(\\])")
        let fullRange = NSRange(json.startIndex..., in: json)
        json = runsInSecondPass.stringByReplacingMatches(in: json, range: fullRange, withTemplate: "$1$2")
        // The id no longer matches after editing passes, so build the document directly.
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(throws: SequenceError.self) { try WorkSequence(chart: try Chart.unchecked(document: doc)) }
    }
}

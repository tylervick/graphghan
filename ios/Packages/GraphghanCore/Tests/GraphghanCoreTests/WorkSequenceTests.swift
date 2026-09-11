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
        #expect(seq.totalStitches == 168)
        #expect(seq.stitchesBefore(Cursor(row: 1, run: 0)) == 0)
        #expect(seq.stitchesBefore(Cursor(row: 3, run: 1)) == 30)
        #expect(seq.stitchesBefore(Cursor(row: 3, run: 3)) == 42)   // past the last run of row 3
        #expect(seq.stitchesBefore(Cursor(row: 13, run: 0)) == nil)
        #expect(seq.stitchesBefore(Cursor(row: 3, run: 4)) == nil)
        #expect(seq.isValid(Cursor(row: 12, run: 1)) && !seq.isValid(Cursor(row: 12, run: 2)))
        #expect(seq.pass(at: 1)?.label == "Row 1" && seq.pass(at: 0) == nil)
    }

    @Test func roundsLabelAndSides() throws {
        let seq = try Self.sequence("minimal-rounds")
        #expect(seq.passes[1].label == "Round 2" && seq.passes[1].side == .rs && seq.passes[1].direction == .rtl)
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
}

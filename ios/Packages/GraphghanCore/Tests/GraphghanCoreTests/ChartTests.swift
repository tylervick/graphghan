import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ChartTests {
    static func chart(_ name: String) throws -> Chart { try Chart.load(Fixtures.data("\(name).chart.json")) }

    static func doc(rows: [String], codes: [String] = ["A", "B"], hexes: [String]? = nil, width: Int? = nil, id: String? = nil) -> Data {
        let technique: JSONValue = .object(["type": .string("rows")])
        let chartID = id ?? ChartID.compute(codes: codes, rows: rows, technique: technique, passes: nil)
        let palette = codes.enumerated().map { i, c in
            #"{"code":"\#(c)","name":"n\#(i)","hex":"\#(hexes?[i] ?? String(format: "#%06x", i * 0x111111))"}"#
        }.joined(separator: ",")
        let w = width ?? (RunString.parse(rows[0])?.reduce(0) { $0 + $1.count } ?? 0)
        return Data(#"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\#(chartID)","width":\#(w),"height":\#(rows.count)},
         "palette":[\#(palette)],"rows":[\#(rows.map { "\"\($0)\"" }.joined(separator: ","))],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"}},"technique":{"type":"rows"}}
        """#.utf8)
    }

    @Test(arguments: Fixtures.chartNames)
    func everyFixtureLoads(name: String) throws {
        let chart = try Self.chart(name)
        #expect(chart.cells.count == chart.width * chart.height)
        #expect(chart.runsByRow.count == chart.height)
        #expect(chart.warnings.isEmpty)
    }

    @Test func cellsAndRuns() throws {
        let chart = try Chart(document: ChartDocument.decode(Self.doc(rows: ["2A2B", "4A"])))
        #expect(chart.width == 4 && chart.height == 2)
        #expect(Array(chart.cells) == [0, 0, 1, 1, 0, 0, 0, 0])
        #expect(chart.runsByRow[0] == [GridRun(colorIndex: 0, count: 2, x0: 0), GridRun(colorIndex: 1, count: 2, x0: 2)])
        #expect(chart.cell(x: 3, y: 0) == 1 && chart.cell(x: 3, y: 1) == 0)
        #expect(chart.colorIndex(of: "B") == 1 && chart.colorIndex(of: "Z") == nil)
    }

    @Test func multiLetterCodes() throws {
        let chart = try Self.chart("two-letter-codes")
        #expect(chart.colorIndex(of: "Gd") == 1)
        #expect(chart.runsByRow[0].map(\.count) == [7, 2, 3])
    }

    @Test func sizesFromGauge() throws {
        let chart = try Self.chart("craigh-na-dun")
        #expect(chart.cellAspect == 0.875)
        #expect(chart.finishedSize.width == 54 && chart.finishedSize.height == 46 && chart.finishedSize.unit == "in")
    }

    @Test func runStringScanner() {
        #expect(RunString.parse("7Gd2G3Y")?.map(\.code) == ["Gd", "G", "Y"])
        #expect(RunString.parse("7YB")?.count == 1)
        #expect(RunString.parse("") == nil)
        #expect(RunString.parse("A7") == nil)
        #expect(RunString.parse("7ABCD") == nil)
        #expect(RunString.parse("7A-") == nil)
        #expect(RunString.parse("2A0B3C")?.map(\.count) == [2, 0, 3])
        #expect(RunString.parse(String(repeating: "9", count: 25) + "A") == nil)
    }

    @Test func rejectsMalformedDocuments() throws {
        func load(_ data: Data) -> ChartError? {
            do { _ = try Chart(document: ChartDocument.decode(data)); return nil } catch let e as ChartError { return e } catch { return nil }
        }
        #expect(load(Self.doc(rows: ["2A2B", "3A"])) == .rowSum(row: 1, got: 3, expected: 4))
        #expect(load(Self.doc(rows: ["2A2C"])) == .unknownCode(row: 0, code: "C"))
        #expect(load(Self.doc(rows: ["2A2B", "4A"], width: 5)) == .rowSum(row: 0, got: 4, expected: 5))
        #expect(load(Self.doc(rows: ["x"])) == .malformedRow(0))
        #expect(load(Self.doc(rows: ["4A"], codes: ["A", "A"])) == .duplicateCode("A"))
        #expect(load(Self.doc(rows: ["4A"], codes: ["ABCD"])) == .invalidCode("ABCD"))
        #expect(load(Self.doc(rows: ["4A"], hexes: ["red", "#000000"])) == .invalidHex(code: "A", hex: "red"))
        let fullwidthHex = "#\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}\u{FF11}"
        #expect(load(Self.doc(rows: ["4A"], hexes: [fullwidthHex, "#000000"])) == .invalidHex(code: "A", hex: fullwidthHex))
        #expect(load(Self.doc(rows: ["4A"], id: "sha256:" + String(repeating: "0", count: 64)))
            == .idMismatch(expected: ChartID.compute(codes: ["A", "B"], rows: ["4A"], technique: .object(["type": .string("rows")]), passes: nil),
                           found: "sha256:" + String(repeating: "0", count: 64)))
    }

    @Test func tooManyColorsIsRejected() throws {
        var codes: [String] = []
        for upper in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            for lower in "abcdefghij" {
                codes.append("\(upper)\(lower)")
            }
        }
        codes = Array(codes.prefix(256))
        #expect(codes.count == 256)
        let rows = ["4" + codes[0]]
        let technique: JSONValue = .object(["type": .string("rows")])
        let chartID = ChartID.compute(codes: codes, rows: rows, technique: technique, passes: nil)
        let hex = "#000000"
        let palette = codes.enumerated().map { i, c in
            #"{"code":"\#(c)","name":"n\#(i)","hex":"\#(hex)"}"#
        }.joined(separator: ",")
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\#(chartID)","width":4,"height":1},
         "palette":[\#(palette)],"rows":["\#(rows[0])"],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"}},"technique":{"type":"rows"}}
        """#
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(throws: ChartError.tooManyColors(256)) { try Chart(document: doc) }
    }

    @Test func heightMismatchAndSchema() throws {
        var bad = String(decoding: Self.doc(rows: ["4A"]), as: UTF8.self)
        bad = bad.replacingOccurrences(of: "\"height\":1", with: "\"height\":2")
        #expect(throws: ChartError.heightMismatch(rows: 1, height: 2)) { try Chart(document: ChartDocument.decode(Data(bad.utf8))) }
        let schema1 = String(decoding: Self.doc(rows: ["4A"]), as: UTF8.self).replacingOccurrences(of: "\"schema\":2", with: "\"schema\":1")
        #expect(throws: ChartError.unsupportedSchema(1)) { try Chart(document: ChartDocument.decode(Data(schema1.utf8))) }
    }

    @Test func caseOnlyDuplicatesWarn() throws {
        let chart = try Chart(document: ChartDocument.decode(Self.doc(rows: ["2a2A"], codes: ["a", "A"])))
        #expect(chart.warnings.count == 1 && chart.warnings[0].contains("differ only by case"))
    }
}

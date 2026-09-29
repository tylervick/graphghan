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
        #expect(chart.finishedSize?.width == 54 && chart.finishedSize?.height == 46 && chart.finishedSize?.unit == "in")
    }

    @Test func sizeDerivesWhenUnitAndKindAgree() throws {
        let chart = try Self.chart("craigh-na-dun")  // neither field present: the defaults pair
        #expect(chart.sizeDerives)
        #expect(chart.finishedSize?.width == 54)
    }

    @Test func sizeIsWithheldWhenUnitAndKindDisagree() throws {
        // filet-blocks declares cell.kind "block" with a stitch gauge — no pairing, no size.
        let chart = try Self.chart("filet-blocks")
        #expect(!chart.sizeDerives)
        #expect(chart.finishedSize == nil)
    }

    @Test func tileGaugeDerivesTheC2CSize() throws {
        let chart = try Self.chart("tiles-gauge")  // 6 tiles over 5.5 tiles = 4 in
        #expect(chart.sizeDerives)
        #expect(chart.finishedSize?.width == 4.4 && chart.finishedSize?.height == 4.4 && chart.finishedSize?.unit == "in")
    }

    @Test func tilesUnitOverStitchCellsWithholds() throws {
        // The complementary mismatch to filet-blocks above: a tiles gauge with no cell.kind
        // declared at all, so it defaults to .stitch. No fixture pairs "tiles" with an absent
        // cell, so this builds the document inline the way anUnknownCellKindRefusesTheDocument
        // does, rather than inventing a fixture.
        var json = String(decoding: Self.doc(rows: ["4A"]), as: UTF8.self)
        json = json.replacingOccurrences(of: #""over":{"value":4,"unit":"in"}},"technique""#,
                                          with: #""over":{"value":4,"unit":"in"},"unit":"tiles"},"technique""#)
        let chart = try Chart(document: ChartDocument.decode(Data(json.utf8)))
        #expect(!chart.sizeDerives)
        #expect(chart.finishedSize == nil)
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
        // an explicit width, because an unparseable row leaves the helper computing width 0, which
        // the empty-grid guard would catch first
        #expect(load(Self.doc(rows: ["x"], width: 4)) == .malformedRow(0))
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

    /// The schema's minimum is 1 for both; an empty grid divides by zero in the size math.
    @Test func rejectsEmptyGrids() throws {
        let zeroWidth = Self.doc(rows: ["0A"], width: 0)  // a row that parses to no stitches at all
        #expect(throws: ChartError.invalidSize(width: 0, height: 1)) { try Chart(document: ChartDocument.decode(zeroWidth)) }
        let rows: [String] = []
        let technique: JSONValue = .object(["type": .string("rows")])
        let id = ChartID.compute(codes: ["A"], rows: rows, technique: technique, passes: nil)
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\#(id)","width":4,"height":0},
         "palette":[{"code":"A","name":"n0","hex":"#000000"}],"rows":[],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"}},"technique":{"type":"rows"}}
        """#
        #expect(throws: ChartError.invalidSize(width: 4, height: 0)) { try Chart(document: ChartDocument.decode(Data(json.utf8))) }
    }

    @Test func caseOnlyDuplicatesWarn() throws {
        let chart = try Chart(document: ChartDocument.decode(Self.doc(rows: ["2a2A"], codes: ["a", "A"])))
        #expect(chart.warnings.count == 1 && chart.warnings[0].contains("differ only by case"))
    }

    @Test func stitchIsResolvedFromGauge() throws {
        let craigh = try Self.chart("craigh-na-dun")
        let stitch = try #require(craigh.stitch)
        #expect(stitch.code == "sc" && stitch.name == "single crochet" && stitch.terms == .us)
        #expect(stitch.boundary?.kind == .turn && stitch.boundary?.chain == 1 && stitch.boundary?.color == .next)
        #expect(craigh.foundation?.chain == 190)
    }

    @Test func stitchIsNilWithoutAGaugeStitch() throws {
        // ChartTests.doc writes a gauge with no `stitch`
        let chart = try Chart(document: ChartDocument.decode(Self.doc(rows: ["2A2B", "4A"])))
        #expect(chart.stitch == nil && chart.foundation == nil)
    }

    @Test func foundationShorterThanTheFirstRowIsRefused() throws {
        // #50: a maker could not work row 1, so the chart does not load at all. Extra chains are fine.
        func doc(chain: Int, into: Int? = 2) -> Data {
            let f = into.map { #"{"chain":\#(chain),"first_stitch_in":\#($0)}"# } ?? #"{"chain":\#(chain)}"#
            var json = String(decoding: Self.doc(rows: ["2A2B", "4A"]), as: UTF8.self)  // width 4
            json = json.replacingOccurrences(of: #""technique":{"type":"rows"}"#, with: #""technique":{"type":"rows"},"foundation":\#(f)"#)
            return Data(json.utf8)
        }
        #expect(try Chart(document: ChartDocument.decode(doc(chain: 5))).foundation?.chain == 5)
        #expect(try Chart(document: ChartDocument.decode(doc(chain: 9))).foundation?.chain == 9)
        #expect(try Chart(document: ChartDocument.decode(doc(chain: 4, into: nil))).foundation?.chain == 4)
        #expect(throws: ChartError.foundationTooShort(chain: 4, needed: 5)) { try Chart(document: ChartDocument.decode(doc(chain: 4))) }
        #expect(throws: ChartError.foundationTooShort(chain: 3, needed: 4)) { try Chart(document: ChartDocument.decode(doc(chain: 3, into: nil))) }
    }

    @Test func termsDefaultToUSAndBoundaryIsNeverDerived() throws {
        let minimal = try Self.chart("minimal-rows")   // gauge.stitch = "sc", nothing else
        let stitch = try #require(minimal.stitch)
        #expect(stitch.terms == .us && stitch.name == "single crochet")
        #expect(stitch.boundary == nil)
    }

    @Test func cellKindDefaultsToStitch() throws {
        let chart = try Self.chart("minimal-rows")
        #expect(chart.cellKind == .stitch)
    }

    @Test func cellKindDecodesADeclaredKind() throws {
        let chart = try Self.chart("filet-blocks")
        #expect(chart.cellKind == .block)
    }

    @Test func anUnknownCellKindRefusesTheDocument() throws {
        // Spec §4.1: a kind outside the enum is refused, not degraded. A kind inside the enum but
        // unimplemented is the other case and opens fine — `filet-blocks` covers that.
        var json = String(decoding: Self.doc(rows: ["4A"]), as: UTF8.self)
        json = json.replacingOccurrences(of: #""chart":{"id":"#, with: #""chart":{"cell":{"kind":"sparkle"},"id":"#)
        #expect(throws: ChartError.unsupportedCellKind("sparkle")) { _ = try Chart.load(Data(json.utf8)) }
    }

    // ---- chart schema 3: shaped rows (spec 2026-09-25 §5.1) ----

    static let shapedRows = ["2N3A2N", "1N2A1B3A", "3A1B3A", "1N5A1N", "2N3A2N"]

    /// A 7-wide shaped chart: A and B are yarns, N the ground; `noStitch` lists the codes marked
    /// `"stitch": false`, `extra` is raw JSON members appended to the document.
    static func shaped(rows: [String] = shapedRows, schema: Int = 3, noStitch: [String] = ["N"], start: String = "bottom",
                       passes: String? = nil, extra: String = "") throws -> Data {
        let codes = ["A", "B", "N"]
        let technique: JSONValue = .object(["type": .string(passes == nil ? "rows" : "none"), "start": .string(start)])
        let passesValue = try passes.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        let id = ChartID.compute(codes: codes, rows: rows, technique: technique, passes: passesValue, noStitch: noStitch.first)
        let palette = codes.enumerated().map { i, c in
            #"{"code":"\#(c)","name":"n\#(i)","hex":"\#(String(format: "#%06x", i * 0x111111))"\#(noStitch.contains(c) ? #","stitch":false"# : "")}"#
        }.joined(separator: ",")
        return Data(#"""
        {"schema":\#(schema),"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"\#(id)","width":7,"height":\#(rows.count)},
         "palette":[\#(palette)],"rows":[\#(rows.map { "\"\($0)\"" }.joined(separator: ","))],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"}},"technique":\#(CanonicalJSON.encode(technique))\#(passes.map { ",\"passes\":\($0)" } ?? "")\#(extra)}
        """#.utf8)
    }

    @Test func aShapedChartLoads() throws {
        let chart = try Chart.load(Self.shaped())
        #expect(chart.noStitchIndex == 2 && chart.isShaped)
        #expect(chart.isStitched(colorIndex: 0) && !chart.isStitched(colorIndex: 2))
        #expect(try !Self.chart("minimal-rows").isShaped)
    }

    @Test func aNoStitchCellBetweenStitchesIsRefused() throws {
        var rows = Self.shapedRows
        rows[0] = "1A1N5A"
        #expect(throws: ChartError.noStitchInsideRow(0)) { try Chart.load(Self.shaped(rows: rows)) }
    }

    @Test func aRowOfOnlyNoStitchIsRefused() throws {
        var rows = Self.shapedRows
        rows[0] = "7N"
        #expect(throws: ChartError.rowWithoutStitches(0)) { try Chart.load(Self.shaped(rows: rows)) }
    }

    @Test func twoNoStitchColoursAreRefused() throws {
        #expect(throws: ChartError.tooManyNoStitch(2)) { try Chart.load(Self.shaped(noStitch: ["B", "N"])) }
    }

    @Test func stitchFalseNeedsSchema3() throws {
        #expect(throws: ChartError.noStitchNeedsSchema3) { try Chart.load(Self.shaped(schema: 2)) }
    }

    @Test func foundationCountsPassOnesStitches() throws {
        _ = try Chart.load(Self.shaped(extra: #","foundation":{"chain":4,"first_stitch_in":2}"#))
        #expect(throws: ChartError.foundationTooShort(chain: 3, needed: 4)) {
            try Chart.load(Self.shaped(extra: #","foundation":{"chain":3,"first_stitch_in":2}"#))
        }
    }

    @Test func foundationReadsPassOneAtTheTop() throws {
        let rows = ["1N5A1N", "3A1B3A", "2N3A2N"]
        #expect(throws: ChartError.foundationTooShort(chain: 5, needed: 6)) {
            try Chart.load(Self.shaped(rows: rows, start: "top", extra: #","foundation":{"chain":5,"first_stitch_in":2}"#))
        }
        _ = try Chart.load(Self.shaped(rows: rows, start: "top", extra: #","foundation":{"chain":6,"first_stitch_in":2}"#))
        _ = try Chart.load(Self.shaped(rows: rows, extra: #","foundation":{"chain":4,"first_stitch_in":2}"#))
    }

    /// The ruling that changes the brief: when the chart is shaped and `passes` is an explicit list,
    /// pass 1's own run counts win over the technique-derived grid row -- grid_row 3 ("1N5A1N", 5
    /// stitches) is used, not the bottom row a "rows" technique would derive ("2N3A2N", 3 stitches).
    /// Mirrors graphghan.chartdoc test_foundation_counts_explicit_pass_1_not_the_technique_derived_row.
    @Test func foundationCountsExplicitPassOnesStitchesNotTheTechniqueDerivedRow() throws {
        let passes = #"""
        [{"label":"Row 1","grid_row":3,"runs":[{"code":"A","count":5,"x0":1}]},
         {"label":"Row 2","grid_row":4,"runs":[{"code":"A","count":3,"x0":2}]}]
        """#
        #expect(throws: ChartError.foundationTooShort(chain: 5, needed: 6)) {
            try Chart.load(Self.shaped(passes: passes, extra: #","foundation":{"chain":5,"first_stitch_in":2}"#))
        }
        _ = try Chart.load(Self.shaped(passes: passes, extra: #","foundation":{"chain":6,"first_stitch_in":2}"#))
    }

    @Test func writtenHasOneEntryPerPass() throws {
        let chart = try Chart.load(Self.shaped(extra: #","written":["R1","R2","R3","R4","R5"]"#))
        #expect(chart.written?.count == 5)
        #expect(throws: ChartError.writtenCount(got: 1, expected: 5)) { try Chart.load(Self.shaped(extra: #","written":["R1"]"#)) }
    }

    @Test func theIDIncludesTheNoStitchCode() {
        let t: JSONValue = .object(["type": .string("rows")])
        #expect(ChartID.compute(codes: ["A", "N"], rows: ["1N1A"], technique: t, passes: nil)
                != ChartID.compute(codes: ["A", "N"], rows: ["1N1A"], technique: t, passes: nil, noStitch: "N"))
    }
}

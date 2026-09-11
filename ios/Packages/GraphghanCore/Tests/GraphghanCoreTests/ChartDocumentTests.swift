import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ChartDocumentTests {
    @Test(arguments: Fixtures.chartNames)
    func decodesEveryFixture(name: String) throws {
        let doc = try ChartDocument.decode(Fixtures.data("\(name).chart.json"))
        #expect(doc.schema == 2)
        #expect(doc.rows.count == doc.chart.height)
        #expect(!doc.palette.isEmpty)
        #expect(doc.gauge.over.unit == "in")
    }

    @Test func craighFields() throws {
        let doc = try ChartDocument.decode(Fixtures.data("craigh-na-dun.chart.json"))
        #expect(doc.pattern.title == "Craigh na Dun Blanket")
        #expect(doc.pattern.dedication == "For Meaghan")
        #expect(doc.chart.variant == "final" && doc.chart.gaugeKey == "sc")
        #expect(doc.chart.width == 189 && doc.chart.height == 184)
        #expect(doc.gauge.stitches == 14 && doc.gauge.rows == 16 && doc.gauge.hook == "5 mm (US H-8)")
        #expect(doc.palette[4].code == "Y" && doc.palette[4].yarn?["note"] == "Gold")
        #expect(doc.instructions.count == 2 && doc.instructions[0].title == "Setup")
        #expect(doc.techniqueType == "rows" && doc.techniqueStart == "bottom")
        #expect(doc.techniqueFirstSide == "RS" && doc.techniqueRSDirection == "rtl")
        #expect(doc.passes == nil)
    }

    @Test func unknownKeysAreIgnoredAndDefaultsApply() throws {
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"sha256:x","width":1,"height":1},
         "palette":[{"code":"A","name":"a","hex":"#000000","mystery":1}],"rows":["1A"],
         "gauge":{"stitches":10,"rows":10,"over":{"value":10,"unit":"cm"}},"technique":{"type":"rows"},"future":{}}
        """#
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(doc.instructions.isEmpty && doc.layers == nil && doc.generator == nil)
        #expect(doc.techniqueStart == "bottom" && doc.techniqueFirstSide == "RS" && doc.techniqueRSDirection == "rtl")
        #expect(doc.technique["type"] == .string("rows"))
    }

    @Test func layersDecode() throws {
        let doc = try ChartDocument.decode(Fixtures.data("layers-stitch.chart.json"))
        let stitch = try #require(doc.layers?["stitch"])
        #expect(stitch.legend["k"] == "knit" && stitch.rows == ["12k", "6k6p"])
    }
}

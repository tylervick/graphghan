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

    @Test func phase1KeysDecode() throws {
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1","craft":"crochet","language":"en"},
         "chart":{"id":"sha256:x","width":1,"height":1},
         "palette":[{"code":"A","name":"a","hex":"#000000"}],"rows":["1A"],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"},"stitch":"sc","unit":"stitches",
                  "stitch_name":"single crochet","terms":"US","terms_also":"UK",
                  "boundary":{"kind":"turn","chain":1,"counts_as_stitch":false,"color":"next"}},
         "technique":{"type":"rows"},
         "foundation":{"chain":2,"first_stitch_in":2,"note":"in a (A)"}}
        """#
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(doc.pattern.craft == "crochet" && doc.pattern.language == "en")
        #expect(doc.gauge.unit == "stitches" && doc.gauge.stitchName == "single crochet")
        #expect(doc.gauge.terms == .us && doc.gauge.termsAlso == .uk)
        #expect(doc.gauge.boundary == Boundary(kind: .turn, chain: 1, countsAsStitch: false, color: .next))
        let f = try #require(doc.foundation)
        #expect(f.chain == 2 && f.firstStitchIn == 2 && f.note == "in a (A)")
    }

    @Test func phase1KeysAbsentAreNil() throws {
        let doc = try ChartDocument.decode(Fixtures.data("minimal-rows.chart.json"))
        #expect(doc.pattern.craft == nil && doc.pattern.language == nil)
        #expect(doc.gauge.unit == nil && doc.gauge.stitchName == nil && doc.gauge.terms == nil && doc.gauge.termsAlso == nil)
        #expect(doc.gauge.boundary == nil && doc.foundation == nil)
    }

    @Test func unknownBoundaryKindOrTermsDecodesAsAbsent() throws {
        let json = #"""
        {"schema":2,"pattern":{"id":"t","title":"T","version":"1"},"chart":{"id":"sha256:x","width":1,"height":1},
         "palette":[{"code":"A","name":"a","hex":"#000000"}],"rows":["1A"],
         "gauge":{"stitches":14,"rows":16,"over":{"value":4,"unit":"in"},"stitch":"sc","terms":"AU",
                  "boundary":{"kind":"somersault","chain":1}},
         "technique":{"type":"rows"}}
        """#
        let doc = try ChartDocument.decode(Data(json.utf8))
        #expect(doc.gauge.stitch == "sc")       // the rest of gauge still loads
        #expect(doc.gauge.boundary == nil && doc.gauge.terms == nil)
    }

    @Test func craighCarriesItsStitch() throws {
        let doc = try ChartDocument.decode(Fixtures.data("craigh-na-dun.chart.json"))
        #expect(doc.gauge.terms == .us)
        #expect(doc.gauge.boundary == Boundary(kind: .turn, chain: 1, countsAsStitch: false, color: .next))
        #expect(doc.foundation?.chain == 190 && doc.foundation?.firstStitchIn == 2)
        #expect(doc.pattern.craft == "crochet")
    }
}

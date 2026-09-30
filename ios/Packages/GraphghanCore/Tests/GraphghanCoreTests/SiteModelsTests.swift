import Foundation
import Testing
@testable import GraphghanCore

@Suite struct SiteModelsTests {
    static let index = #"""
    [{"slug":"craigh-na-dun","title":"Craigh na Dun Blanket","version":"1.0.0","stitch":"sc","width":189,"height":184,
      "size_in":[54.0,46.0],"dedication":"For Meaghan","colors":5,"preview":"patterns/craigh-na-dun/preview.png",
      "manifest":"patterns/craigh-na-dun/pattern.json","charts":2}]
    """#
    static let manifest = #"""
    {"schema":1,"id":"craigh-na-dun","title":"Craigh na Dun Blanket","version":"1.0.0","dedication":"For Meaghan",
     "quote":"Lord…","author":"Tyler Vick","license":"CC-BY-NC-SA-4.0","preview":"preview.png",
     "palette":[{"code":"C","name":"Cream","hex":"#f2e8d5"}],
     "charts":[
       {"id":"sha256:aaaa","variant":"final","gauge_key":"sc","default":true,"path":"charts/final-sc/chart.json",
        "preview":"charts/final-sc/preview.png","width":189,"height":184,"size":{"width":54.0,"height":46.0,"unit":"in"},
        "stitch":"sc","colors":5,"stitches":34776,"changes_per_row":{"mean":6.1,"max":23},"yards_est":3200},
       {"id":"sha256:bbbb","variant":"final","gauge_key":"hdc","default":false,"path":"charts/final-hdc/chart.json",
        "preview":"charts/final-hdc/preview.png","width":176,"height":115,"size":{"width":54.2,"height":46.0,"unit":"in"},
        "stitch":"hdc","colors":5,"stitches":20240,"changes_per_row":{"mean":5.0,"max":20},"yards_est":2100}],
     "updated":"2026-09-11T03:00:00Z"}
    """#

    @Test func decodesIndex() throws {
        let entries = try JSONDecoder().decode([IndexEntry].self, from: Data(Self.index.utf8))
        #expect(entries.count == 1 && entries[0].id == "craigh-na-dun" && entries[0].sizeIn == [54, 46])
        #expect(entries[0].manifest == "patterns/craigh-na-dun/pattern.json" && entries[0].charts == 2)
    }

    @Test func decodesManifest() throws {
        let m = try JSONDecoder().decode(PatternManifest.self, from: Data(Self.manifest.utf8))
        #expect(m.charts.count == 2 && m.defaultChart?.gaugeKey == "sc" && m.charts[1].isDefault == false)
        #expect(m.charts[0].key == "final-sc" && m.charts[1].size?.width == 54.2 && m.charts[1].changesPerRow.max == 20)
        #expect(m.palette[0].hex == "#f2e8d5" && m.license == "CC-BY-NC-SA-4.0")
    }

    @Test func indexToleratesMissingNewKeys() throws {
        let old = Self.index.replacingOccurrences(of: ",\n  \"manifest\":\"patterns/craigh-na-dun/pattern.json\",\"charts\":2", with: "")
        let entries = try JSONDecoder().decode([IndexEntry].self, from: Data(old.utf8))
        #expect(entries[0].manifest == nil && entries[0].charts == nil)
    }

    @Test func aPiecedManifestDecodesItsPiecesAndAssembly() throws {
        let m = try JSONDecoder().decode(PatternManifest.self, from: Fixtures.pieces("pattern.json"))
        #expect(m.schema == 2 && m.isPieced)
        #expect(m.pieces?.map(\.id) == ["panel", "strip", "fin", "strap"])
        #expect(m.pieces?[0].chart == m.charts[0].id && m.pieces?[0].isWritten == false)
        #expect(m.pieces?[1].rows == "pieces/strip.rows.json" && m.pieces?[1].isWritten == true)
        #expect(m.pieces?[2].make == 2 && m.piecesTotal == 5)
        #expect(m.assembly.map(\.title) == ["Sew the strip round the panel", "Pages 4–5"])
        #expect(m.assembly[1].text == nil && m.assembly[1].pages == [4, 5])
    }

    @Test func aManifestWithoutPiecesIsOnePiece() throws {
        let data = try Data(contentsOf: Fixtures.root.appendingPathComponent("fixtures/bundle/craigh-na-dun.graphghan"))
        let m = try PatternBundle.read(data).manifest
        #expect(!m.isPieced && m.pieces == nil && m.assembly.isEmpty && m.piecesTotal == 1)
    }
}

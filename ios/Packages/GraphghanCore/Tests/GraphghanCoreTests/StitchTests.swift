import Foundation
import Testing
@testable import GraphghanCore

@Suite struct StitchTests {
    @Test func usNamesCoverTheCYCList() {
        #expect(StitchNames.name("sc", terms: .us) == "single crochet")
        #expect(StitchNames.name("hdc", terms: .us) == "half double crochet")
        #expect(StitchNames.name("dc", terms: .us) == "double crochet")
        #expect(StitchNames.name("tr", terms: .us) == "treble crochet")
        #expect(StitchNames.name("dtr", terms: .us) == "double treble crochet")
        #expect(StitchNames.name("sl st", terms: .us) == "slip stitch")
        #expect(StitchNames.name("ch", terms: .us) == "chain")
    }

    @Test func ukNamesCollideWithUSOnPurpose() {
        // The same abbreviation names a different stitch under each system: the reason terms is declared.
        #expect(StitchNames.name("dc", terms: .uk) == "double crochet")
        #expect(StitchNames.name("tr", terms: .uk) == "treble")
        #expect(StitchNames.name("htr", terms: .uk) == "half treble")
        #expect(StitchNames.name("dtr", terms: .uk) == "double treble")
        #expect(StitchNames.name("ss", terms: .uk) == "slip stitch")
        #expect(StitchNames.name("sc", terms: .uk) == nil)   // not a UK abbreviation
        #expect(StitchNames.name("hdc", terms: .uk) == nil)
    }

    @Test func unknownCodeHasNoName() {
        #expect(StitchNames.name("hhdc", terms: .us) == nil)
        #expect(StitchNames.name("", terms: .us) == nil)
    }

    @Test func boundaryDecodesWithDefaults() throws {
        let b = try JSONDecoder().decode(Boundary.self, from: Data(#"{"kind":"turn","chain":1}"#.utf8))
        #expect(b == Boundary(kind: .turn, chain: 1, countsAsStitch: false, color: nil))
        let full = try JSONDecoder().decode(Boundary.self, from: Data(#"{"kind":"join","chain":3,"counts_as_stitch":true,"color":"next"}"#.utf8))
        #expect(full == Boundary(kind: .join, chain: 3, countsAsStitch: true, color: .next))
    }

    @Test func boundaryRejectsUnknownKindAndMissingChain() {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Boundary.self, from: Data(#"{"kind":"flip","chain":1}"#.utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Boundary.self, from: Data(#"{"kind":"turn"}"#.utf8)) }
    }

    @Test func stitchResolvesNameFromTermsOrOverride() {
        let sc = Stitch(code: "sc", terms: .us, stitchName: nil, boundary: nil)
        #expect(sc.name == "single crochet")
        let ukDC = Stitch(code: "dc", terms: .uk, stitchName: nil, boundary: nil)
        #expect(ukDC.name == "double crochet")
        let custom = Stitch(code: "hhdc", terms: .us, stitchName: "herringbone half double crochet", boundary: nil)
        #expect(custom.name == "herringbone half double crochet")
        let renamed = Stitch(code: "sc", terms: .us, stitchName: "not really", boundary: nil)
        #expect(renamed.name == "single crochet")  // a chart cannot rename a CYC stitch
        let unknown = Stitch(code: "xyz", terms: .us, stitchName: nil, boundary: nil)
        #expect(unknown.name == nil)
    }
}

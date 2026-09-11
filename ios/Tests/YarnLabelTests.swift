import Testing
@testable import Graphghan

@Suite struct YarnLabelTests {
    @Test func emptyYarnFieldsFallBackToTheNote() {
        let yarn = ["brand": "", "line": "", "colorway": "", "note": "Gold"]
        #expect(YarnLabel.text(yarn: yarn, use: "moon") == "Gold · moon")
    }

    @Test func brandLineAndColorwayJoinWithSpaces() {
        let yarn = ["brand": "Lion Brand", "line": "Vanna's Choice", "colorway": "Mustard"]
        #expect(YarnLabel.text(yarn: yarn, use: nil) == "Lion Brand Vanna's Choice Mustard")
        #expect(YarnLabel.text(yarn: yarn, use: "moon") == "Lion Brand Vanna's Choice Mustard · moon")
    }

    @Test func partialYarnFieldsNeverLeaveAStraySeparator() {
        #expect(YarnLabel.text(yarn: ["brand": "", "colorway": "Mustard"], use: nil) == "Mustard")
        #expect(YarnLabel.text(yarn: ["brand": "Lion Brand", "line": ""], use: nil) == "Lion Brand")
    }

    @Test func nothingToSay() {
        #expect(YarnLabel.text(yarn: nil, use: nil) == nil)
        #expect(YarnLabel.text(yarn: ["brand": "", "note": ""], use: "") == nil)
    }

    @Test func useAloneWhenTheNoteIsEmpty() {
        #expect(YarnLabel.text(yarn: ["note": ""], use: "moon") == "moon")
        #expect(YarnLabel.text(yarn: nil, use: "moon") == "moon")
    }
}

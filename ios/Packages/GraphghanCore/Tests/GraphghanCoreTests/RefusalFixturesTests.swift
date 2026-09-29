import Testing
@testable import GraphghanCore

/// fixtures/chart-format/refused/ (spec §9): five otherwise-valid schema-3 documents, each
/// refused for exactly the one rule its name says. `FixturesTests` covers the top-level
/// `*.chart.json` set; this suite covers the refused subdirectory it deliberately leaves out.
@Suite struct RefusalFixturesTests {
    @Test func refusedFixtureSetMatchesSpec() {
        #expect(Set(Fixtures.refusedNames) == [
            "foundation-too-short", "gap-in-row", "row-without-stitches", "two-no-stitch-codes", "written-wrong-length",
        ])
    }

    @Test func gapInRowIsRefused() throws {
        #expect(throws: ChartError.noStitchInsideRow(0)) { try Chart.load(Fixtures.refusedData("gap-in-row")) }
    }

    @Test func rowWithoutStitchesIsRefused() throws {
        #expect(throws: ChartError.rowWithoutStitches(0)) { try Chart.load(Fixtures.refusedData("row-without-stitches")) }
    }

    @Test func twoNoStitchCodesAreRefused() throws {
        #expect(throws: ChartError.tooManyNoStitch(2)) { try Chart.load(Fixtures.refusedData("two-no-stitch-codes")) }
    }

    @Test func foundationTooShortIsRefused() throws {
        #expect(throws: ChartError.foundationTooShort(chain: 3, needed: 4)) {
            try Chart.load(Fixtures.refusedData("foundation-too-short"))
        }
    }

    @Test func writtenWrongLengthIsRefused() throws {
        #expect(throws: ChartError.writtenCount(got: 1, expected: 5)) {
            try Chart.load(Fixtures.refusedData("written-wrong-length"))
        }
    }
}

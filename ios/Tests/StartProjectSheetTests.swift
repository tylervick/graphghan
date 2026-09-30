import Testing
@testable import Graphghan

/// #206 review: a failed start of a pieced pattern names its pieces, not "the chart" -- there is
/// no single chart download to fail.
@Suite struct StartProjectSheetTests {
    @Test func aPiecedFailureNamesThePieces() {
        #expect(StartProjectSheet.startErrorText(pieced: true) == "Couldn't read this pattern's pieces.")
    }

    @Test func aSingleChartFailureKeepsTheOldSentence() {
        #expect(StartProjectSheet.startErrorText(pieced: false) == "Couldn't download the chart. Check your connection and try again.")
    }
}

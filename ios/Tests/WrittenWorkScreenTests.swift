import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct WrittenWorkScreenTests {
    static let phone = CGSize(width: 390, height: 844)
    static let strip = try! WrittenSequence(RowsDocument.load(TestFixtures.pieces("pieces/strip.rows.json")))
    static let strap = try! WrittenSequence(RowsDocument.load(TestFixtures.pieces("pieces/strap.rows.json")))
    /// One very long row: proves a long row (or an accessibility text size) never pushes the
    /// Back/Done bar off-screen (fix round 1, Critical).
    static let longRow: WrittenSequence = {
        let text = Array(repeating: "ch 1, turn, 6 sc,", count: 60).joined(separator: " ") + " fasten off."
        let entry = RowsDocument.Entry(label: "R 1", from: 1, to: 1, text: text, count: 6, code: nil, repeatText: nil)
        let id = RowsDocument.computeID([entry])
        let json = """
        {"schema":1,"id":"\(id)","piece":{"title":"Long"},"rows":[{"label":"R 1","from":1,"to":1,"count":6,"text":"\(text)"}]}
        """
        return WrittenSequence(try! RowsDocument.load(Data(json.utf8)))
    }()

    private func screen(_ seq: WrittenSequence, row: Int, title: String, finished: Bool = false, next: String? = nil) -> some View {
        WrittenWorkScreen(title: title, sequence: seq, cursor: Cursor(row: row, run: 0), finished: finished, next: next,
                          onDone: {}, onBack: {}, onClose: {}, onJump: {}, onFinishPiece: {}, onNext: {})
    }

    @Test func aRowInARange() throws {
        #expect(try Snapshots.assert(screen(Self.strip, row: 3, title: "Strip"), named: "written-work", size: Self.phone))
    }

    /// Review focus 3: no total, no "of", and a Finish piece action.
    @Test func anOpenEndedRow() throws {
        #expect(try Snapshots.assert(screen(Self.strap, row: 57, title: "Strap"), named: "written-work-open", size: Self.phone))
    }

    @Test func aFinishedPieceOffersTheNext() throws {
        #expect(try Snapshots.assert(screen(Self.strip, row: 5, title: "Strip", finished: true, next: "Fin 1 of 2"),
                                     named: "written-work-finished", size: Self.phone))
    }

    /// Fix round 1, Critical: the row card scrolls inside `WrittenWorkScreen`, with the Back/Done
    /// bar pinned outside the scroll region via `safeAreaInset`, so a very long row still leaves
    /// the bar on screen. `ImageRenderer` cannot flatten a `ScrollView` -- its content renders
    /// blank (#67) -- so this snapshot's card region is empty; what it proves is that the bar
    /// beneath it is still there.
    @Test func aLongRowKeepsTheBarOnScreen() throws {
        #expect(try Snapshots.assert(screen(Self.longRow, row: 1, title: "Long"), named: "written-work-long-row", size: Self.phone))
    }

    /// Fix round 1, Critical: `WrittenRowPanel` on its own, unscrolled -- what actually pins the
    /// row text down, since a full-screen snapshot can't show inside the `ScrollView` it lives in
    /// (#67).
    @Test func rowPanel() throws {
        let pass = try #require(Self.strip.pass(at: 3))
        let view = WrittenRowPanel(pass: pass, rowText: WrittenWorkScreen.rowText(row: 3, total: Self.strip.totalRows))
            .padding(16)
            .background(Color.ground.weave())
        #expect(try Snapshots.assert(view, named: "written-row-panel", size: CGSize(width: 390, height: 220)))
    }

    /// Same, for an open-ended row: "2. (56)", no total anywhere (review focus 3).
    @Test func rowPanelOpen() throws {
        let pass = try #require(Self.strap.pass(at: 57))
        let view = WrittenRowPanel(pass: pass, rowText: WrittenWorkScreen.rowText(row: 57, total: Self.strap.totalRows))
            .padding(16)
            .background(Color.ground.weave())
        #expect(try Snapshots.assert(view, named: "written-row-panel-open", size: CGSize(width: 390, height: 260)))
    }

    @Test func headerText() {
        #expect(WrittenWorkScreen.rowText(row: 31, total: 104) == "Row 31 of 104")
        #expect(WrittenWorkScreen.rowText(row: 57, total: nil) == "Row 57")
    }

    /// A cursor past the rows (a closed piece whose document lost rows) says so rather than
    /// showing an empty panel.
    @Test func aRowNoLongerInThePatternSaysSo() {
        #expect(WrittenWorkScreen.missingRowMessage(sequence: Self.strip, row: 9, finished: false) == "This row isn't in the pattern any more.")
        #expect(WrittenWorkScreen.missingRowMessage(sequence: Self.strip, row: 3, finished: false) == nil)
        #expect(WrittenWorkScreen.missingRowMessage(sequence: Self.strip, row: 9, finished: true) == nil)
    }
}

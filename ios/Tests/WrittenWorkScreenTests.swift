import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@MainActor
@Suite struct WrittenWorkScreenTests {
    static let phone = CGSize(width: 390, height: 844)
    static let strip = try! WrittenSequence(RowsDocument.load(TestFixtures.pieces("pieces/strip.rows.json")))
    static let strap = try! WrittenSequence(RowsDocument.load(TestFixtures.pieces("pieces/strap.rows.json")))

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

    @Test func headerText() {
        #expect(WrittenWorkScreen.rowText(row: 31, total: 104) == "Row 31 of 104")
        #expect(WrittenWorkScreen.rowText(row: 57, total: nil) == "Row 57")
    }
}

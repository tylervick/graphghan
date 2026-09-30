import Foundation
import SwiftData
import GraphghanCore

/// One piece copy's place in a pieced project (spec 2026-09-25 §6.1). The project's own cursor
/// fields mirror the current piece's; this keeps every started copy's.
@Model
final class PieceProgress {
    var pieceID: String
    var copy: Int
    /// The chart id or rows id the cursor walks.
    var docID: String
    var cursorRow: Int = 1
    var cursorRun: Int = 0
    var cursorStitch: Int = 0
    var finished: Date?
    /// Deliberately no inverse array on `Project`, as for `ProgressEvent` (#79).
    var project: Project?

    init(pieceID: String, copy: Int, docID: String) {
        self.pieceID = pieceID; self.copy = copy; self.docID = docID
        self.cursorRow = 1; self.cursorRun = 0; self.cursorStitch = 0; self.finished = nil; self.project = nil
    }

    var cursor: Cursor {
        get { Cursor(row: cursorRow, run: cursorRun, stitch: cursorStitch) }
        set { cursorRow = newValue.row; cursorRun = newValue.run; cursorStitch = newValue.stitch }
    }
    var key: PieceKey { PieceKey(piece: pieceID, copy: copy) }
}

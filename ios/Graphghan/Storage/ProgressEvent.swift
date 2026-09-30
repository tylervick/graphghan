import Foundation
import SwiftData
import GraphghanCore

@Model
final class ProgressEvent {
    var t: Date
    var row: Int
    var run: Int
    var stitch: Int = 0
    var kindRaw: String
    /// Which piece copy of a pieced project; nil for a single-chart project.
    var piece: String? = nil
    var copy: Int = 1
    /// The project this event belongs to. Deliberately no inverse array on `Project` (#79).
    var project: Project?

    init(t: Date, row: Int, run: Int, stitch: Int = 0, kind: EventKind, piece: String? = nil, copy: Int = 1) {
        self.t = t; self.row = row; self.run = run; self.stitch = stitch; self.kindRaw = kind.rawValue
        self.piece = piece; self.copy = copy; self.project = nil
    }

    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .advance }
}

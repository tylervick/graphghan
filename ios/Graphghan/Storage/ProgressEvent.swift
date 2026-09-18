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
    /// The project this event belongs to. Deliberately no inverse array on `Project` (#79).
    var project: Project?

    init(t: Date, row: Int, run: Int, stitch: Int = 0, kind: EventKind) {
        self.t = t; self.row = row; self.run = run; self.stitch = stitch; self.kindRaw = kind.rawValue; self.project = nil
    }

    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .advance }
}

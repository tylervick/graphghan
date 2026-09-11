import Foundation
import SwiftData
import GraphghanCore

@Model
final class ProgressEvent {
    var t: Date
    var row: Int
    var run: Int
    var kindRaw: String
    var project: Project?

    init(t: Date, row: Int, run: Int, kind: EventKind) {
        self.t = t; self.row = row; self.run = run; self.kindRaw = kind.rawValue; self.project = nil
    }

    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .advance }
}

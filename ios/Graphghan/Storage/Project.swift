import Foundation
import SwiftData
import GraphghanCore

/// One instance of working a chart: which chart, where the crocheter is, and the event log.
@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var patternID: String
    var chartID: String
    var chartVariant: String
    var chartGaugeKey: String
    var patternVersion: String
    var title: String
    var started: Date
    var finished: Date?
    var notes: String
    var cursorRow: Int
    var cursorRun: Int
    /// Cells of the current run already worked (spec §4.2). Added after build 5; the default is
    /// what makes this a lightweight migration.
    var cursorStitch: Int = 0
    /// `CountStep.rawValue`: how many cells a tap counts inside a fill. App state, never exported.
    var countStep: Int = CountStep.default.rawValue
    var lastWorked: Date?
    // The event log is not modelled as an array here on purpose (#79): a to-many relationship
    // made every insert maintain its inverse, so a tap cost time proportional to the project's
    // history. Events point at their project (`ProgressEvent.project`) and are fetched by
    // predicate through `ProjectService.events(for:)`; deleting a project deletes them explicitly.

    init(patternID: String, chartID: String, chartVariant: String, chartGaugeKey: String, patternVersion: String, title: String, started: Date) {
        self.id = UUID()
        self.patternID = patternID
        self.chartID = chartID
        self.chartVariant = chartVariant
        self.chartGaugeKey = chartGaugeKey
        self.patternVersion = patternVersion
        self.title = title
        self.started = started
        self.finished = nil
        self.notes = ""
        self.cursorRow = 1
        self.cursorRun = 0
        self.cursorStitch = 0
        self.countStep = CountStep.default.rawValue
        self.lastWorked = nil
    }

    var cursor: Cursor {
        get { Cursor(row: cursorRow, run: cursorRun, stitch: cursorStitch) }
        set { cursorRow = newValue.row; cursorRun = newValue.run; cursorStitch = newValue.stitch }
    }

    var step: CountStep {
        get { CountStep(rawValue: countStep) ?? .default }
        set { countStep = newValue.rawValue }
    }

    var isFinished: Bool { finished != nil }
}

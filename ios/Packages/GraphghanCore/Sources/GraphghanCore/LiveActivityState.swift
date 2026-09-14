import Foundation

/// A palette entry as the Live Activity draws it.
public struct ActivitySwatch: Codable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let hex: String
    public init(code: String, name: String, hex: String) { self.code = code; self.name = name; self.hex = hex }
}

/// Static attributes of one project's activity (spec §7). `stitch` and `turningChain` are static
/// for a project, so they live here rather than in the state.
public struct WorkActivityInfo: Codable, Hashable, Sendable {
    public let projectID: UUID
    public let title: String
    public let totalRows: Int
    public let totalStitches: Int
    public let palette: [ActivitySwatch]
    /// The abbreviation the chart is worked in (`gauge.stitch`), when the chart says.
    public let stitch: String?
    /// Chains to make at the turn, only for a `turn` boundary; nil means the chart does not say.
    public let turningChain: Int?
    public init(projectID: UUID, title: String, totalRows: Int, totalStitches: Int, palette: [ActivitySwatch],
                stitch: String? = nil, turningChain: Int? = nil) {
        self.projectID = projectID; self.title = title; self.totalRows = totalRows; self.totalStitches = totalStitches; self.palette = palette
        self.stitch = stitch; self.turningChain = turningChain
    }
    public func swatch(for code: String) -> ActivitySwatch? { palette.first { $0.code == code } }
}

/// Dynamic state of the activity: what the crocheter is on right now.
public struct WorkActivityState: Codable, Hashable, Sendable {
    public var row: Int
    public var rowCount: Int
    public var side: String?
    public var runIndex: Int
    public var currentCode: String?
    public var currentCount: Int?
    public var nextCode: String?
    public var nextCount: Int?
    public var isLastInRow: Bool
    public var percent: Double
    public var finished: Bool
    /// Only set for the explanatory final state (project or chart gone).
    public var message: String?
    /// The run Back returns to (the one before the cursor, or the last of the previous row); nil at the start.
    public var previousCode: String?
    public var previousCount: Int?

    public init(row: Int, rowCount: Int, side: String?, runIndex: Int, currentCode: String?, currentCount: Int?, nextCode: String?, nextCount: Int?,
                isLastInRow: Bool, percent: Double, finished: Bool, message: String? = nil, previousCode: String? = nil, previousCount: Int? = nil) {
        self.row = row; self.rowCount = rowCount; self.side = side; self.runIndex = runIndex
        self.currentCode = currentCode; self.currentCount = currentCount; self.nextCode = nextCode; self.nextCount = nextCount
        self.isLastInRow = isLastInRow; self.percent = percent; self.finished = finished; self.message = message
        self.previousCode = previousCode; self.previousCount = previousCount
    }

    public static func unavailable(_ message: String) -> WorkActivityState {
        WorkActivityState(row: 0, rowCount: 0, side: nil, runIndex: 0, currentCode: nil, currentCount: nil, nextCode: nil, nextCount: nil,
                          isLastInRow: true, percent: 0, finished: true, message: message)
    }
}

/// Pure builders: no ActivityKit here, so the app and its tests share one definition of "what the lock screen shows".
public enum LiveActivityState {
    public static func make(cursor: Cursor, sequence: WorkSequence) -> WorkActivityState? {
        guard let pass = sequence.pass(at: cursor.row), let done = sequence.stitchesBefore(cursor) else { return nil }
        let finished = WorkEngine.isFinished(cursor, in: sequence)
        let current: Run? = cursor.run < pass.runs.count ? pass.runs[cursor.run] : nil
        let next: Run? = cursor.run + 1 < pass.runs.count ? pass.runs[cursor.run + 1] : nil
        let total = sequence.totalStitches
        let percent = total > 0 ? (100 * Double(done) / Double(total) * 10).rounded(.toNearestOrEven) / 10 : 0
        let previous: Run? = WorkEngine.apply(.back, to: cursor, in: sequence).flatMap { step in
            sequence.pass(at: step.cursor.row).flatMap { step.cursor.run < $0.runs.count ? $0.runs[step.cursor.run] : nil }
        }
        return WorkActivityState(
            row: cursor.row, rowCount: sequence.passes.count, side: pass.side?.rawValue, runIndex: cursor.run,
            currentCode: current?.code, currentCount: current?.count, nextCode: next?.code, nextCount: next?.count,
            isLastInRow: next == nil, percent: percent, finished: finished, message: nil,
            previousCode: previous?.code, previousCount: previous?.count)
    }

    public static func info(projectID: UUID, chart: Chart, sequence: WorkSequence) -> WorkActivityInfo {
        let stitch = chart.stitch
        let chain: Int? = stitch?.boundary.flatMap { $0.kind == .turn ? $0.chain : nil }
        return WorkActivityInfo(projectID: projectID, title: chart.title, totalRows: sequence.passes.count, totalStitches: sequence.totalStitches,
                                palette: chart.palette.map { ActivitySwatch(code: $0.code, name: $0.name, hex: $0.hex) },
                                stitch: stitch?.code, turningChain: chain)
    }
}

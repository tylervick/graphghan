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
    public let totalCells: Int
    public let palette: [ActivitySwatch]
    /// The abbreviation the chart is worked in (`gauge.stitch`), when the chart says.
    public let stitch: String?
    /// Chains to make at the turn, only for a `turn` boundary; nil means the chart does not say.
    public let turningChain: Int?

    // The encoded name stays `totalStitches`: an activity started before an app upgrade is still
    // running in the extension and decodes with the old key. Only the Swift name moves.
    enum CodingKeys: String, CodingKey {
        case projectID, title, totalRows, totalCells = "totalStitches", palette, stitch, turningChain
    }

    public init(projectID: UUID, title: String, totalRows: Int, totalCells: Int, palette: [ActivitySwatch],
                stitch: String? = nil, turningChain: Int? = nil) {
        self.projectID = projectID; self.title = title; self.totalRows = totalRows; self.totalCells = totalCells; self.palette = palette
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
    /// Cells of the current run already worked; only meaningful when `counting`.
    public var stitch: Int
    /// The current run is a fill: the lock screen shows `stitch of currentCount`.
    public var counting: Bool
    /// The row is worked and the turn is the next tap.
    public var atBoundary: Bool

    public init(row: Int, rowCount: Int, side: String?, runIndex: Int, currentCode: String?, currentCount: Int?, nextCode: String?, nextCount: Int?,
                isLastInRow: Bool, percent: Double, finished: Bool, message: String? = nil, previousCode: String? = nil, previousCount: Int? = nil,
                stitch: Int = 0, counting: Bool = false, atBoundary: Bool = false) {
        self.row = row; self.rowCount = rowCount; self.side = side; self.runIndex = runIndex
        self.currentCode = currentCode; self.currentCount = currentCount; self.nextCode = nextCode; self.nextCount = nextCount
        self.isLastInRow = isLastInRow; self.percent = percent; self.finished = finished; self.message = message
        self.previousCode = previousCode; self.previousCount = previousCount
        self.stitch = stitch; self.counting = counting; self.atBoundary = atBoundary
    }

    public static func unavailable(_ message: String) -> WorkActivityState {
        WorkActivityState(row: 0, rowCount: 0, side: nil, runIndex: 0, currentCode: nil, currentCount: nil, nextCode: nil, nextCount: nil,
                          isLastInRow: true, percent: 0, finished: true, message: message)
    }

    enum CodingKeys: String, CodingKey {
        case row, rowCount, side, runIndex, currentCode, currentCount, nextCode, nextCount, isLastInRow, percent, finished, message
        case previousCode, previousCount, stitch, counting, atBoundary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        row = try c.decode(Int.self, forKey: .row)
        rowCount = try c.decode(Int.self, forKey: .rowCount)
        side = try c.decodeIfPresent(String.self, forKey: .side)
        runIndex = try c.decode(Int.self, forKey: .runIndex)
        currentCode = try c.decodeIfPresent(String.self, forKey: .currentCode)
        currentCount = try c.decodeIfPresent(Int.self, forKey: .currentCount)
        nextCode = try c.decodeIfPresent(String.self, forKey: .nextCode)
        nextCount = try c.decodeIfPresent(Int.self, forKey: .nextCount)
        isLastInRow = try c.decode(Bool.self, forKey: .isLastInRow)
        percent = try c.decode(Double.self, forKey: .percent)
        finished = try c.decode(Bool.self, forKey: .finished)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        previousCode = try c.decodeIfPresent(String.self, forKey: .previousCode)
        previousCount = try c.decodeIfPresent(Int.self, forKey: .previousCount)
        stitch = try c.decodeIfPresent(Int.self, forKey: .stitch) ?? 0
        counting = try c.decodeIfPresent(Bool.self, forKey: .counting) ?? false
        atBoundary = try c.decodeIfPresent(Bool.self, forKey: .atBoundary) ?? false
    }
}

/// Pure builders: no ActivityKit here, so the app and its tests share one definition of "what the lock screen shows".
public enum LiveActivityState {
    public static func make(cursor: Cursor, sequence: WorkSequence) -> WorkActivityState? {
        guard let pass = sequence.pass(at: cursor.row), let done = sequence.cellsBefore(cursor) else { return nil }
        let finished = WorkEngine.isFinished(cursor, in: sequence)
        let atBoundary = !finished && cursor.run == pass.runs.count
        let current: Run? = cursor.run < pass.runs.count ? pass.runs[cursor.run] : nil
        let next: Run? = atBoundary
            ? sequence.pass(at: cursor.row + 1)?.runs.first
            : (cursor.run + 1 < pass.runs.count ? pass.runs[cursor.run + 1] : nil)
        let total = sequence.totalCells
        let percent = total > 0 ? (100 * Double(done) / Double(total) * 10).rounded(.toNearestOrEven) / 10 : 0
        // At the boundary, or crossing a row: `apply(.back)` can itself land on a boundary
        // position (`run == runs.count`), so clamp to the row's last run rather than miss it.
        let previous: Run? = WorkEngine.apply(.back, to: cursor, in: sequence).flatMap { step in
            sequence.pass(at: step.cursor.row).flatMap { pass in
                pass.runs.isEmpty ? nil : pass.runs[min(step.cursor.run, pass.runs.count - 1)]
            }
        }
        return WorkActivityState(
            row: cursor.row, rowCount: sequence.passes.count, side: pass.side?.rawValue, runIndex: cursor.run,
            currentCode: current?.code, currentCount: current?.count, nextCode: next?.code, nextCount: next?.count,
            isLastInRow: atBoundary || cursor.run + 1 >= pass.runs.count, percent: percent, finished: finished, message: nil,
            previousCode: previous?.code, previousCount: previous?.count,
            stitch: cursor.stitch, counting: WorkEngine.isCounting(cursor, in: sequence), atBoundary: atBoundary)
    }

    public static func info(projectID: UUID, chart: Chart, sequence: WorkSequence) -> WorkActivityInfo {
        let stitch = chart.stitch
        let chain: Int? = stitch?.boundary.flatMap { $0.kind == .turn ? $0.chain : nil }
        return WorkActivityInfo(projectID: projectID, title: chart.title, totalRows: sequence.passes.count, totalCells: sequence.totalCells,
                                palette: chart.palette.map { ActivitySwatch(code: $0.code, name: $0.name, hex: $0.hex) },
                                stitch: stitch?.code, turningChain: chain)
    }
}

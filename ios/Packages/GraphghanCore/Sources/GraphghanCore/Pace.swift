import Foundation

public struct Session: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let stitches: Int
    public init(start: Date, end: Date, stitches: Int) { self.start = start; self.end = end; self.stitches = stitches }
    public var seconds: Int { Int(end.timeIntervalSince(start).rounded(.down)) }
}

public struct ProgressSummary: Equatable, Sendable {
    public let percent: Double
    public let stitchesDone: Int
    public let totalStitches: Int
    public let sessions: [Session]
    public let activeSeconds: Int
    public let stitchesPerHour: Double?
    public init(percent: Double, stitchesDone: Int, totalStitches: Int, sessions: [Session], activeSeconds: Int, stitchesPerHour: Double?) {
        self.percent = percent; self.stitchesDone = stitchesDone; self.totalStitches = totalStitches
        self.sessions = sessions; self.activeSeconds = activeSeconds; self.stitchesPerHour = stitchesPerHour
    }
}

/// Sessions, rate and percent exactly as graphghan.progress.summarize computes them, plus the finish estimate.
public enum Pace {
    public static let sessionGap: TimeInterval = 1200

    private static func round1(_ x: Double) -> Double { (x * 10).rounded(.toNearestOrEven) / 10 }

    public static func summarize(events: [ProgressEventRecord], cursor: Cursor, sequence: WorkSequence, gap: TimeInterval = sessionGap) -> ProgressSummary {
        let total = sequence.totalStitches
        let done = sequence.stitchesBefore(cursor) ?? 0
        let sorted = events.sorted { $0.t < $1.t }
        var sessions: [Session] = []
        var start: Date?
        var end: Date?
        var fromCursor = Cursor.start
        var toCursor = Cursor.start
        var prevCursor = Cursor.start
        func close() {
            if let s = start, let e = end {
                let before = sequence.stitchesBefore(fromCursor) ?? 0
                let after = sequence.stitchesBefore(toCursor) ?? 0
                sessions.append(Session(start: s, end: e, stitches: max(0, after - before)))
            }
        }
        for e in sorted {
            if let last = end, e.t.timeIntervalSince(last) <= gap {
                end = e.t
            } else {
                close()
                start = e.t
                end = e.t
                fromCursor = prevCursor
            }
            toCursor = Cursor(row: e.row, run: e.run)
            prevCursor = toCursor
        }
        close()
        let active = sessions.reduce(0) { $0 + $1.seconds }
        let advanced = sessions.reduce(0) { $0 + $1.stitches }
        let rate: Double? = active > 0 ? round1(Double(advanced) / (Double(active) / 3600)) : nil
        return ProgressSummary(
            percent: total > 0 ? round1(100 * Double(done) / Double(total)) : 0,
            stitchesDone: done, totalStitches: total, sessions: sessions, activeSeconds: active, stitchesPerHour: rate
        )
    }

    /// Remaining stitches at the observed rate, spread over the mean active hours per calendar day
    /// across the last `windowDays`. Nil until `minimumSessions` sessions exist or with no rate.
    public static func estimatedFinish(remainingStitches: Int, stitchesPerHour: Double?, sessions: [Session], now: Date, windowDays: Int = 14, minimumSessions: Int = 3) -> Date? {
        guard sessions.count >= minimumSessions, let rate = stitchesPerHour, rate > 0 else { return nil }
        if remainingStitches <= 0 { return now }
        let windowStart = now.addingTimeInterval(-Double(windowDays) * 86400)
        var activeSeconds = 0.0
        for s in sessions {
            let start = max(s.start, windowStart)
            let end = min(s.end, now)
            if end > start { activeSeconds += end.timeIntervalSince(start) }
        }
        let hoursPerDay = activeSeconds / 3600 / Double(windowDays)
        guard hoursPerDay > 0 else { return nil }
        let hoursNeeded = Double(remainingStitches) / rate
        return now.addingTimeInterval(hoursNeeded / hoursPerDay * 86400)
    }
}

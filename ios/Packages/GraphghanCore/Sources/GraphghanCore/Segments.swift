/// A group of runs in a pass that the crocheter attends to as one thing (spec §4.1).
public struct Segment: Equatable, Sendable {
    public enum Kind: String, Sendable { case braid, `repeat`, fill, run }
    public let kind: Kind
    /// Run indices in reading order.
    public let runs: Range<Int>
    /// Runs per repetition; 0 unless `kind == .repeat`.
    public let period: Int
    /// How many times the unit repeats; 0 unless `kind == .repeat`.
    public let repetitions: Int
    public init(kind: Kind, runs: Range<Int>, period: Int = 0, repetitions: Int = 0) {
        self.kind = kind; self.runs = runs; self.period = period; self.repetitions = repetitions
    }
}

/// Where a fill ends, said against the row below: `offset` is how many cells past (positive) or
/// before (negative) the place where `code` starts in the row below, in reading direction.
public struct Landmark: Equatable, Sendable {
    public let code: String
    public let offset: Int
    public init(code: String, offset: Int) { self.code = code; self.offset = offset }
}

/// Pure partition of a pass's runs into segments. The thresholds are the spec's; the fixture rows in
/// SegmentsTests pin them.
public enum Segments {
    /// A twisted-cord border produces eight runs of four or fewer at each edge of a row.
    public static let braidRuns = 8
    public static let braidMaxCount = 4
    /// A repeat band is a unit of 2 to 4 runs repeated at least three times in a row.
    public static let repeatMinPeriod = 2
    public static let repeatMaxPeriod = 4
    public static let repeatMinRepetitions = 3
    /// A single run this long is worked by counting, not by reading.
    public static let fillMinCells = 20

    public static func of(_ pass: Pass) -> [Segment] {
        let runs = pass.runs
        let n = runs.count
        var segments: [Segment] = []
        var lo = 0
        var hi = n
        func shortRuns(_ range: Range<Int>) -> Bool { range.allSatisfy { runs[$0].count <= braidMaxCount } }
        if n >= braidRuns, shortRuns(0..<braidRuns) {
            segments.append(Segment(kind: .braid, runs: 0..<braidRuns))
            lo = braidRuns
        }
        if n >= 2 * braidRuns, shortRuns((n - braidRuns)..<n) {
            hi = n - braidRuns
        }
        var i = lo
        while i < hi {
            if let band = repeatBand(at: i, in: runs, until: hi) {
                segments.append(band)
                i = band.runs.upperBound
            } else {
                segments.append(Segment(kind: runs[i].count >= fillMinCells ? .fill : .run, runs: i..<(i + 1)))
                i += 1
            }
        }
        if hi < n { segments.append(Segment(kind: .braid, runs: hi..<n)) }
        return segments
    }

    /// The longest repeat band that starts exactly at `start`, or nil when none reaches three repetitions.
    private static func repeatBand(at start: Int, in runs: [Run], until end: Int) -> Segment? {
        var best: Segment?
        for period in repeatMinPeriod...repeatMaxPeriod {
            guard start + period <= end else { break }
            let unit = runs[start..<(start + period)].map { ($0.count, $0.code) }
            var reps = 1
            while start + (reps + 1) * period <= end,
                  runs[(start + reps * period)..<(start + (reps + 1) * period)].map({ ($0.count, $0.code) }).elementsEqual(unit, by: ==) {
                reps += 1
            }
            guard reps >= repeatMinRepetitions else { continue }
            let span = reps * period
            if best == nil || span > best!.runs.count {
                best = Segment(kind: .repeat, runs: start..<(start + span), period: period, repetitions: reps)
            }
        }
        return best
    }

    public static func segment(containing run: Int, in pass: Pass) -> Segment? {
        of(pass).first { $0.runs.contains(run) }
    }

    public static func repetition(of run: Int, in segment: Segment) -> Int? {
        guard segment.kind == .repeat, segment.runs.contains(run), segment.period > 0 else { return nil }
        return (run - segment.runs.lowerBound) / segment.period
    }

    /// The colour start in the row below nearest to where `run` ends, in reading direction, counting
    /// only starts strictly inside the run's span. Nil without grid columns, without a row below, or
    /// when the row below is plain under the run.
    public static func landmark(for run: Run, direction: Direction?, below: Pass?) -> Landmark? {
        guard let x0 = run.x0, let below, let direction else { return nil }
        let x1 = x0 + run.count
        let end = direction == .ltr ? x1 : x0
        var starts: [(x: Int, code: String)] = []
        for r in below.runs {
            guard let bx0 = r.x0 else { return nil }
            let startX = direction == .ltr ? bx0 : bx0 + r.count
            if startX > x0, startX < x1 { starts.append((startX, r.code)) }
        }
        guard let best = starts.min(by: { abs($0.x - end) < abs($1.x - end) }) else { return nil }
        let offset = direction == .ltr ? end - best.x : best.x - end
        return Landmark(code: best.code, offset: offset)
    }
}

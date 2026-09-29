import Foundation

public enum ChartError: Error, Equatable {
    case unsupportedSchema(Int)
    case invalidSize(width: Int, height: Int)
    case tooManyColors(Int)
    case invalidCode(String)
    case duplicateCode(String)
    case invalidHex(code: String, hex: String)
    case heightMismatch(rows: Int, height: Int)
    case malformedRow(Int)
    case unknownCode(row: Int, code: String)
    case rowSum(row: Int, got: Int, expected: Int)
    case idMismatch(expected: String, found: String)
    /// The foundation cannot carry row 1: refused, not warned (#50).
    case foundationTooShort(chain: Int, needed: Int)
    /// `chart.cell.kind` is outside the closed enum (spec §4.1): the document is refused, not
    /// degraded — an unrecognised cardinality is one this repo's writers did not produce and a
    /// reader cannot reason about at all.
    case unsupportedCellKind(String)
    /// `"stitch": false` in a schema 2 document: a schema 2 reader would count the ground (spec §5.1).
    case noStitchNeedsSchema3
    /// More than one palette colour is `"stitch": false`.
    case tooManyNoStitch(Int)
    /// A no-stitch cell between stitches of a grid row: one stitched span per row.
    case noStitchInsideRow(Int)
    /// A grid row with no stitches at all.
    case rowWithoutStitches(Int)
    /// `written` must have one entry per pass.
    case writtenCount(got: Int, expected: Int)
}

/// One run of a grid row in left-to-right order: palette index, length, leftmost column.
public struct GridRun: Equatable, Sendable {
    public let colorIndex: Int
    public let count: Int
    public let x0: Int
    public init(colorIndex: Int, count: Int, x0: Int) {
        self.colorIndex = colorIndex; self.count = count; self.x0 = x0
    }
}

public struct FinishedSize: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let unit: String
}

/// A decoded, validated chart: the document plus its cells as palette indexes, top row first.
public struct Chart: Sendable {
    public let document: ChartDocument
    public let width: Int
    public let height: Int
    public let palette: [ChartDocument.PaletteEntry]
    public let cells: [UInt8]
    public let runsByRow: [[GridRun]]
    /// Non-fatal observations, e.g. codes that differ only by case.
    public let warnings: [String]
    private let index: [String: Int]
    /// The palette index of a shaped piece's ground (`"stitch": false`, schema 3), or nil.
    public let noStitchIndex: Int?

    public var id: String { document.chart.id }
    public var title: String { document.pattern.title }
    /// The chart has a ground nobody stitches: its rows are shaped.
    public var isShaped: Bool { noStitchIndex != nil }
    /// Whether cells of this palette index are worked.
    public func isStitched(colorIndex: Int) -> Bool { colorIndex != noStitchIndex }
    /// The pattern's own row text, one per pass, when the chart carries it.
    public var written: [String]? { document.written }

    /// The stitch the chart is worked in, from `gauge` only. Nil without `gauge.stitch`; the
    /// boundary comes from the document or not at all (spec §6.3: never derived).
    public var stitch: Stitch? {
        guard let code = document.gauge.stitch, !code.isEmpty else { return nil }
        return Stitch(code: code, terms: document.gauge.terms ?? .us, stitchName: document.gauge.stitchName, boundary: document.gauge.boundary)
    }

    public var foundation: ChartDocument.Foundation? { document.foundation }

    /// What one grid cell is. `.stitch` unless the chart says otherwise.
    public var cellKind: CellKind { document.chart.cell?.kind ?? .stitch }

    public var cellAspect: Double {
        (document.gauge.stitches / document.gauge.rows * 10000).rounded() / 10000
    }

    /// `gauge.unit` says what the gauge counts; `cellKind` says what one grid cell is. Dividing the
    /// grid by the gauge is valid exactly when they name the same thing (#48). Mirrors
    /// graphghan.chartdoc.size_derives.
    public var sizeDerives: Bool {
        let unit = document.gauge.unit ?? "stitches"
        switch cellKind {
        case .stitch: return unit == "stitches"
        case .tile: return unit == "tiles"
        case .block, .motif, .pair: return false
        }
    }

    /// Finished size at the design gauge, or nil when the gauge and the grid do not count the same
    /// thing. A wrong size is worse than none.
    public var finishedSize: FinishedSize? {
        guard sizeDerives else { return nil }
        let g = document.gauge
        let w = Double(width) / (g.stitches / g.over.value)
        let h = Double(height) / (g.rows / g.over.value)
        return FinishedSize(width: (w * 10).rounded() / 10, height: (h * 10).rounded() / 10, unit: g.over.unit)
    }

    public func colorIndex(of code: String) -> Int? { index[code] }

    public func cell(x: Int, y: Int) -> Int { Int(cells[y * width + x]) }

    public static func load(_ data: Data) throws -> Chart {
        try Chart(document: ChartDocument.decode(data))
    }

    public init(document: ChartDocument) throws { try self.init(document: document, verifyID: true) }

    static func unchecked(document: ChartDocument) throws -> Chart { try Chart(document: document, verifyID: false) }

    init(document: ChartDocument, verifyID: Bool) throws {
        guard document.schema == 2 || document.schema == 3 else { throw ChartError.unsupportedSchema(document.schema) }
        // The schema's minimum is 1 for both; an empty grid would divide by zero in the size and
        // strip math and index nothing safely.
        guard document.chart.width >= 1, document.chart.height >= 1 else {
            throw ChartError.invalidSize(width: document.chart.width, height: document.chart.height)
        }
        guard document.palette.count <= 255 else { throw ChartError.tooManyColors(document.palette.count) }
        var index: [String: Int] = [:]
        var folded: [String: String] = [:]
        var warnings: [String] = []
        for (i, entry) in document.palette.enumerated() {
            guard RunString.isValidCode(entry.code) else { throw ChartError.invalidCode(entry.code) }
            guard index[entry.code] == nil else { throw ChartError.duplicateCode(entry.code) }
            guard Chart.isHex(entry.hex) else { throw ChartError.invalidHex(code: entry.code, hex: entry.hex) }
            index[entry.code] = i
            if let other = folded[entry.code.lowercased()] {
                warnings.append("palette codes \(other) and \(entry.code) differ only by case; easy to misread at the hook")
            } else {
                folded[entry.code.lowercased()] = entry.code
            }
        }
        let marked = document.palette.filter { $0.stitch == false }.map(\.code)
        guard marked.count <= 1 else { throw ChartError.tooManyNoStitch(marked.count) }
        guard marked.isEmpty || document.schema == 3 else { throw ChartError.noStitchNeedsSchema3 }
        let noStitchIndex = marked.first.flatMap { index[$0] }
        let width = document.chart.width
        let height = document.chart.height
        guard document.rows.count == height else { throw ChartError.heightMismatch(rows: document.rows.count, height: height) }
        var cells = [UInt8](repeating: 0, count: width * height)
        var runsByRow: [[GridRun]] = []
        runsByRow.reserveCapacity(height)
        for (y, row) in document.rows.enumerated() {
            guard let parsed = RunString.parse(row) else { throw ChartError.malformedRow(y) }
            var x = 0
            var runs: [GridRun] = []
            for (code, count) in parsed {
                guard let ci = index[code] else { throw ChartError.unknownCode(row: y, code: code) }
                guard x + count <= width else { throw ChartError.rowSum(row: y, got: parsed.reduce(0) { $0 + $1.count }, expected: width) }
                for i in 0..<count { cells[y * width + x + i] = UInt8(ci) }
                runs.append(GridRun(colorIndex: ci, count: count, x0: x))
                x += count
            }
            guard x == width else { throw ChartError.rowSum(row: y, got: x, expected: width) }
            if let ns = noStitchIndex {
                let stitched = runs.filter { $0.colorIndex != ns }
                guard let first = stitched.first, let last = stitched.last else { throw ChartError.rowWithoutStitches(y) }
                // One stitched span per row: the stitched runs fill it without a gap.
                guard last.x0 + last.count - first.x0 == stitched.reduce(0, { $0 + $1.count }) else { throw ChartError.noStitchInsideRow(y) }
            }
            runsByRow.append(runs)
        }
        if verifyID {
            let expected = ChartID.compute(codes: document.palette.map(\.code), rows: document.rows, technique: document.technique,
                                           passes: document.passes, cell: document.chart.cellRaw, noStitch: marked.first)
            guard expected == document.chart.id else { throw ChartError.idMismatch(expected: expected, found: document.chart.id) }
        }
        if let foundation = document.foundation {
            // Pass 1 works the bottom row unless the technique starts at the top (WorkSequence),
            // and a shaped row 1 is its stitches, not the chart's width (spec §5.1).
            let y1 = document.techniqueStart == "bottom" ? height - 1 : 0
            let first = Chart.pass1Stitches(noStitchIndex: noStitchIndex, width: width, passes: document.passes, y1Runs: runsByRow[y1])
            let needed = first + (foundation.firstStitchIn ?? 1) - 1
            guard foundation.chain >= needed else { throw ChartError.foundationTooShort(chain: foundation.chain, needed: needed) }
        }
        if let written = document.written {
            let passCount = document.passes?.arrayValue?.count ?? height
            guard written.count == passCount else { throw ChartError.writtenCount(got: written.count, expected: passCount) }
        }
        self.document = document
        self.width = width
        self.height = height
        self.palette = document.palette
        self.cells = cells
        self.runsByRow = runsByRow
        self.warnings = warnings
        self.index = index
        self.noStitchIndex = noStitchIndex
    }

    static func isHex(_ s: String) -> Bool {
        s.count == 7 && s.hasPrefix("#") && s.dropFirst().allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// Stitches in the grid row pass 1 works: the chart's width unless the chart is shaped.
    /// Explicit `passes` win here exactly as they win in `WorkSequence`: pass 1's own run counts
    /// are used, since its grid row need not be the technique-derived one at all. Otherwise
    /// `y1Runs` -- the row `WorkSequence` would derive for pass 1. Falls back to `width` wherever
    /// the shape doesn't parse cleanly. Mirrors graphghan.chartdoc._pass_1_stitches.
    private static func pass1Stitches(noStitchIndex: Int?, width: Int, passes: JSONValue?, y1Runs: [GridRun]) -> Int {
        guard let ns = noStitchIndex else { return width }
        if let list = passes?.arrayValue, !list.isEmpty {
            guard let runsRaw = list[0].objectValue?["runs"]?.arrayValue, !runsRaw.isEmpty else { return width }
            var total = 0
            for r in runsRaw {
                guard let count = r.objectValue?["count"]?.intValue else { return width }
                total += count
            }
            return total
        }
        return y1Runs.filter { $0.colorIndex != ns }.reduce(0) { $0 + $1.count }
    }
}

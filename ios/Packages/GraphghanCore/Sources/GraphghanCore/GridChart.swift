import Foundation

/// `ext.graphghan.import` (phone import spec §6.3): where the chart came from and how far the
/// written rows were checked against it. The chart id ignores it; the detail screen reads it.
public struct ImportRecord: Sendable, Equatable {
    /// `noRows` is the spec's `none`: the pages had no written rows to check. (Not named
    /// `none`: `record?.check == .none` would compare against nil.)
    public enum Check: String, Sendable { case finished, stopped, unavailable, noRows = "none" }
    public var grid: Bool
    public var check: Check
    /// The highest row number compared, and how many written rows the pages hold.
    public var rowsChecked: Int
    public var rowsTotal: Int
    public var rowsDisagree: [Int]
    public var gaugePrinted: Bool
    /// Why the rows could not be compared at all (`CheckOutcome.incomparable`), when they could not.
    public var problem: String?

    /// The one `problem` the app words for the maker rather than reporting as it stands: the
    /// on-device model refused every attempt because it is being asked too often (#176). The
    /// reader writes the same words on each row it gave up on (`ProseReader.busyMessage`), which
    /// is where the importer gets them; keeping it a `problem` keeps the record's shape (§6.3).
    public static let modelBusy = "the on-device model is busy"
    /// What the sheet and the detail screen say for it: a state that passes, not a fault.
    public static let modelBusySentence = "The on-device model is busy; try the check again in a minute."

    public init(grid: Bool, check: Check, rowsChecked: Int, rowsTotal: Int, rowsDisagree: [Int], gaugePrinted: Bool, problem: String?) {
        self.grid = grid
        self.check = check
        self.rowsChecked = rowsChecked
        self.rowsTotal = rowsTotal
        self.rowsDisagree = rowsDisagree
        self.gaugePrinted = gaugePrinted
        self.problem = problem
    }

    public func json() -> JSONValue {
        var o: [String: JSONValue] = [
            "source": .string("pdf"), "grid": .bool(grid), "check": .string(check.rawValue),
            "rows_checked": .int(rowsChecked), "rows_total": .int(rowsTotal),
            "rows_disagree": .array(rowsDisagree.map(JSONValue.int)), "gauge_printed": .bool(gaugePrinted),
        ]
        if let problem { o["problem"] = .string(problem) }
        return .object(["graphghan": .object(["import": .object(o)])])
    }

    /// The record inside a chart document's `ext`, or nil when it has none.
    public init?(json ext: JSONValue?) {
        guard let o = ext?["graphghan"]?["import"], let check = Check(rawValue: o["check"]?.stringValue ?? "") else { return nil }
        self.init(grid: o["grid"]?.boolValue ?? false, check: check, rowsChecked: o["rows_checked"]?.intValue ?? 0,
                  rowsTotal: o["rows_total"]?.intValue ?? 0,
                  rowsDisagree: (o["rows_disagree"]?.arrayValue ?? []).compactMap(\.intValue), gaugePrinted: o["gauge_printed"]?.boolValue ?? false,
                  problem: o["problem"]?.stringValue)
    }

    /// The sentence the sheet and the detail screen show for this record (spec §5.4, §6.3); nil
    /// when there is nothing to say.
    public var sentence: String? {
        if problem == Self.modelBusy {
            // How far it got before the model stopped answering is the whole of what tells a
            // refusal that began at once apart from one that set in part way down (#176).
            guard rowsChecked > 0, rowsTotal > 0 else { return Self.modelBusySentence }
            return "The on-device model is busy; \(rowsChecked) of \(rowsTotal) written rows were checked. Try the check again in a minute."
        }
        if let problem { return "Written rows could not be compared with the chart: \(problem)." }
        switch check {
        case .noRows: return nil
        case .unavailable: return "Written rows not checked on this iPhone."
        case .stopped where rowsChecked < rowsTotal:
            let disagree = rowsDisagree.isEmpty ? "" : " " + Self.disagreeSentence(rowsDisagree)
            return "Written rows checked up to row \(rowsChecked); \(rowsChecked + 1)–\(rowsTotal) not checked." + disagree
        case .stopped: return rowsDisagree.isEmpty ? nil : Self.disagreeSentence(rowsDisagree)  // stopped after the last row: nothing unchecked
        case .finished: return rowsDisagree.isEmpty ? nil : Self.disagreeSentence(rowsDisagree)
        }
    }

    /// "Rows 12, 40 and 41 disagree with the chart. The chart is as drawn; check those rows against the PDF."
    static func disagreeSentence(_ rows: [Int]) -> String {
        let list: String
        switch rows.count {
        case 1: list = "Row \(rows[0]) disagrees"
        case 2: list = "Rows \(rows[0]) and \(rows[1]) disagree"
        default: list = "Rows " + rows.dropLast().map(String.init).joined(separator: ", ") + " and \(rows[rows.count - 1]) disagree"
        }
        return "\(list) with the chart. The chart is as drawn; check those rows against the PDF."
    }
}

/// A grid region on a page as the chart the library stores (phone import spec §4.2): colours
/// clustered by frequency and coded A, B, …, named by the nearest named colour, the format's
/// default gauge since a picture prints none.
public enum GridChart {
    /// Throws `GridColoursError.tooManyColours` for a grid of more than 256 flat colours.
    public static func draft(image: GridImage, region: Region, title: String) throws -> (draft: ChartDraft, cells: [UInt8], warnings: [String]) {
        let samples = GridReader.readRegion(image, region)
        let (grid, hexes, warnings) = try GridColours.clusterPalette(samples)
        // The hexes are `GridColours.hex` output, so each has a name; the code is the fallback in case.
        let palette = hexes.enumerated().map { ChartDraft.Palette(code: GridColours.code($0.offset), name: GridColours.nameColour($0.element) ?? GridColours.code($0.offset), hex: $0.element) }
        let codes = palette.map(\.code)
        let rows = grid.map { row -> String in
            var runs: [(code: String, count: Int)] = []
            for c in row {
                if let last = runs.last, last.code == codes[Int(c)] { runs[runs.count - 1].count += 1 } else { runs.append((codes[Int(c)], 1)) }
            }
            return ChartWriter.runString(runs)
        }
        var gauge = ChartDraft.Gauge()
        gauge.stitch = "sc"
        let record = ImportRecord(grid: true, check: .noRows, rowsChecked: 0, rowsTotal: 0, rowsDisagree: [], gaugePrinted: false, problem: nil)
        let draft = ChartDraft(pattern: .init(id: "", title: title, version: "0.1.0"), palette: palette, rows: rows,
                               width: region.cols, height: region.rows, gauge: gauge, ext: record.json())
        return (draft, grid.flatMap { $0 }, region.warnings + warnings)
    }
}

import Foundation

/// A chart to place in a manifest's `charts[]`, as `ManifestWriter.encodePieced` takes several.
public struct ManifestChartInput {
    public let chart: Chart
    public let chartID: String
    public let variant: String
    public let gaugeKey: String
    public let palette: [ChartDraft.Palette]
    public init(chart: Chart, chartID: String, variant: String, gaugeKey: String, palette: [ChartDraft.Palette]) {
        self.chart = chart
        self.chartID = chartID
        self.variant = variant
        self.gaugeKey = gaugeKey
        self.palette = palette
    }
}

/// One of a pieced manifest's `pieces[]`: a chart (`chart` set) or written rows (`rows`/`rowsID`
/// set) worked `make` times. Plain writer input; `ManifestPiece` (decoded from a bundle) stays as
/// it is.
public struct PieceEntry: Sendable, Equatable {
    public var id: String
    public var title: String
    public var make: Int
    public var chart: String?
    public var rows: String?
    public var rowsID: String?
    public var pages: [Int]
    public init(id: String, title: String, make: Int, chart: String?, rows: String?, rowsID: String?, pages: [Int]) {
        self.id = id
        self.title = title
        self.make = make
        self.chart = chart
        self.rows = rows
        self.rowsID = rowsID
        self.pages = pages
    }
}

/// One of a pieced manifest's `assembly[]` steps. Plain writer input; `AssemblyStep` (decoded from
/// a bundle) stays as it is.
public struct AssemblyEntry: Sendable, Equatable {
    public var title: String
    public var text: String?
    public var pages: [Int]
    public init(title: String, text: String?, pages: [Int]) {
        self.title = title
        self.text = text
        self.pages = pages
    }
}

/// `pattern.json` (manifest schema 1, or 2 with pieces) for a pattern the phone imported (phone
/// import spec §5.3), with the numbers `manifest.py` derives from a chart's stats, derived here
/// the same way.
public enum ManifestWriter {
    /// A bundle is content, not a build (bundle design §3.2): the same fixed instant the writer uses.
    public static let fixedUpdated = "1980-01-01T00:00:00Z"

    public static func encode(id: String, title: String, version: String, dedication: String, chart: Chart, chartID: String,
                              variant: String, gaugeKey: String, palette: [ChartDraft.Palette]) -> Data {
        let entry = chartEntry(chart: chart, chartID: chartID, variant: variant, gaugeKey: gaugeKey, palette: palette, isDefault: true)
        let manifest: JSONValue = .object([
            "schema": .int(1), "id": .string(id), "title": .string(title), "version": .string(version),
            "dedication": .string(dedication), "quote": .string(""), "author": .string(""), "license": .string(""),
            "preview": .string("preview.png"),
            "palette": .array(palette.map { .object(["code": .string($0.code), "name": .string($0.name), "hex": .string($0.hex)]) }),
            "charts": .array([entry]),
            "updated": .string(fixedUpdated),
        ])
        return Data(CanonicalJSON.encode(manifest).utf8)
    }

    /// Manifest schema 2: several charts and/or written pieces, assembled per `assembly`. Each
    /// `charts[]` entry is built exactly as `encode`'s one entry is, `default: true` on the first
    /// only. `preview` is "" for a pattern with no chart to draw one from (written pieces only):
    /// a non-empty preview is a file the bundle must carry.
    public static func encodePieced(id: String, title: String, version: String, dedication: String, charts: [ManifestChartInput],
                                    pieces: [PieceEntry], assembly: [AssemblyEntry], palette: [ChartDraft.Palette],
                                    preview: String = "preview.png") -> Data {
        let chartEntries: [JSONValue] = charts.enumerated().map { i, input in
            chartEntry(chart: input.chart, chartID: input.chartID, variant: input.variant, gaugeKey: input.gaugeKey,
                      palette: input.palette, isDefault: i == 0)
        }
        let pieceEntries: [JSONValue] = pieces.map { piece in
            var o: [String: JSONValue] = ["id": .string(piece.id), "title": .string(piece.title), "make": .int(piece.make)]
            if let chart = piece.chart { o["chart"] = .string(chart) }
            if let rows = piece.rows { o["rows"] = .string(rows) }
            if let rowsID = piece.rowsID { o["rows_id"] = .string(rowsID) }
            if !piece.pages.isEmpty { o["pages"] = .array(piece.pages.map(JSONValue.int)) }
            return .object(o)
        }
        let assemblyEntries: [JSONValue] = assembly.map { step in
            var o: [String: JSONValue] = ["title": .string(step.title)]
            if let text = step.text { o["text"] = .string(text) }
            if !step.pages.isEmpty { o["pages"] = .array(step.pages.map(JSONValue.int)) }
            return .object(o)
        }
        let manifest: JSONValue = .object([
            "schema": .int(2), "id": .string(id), "title": .string(title), "version": .string(version),
            "dedication": .string(dedication), "quote": .string(""), "author": .string(""), "license": .string(""),
            "preview": .string(preview),
            "palette": .array(palette.map { .object(["code": .string($0.code), "name": .string($0.name), "hex": .string($0.hex)]) }),
            "charts": .array(chartEntries),
            "pieces": .array(pieceEntries),
            "assembly": .array(assemblyEntries),
            "updated": .string(fixedUpdated),
        ])
        return Data(CanonicalJSON.encode(manifest).utf8)
    }

    /// One `charts[]` entry, with the numbers `manifest.py` derives from a chart's stats.
    private static func chartEntry(chart: Chart, chartID: String, variant: String, gaugeKey: String,
                                   palette: [ChartDraft.Palette], isDefault: Bool) -> JSONValue {
        // A shaped piece's ground is in the grid but is no stitch (spec §5.1): every number below
        // counts stitched runs, which for a rectangle is every run, as before.
        let stitchedRows = chart.runsByRow.map { $0.filter { chart.isStitched(colorIndex: $0.colorIndex) } }
        let stitches = stitchedRows.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
        let perRow = stitchedRows.map { max(0, $0.count - 1) }
        let mean = perRow.isEmpty ? 0.0 : (Double(perRow.reduce(0, +)) / Double(perRow.count) * 10).rounded() / 10
        let g = chart.document.gauge
        let inches = g.over.unit == "cm" ? g.over.value / 2.54 : g.over.value
        let sw = inches / g.stitches
        let sh = inches / g.rows
        let yards = Int((Double(stitches) * sw * sh * 1.1 * 1.2).rounded())  // 1.1 yd/sq in worsted sc, +20% tails
        let sizeW = (Double(chart.width) * g.over.value / g.stitches * 10).rounded() / 10
        let sizeH = (Double(chart.height) * g.over.value / g.rows * 10).rounded() / 10
        let dir = "charts/\(variant)-\(gaugeKey)"
        // A shaped piece's background stays in the palette but is not a yarn (#205).
        let colours = palette.filter { $0.use != ChartDraft.Palette.noStitch }.count
        return .object([
            "id": .string(chartID), "variant": .string(variant), "gauge_key": .string(gaugeKey), "default": .bool(isDefault),
            "path": .string("\(dir)/chart.json"), "preview": .string("\(dir)/preview.png"),
            "width": .int(chart.width), "height": .int(chart.height),
            "size": .object(["width": .double(sizeW), "height": .double(sizeH), "unit": .string(g.over.unit)]),
            "stitch": .string(g.stitch ?? ""), "colors": .int(colours), "stitches": .int(stitches),
            "changes_per_row": .object(["mean": .double(mean), "max": .int(perRow.max() ?? 0)]),
            "yards_est": .int(yards),
        ])
    }
}

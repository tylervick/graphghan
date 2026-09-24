import Foundation

/// `pattern.json` (manifest schema 1) for a pattern the phone imported (phone import spec §5.3),
/// with the numbers `manifest.py` derives from a chart's stats, derived here the same way.
public enum ManifestWriter {
    /// A bundle is content, not a build (bundle design §3.2): the same fixed instant the writer uses.
    public static let fixedUpdated = "1980-01-01T00:00:00Z"

    public static func encode(id: String, title: String, version: String, dedication: String, chart: Chart, chartID: String,
                              variant: String, gaugeKey: String, palette: [ChartDraft.Palette]) -> Data {
        let perRow = chart.runsByRow.map { max(0, $0.count - 1) }
        // Display statistics, rounded the way `export.py`'s `stats` rounds them (`round(x, 1)`).
        let mean = perRow.isEmpty ? 0.0 : (Double(perRow.reduce(0, +)) / Double(perRow.count) * 10).rounded() / 10
        let g = chart.document.gauge
        let inches = g.over.unit == "cm" ? g.over.value / 2.54 : g.over.value
        let sw = inches / g.stitches
        let sh = inches / g.rows
        let yards = Int((Double(chart.width * chart.height) * sw * sh * 1.1 * 1.2).rounded())  // 1.1 yd/sq in worsted sc, +20% tails
        let sizeW = (Double(chart.width) * g.over.value / g.stitches * 10).rounded() / 10
        let sizeH = (Double(chart.height) * g.over.value / g.rows * 10).rounded() / 10
        let dir = "charts/\(variant)-\(gaugeKey)"
        // A shaped piece's background stays in the palette but is not a yarn (#205).
        let colours = palette.filter { $0.use != ChartDraft.Palette.noStitch }.count
        let entry: JSONValue = .object([
            "id": .string(chartID), "variant": .string(variant), "gauge_key": .string(gaugeKey), "default": .bool(true),
            "path": .string("\(dir)/chart.json"), "preview": .string("\(dir)/preview.png"),
            "width": .int(chart.width), "height": .int(chart.height),
            "size": .object(["width": .double(sizeW), "height": .double(sizeH), "unit": .string(g.over.unit)]),
            "stitch": .string(g.stitch ?? ""), "colors": .int(colours), "stitches": .int(chart.width * chart.height),
            "changes_per_row": .object(["mean": .double(mean), "max": .int(perRow.max() ?? 0)]),
            "yards_est": .int(yards),
        ])
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
}

import Foundation

/// A written-rows document (schema 1) for a piece that is not a grid — `docs/chart-format.md`
/// §Written-rows document. Mirrors `ChartWriter`/`ManifestWriter`'s use of `CanonicalJSON`.
public enum RowsWriter {
    public static func encode(title: String, palette: [ChartDraft.Palette], entries: [RowsDocument.Entry], pages: [Int]) -> (data: Data, id: String) {
        let id = RowsDocument.computeID(entries)
        var doc: [String: JSONValue] = [
            "schema": .int(GraphghanCore.rowsSchema),
            "id": .string(id),
            "piece": .object(["title": .string(title)]),
            "rows": .array(entries.map(entry)),
        ]
        if !palette.isEmpty {
            doc["palette"] = .array(palette.map { .object(["code": .string($0.code), "name": .string($0.name), "hex": .string($0.hex)]) })
        }
        if !pages.isEmpty {
            doc["source"] = .object(["pages": .array(pages.map(JSONValue.int))])
        }
        return (Data(CanonicalJSON.encode(.object(doc)).utf8), id)
    }

    private static func entry(_ e: RowsDocument.Entry) -> JSONValue {
        var o: [String: JSONValue] = ["label": .string(e.label), "from": .int(e.from), "text": .string(e.text)]
        if let to = e.to { o["to"] = .int(to) }
        if let n = e.count { o["count"] = .int(n) }
        if let c = e.code { o["code"] = .string(c) }
        if let r = e.repeatText { o["repeat"] = .string(r) }
        return .object(o)
    }
}

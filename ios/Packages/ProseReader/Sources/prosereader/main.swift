// prosereader <pdf|dir of pNN.txt> --model ondevice|cloud [--batch row|page] [--chunk N] [--reuse-session] [--out prose.json]
//
// Reads a pattern's text through Apple's Foundation Models and writes the graphghan-import/1
// document the Python importer consumes. Text comes from PDFKit for a PDF, or from the
// pNN.txt files `graphghan import` stages, so both sides read exactly the same characters.

import Foundation
import PDFKit
import ProseReaderKit

@available(macOS 26.0, *)
func run() async -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    func take(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        args.removeSubrange(i...(i + 1))
        return v
    }
    let modelName = take("--model") ?? "ondevice"
    let batchName = take("--batch") ?? "row"
    let out = take("--out")
    let reuse = args.contains("--reuse-session")
    args.removeAll { $0 == "--reuse-session" }
    let chunk = Int(take("--chunk") ?? "8") ?? 8
    guard let input = args.first, let model = ReaderModel(rawValue: modelName), let batching = RowBatching(rawValue: batchName) else {
        FileHandle.standardError.write("usage: prosereader <pdf|dir> --model ondevice|cloud [--batch row|page] [--chunk N] [--reuse-session] [--out prose.json]\n".data(using: .utf8)!)
        return 2
    }
    let pages: [String]
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: input, isDirectory: &isDir), isDir.boolValue {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: input))?.filter { $0.hasSuffix(".txt") }.sorted() ?? []
        pages = files.map { (try? String(contentsOfFile: input + "/" + $0, encoding: .utf8)) ?? "" }
    } else if let pdf = PDFDocument(url: URL(fileURLWithPath: input)) {
        pages = (0..<pdf.pageCount).map { pdf.page(at: $0)?.string ?? "" }
    } else {
        FileHandle.standardError.write("cannot read \(input)\n".data(using: .utf8)!)
        return 1
    }
    let reader = ProseReader(model: model, options: ReaderOptions(batching: batching, reuseSession: reuse, chunkRuns: chunk))
    if let why = reader.unavailableReason() {
        FileHandle.standardError.write("\(why)\n".data(using: .utf8)!)
        return 1
    }
    let doc = await reader.read(pages: pages) { p in
        FileHandle.standardError.write("  page \(p.page): \(p.rowsSoFar) rows, \(Int(p.seconds)) s\r".data(using: .utf8)!)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try! encoder.encode(doc)
    if let out {
        try! data.write(to: URL(fileURLWithPath: out))
        FileHandle.standardError.write("\nwrote \(out): \(doc.written_rows?.count ?? 0) rows\n".data(using: .utf8)!)
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }
    return 0
}

if #available(macOS 26.0, *) {
    exit(await run())
} else {
    FileHandle.standardError.write("prosereader needs macOS 26 or later\n".data(using: .utf8)!)
    exit(1)
}

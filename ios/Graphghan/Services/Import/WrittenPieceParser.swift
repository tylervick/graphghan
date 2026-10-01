import Foundation
import GraphghanCore
import ProseReaderKit

/// A written piece's rows as a rows document holds them, and where reading stopped.
struct ParsedPiece: Sendable, Equatable {
    let entries: [RowsDocument.Entry]
    /// The 1-based pages of the parsed blocks only.
    let pages: [Int]
    /// The 1-based page of the block that stopped the parse, nil when every head continued the rows.
    let stoppedAtPage: Int?
    /// The last row parsed before the stop.
    let stoppedAfterRow: Int?
}

/// A section of written rows parsed by code, never the model (pieces spec §7.2): heads and ranges
/// give `from`/`to`, a trailing "[n]" the count, a leading "(Name)" the colour code when the chart's
/// key names that colour.
enum WrittenPieceParser {
    static let countRe = try! NSRegularExpression(pattern: #"\[(\d+)\]\s*\.?\s*$"#)
    static let colourRe = try! NSRegularExpression(pattern: #"^\(([A-Za-z][A-Za-z ]*)\)"#)

    /// The section's rows from row 1 on. A rows document may not have a gap (spec §5.2), so the
    /// first head that does not continue the rows (a gap, an overlap, or prose that mentions a row
    /// and goes backwards) stops the parse rather than being skipped: what follows is not trusted
    /// to be this piece's, and the outline names it as left out.
    static func parse(_ section: RowSection, palette: [ChartDraft.Palette]) -> ParsedPiece {
        var entries: [RowsDocument.Entry] = []
        var pages: [Int] = []
        for block in section.blocks {
            guard let head = RowText.splitHead(block.text), let from = head.rows.first, let to = head.rows.last else { continue }
            let next = (entries.last?.to ?? 0) + 1
            guard from == next else {
                return ParsedPiece(entries: entries, pages: pages, stoppedAtPage: block.page + 1, stoppedAfterRow: next - 1)
            }
            entries.append(RowsDocument.Entry(label: head.label, from: from, to: to, text: head.body,
                                              count: count(in: head.body), code: code(in: head.body, palette: palette), repeatText: nil))
            if pages.last != block.page + 1 { pages.append(block.page + 1) }
        }
        return ParsedPiece(entries: entries, pages: pages, stoppedAtPage: nil, stoppedAfterRow: nil)
    }

    /// The stitch count a row ends with, "[6]" or "[6].".
    static func count(in body: String) -> Int? {
        firstGroup(countRe, in: body).flatMap { Int($0) }
    }

    /// The code of the key colour a row opens with, "(Black) ch 7", matched by name, any case.
    static func code(in body: String, palette: [ChartDraft.Palette]) -> String? {
        guard let name = firstGroup(colourRe, in: body)?.trimmingCharacters(in: .whitespaces) else { return nil }
        return palette.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.code
    }

    private static func firstGroup(_ re: NSRegularExpression, in text: String) -> String? {
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

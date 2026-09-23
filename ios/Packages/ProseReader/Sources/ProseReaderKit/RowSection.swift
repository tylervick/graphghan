// Which written rows belong to a chart (#176, #197, #198). A pattern PDF prints more than one run
// of rows: Orca prints the bag's body, its strap, and two panels that each count from row 1, and
// only one panel is the chart the check compares with. The cactus blanket prints c2c construction
// rows ("1st row: 1 dc in 4th ch from hook") whose colour is all in the chart picture. Read whole,
// the first came back "row 1 printed twice" and the second as colour codes 'RS', 'Beg' and 'sc'.
// Both are settled here, from the text alone, before the model is asked anything.

import Foundation

/// One run of written rows: from a head that counts from row 1 up to the next one that does.
public struct RowSection: Equatable, Sendable {
    public struct Block: Equatable, Hashable, Sendable {
        /// The page, from 0, and the block's place among `RowText.blocks(in:)` of that page.
        public let page: Int
        public let index: Int
        public let text: String
    }
    public var blocks: [Block] = []
    /// Every row the heads cover, so "Rows 2-4" is three.
    public var rows = 0
    /// The highest row number printed.
    public var lastRow = 0
    /// Rows that name a colour, of `blocks.count`.
    public var colourBlocks = 0
    /// Most of its rows name a colour. A body worked in one colour names it once, at row 1, and a
    /// run of construction rows never does; neither is anything a colour chart can be checked by.
    public var isColour: Bool { !blocks.isEmpty && colourBlocks * 2 >= blocks.count }

    /// Whether the block at `index` of page `page` (both from 0) is one of this section's.
    public func contains(page: Int, index: Int) -> Bool {
        blocks.contains { $0.page == page && $0.index == index }
    }
}

extension RowText {
    /// Words a count stands before that are not colours: stitches, what a stitch makes, how often.
    static let notAColour: Set<String> = [
        "sc", "dc", "hdc", "tr", "dtr", "sl", "fsc", "fdc", "ch", "chs", "chain", "chains", "st", "sts", "stitch", "stitches",
        "inc", "dec", "tog", "sp", "sps", "space", "spaces", "block", "blocks", "tile", "tiles", "square", "squares",
        "box", "boxes", "row", "rows", "round", "rounds", "rnd", "rnds", "time", "times", "x", "more", "rep", "repeats",
        "loop", "loops", "yo", "yoh", "turn", "in", "of", "and", "to", "from", "cm", "mm", "inch", "inches",
        "th", "nd", "rd", "first", "last", "next", "nxt", "each", "every", "all", "same", "into", "over", "hook", "ss",
    ]
    /// Side markers, which a page also prints in parentheses.
    static let markers: Set<String> = ["rs", "ws", "lr", "rl"]
    /// "8 A", "14 white", "3G": a count, then a word.
    static let countWordRe = try! NSRegularExpression(pattern: #"\b\d+\s*([A-Za-z]+)\b"#)
    /// "A 23", "A (7)", "White x 46": a word, then a count.
    static let wordCountRe = try! NSRegularExpression(pattern: #"\b([A-Za-z]+)\s*(?:x\s*)?\(?\d+\b"#)
    static let nameInBracketsRe = try! NSRegularExpression(pattern: #"\(([A-Za-z][A-Za-z ]*)\)"#)

    /// Whether a row's text names a colour: a count beside a word that is no stitch or construction
    /// word, on either side ("8 A", "3G", "A 23", "White x 46"), or a name in brackets that is no side
    /// marker ("(Black) 3 sc").
    public static func namesColour(_ block: String) -> Bool {
        let text = normalized(block)
        let body = head(of: text).map { String(text[$0.end...]) } ?? text
        let range = NSRange(body.startIndex..., in: body)
        for m in countWordRe.matches(in: body, range: range) + wordCountRe.matches(in: body, range: range) {
            guard let w = Range(m.range(at: 1), in: body) else { continue }
            if !notAColour.contains(body[w].lowercased()) { return true }
        }
        for m in nameInBracketsRe.matches(in: body, range: range) {
            guard let n = Range(m.range(at: 1), in: body) else { continue }
            let words = body[n].lowercased().split(separator: " ").map(String.init)
            if !words.contains(where: { markers.contains($0) || notAColour.contains($0) }) { return true }
        }
        return false
    }

    /// The pages' written rows cut into sections wherever the rows count from 1 again, in page order.
    public static func sections(in pages: [String]) -> [RowSection] {
        var out: [RowSection] = []
        var current = RowSection()
        var covered = Set<Int>()
        for (p, page) in pages.enumerated() {
            for (i, text) in blocks(in: page).enumerated() {
                let numbers = rowNumbers(of: text)
                if numbers.first == 1, covered.contains(1) {
                    out.append(current)
                    current = RowSection()
                    covered = []
                }
                current.blocks.append(RowSection.Block(page: p, index: i, text: text))
                current.rows += max(1, numbers.count)
                current.lastRow = max(current.lastRow, numbers.last ?? 0)
                if namesColour(text) { current.colourBlocks += 1 }
                covered.formUnion(numbers)
            }
        }
        if !current.blocks.isEmpty { out.append(current) }
        return out
    }

    /// The rows a chart `height` rows tall is checked by: the first colour section whose rows run to
    /// that height (Orca's two panels are both 77; the first is the one its page draws first), else
    /// the longest colour section, which the check then reports on as it finds it. Nil when no
    /// section names colours: there are no written colour rows to check.
    public static func section(fitting height: Int, in pages: [String]) -> RowSection? {
        let colour = sections(in: pages).filter(\.isColour)
        if let tall = colour.first(where: { $0.lastRow == height }) { return tall }
        return colour.max { $0.rows < $1.rows }
    }
}

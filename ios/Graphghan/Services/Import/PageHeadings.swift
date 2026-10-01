import Foundation

/// The lines of a page that read as a piece's heading ("Side Panel", "Pectoral Fin (Front)"), the
/// titles code guesses for what it found (pieces spec §7.3). A guess: the maker renames in the list.
enum PageHeadings {
    /// One to four capitalised words of letters and parentheses. A lone word needs four letters
    /// ("Tail", not "Sew"), and a run of single letters is a chart's key ("C B A"), not a title.
    static func isHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.allSatisfy({ $0.isLetter || $0 == " " || $0 == "(" || $0 == ")" }) else { return false }
        let words = trimmed.split(separator: " ").map { $0.filter { $0 != "(" && $0 != ")" } }.filter { !$0.isEmpty }
        guard (1...4).contains(words.count), words.allSatisfy({ $0.first?.isUppercase == true }) else { return false }
        if words.count == 1, words[0].count < 4 { return false }
        return !words.allSatisfy { $0.count == 1 }
    }

    /// Per page, its heading lines in text order. A line that is a heading on more than one page is
    /// a running header, which titles no piece.
    static func headings(in pageTexts: [String]) -> [[String]] {
        let perPage = pageTexts.map { text in
            text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter(isHeading)
        }
        var pagesOf: [String: Set<Int>] = [:]
        for (p, lines) in perPage.enumerated() { for line in lines { pagesOf[line, default: []].insert(p) } }
        return perPage.map { $0.filter { pagesOf[$0, default: []].count <= 1 } }
    }
}

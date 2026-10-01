import Foundation
import GraphghanCore

/// The maker's edits to a `PatternOutline` before "Add to library" saves it (pieces spec §7.3–7.4):
/// rename a piece or step, drop one, reorder, set how many copies to make. Edited in the import
/// sheet by `OutlineReviewSection`; saved by Task 8.
struct OutlineDraft: Equatable, Sendable {
    struct Piece: Equatable, Sendable, Identifiable {
        /// Index into the outline's pieces at the time this draft was built; stable while editing
        /// so a `TextField`'s identity survives a reorder.
        let id: Int
        var title: String
        var make: Int
        let isChart: Bool
        let pages: [Int]
        /// Passes for a chart, the last row for a written piece.
        let rows: Int
    }
    struct Step: Equatable, Sendable, Identifiable { let id: Int; var title: String; let pages: [Int] }

    var pieces: [Piece]
    var assembly: [Step]

    init(_ outline: PatternOutline, charts: [PiecedChart]) {
        pieces = outline.pieces.enumerated().map { i, piece in
            switch piece.kind {
            case .chart(let ci):
                let rows = charts.indices.contains(ci) ? charts[ci].height : 0
                return Piece(id: i, title: piece.title, make: piece.make, isChart: true, pages: piece.pages, rows: rows)
            case .rows:
                let rows = piece.entries.compactMap(\.to).max() ?? 0
                return Piece(id: i, title: piece.title, make: piece.make, isChart: false, pages: piece.pages, rows: rows)
            }
        }
        assembly = outline.assembly.enumerated().map { i, step in Step(id: i, title: step.title, pages: step.pages) }
    }

    mutating func rename(_ id: Int, to title: String) {
        guard let i = pieces.firstIndex(where: { $0.id == id }) else { return }
        pieces[i].title = title
    }

    /// By stable id, not current position: a delete button holds the id of the row it was drawn
    /// for, and after a reorder that is no longer the row at any particular index.
    mutating func remove(_ id: Int) {
        pieces.removeAll { $0.id == id }
    }

    mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        pieces.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    /// Clamped to 1...20 (pieces spec §7.3): nobody is making 0 or 100 of a piece.
    mutating func setMake(_ id: Int, _ make: Int) {
        guard let i = pieces.firstIndex(where: { $0.id == id }) else { return }
        pieces[i].make = min(max(make, 1), 20)
    }

    mutating func removeStep(_ id: Int) {
        assembly.removeAll { $0.id == id }
    }

    mutating func renameStep(_ id: Int, to title: String) {
        guard let i = assembly.firstIndex(where: { $0.id == id }) else { return }
        assembly[i].title = title
    }

    /// Unique slugs in the current order, from each title ("Front Panel" → "front-panel", a
    /// repeat → "front-panel-2", empty → "piece"). A suffix skips any id already taken, so
    /// "Strap", "Strap", "Strap 2" give "strap", "strap-2", "strap-2-2". `PDFImporter.slug` falls
    /// back to "pattern" for a title with no ASCII letter or digit; the review list wants "piece"
    /// for that case instead.
    func pieceIDs() -> [Int: String] {
        var result: [Int: String] = [:]
        var used: Set<String> = []
        for piece in pieces {
            let hasLetterOrDigit = piece.title.unicodeScalars.contains {
                (0x41...0x5a).contains($0.value) || (0x61...0x7a).contains($0.value) || (0x30...0x39).contains($0.value)
            }
            let base = hasLetterOrDigit ? PDFImporter.slug(piece.title) : "piece"
            var id = base
            var n = 2
            while used.contains(id) {
                id = "\(base)-\(n)"
                n += 1
            }
            used.insert(id)
            result[piece.id] = id
        }
        return result
    }

    /// One chart, nothing else: save as today (spec §7.4, §7.5).
    var isSingleChart: Bool {
        pieces.count == 1 && pieces[0].isChart && assembly.isEmpty
    }
}

/// `onMove`'s reordering, available outside a `List` too (the review list uses up/down buttons,
/// not drag, per the brief: `ImageRenderer` cannot flatten a `List`, and the sheet's rows are
/// snapshotted as plain stacks).
private extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { self[$0] }
        var destination = destination
        for offset in source.sorted(by: >) {
            if offset < destination { destination -= 1 }
            remove(at: offset)
        }
        insert(contentsOf: moving, at: destination)
    }
}

import SwiftUI
import GraphghanCore

/// The review list under the import sheet's "N × M stitches, K colours" (pieces spec §7.3): each
/// piece found, to rename, remove, reorder (up/down -- `onMove`'s drag needs a `List`, which
/// `ImageRenderer` cannot snapshot) or make more than once; then the assembly steps; then what
/// was found and left out. A plain `VStack`, snapshotted directly the way `project-pieces-rows`
/// snapshots `PieceRow`.
struct OutlineReviewSection: View {
    @Binding var draft: OutlineDraft
    let leftOut: [String]
    /// Each checked chart piece's check line, by `OutlineDraft.Piece.id` (pieces spec §7.2).
    var checkLines: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(draft.pieces.enumerated()), id: \.element.id) { i, piece in
                pieceRow(i, piece)
            }
            if !draft.assembly.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Assembly").font(Font.Heather.heading).foregroundStyle(Color.ink)
                    ForEach(draft.assembly) { step in
                        stepRow(step)
                    }
                }
            }
            if let sentence = Self.leftOutSentence(leftOut) {
                Text(sentence).font(Font.Heather.caption).foregroundStyle(Color.ink2)
            }
        }
    }

    /// `i` is only the row's current position, for the up/down reorder (which is positional, like
    /// `onMove`); every edit or delete goes by `piece.id`, the row's stable identity, since after a
    /// reorder `i` no longer names the row the button was drawn for.
    @ViewBuilder private func pieceRow(_ i: Int, _ piece: OutlineDraft.Piece) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Title", text: Binding(get: { piece.title }, set: { draft.rename(piece.id, to: $0) }))
                    .font(Font.Heather.body).foregroundStyle(Color.ink)
                Spacer()
                Button { draft.remove(piece.id) } label: { Image(systemName: "trash") }
                    .foregroundStyle(Color.ink2)
            }
            HStack(spacing: 10) {
                Text(piece.isChart ? "Chart" : "Written rows").font(Font.Heather.caption).foregroundStyle(Color.ink2)
                if !piece.pages.isEmpty {
                    Text(Self.piecePages(piece.pages)).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                }
                Text("\(piece.rows) rows").font(Font.Heather.caption).foregroundStyle(Color.ink2)
            }
            if let line = checkLines[piece.id] {
                Text(line).font(Font.Heather.caption).foregroundStyle(Color.ink2)
            }
            HStack(spacing: 10) {
                Stepper("Make × \(piece.make)", value: Binding(get: { piece.make }, set: { draft.setMake(piece.id, $0) }), in: 1...20)
                    .font(Font.Heather.caption).foregroundStyle(Color.ink2)
                Spacer()
                Button { draft.move(fromOffsets: [i], toOffset: i - 1) } label: { Image(systemName: "chevron.up") }
                    .disabled(i == 0)
                Button { draft.move(fromOffsets: [i], toOffset: i + 2) } label: { Image(systemName: "chevron.down") }
                    .disabled(i == draft.pieces.count - 1)
            }
            .foregroundStyle(Color.ink2)
        }
        .padding(10)
        .background(Color.ground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func stepRow(_ step: OutlineDraft.Step) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Title", text: Binding(get: { step.title }, set: { draft.renameStep(step.id, to: $0) }))
                    .font(Font.Heather.body).foregroundStyle(Color.ink)
                if !step.pages.isEmpty {
                    Text(Self.stepPages(step.pages)).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                }
            }
            Spacer()
            Button { draft.removeStep(step.id) } label: { Image(systemName: "trash") }
                .foregroundStyle(Color.ink2)
        }
    }

    /// "pages 9, 17" / "page 9" -- consecutive pages collapse to a dash range, as
    /// `PieceListSection.pageText` does, but without its " of the original PDF" tail.
    nonisolated static func piecePages(_ pages: [Int]) -> String {
        guard let first = pages.first else { return "" }
        if pages.count == 1 { return "page \(first)" }
        let consecutive = zip(pages, pages.dropFirst()).allSatisfy { $1 == $0 + 1 }
        let list = consecutive ? "\(first)–\(pages.last!)" : pages.map(String.init).joined(separator: ", ")
        return "pages \(list)"
    }

    /// "pages 13–16 of this PDF" -- an assembly step's pages, which (unlike a piece's) are
    /// always said against the PDF the maker is importing.
    nonisolated static func stepPages(_ pages: [Int]) -> String {
        let base = piecePages(pages)
        return base.isEmpty ? "" : base + " of this PDF"
    }

    /// "Left out: text after R 2 (page 7); text after R 104 (page 10)." Nil when nothing was.
    nonisolated static func leftOutSentence(_ items: [String]) -> String? {
        guard !items.isEmpty else { return nil }
        return "Left out: " + items.joined(separator: "; ") + "."
    }
}

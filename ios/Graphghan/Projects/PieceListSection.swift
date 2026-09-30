import SwiftUI
import GraphghanCore

/// A pieced project's pieces in the pattern's order, then its assembly steps (spec 2026-09-25 §6.2).
struct PieceListSection: View {
    let statuses: [PieceStatus]
    let assembly: [AssemblyStep]
    let assemblyDone: [Int]
    let onSelect: (PieceKey) -> Void
    let onToggleStep: (Int, Bool) -> Void

    var body: some View {
        Section("Pieces") {
            ForEach(statuses) { s in
                Button { onSelect(s.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: s.finished ? "checkmark.circle.fill" : (s.isCurrent ? "play.circle.fill" : "circle"))
                            .foregroundStyle(s.finished || s.isCurrent ? Color.heather : Color.ink2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(s)).font(Font.Heather.body).foregroundStyle(Color.ink)
                            Text(s.isWritten ? "Written rows" : "Chart").font(Font.Heather.caption).foregroundStyle(Color.ink2)
                        }
                        Spacer()
                        Text(s.line).font(Font.Heather.caption).foregroundStyle(Color.ink2).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(s.finished ? "Finished" : "Work this piece")
            }
        }
        if !assembly.isEmpty {
            Section("Assembly · \(assemblyDone.count) of \(assembly.count)") {
                ForEach(Array(assembly.enumerated()), id: \.offset) { i, step in
                    Toggle(isOn: Binding(get: { assemblyDone.contains(i) }, set: { onToggleStep(i, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(Font.Heather.body).foregroundStyle(Color.ink)
                            if let text = step.text { Text(text).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                            if !step.pages.isEmpty { Text(Self.pageText(step.pages)).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                        }
                    }
                    .tint(.heather)
                }
            }
        }
    }

    private func title(_ s: PieceStatus) -> String {
        s.piece.make > 1 ? "\(s.piece.title) \(s.copy) of \(s.piece.make)" : s.piece.title
    }

    /// Where the source PDF is not on this phone (always, until the importer keeps it, spec §5.5).
    /// `nonisolated`: a pure string function, called from tests that are not on the main actor.
    nonisolated static func pageText(_ pages: [Int]) -> String {
        guard let first = pages.first else { return "" }
        if pages.count == 1 { return "page \(first) of the original PDF" }
        let consecutive = zip(pages, pages.dropFirst()).allSatisfy { $1 == $0 + 1 }
        let list = consecutive ? "\(first)–\(pages.last!)" : pages.map(String.init).joined(separator: ", ")
        return "pages \(list) of the original PDF"
    }
}

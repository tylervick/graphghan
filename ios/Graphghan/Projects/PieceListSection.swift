import SwiftUI
import GraphghanCore

/// One piece row (spec 2026-09-25 §6.2): its current/finished marker, title, chart/written-rows
/// subtitle, and row line. A plain view (not a `Section` row) so it can be snapshot directly --
/// `ImageRenderer` cannot render a `List`, which `Section` needs as a container.
struct PieceRow: View {
    let status: PieceStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: status.finished ? "checkmark.circle.fill" : (status.isCurrent ? "play.circle.fill" : "circle"))
                .foregroundStyle(status.finished || status.isCurrent ? Color.heather : Color.ink2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Font.Heather.body).foregroundStyle(Color.ink)
                Text(status.isWritten ? "Written rows" : "Chart").font(Font.Heather.caption).foregroundStyle(Color.ink2)
            }
            Spacer()
            Text(status.line).font(Font.Heather.caption).foregroundStyle(Color.ink2).monospacedDigit()
        }
    }

    private var title: String {
        status.piece.make > 1 ? "\(status.piece.title) \(status.copy) of \(status.piece.make)" : status.piece.title
    }
}

/// One assembly step row: its title, text and page reference, with its own done toggle. When the
/// step's PDF is kept on this phone (`onOpenPage` non-nil, Task 9), the page reference becomes a
/// button that opens it there instead of the plain "page N of the original PDF" text.
///
/// The button sits below the `Toggle`, not inside its label: a `List` row's `Toggle` treats its
/// whole label as part of the switch's tap target, so a button nested in that label would flip
/// `done` on the same tap that opens the PDF. `.buttonStyle(.borderless)` keeps the button's own
/// tap from being swallowed by the row underneath it (fix round 1, review focus 1).
struct AssemblyStepRow: View {
    let step: AssemblyStep
    let done: Bool
    let onToggle: (Bool) -> Void
    var onOpenPage: ((Int) -> Void)? = nil

    var body: some View {
        let label = Self.pageAction(pages: step.pages, hasPDF: onOpenPage != nil)
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { done }, set: onToggle)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title).font(Font.Heather.body).foregroundStyle(Color.ink)
                    if let text = step.text { Text(text).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                    if label == nil, !step.pages.isEmpty {
                        Text(PieceListSection.pageText(step.pages)).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                    }
                }
            }
            .tint(.heather)
            if let label {
                Button(label) { if let first = step.pages.first { onOpenPage?(first) } }
                    .buttonStyle(.borderless)
                    .font(Font.Heather.caption)
                    .foregroundStyle(Color.heather)
            }
        }
    }

    /// "Open page 15" / "Open pages 13–16" when the kept PDF can show this step's pages; nil
    /// when there is none, which keeps today's plain text. `nonisolated`: a pure string
    /// function, called from tests that are not on the main actor.
    nonisolated static func pageAction(pages: [Int], hasPDF: Bool) -> String? {
        guard hasPDF, let first = pages.first else { return nil }
        if pages.count == 1 { return "Open page \(first)" }
        let consecutive = zip(pages, pages.dropFirst()).allSatisfy { $1 == $0 + 1 }
        let list = consecutive ? "\(first)–\(pages.last!)" : pages.map(String.init).joined(separator: ", ")
        return "Open pages \(list)"
    }
}

/// A pieced project's pieces in the pattern's order, then its assembly steps (spec 2026-09-25 §6.2).
struct PieceListSection: View {
    let statuses: [PieceStatus]
    let assembly: [AssemblyStep]
    let assemblyDone: [Int]
    let onSelect: (PieceKey) -> Void
    let onToggleStep: (Int, Bool) -> Void
    /// Whether the pattern's source PDF is kept on this phone (Task 9): when true, each step's
    /// page reference becomes a button through `onOpenPage` instead of plain text.
    var hasSourcePDF: Bool = false
    var onOpenPage: (Int) -> Void = { _ in }

    var body: some View {
        Section("Pieces") {
            ForEach(statuses) { s in
                Button { onSelect(s.id) } label: { PieceRow(status: s) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(s.finished ? "Finished" : "Work this piece")
            }
        }
        if !assembly.isEmpty {
            Section("Assembly · \(assemblyDone.count) of \(assembly.count)") {
                ForEach(Array(assembly.enumerated()), id: \.offset) { i, step in
                    AssemblyStepRow(step: step, done: assemblyDone.contains(i), onToggle: { onToggleStep(i, $0) },
                                    onOpenPage: hasSourcePDF ? onOpenPage : nil)
                }
            }
        }
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

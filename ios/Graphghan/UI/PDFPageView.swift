import PDFKit
import SwiftUI

/// A PDF page, opened directly at one page (Task 9: an assembly step's kept PDF). A thin wrapper
/// over PDFKit's own view -- SwiftUI has no PDF viewer of its own, and `PageRenderer` only
/// rasterises a page for the grid reader, which is not what a maker wants to look at here.
///
/// `page` is 1-based, matching the page numbers the assembly text already reads ("page 15 of the
/// original PDF"). A page past the document's end clamps to its last page rather than showing
/// nothing; data that is not a PDF at all leaves the view blank rather than crashing.
struct PDFPageView: UIViewRepresentable {
    let data: Data
    let page: Int

    /// What has already been applied to the `PDFView`, so `updateUIView` -- called on every
    /// SwiftUI re-render, not just when `data` or `page` actually change -- does not rebuild the
    /// document or re-navigate when nothing asked for it (fix round 1, review focus 3: comparing
    /// `view.document` against a document freshly allocated from `data` is always a mismatch,
    /// since `PDFDocument(data:)` never returns the same instance twice).
    final class Coordinator {
        var data: Data?
        var page: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        apply(to: view, coordinator: context.coordinator)
    }

    private func apply(to view: PDFView, coordinator: Coordinator) {
        if coordinator.data != data {
            guard let document = PDFDocument(data: data) else { return }
            view.document = document
            coordinator.data = data
            coordinator.page = nil  // the new document has shown no page yet
        }
        guard coordinator.page != page, let document = view.document, document.pageCount > 0 else { return }
        let index = min(max(page - 1, 0), document.pageCount - 1)
        guard let pdfPage = document.page(at: index) else { return }
        view.go(to: pdfPage)
        coordinator.page = page
    }
}

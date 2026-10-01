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

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        apply(to: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: PDFView) {
        guard let document = PDFDocument(data: data) else { return }
        if view.document !== document { view.document = document }
        guard document.pageCount > 0 else { return }
        let index = min(max(page - 1, 0), document.pageCount - 1)
        guard let pdfPage = document.page(at: index) else { return }
        view.go(to: pdfPage)
    }
}

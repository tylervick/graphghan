import PDFKit
import Testing
@testable import Graphghan

/// `PDFPageView` applies a document once per caller identity, not on every render, and without
/// comparing the whole PDF each time.
@MainActor
@Suite struct PDFPageViewTests {
    @Test func theSameRequestKeepsItsDocumentAndANewOneReloads() throws {
        let data = try #require(PDFTestDocuments.twoCharts(rowsText: "Front", morePages: ["Strap"]))
        let view = PDFView()
        let coordinator = PDFPageView.Coordinator()
        let first = UUID()
        PDFPageView(data: data, page: 2, documentID: first).apply(to: view, coordinator: coordinator)
        let shown = try #require(view.document)
        #expect(view.currentPage == shown.page(at: 1))
        // A re-render with the same request: the same document instance, still at its page.
        PDFPageView(data: data, page: 2, documentID: first).apply(to: view, coordinator: coordinator)
        #expect(view.document === shown && view.currentPage == shown.page(at: 1))
        // The same bytes asked for again by a new request: loaded afresh.
        PDFPageView(data: data, page: 1, documentID: UUID()).apply(to: view, coordinator: coordinator)
        #expect(view.document !== shown && view.currentPage == view.document?.page(at: 0))
    }
}

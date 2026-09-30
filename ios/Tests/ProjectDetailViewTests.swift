import Foundation
import SwiftUI
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct ProjectDetailViewTests {
    /// Byte-identical to the pre-#44 text: a stitch chart's Sessions row must not move.
    @Test func sessionValueTextIsByteIdenticalForAStitchChart() {
        #expect(ProjectDetailView.sessionValueText(cells: 18, cellKind: .stitch, seconds: 300) == "18 stitches · 5 min")
    }

    @Test func sessionValueTextNamesTheNounForANonStitchKind() {
        #expect(ProjectDetailView.sessionValueText(cells: 18, cellKind: .block, seconds: 300) == "18 blocks · 5 min")
    }

    /// `PieceListSection` itself can't be snapshot -- `ImageRenderer` can't render the `List`
    /// `Section` needs as a container (it logs "Unable to render flattened version of
    /// ListRepresentable…" and returns a system placeholder instead of throwing). `PieceRow` and
    /// `AssemblyStepRow` carry the same visual content without that container, the way
    /// `project-cards` snapshots `ProjectCardView`s in a plain `VStack`.
    @Test @MainActor func pieceRowsSnapshot() throws {
        let manifest = try JSONDecoder().decode(PatternManifest.self, from: TestFixtures.pieces("pattern.json"))
        let pieces = manifest.pieces!
        let statuses = [
            PieceStatus(piece: pieces[0], copy: 1, isWritten: false, line: "Row 3 of 5", finished: false, isCurrent: true),
            PieceStatus(piece: pieces[1], copy: 1, isWritten: true, line: "Done", finished: true, isCurrent: false),
            PieceStatus(piece: pieces[2], copy: 1, isWritten: true, line: "Row 2 of 3", finished: false, isCurrent: false),
            PieceStatus(piece: pieces[2], copy: 2, isWritten: true, line: "3 rows", finished: false, isCurrent: false),
            PieceStatus(piece: pieces[3], copy: 1, isWritten: true, line: "Open-ended", finished: false, isCurrent: false),
        ]
        let view = VStack(alignment: .leading, spacing: 14) {
            ForEach(statuses) { PieceRow(status: $0) }
            AssemblyStepRow(step: manifest.assembly[0], done: true, onToggle: { _ in })
            AssemblyStepRow(step: manifest.assembly[1], done: false, onToggle: { _ in })
        }
        .padding(16)
        .background(Color.ground.weave())
        #expect(try Snapshots.assert(view, named: "project-pieces-rows", size: CGSize(width: 390, height: 480)))
    }

    @Test func pagesReadAsTheOriginalPDFsPages() {
        #expect(PieceListSection.pageText([15]) == "page 15 of the original PDF")
        #expect(PieceListSection.pageText([4, 5]) == "pages 4–5 of the original PDF")
        #expect(PieceListSection.pageText([3, 7]) == "pages 3, 7 of the original PDF")
        #expect(PieceListSection.pageText([]) == "")
    }
}

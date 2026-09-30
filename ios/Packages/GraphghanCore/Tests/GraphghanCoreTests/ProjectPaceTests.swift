import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ProjectPaceTests {
    struct Expected: Decodable {
        struct Piece: Decodable {
            let piece: String; let copy: Int; let kind: String; let finished: Bool; let percent: Double?
            let cells_done: Int?; let total_cells: Int?; let rows_done: Int?; let total_rows: Int?
            let stitches_done: Int?; let total_stitches: Int?
        }
        struct S: Decodable { let start: String; let end: String; let cells: Int; let rows: Int }
        let pieces: [Piece]; let pieces_done: Int; let pieces_total: Int; let assembly_done: Int; let assembly_total: Int
        let sessions: [S]; let active_seconds: Int; let stitches_per_hour: Double?
    }

    @Test func matchesThePiecesFixture() throws {
        let manifest = try JSONDecoder().decode(PatternManifest.self, from: Fixtures.pieces("pattern.json"))
        var models: [String: PieceModel] = [:]
        for piece in manifest.pieces ?? [] {
            if let rows = piece.rows {
                models[piece.id] = .written(WrittenSequence(try RowsDocument.load(Fixtures.pieces(rows))))
            } else if let path = manifest.charts.first(where: { $0.id == piece.chart })?.path {
                models[piece.id] = .chart(try WorkSequence(chart: Chart.load(Fixtures.pieces(path))))
            }
        }
        let doc = try ProjectProgressDocument.decode(Fixtures.pieces("progress.json"))
        let s = ProjectPace.summarize(doc, manifest: manifest, models: models)
        let e = try JSONDecoder().decode(Expected.self, from: Fixtures.pieces("progress.expected.json"))
        #expect(s.pieces.count == e.pieces.count)
        for (got, want) in zip(s.pieces, e.pieces) {
            #expect(got.key == PieceKey(piece: want.piece, copy: want.copy))
            #expect(got.isWritten == (want.kind == "rows") && got.finished == want.finished)
            #expect(got.percent.map { abs($0 - (want.percent ?? -1)) < 0.001 } ?? (want.percent == nil))
            #expect(got.cellsDone == want.cells_done && got.totalCells == want.total_cells)
            #expect(got.rowsDone == want.rows_done && got.totalRows == want.total_rows)
            #expect(got.stitchesDone == want.stitches_done && got.totalStitches == want.total_stitches)
        }
        #expect(s.piecesDone == e.pieces_done && s.piecesTotal == e.pieces_total)
        #expect(s.assemblyDone == e.assembly_done && s.assemblyTotal == e.assembly_total)
        #expect(s.sessions.map(\.cells) == e.sessions.map(\.cells) && s.sessions.map(\.rows) == e.sessions.map(\.rows))
        #expect(s.sessions.map { ProgressDates.format($0.start) } == e.sessions.map(\.start))
        #expect(s.activeSeconds == e.active_seconds)
        #expect(s.stitchesPerHour.map { abs($0 - (e.stitches_per_hour ?? -1)) < 0.001 } ?? (e.stitches_per_hour == nil))
    }

    @Test func aProgressDocumentRoundTrips() throws {
        let data = try Fixtures.pieces("progress.json")
        let doc = try ProjectProgressDocument.decode(data)
        #expect(try ProjectProgressDocument.decode(doc.encode()) == doc)
        #expect(doc.pieces[3].cursor == Cursor(row: 10, run: 0) && doc.current == PieceKey(piece: "panel", copy: 1))
    }

    /// Mirrors Python's test_refinishing_after_a_gap_adds_no_rows (tests/test_progress_project.py):
    /// un-finishing then re-finishing a written piece across a session gap, with the row never
    /// moving, must add no rows to the second session -- the running (cursor, finished) state
    /// carries across the gap rather than resetting per session.
    @Test func refinishingAfterAGapAddsNoRows() throws {
        let rows = [
            RowsDocument.Entry(label: "R 1", from: 1, to: 1, text: "a", count: 6, code: nil, repeatText: nil),
            RowsDocument.Entry(label: "R 2 - R 4", from: 2, to: 4, text: "b", count: 6, code: nil, repeatText: nil),
        ]
        let rdocID = RowsDocument.computeID(rows)
        let manifest = PatternManifest(schema: 2, id: "bag", title: "Bag", version: "1", dedication: "", quote: "",
                                       author: "", license: "", preview: "preview.png", palette: [], charts: [],
                                       updated: "2026-01-01T00:00:00Z",
                                       pieces: [ManifestPieceFixture.make(id: "strip", title: "Strip", make: 2,
                                                                          rows: "pieces/strip.rows.json", rowsID: rdocID)],
                                       assembly: [AssemblyStepFixture.make(title: "Sew up")])
        let rdocJSON = """
        {"schema":1,"id":"\(rdocID)","piece":{"title":"Strip"},"rows":[
            {"label":"R 1","from":1,"to":1,"count":6,"text":"a"},
            {"label":"R 2 - R 4","from":2,"to":4,"count":6,"text":"b"}
        ]}
        """
        let document = try RowsDocument.load(Data(rdocJSON.utf8))
        let models: [String: PieceModel] = ["strip": .written(WrittenSequence(document))]

        func ev(_ t: String, _ row: Int, _ kind: EventKind = .advance) -> PiecedEventRecord {
            PiecedEventRecord(t: ProgressDates.parse(t)!, piece: "strip", copy: 1, row: row, run: 0, kind: kind)
        }
        let events = [
            ev("2026-09-12T18:00:00Z", 2),
            ev("2026-09-12T18:01:00Z", 4, .jump),
            ev("2026-09-12T18:02:00Z", 4),                    // finishes the piece: session 1 counts row 4
            ev("2026-09-12T18:30:00Z", 4, .back),              // > 20 minutes later: a new session
            ev("2026-09-12T18:31:00Z", 4),                    // re-finishes; the row never moved, so no new rows
        ]
        let record = PieceProgressRecord(piece: "strip", copy: 1, docID: rdocID, cursor: Cursor(row: 4, run: 0),
                                          finished: ProgressDates.parse("2026-09-12T18:31:00Z"))
        let doc = ProjectProgressDocument(patternID: "bag", patternVersion: nil, pieces: [record],
                                          current: PieceKey(piece: "strip", copy: 1), assemblyDone: [],
                                          started: nil, finished: nil, events: events)
        let s = ProjectPace.summarize(doc, manifest: manifest, models: models)
        #expect(s.sessions.map(\.rows) == [4, 0])
    }

    /// Same-second events keep their recorded order, as Python's stable sort does: the log ends on
    /// a finishing advance, so the strip is finished at row 4 (4 rows done); taken in any other
    /// order it would end on a jump and leave the strip unfinished (3).
    @Test func sameSecondEventsKeepTheirRecordedOrder() throws {
        let rows = [
            RowsDocument.Entry(label: "R 1", from: 1, to: 1, text: "a", count: 6, code: nil, repeatText: nil),
            RowsDocument.Entry(label: "R 2 - R 4", from: 2, to: 4, text: "b", count: 6, code: nil, repeatText: nil),
        ]
        let rdocID = RowsDocument.computeID(rows)
        let manifest = PatternManifest(schema: 2, id: "bag", title: "Bag", version: "1", dedication: "", quote: "",
                                       author: "", license: "", preview: "preview.png", palette: [], charts: [],
                                       updated: "2026-01-01T00:00:00Z",
                                       pieces: [ManifestPieceFixture.make(id: "strip", title: "Strip", make: 1,
                                                                          rows: "pieces/strip.rows.json", rowsID: rdocID)],
                                       assembly: [])
        let rdocJSON = """
        {"schema":1,"id":"\(rdocID)","piece":{"title":"Strip"},"rows":[
            {"label":"R 1","from":1,"to":1,"count":6,"text":"a"},
            {"label":"R 2 - R 4","from":2,"to":4,"count":6,"text":"b"}
        ]}
        """
        let models: [String: PieceModel] = ["strip": .written(WrittenSequence(try RowsDocument.load(Data(rdocJSON.utf8))))]
        let t = ProgressDates.parse("2026-09-12T18:00:00Z")!
        // Many same-second events, so the sort cannot fall back on an insertion sort's stability.
        var events: [PiecedEventRecord] = []
        for _ in 0..<40 {
            events.append(PiecedEventRecord(t: t, piece: "strip", copy: 1, row: 4, run: 0, kind: .jump))
            events.append(PiecedEventRecord(t: t, piece: "strip", copy: 1, row: 4, run: 0, kind: .advance))  // finishes
        }
        let doc = ProjectProgressDocument(patternID: "bag", patternVersion: nil,
                                          pieces: [PieceProgressRecord(piece: "strip", copy: 1, docID: rdocID,
                                                                       cursor: Cursor(row: 4, run: 0), finished: nil)],
                                          current: PieceKey(piece: "strip", copy: 1), assemblyDone: [],
                                          started: nil, finished: nil, events: events)
        #expect(ProjectPace.summarize(doc, manifest: manifest, models: models).sessions.map(\.rows) == [4])
    }
}

/// Test-only convenience initializers: `ManifestPiece` and `AssemblyStep` are `Decodable` only.
private enum ManifestPieceFixture {
    static func make(id: String, title: String, make: Int, rows: String, rowsID: String) -> ManifestPiece {
        let json = """
        {"id":"\(id)","title":"\(title)","make":\(make),"rows":"\(rows)","rows_id":"\(rowsID)"}
        """
        return try! JSONDecoder().decode(ManifestPiece.self, from: Data(json.utf8))
    }
}

private enum AssemblyStepFixture {
    static func make(title: String) -> AssemblyStep {
        let json = """
        {"title":"\(title)"}
        """
        return try! JSONDecoder().decode(AssemblyStep.self, from: Data(json.utf8))
    }
}

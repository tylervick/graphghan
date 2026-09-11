import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ProgressDocumentTests {
    @Test func decodesTheFixture() throws {
        let doc = try ProgressDocument.decode(Fixtures.data("progress-basic.progress.json"))
        #expect(doc.schema == 1 && doc.patternID == "minimal" && doc.patternVersion == "1.0.0")
        #expect(doc.cursor == Cursor(row: 5, run: 1) && doc.finished == nil)
        #expect(doc.events.count == 8 && doc.events[4].kind == .back && doc.events[6].kind == .jump)
        #expect(ProgressDates.format(doc.started!) == "2026-09-12T18:00:00Z")
    }

    @Test func roundTripsAndWritesNullChartID() throws {
        let doc = ProgressDocument.legacy(slug: "craigh-na-dun", row: 42, run: 3)
        let data = try doc.encode()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"chart_id\":null"))
        #expect(text.contains("\"pattern_id\":\"craigh-na-dun\""))
        #expect(try ProgressDocument.decode(data) == doc)
    }

    @Test func datesAcceptFractionalSeconds() {
        #expect(ProgressDates.parse("2026-09-12T18:00:00Z") != nil)
        #expect(ProgressDates.parse("2026-09-12T18:00:00.250Z") != nil)
        #expect(ProgressDates.parse("yesterday") == nil)
    }
}

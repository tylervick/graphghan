import Foundation

/// What the app asks of a written-row reader (phone import spec §9): the same call `ProseReader`
/// answers, so a test can stand a canned document in for the model.
public protocol RowReading: Sendable {
    func read(pages: [String], progress: (@Sendable (ReaderProgress) -> Void)?) async -> ProseDocument
}

@available(macOS 26.0, iOS 26.0, *)
extension ProseReader: RowReading {}

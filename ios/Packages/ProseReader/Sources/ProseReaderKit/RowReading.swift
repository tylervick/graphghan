import Foundation

/// What the app asks of a written-row reader (phone import spec §9): the same call `ProseReader`
/// answers, so a test can stand a canned document in for the model.
public protocol RowReading: Sendable {
    /// `section` limits the rows read to one run of them (`RowText.section(fitting:in:)`); nil reads every row.
    func read(pages: [String], section: RowSection?, progress: (@Sendable (ReaderProgress) -> Void)?) async -> ProseDocument
}

/// Words a reader writes on a row's `error` that the app acts on rather than shows (#176). Not
/// on `ProseReader`, which needs iOS 26: the importer that matches them runs on iOS 17 too.
public enum ReaderFailure {
    /// Every attempt at this row was refused because the model is being asked too often.
    public static let modelBusy = "the on-device model is busy"
}

@available(macOS 26.0, iOS 26.0, *)
extension ProseReader: RowReading {}

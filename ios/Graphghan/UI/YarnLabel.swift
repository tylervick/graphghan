import GraphghanCore

/// The secondary line under a palette entry: the yarn it was worked in, and what it is used for.
/// Pure so it is testable; `PatternDetailView` renders it.
enum YarnLabel {
    /// `[yarn.brand, yarn.line, yarn.colorway]` joined with spaces, falling back to `yarn.note`,
    /// then to `use` alone. Empty strings count as absent, so nothing ever renders as " · " or a
    /// stray separator.
    static func text(yarn: [String: String]?, use: String?) -> String? {
        func present(_ s: String?) -> String? {
            guard let s, !s.isEmpty else { return nil }
            return s
        }
        let joined = ["brand", "line", "colorway"].compactMap { present(yarn?[$0]) }.joined(separator: " ")
        let yarnText = joined.isEmpty ? present(yarn?["note"]) : joined
        switch (yarnText, present(use)) {
        case let (.some(y), .some(u)): return "\(y) · \(u)"
        case let (.some(y), .none): return y
        case let (.none, .some(u)): return u
        case (.none, .none): return nil
        }
    }

    static func text(for entry: ChartDocument.PaletteEntry) -> String? {
        text(yarn: entry.yarn, use: entry.use)
    }
}

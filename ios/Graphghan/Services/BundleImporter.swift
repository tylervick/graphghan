import Foundation
import GraphghanCore

/// Turns the bytes of a `.graphghan` file into a pattern the library shows and a project can
/// start from. It knows nothing about where the file came from -- Files, Mail, AirDrop and the
/// `--import` launch argument all arrive here as `Data`.
///
/// The order is the point (design spec §6.2). `PatternBundle.read` decodes and validates every
/// chart in memory first, so a bundle that is wrong in any way throws before a single byte is
/// written and the library is exactly as it was. Only then are the charts stored and the pattern
/// directory swapped into place.
struct BundleImporter: Sendable {
    let charts: ChartLibrary
    let local: LocalPatternStore

    /// The imported pattern's manifest. Re-importing an id that is already local replaces it:
    /// charts are keyed by content hash, so the same chart rewrites the same file, and the
    /// pattern directory is written whole.
    @discardableResult
    func importBundle(_ data: Data) async throws -> PatternManifest {
        let bundle = try PatternBundle.read(data)
        for chart in bundle.charts {
            _ = try await charts.store(chart.data)
        }
        try await local.save(bundle)
        return bundle.manifest
    }
}

/// The graphghan chart format, as read by this package. See docs/chart-format.md at the repo root.
public enum GraphghanCore {
    /// The chart document schema this package decodes.
    public static let formatSchema = 2
    /// The progress document schema this package reads and writes.
    public static let progressSchema = 1
}

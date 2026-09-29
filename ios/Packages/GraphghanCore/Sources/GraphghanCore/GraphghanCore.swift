/// The graphghan chart format, as read by this package. See docs/chart-format.md at the repo root.
public enum GraphghanCore {
    /// The schema this package writes a rectangular chart at. `Chart` reads both schemas 2 and 3
    /// (3 = shaped rows, a palette entry marked `"stitch": false`; docs/chart-format.md §Shaped rows).
    public static let formatSchema = 2
    /// The progress document schema this package reads and writes.
    public static let progressSchema = 1
}

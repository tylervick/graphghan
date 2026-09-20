import Foundation
import Testing
@testable import GraphghanCore

@Suite struct PatternBundleTests {
    static let slug = "craigh-na-dun"

    static func fixture() throws -> Data { try Fixtures.bundle(slug) }

    /// The committed fixture with entries dropped or replaced, repacked stored — the shapes a
    /// hand-made or half-broken bundle has, without committing one of each.
    static func rebuilt(dropping: Set<String> = [], replacing: [String: Data] = [:]) throws -> Data {
        let archive = try ZipArchive(fixture())
        var items: [ZipBuilder.Item] = []
        for name in archive.names where !dropping.contains(name) {
            let bytes = try replacing[name] ?? archive.data(named: name)
            items.append(ZipBuilder.Item(name, bytes))
        }
        return ZipBuilder(items: items).build()
    }

    static func manifestJSON() throws -> [String: Any] {
        let data = try ZipArchive(fixture()).data(named: PatternBundle.manifestName)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    static func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: the committed fixture

    @Test func opensTheCommittedFixture() throws {
        let bundle = try PatternBundle.read(Self.fixture())
        #expect(bundle.manifest.id == Self.slug)
        #expect(bundle.manifest.schema == 1)
        #expect(bundle.manifest.title == "Craigh na Dun Blanket")
        #expect(bundle.charts.count == 2)
        // Default first, as the manifest lists them.
        #expect(bundle.charts.first?.entry.isDefault == true)
    }

    @Test func everyChartLoadsAndMatchesItsManifestEntry() throws {
        let bundle = try PatternBundle.read(Self.fixture())
        for chart in bundle.charts {
            #expect(chart.chart.id == chart.entry.id)
            #expect(chart.chart.width == chart.entry.width)
            #expect(chart.chart.height == chart.entry.height)
            #expect(!chart.data.isEmpty)
            // The bytes are the file, not a re-encode: ChartLibrary stores them as they came.
            #expect(try Chart.load(chart.data).id == chart.entry.id)
        }
    }

    @Test func everyReferencedPreviewIsPresentAndIsAPNG() throws {
        let bundle = try PatternBundle.read(Self.fixture())
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        let wanted = [bundle.manifest.preview] + bundle.manifest.charts.map(\.preview)
        for path in wanted {
            let data = try #require(bundle.previews[path], "no preview at \(path)")
            #expect(Array(data.prefix(4)) == png)
        }
    }

    @Test func theBundleCarriesNothingUnreferenced() throws {
        // §2: the manifest's paths and nothing else, so the bundle is not a copy of the site tree.
        let archive = try ZipArchive(Self.fixture())
        let bundle = try PatternBundle.read(Self.fixture())
        var expected = Set([PatternBundle.manifestName, bundle.manifest.preview])
        for chart in bundle.manifest.charts { expected.formUnion([chart.path, chart.preview]) }
        #expect(Set(archive.names) == expected)
    }

    // MARK: refusals

    @Test func somethingThatIsNotAZipIsRefused() {
        #expect(throws: BundleError.badArchive(.notAZip)) { try PatternBundle.read(Data("nope".utf8)) }
    }

    @Test func aTruncatedBundleIsRefused() throws {
        let half = try Self.fixture().prefix(20_000)
        #expect(throws: BundleError.badArchive(.notAZip)) { try PatternBundle.read(half) }
    }

    @Test func aZipWithoutAManifestIsRefused() throws {
        let data = try Self.rebuilt(dropping: [PatternBundle.manifestName])
        #expect(throws: BundleError.noManifest) { try PatternBundle.read(data) }
    }

    @Test func anUndecodableManifestIsRefused() throws {
        let data = try Self.rebuilt(replacing: [PatternBundle.manifestName: Data("{".utf8)])
        do {
            _ = try PatternBundle.read(data)
            Issue.record("expected a refusal")
        } catch let error as BundleError {
            guard case .badManifest = error else { Issue.record("got \(error)"); return }
        }
    }

    @Test func aMissingChartFileIsRefused() throws {
        let missing = "charts/final-hdc/chart.json"
        let data = try Self.rebuilt(dropping: [missing])
        #expect(throws: BundleError.missingFile(missing)) { try PatternBundle.read(data) }
    }

    @Test func aMissingPreviewIsRefused() throws {
        // Every path the manifest references has to be there, previews included: a manifest that
        // names a file the archive does not carry is a manifest that lies.
        let missing = "preview.png"
        let data = try Self.rebuilt(dropping: [missing])
        #expect(throws: BundleError.missingFile(missing)) { try PatternBundle.read(data) }
    }

    @Test func aChartThatFailsValidationIsRefusedNamingIt() throws {
        let path = "charts/final-sc/chart.json"
        let broken = Data(#"{"schema":99,"pattern":{},"chart":{}}"#.utf8)
        let data = try Self.rebuilt(replacing: [path: broken])
        do {
            _ = try PatternBundle.read(data)
            Issue.record("expected a refusal")
        } catch let error as BundleError {
            guard case .invalidChart(let named, _) = error else { Issue.record("got \(error)"); return }
            #expect(named == path)
            #expect(error.message.contains(path))
        }
    }

    @Test func aChartIDThatDisagreesWithTheManifestIsRefused() throws {
        var object = try Self.manifestJSON()
        var charts = object["charts"] as! [[String: Any]]
        let fake = "sha256:" + String(repeating: "0", count: 64)
        charts[0]["id"] = fake
        object["charts"] = charts
        let data = try Self.rebuilt(replacing: [PatternBundle.manifestName: try Self.encode(object)])
        do {
            _ = try PatternBundle.read(data)
            Issue.record("expected a refusal")
        } catch let error as BundleError {
            guard case .chartIDMismatch(_, let expected, let found) = error else {
                Issue.record("got \(error)")
                return
            }
            #expect(expected == fake)
            #expect(found != fake)
        }
    }

    @Test func aManifestFromANewerFormatIsRefused() throws {
        var object = try Self.manifestJSON()
        object["schema"] = 2
        let data = try Self.rebuilt(replacing: [PatternBundle.manifestName: try Self.encode(object)])
        #expect(throws: BundleError.unsupportedManifestSchema(2)) { try PatternBundle.read(data) }
    }

    @Test(arguments: ["", "../evil", "Craigh Na Dun", "a/b"])
    func aPatternIDThatIsNotASlugIsRefused(id: String) throws {
        var object = try Self.manifestJSON()
        object["id"] = id
        let data = try Self.rebuilt(replacing: [PatternBundle.manifestName: try Self.encode(object)])
        #expect(throws: BundleError.badPatternID(id)) { try PatternBundle.read(data) }
    }

    @Test func aManifestWithNoChartsIsRefused() throws {
        var object = try Self.manifestJSON()
        object["charts"] = [[String: Any]]()
        let data = try Self.rebuilt(replacing: [PatternBundle.manifestName: try Self.encode(object)])
        #expect(throws: BundleError.noCharts) { try PatternBundle.read(data) }
    }

    @Test func aManifestListingOneChartTwiceIsRefused() throws {
        var object = try Self.manifestJSON()
        let charts = object["charts"] as! [[String: Any]]
        object["charts"] = [charts[0], charts[0]]
        let data = try Self.rebuilt(replacing: [PatternBundle.manifestName: try Self.encode(object)])
        #expect(throws: BundleError.duplicateChartPath(charts[0]["path"] as! String)) {
            try PatternBundle.read(data)
        }
    }

    // MARK: the sentences

    @Test(arguments: [
        BundleError.badArchive(.notAZip), .badArchive(.encrypted("a")), .badArchive(.zip64),
        .badArchive(.unsafeName("../x")), .badArchive(.corrupt("a")), .badArchive(.entryTooLarge("a", 1)),
        .noManifest, .badManifest("x"), .unsupportedManifestSchema(2), .badPatternID("X"),
        .noCharts, .duplicateChartPath("p"), .missingFile("p"),
        .invalidChart(path: "p", reason: "r"), .chartIDMismatch(path: "p", expected: "a", found: "b"),
    ])
    func everyRefusalHasASentence(error: BundleError) {
        #expect(!error.message.isEmpty)
        #expect(error.message.hasSuffix("."))
    }

    // MARK: the index projection

    @Test func theManifestProjectsToTheRowTheSiteWouldPublish() throws {
        let manifest = try PatternBundle.read(Self.fixture()).manifest
        let entry = IndexEntry(manifest: manifest)
        let chart = try #require(manifest.defaultChart)
        #expect(entry.slug == manifest.id)
        #expect(entry.title == manifest.title)
        #expect(entry.dedication == manifest.dedication)
        #expect(entry.version == manifest.version)
        #expect(entry.stitch == chart.stitch)
        #expect(entry.width == chart.width)
        #expect(entry.height == chart.height)
        #expect(entry.colors == chart.colors)
        #expect(entry.sizeIn == [chart.size.width, chart.size.height])
        #expect(entry.charts == manifest.charts.count)
        #expect(entry.preview == manifest.preview)
        #expect(entry.manifest == nil)  // nothing to fetch: a local pattern has no site path
    }

    @Test func aCentimetreGaugeProjectsToInches() throws {
        let json = """
        {"schema":1,"id":"p","title":"P","version":"1","dedication":"","quote":"","author":"","license":"",
         "preview":"preview.png","palette":[],"charts":[{"id":"sha256:x","variant":"final","gauge_key":"sc",
         "default":true,"path":"c.json","preview":"p.png","width":10,"height":20,
         "size":{"width":127.0,"height":254.0,"unit":"cm"},"stitch":"sc","colors":3,"stitches":200,
         "changes_per_row":{"mean":1,"max":2},"yards_est":5}],"updated":"2026-01-01T00:00:00Z"}
        """
        let manifest = try JSONDecoder().decode(PatternManifest.self, from: Data(json.utf8))
        #expect(IndexEntry(manifest: manifest).sizeIn == [50.0, 100.0])
    }
}

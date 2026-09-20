import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

/// Opening a `.graphghan` file: the whole path from bytes to a pattern a project starts from,
/// against the committed fixture the Python writer produces (#16).
@MainActor
@Suite struct BundleImportTests {
    struct Harness {
        let model: AppModel
        let client: StubClient
        let chartsDirectory: URL
        let localDirectory: URL
    }

    static let slug = "craigh-na-dun"

    func make() async throws -> Harness {
        let container = try makeInMemoryContainer()
        let client = StubClient()
        let chartsDirectory = try temporaryDirectory()
        let localDirectory = try temporaryDirectory()
        // The stub answers nothing: every path below has to work without the network.
        let patterns = PatternStore(baseURL: URL(string: "https://example.test/")!,
                                    cacheDirectory: try temporaryDirectory(), client: client)
        let model = AppModel(context: container.mainContext,
                             patterns: patterns,
                             charts: ChartLibrary(directory: chartsDirectory),
                             localPatterns: LocalPatternStore(directory: localDirectory))
        return Harness(model: model, client: client, chartsDirectory: chartsDirectory, localDirectory: localDirectory)
    }

    func fixture() throws -> Data { try TestFixtures.bundle(Self.slug) }

    func storedChartFiles(_ harness: Harness) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: harness.chartsDirectory.path)) ?? []).sorted()
    }

    func localDirectories(_ harness: Harness) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: harness.localDirectory.path)) ?? []).sorted()
    }

    // MARK: importing

    @Test func importingStoresEveryChartAndShowsThePattern() async throws {
        let harness = try await make()
        let manifest = try #require(await harness.model.importBundle(data: fixture()))
        #expect(manifest.id == Self.slug)

        let expected = try PatternBundle.read(fixture())
        for chart in expected.charts {
            #expect(await harness.model.charts.hasChart(id: chart.entry.id))
        }
        #expect(storedChartFiles(harness).count == expected.charts.count)

        // ...and it is in the Patterns tab, in the local section.
        let local = harness.model.libraryItems.filter(\.isLocal)
        #expect(local.map(\.slug) == [Self.slug])
        #expect(local.first?.entry.title == manifest.title)
        #expect(harness.model.isLocal(Self.slug))
        #expect(harness.model.importFailure == nil)
    }

    @Test func importingLandsOnThePatternItJustOpened() async throws {
        let harness = try await make()
        await harness.model.importBundle(data: try fixture())
        #expect(harness.model.tab == .patterns)
        #expect(harness.model.libraryPath.map(\.slug) == [Self.slug])
        #expect(harness.model.libraryPath.first?.source == .local)
    }

    @Test func theManifestAndPreviewsComeBackWithoutTheNetwork() async throws {
        let harness = try await make()
        await harness.model.importBundle(data: try fixture())
        let manifest = try await harness.model.manifest(for: Self.slug, path: nil)
        #expect(manifest.id == Self.slug)
        #expect(!manifest.charts.isEmpty)
        #expect(await harness.model.preview(for: Self.slug, sitePath: "patterns/\(Self.slug)/preview.png") != nil)
        let chart = try #require(manifest.defaultChart)
        #expect(await harness.model.chartPreview(for: Self.slug, path: chart.preview) != nil)
        #expect(await harness.client.requests().isEmpty, "a local pattern must not reach for the network")
    }

    @Test func aProjectStartsFromALocalPatternWithNoNetwork() async throws {
        let harness = try await make()
        let manifest = try #require(await harness.model.importBundle(data: fixture()))
        let chart = try #require(manifest.defaultChart)
        let project = try await harness.model.projects.startProject(manifest: manifest, chart: chart, title: "Meaghan's")
        #expect(project.chartID == chart.id)
        #expect(project.patternID == Self.slug)
        #expect(await harness.client.requests().isEmpty)
        // The Work screen's input comes off the stored chart, not a download.
        let sequence = try await harness.model.projects.sequence(for: project)
        #expect(sequence.totalCells > 0)
    }

    @Test func reimportingUpdatesRatherThanDuplicates() async throws {
        let harness = try await make()
        await harness.model.importBundle(data: try fixture())
        let firstCharts = storedChartFiles(harness)
        await harness.model.importBundle(data: try fixture())
        #expect(harness.model.libraryItems.filter(\.isLocal).count == 1)
        #expect(localDirectories(harness) == [Self.slug])
        #expect(storedChartFiles(harness) == firstCharts)
    }

    @Test func reimportingTakesTheNewVersionsTitle() async throws {
        let harness = try await make()
        await harness.model.importBundle(data: try fixture())
        let renamed = try Self.rebuiltFixture { $0["title"] = "Craigh na Dun, revised" }
        let manifest = try #require(await harness.model.importBundle(data: renamed))
        #expect(manifest.title == "Craigh na Dun, revised")
        let local = harness.model.libraryItems.filter(\.isLocal)
        #expect(local.count == 1)
        #expect(local.first?.entry.title == "Craigh na Dun, revised")
    }

    // MARK: refusals leave everything alone

    @Test(arguments: ["truncated", "not-a-zip", "bad-chart"])
    func aBrokenBundleReportsWhyAndChangesNothing(kind: String) async throws {
        let harness = try await make()
        let broken: Data = switch kind {
        case "truncated": try fixture().prefix(20_000)
        case "not-a-zip": Data("this is not a pattern".utf8)
        default: try Self.rebuiltFixture(replacingChart: Data(#"{"schema":99}"#.utf8))
        }
        let result = await harness.model.importBundle(data: broken)
        #expect(result == nil)
        let failure = try #require(harness.model.importFailure)
        #expect(!failure.isEmpty)
        #expect(harness.model.libraryItems.filter(\.isLocal).isEmpty)
        #expect(storedChartFiles(harness).isEmpty, "nothing may be stored before the whole bundle validates")
        #expect(localDirectories(harness).isEmpty)
    }

    @Test func abrokenBundleLeavesAnAlreadyImportedPatternAlone() async throws {
        let harness = try await make()
        await harness.model.importBundle(data: try fixture())
        let before = storedChartFiles(harness)
        await harness.model.importBundle(data: Data("nope".utf8))
        #expect(harness.model.importFailure != nil)
        #expect(harness.model.libraryItems.filter(\.isLocal).count == 1)
        #expect(storedChartFiles(harness) == before)
    }

    @Test func theFailureNamesTheChartThatIsWrong() async throws {
        let harness = try await make()
        let broken = try Self.rebuiltFixture(replacingChart: Data(#"{"schema":99}"#.utf8))
        await harness.model.importBundle(data: broken)
        let failure = try #require(harness.model.importFailure)
        #expect(failure.contains("chart.json"))
    }

    // MARK: file URLs

    @Test func afileTooBigToBeAPatternIsRefusedWithoutReadingIt() async throws {
        let harness = try await make()
        let url = try temporaryDirectory().appendingPathComponent("huge.graphghan")
        // Sparse: the point is that the size attribute is consulted before the bytes are.
        try Data().write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(AppModel.maximumBundleBytes) + 1)
        try handle.close()
        await harness.model.importBundle(at: url)
        #expect(harness.model.importFailure == "That file is too big to be a pattern.")
        #expect(harness.model.libraryItems.filter(\.isLocal).isEmpty)
    }

    @Test func afileThatIsNotThereIsReportedNotCrashed() async throws {
        let harness = try await make()
        await harness.model.importBundle(at: URL(fileURLWithPath: "/nonexistent/x.graphghan"))
        #expect(harness.model.importFailure != nil)
    }

    @Test func aFileURLImportsLikeBytes() async throws {
        let harness = try await make()
        let url = try temporaryDirectory().appendingPathComponent("\(Self.slug).graphghan")
        try fixture().write(to: url)
        await harness.model.importBundle(at: url)
        #expect(harness.model.libraryItems.filter(\.isLocal).map(\.slug) == [Self.slug])
        // Outside the Inbox, the file is the maker's; it stays where it is.
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: [true, false])
    func theInboxCopyIsDeletedEitherWay(valid: Bool) async throws {
        let harness = try await make()
        let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let url = inbox.appendingPathComponent("\(UUID().uuidString).graphghan")
        try (valid ? fixture() : Data("nope".utf8)).write(to: url)
        await harness.model.importBundle(at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path), "the Inbox copy has to go either way")
    }

    // MARK: the launch argument

    @Test func theLaunchArgumentNamesTheFileToImport() {
        #expect(AppModel.launchImportURL(["Graphghan", "--import", "/tmp/a.graphghan"])?.path == "/tmp/a.graphghan")
        #expect(AppModel.launchImportURL(["Graphghan"]) == nil)
        #expect(AppModel.launchImportURL(["Graphghan", "--import"]) == nil)
    }

    // MARK: fixture surgery

    /// The committed bundle repacked with its manifest edited, for the cases a second committed
    /// fixture would otherwise be needed for.
    static func rebuiltFixture(_ edit: (inout [String: Any]) -> Void) throws -> Data {
        let data = try TestFixtures.bundle(slug)
        let archive = try ZipArchive(data)
        var object = try JSONSerialization.jsonObject(
            with: try archive.data(named: PatternBundle.manifestName)) as! [String: Any]
        edit(&object)
        return try repack(archive, replacing: [PatternBundle.manifestName: JSONSerialization.data(withJSONObject: object)])
    }

    static func rebuiltFixture(replacingChart bytes: Data) throws -> Data {
        let data = try TestFixtures.bundle(slug)
        let archive = try ZipArchive(data)
        let manifest = try JSONDecoder().decode(
            PatternManifest.self, from: try archive.data(named: PatternBundle.manifestName))
        let path = try #require(manifest.defaultChart).path
        return try repack(archive, replacing: [path: bytes])
    }

    /// Repacks an archive's entries stored, which is how the writer packs them anyway.
    ///
    /// Written as appends rather than one chain of `+`: a long chain of `Data + Data` is a
    /// type-checker timeout waiting to happen, and it timed out on CI's Xcode before this.
    static func repack(_ archive: ZipArchive, replacing: [String: Data]) throws -> Data {
        var out = Data()
        var central = Data()
        for name in archive.names {
            let bytes = try replacing[name] ?? archive.data(named: name)
            let nameBytes = Data(name.utf8)
            let offset = UInt32(out.count)
            let size = UInt32(bytes.count)

            // The fields a local and a central header share, in the same order in both.
            var common = Data()
            append16(&common, 20)      // version needed
            append16(&common, 0)       // flags
            append16(&common, 0)       // method: stored
            append16(&common, 0)       // time
            append16(&common, 0x0021)  // date: 1980-01-01
            append32(&common, crc32(bytes))
            append32(&common, size)    // compressed
            append32(&common, size)    // uncompressed
            append16(&common, UInt16(nameBytes.count))
            append16(&common, 0)       // extra length

            append32(&out, 0x0403_4b50)
            out.append(common)
            out.append(nameBytes)
            out.append(bytes)

            append32(&central, 0x0201_4b50)
            append16(&central, 20)     // version made by
            central.append(common)
            append16(&central, 0)      // comment length
            append16(&central, 0)      // disk start
            append16(&central, 0)      // internal attributes
            append32(&central, 0o644 << 16)
            append32(&central, offset)
            central.append(nameBytes)
        }
        let directoryOffset = UInt32(out.count)
        let count = UInt16(archive.names.count)
        out.append(central)
        append32(&out, 0x0605_4b50)
        append16(&out, 0)              // this disk
        append16(&out, 0)              // disk with the directory
        append16(&out, count)
        append16(&out, count)
        append32(&out, UInt32(central.count))
        append32(&out, directoryOffset)
        append16(&out, 0)              // comment length
        return out
    }

    static func append16(_ data: inout Data, _ v: UInt16) {
        data.append(UInt8(v & 0xFF))
        data.append(UInt8(v >> 8 & 0xFF))
    }

    static func append32(_ data: inout Data, _ v: UInt32) {
        append16(&data, UInt16(v & 0xFFFF))
        append16(&data, UInt16(v >> 16 & 0xFFFF))
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1 == 1) ? (0xEDB8_8320 ^ (crc >> 1)) : (crc >> 1) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

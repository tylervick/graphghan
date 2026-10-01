import Foundation
import Testing
import GraphghanCore
@testable import Graphghan

@Suite struct LocalPatternStoreTests {
    static let slug = "craigh-na-dun"

    func make() throws -> (LocalPatternStore, URL) {
        let directory = try temporaryDirectory()
        return (LocalPatternStore(directory: directory), directory)
    }

    func bundle() throws -> PatternBundle { try PatternBundle.read(TestFixtures.bundle(Self.slug)) }

    @Test func savingThenReadingGivesTheSameManifest() async throws {
        let (store, _) = try make()
        let bundle = try bundle()
        try await store.save(bundle)
        let read = try #require(await store.manifest(for: Self.slug))
        // The manifest is written back as the bytes that arrived, so it round-trips exactly.
        #expect(read == bundle.manifest)
        #expect(await store.has(id: Self.slug))
        #expect(await store.manifests().map(\.id) == [Self.slug])
    }

    @Test func previewsComeBackAtTheirManifestRelativePaths() async throws {
        let (store, _) = try make()
        let bundle = try bundle()
        try await store.save(bundle)
        for (path, bytes) in bundle.previews {
            #expect(await store.preview(for: Self.slug, path: path) == bytes, "\(path)")
        }
    }

    @Test func savingTwiceReplacesRatherThanMerges() async throws {
        let (store, directory) = try make()
        let bundle = try bundle()
        try await store.save(bundle)
        // A stray file inside the pattern's directory must not survive the next save.
        let stray = directory.appendingPathComponent("\(Self.slug)/stray.txt")
        try Data("x".utf8).write(to: stray)
        try await store.save(bundle)
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        #expect(await store.manifests().count == 1)
    }

    @Test func aSaveLeavesNoStagingDirectoryBehind() async throws {
        let (store, directory) = try make()
        try await store.save(try bundle())
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names == [Self.slug])
    }

    @Test func anUnreadableDirectoryIsSkippedRatherThanFatal() async throws {
        let (store, directory) = try make()
        try await store.save(try bundle())
        let junk = directory.appendingPathComponent("junk", isDirectory: true)
        try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: junk.appendingPathComponent("pattern.json"))
        #expect(await store.manifests().map(\.id) == [Self.slug])
    }

    @Test func manifestsAreSortedByTitle() async throws {
        let (store, directory) = try make()
        let bundle = try bundle()
        try await store.save(bundle)
        // A second pattern, by hand: the same manifest under another id and title.
        for (id, title) in [("aardvark", "Aardvark Blanket"), ("zebra", "Zebra Blanket")] {
            var object = try JSONSerialization.jsonObject(with: bundle.manifestData) as! [String: Any]
            object["id"] = id
            object["title"] = title
            let dir = directory.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: object)
                .write(to: dir.appendingPathComponent("pattern.json"))
        }
        #expect(await store.manifests().map(\.title) == ["Aardvark Blanket", "Craigh na Dun Blanket", "Zebra Blanket"])
    }

    @Test(arguments: ["../escape.png", "/etc/passwd", "a/../../b.png", ""])
    func aPathThatCouldLeaveThePatternDirectoryAnswersNothing(path: String) async throws {
        let (store, _) = try make()
        try await store.save(try bundle())
        #expect(await store.preview(for: Self.slug, path: path) == nil)
    }

    @Test(arguments: ["..", "a/b", "", ".hidden"])
    func anIDThatIsNotADirectoryNameAnswersNothing(id: String) async throws {
        let (store, _) = try make()
        try await store.save(try bundle())
        #expect(await store.preview(for: id, path: "preview.png") == nil)
    }

    /// A PDF import keeps its source PDF beside the pattern (pieces spec §5.5), written into the
    /// same staging directory so it lands with the pattern or not at all, and replaced with it.
    @Test func aSourcePDFIsSavedBesideThePatternAndGoesWithIt() async throws {
        let (store, directory) = try make()
        let bundle = try bundle()
        let pdf = Data("%PDF-1.7 not really".utf8)
        try await store.save(bundle, sourcePDF: pdf)
        #expect(await store.sourcePDF(for: Self.slug) == pdf)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(Self.slug)/source.pdf").path))
        // The directory is replaced whole: a save without a PDF leaves none behind.
        try await store.save(bundle)
        #expect(await store.sourcePDF(for: Self.slug) == nil)
        #expect(await store.sourcePDF(for: "nothing") == nil)
        #expect(await store.sourcePDF(for: "..") == nil)
    }

    /// Fix round 1, review focus 2: `hasSourcePDF` answers from the filesystem alone, without
    /// reading the PDF's bytes -- true once a PDF is saved beside the pattern, false for one saved
    /// without a PDF or that never existed.
    @Test func hasSourcePDFAnswersWithoutLoadingIt() async throws {
        let (store, _) = try make()
        let bundle = try bundle()
        #expect(await store.hasSourcePDF(for: Self.slug) == false)
        try await store.save(bundle, sourcePDF: Data("%PDF-1.7 not really".utf8))
        #expect(await store.hasSourcePDF(for: Self.slug) == true)
        // The directory is replaced whole: a save without a PDF leaves none behind.
        try await store.save(bundle)
        #expect(await store.hasSourcePDF(for: Self.slug) == false)
        #expect(await store.hasSourcePDF(for: "nothing") == false)
    }

    /// Review Focus 5: a PDF imported twice gets its own slug and its own `source.pdf`; deleting
    /// one pattern's directory (the store has no delete of its own -- `FileManager`, as a maker's
    /// own removal of a pattern would reach, at the store's directory for that id) never touches
    /// the other's PDF.
    @Test func eachImportKeepsItsOwnPDF() async throws {
        let (store, directory) = try make()
        let bundle = try bundle()
        let pdfA = Data("%PDF-1.7 A".utf8)
        let pdfB = Data("%PDF-1.7 B".utf8)
        try await store.save(bundle, sourcePDF: pdfA)

        var object = try JSONSerialization.jsonObject(with: bundle.manifestData) as! [String: Any]
        object["id"] = "second-id"
        object["title"] = "Second Blanket"
        let secondData = try JSONSerialization.data(withJSONObject: object)
        let secondManifest = try JSONDecoder().decode(PatternManifest.self, from: secondData)
        let secondBundle = PatternBundle(manifest: secondManifest, manifestData: secondData,
                                         charts: bundle.charts, previews: bundle.previews, rows: bundle.rows)
        try await store.save(secondBundle, sourcePDF: pdfB)

        #expect(await store.sourcePDF(for: Self.slug) == pdfA)
        #expect(await store.sourcePDF(for: "second-id") == pdfB)

        try FileManager.default.removeItem(at: directory.appendingPathComponent(Self.slug, isDirectory: true))
        #expect(await store.sourcePDF(for: Self.slug) == nil)
        #expect(await store.sourcePDF(for: "second-id") == pdfB)
    }

    @Test func anEmptyStoreIsEmptyRatherThanAnError() async throws {
        let (store, _) = try make()
        #expect(await store.manifests().isEmpty)
        #expect(await store.manifest(for: "nothing") == nil)
        #expect(await store.has(id: "nothing") == false)
    }
}

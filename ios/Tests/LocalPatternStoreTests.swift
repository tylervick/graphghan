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

    @Test func anEmptyStoreIsEmptyRatherThanAnError() async throws {
        let (store, _) = try make()
        #expect(await store.manifests().isEmpty)
        #expect(await store.manifest(for: "nothing") == nil)
        #expect(await store.has(id: "nothing") == false)
    }
}

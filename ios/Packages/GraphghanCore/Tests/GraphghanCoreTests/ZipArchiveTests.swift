import Foundation
import Testing
@testable import GraphghanCore

@Suite struct ZipArchiveTests {
    // MARK: reading

    @Test func readsStoredEntriesInCentralDirectoryOrder() throws {
        let zip = try ZipArchive(ZipBuilder.stored([("a.txt", "alpha"), ("nested/b.txt", "beta")]))
        #expect(zip.names == ["a.txt", "nested/b.txt"])
        #expect(zip.contains("nested/b.txt"))
        #expect(!zip.contains("missing.txt"))
        #expect(try zip.data(named: "a.txt") == Data("alpha".utf8))
        #expect(try zip.data(named: "nested/b.txt") == Data("beta".utf8))
    }

    @Test func aDeflatedEntryReadsTheSameAsAStoredOne() throws {
        // The writer in this repo stores; a bundle from another tool may deflate, and the reader
        // is liberal about that (design spec §3.2).
        let text = String(repeating: "graphghan ", count: 400)
        let stored = try ZipArchive(ZipBuilder(items: [.init("x", text)]).build())
        let deflated = try ZipArchive(ZipBuilder(items: [.init("x", text, deflate: true)]).build())
        #expect(try stored.data(named: "x") == Data(text.utf8))
        #expect(try deflated.data(named: "x") == Data(text.utf8))
    }

    @Test func anEmptyEntryReads() throws {
        let zip = try ZipArchive(ZipBuilder.stored([("empty", "")]))
        #expect(try zip.data(named: "empty").isEmpty)
    }

    @Test func aTrailingCommentStillFindsTheDirectory() throws {
        var builder = ZipBuilder(items: [.init("a", "alpha")])
        builder.comment = Data(repeating: 0x2E, count: 300)
        let zip = try ZipArchive(builder.build())
        #expect(try zip.data(named: "a") == Data("alpha".utf8))
    }

    @Test func anUnknownNameIsNotFound() throws {
        let zip = try ZipArchive(ZipBuilder.stored([("a", "alpha")]))
        #expect(throws: ZipArchive.ZipError.notFound("b")) { try zip.data(named: "b") }
    }

    // MARK: refusals

    @Test func emptyAndGarbageAreNotZips() {
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive(Data()) }
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive(Data(repeating: 0x41, count: 4096)) }
    }

    @Test func aTruncatedArchiveIsRefused() {
        let whole = ZipBuilder.stored([("a", "alpha")])
        // Chopping the tail takes the EOCD with it; chopping the head leaves an offset past the end.
        #expect(throws: ZipArchive.ZipError.notAZip) { try ZipArchive(whole.prefix(whole.count - 8)) }
        #expect(throws: ZipArchive.ZipError.truncated("central directory")) { try ZipArchive(whole.suffix(30)) }
    }

    @Test func multipleDisksAreRefused() {
        var builder = ZipBuilder(items: [.init("a", "alpha")])
        builder.diskNumber = 1
        #expect(throws: ZipArchive.ZipError.multiDisk) { try ZipArchive(builder.build()) }
    }

    @Test func aZip64LocatorIsRefused() {
        var builder = ZipBuilder(items: [.init("a", "alpha")])
        builder.prefixEOCDWith = Data([0x50, 0x4B, 0x06, 0x07]) + Data(repeating: 0, count: 16)
        #expect(throws: ZipArchive.ZipError.zip64) { try ZipArchive(builder.build()) }
    }

    @Test func aZip64SentinelSizeIsRefused() {
        var item = ZipBuilder.Item("a", "alpha")
        item.uncompressedOverride = 0xFFFF_FFFF
        #expect(throws: ZipArchive.ZipError.zip64) { try ZipArchive(ZipBuilder(items: [item]).build()) }
    }

    @Test func anEncryptedEntryIsRefused() {
        var item = ZipBuilder.Item("a", "alpha")
        item.flags = 0x0001
        #expect(throws: ZipArchive.ZipError.encrypted("a")) { try ZipArchive(ZipBuilder(items: [item]).build()) }
    }

    @Test func aDataDescriptorEntryIsRefused() {
        var item = ZipBuilder.Item("a", "alpha")
        item.flags = 0x0008
        #expect(throws: ZipArchive.ZipError.dataDescriptor("a")) {
            try ZipArchive(ZipBuilder(items: [item]).build())
        }
    }

    @Test func anUnsupportedCompressionMethodIsRefused() {
        var item = ZipBuilder.Item("a", "alpha")
        item.methodOverride = 14  // LZMA
        #expect(throws: ZipArchive.ZipError.unsupportedMethod("a", 14)) {
            try ZipArchive(ZipBuilder(items: [item]).build())
        }
    }

    @Test(arguments: ["/etc/passwd", "../escape.json", "charts/../../escape.json", "a\\b"])
    func aNameThatCouldEscapeIsRefused(name: String) {
        #expect(throws: ZipArchive.ZipError.unsafeName(name)) {
            try ZipArchive(ZipBuilder(items: [.init(name, "x")]).build())
        }
    }

    @Test func anEmptyNameIsRefused() {
        #expect(throws: ZipArchive.ZipError.malformedName("")) {
            try ZipArchive(ZipBuilder(items: [.init("", "x")]).build())
        }
    }

    @Test func aDirectoryEntryWithBytesIsRefused() {
        #expect(throws: ZipArchive.ZipError.malformedName("charts/")) {
            try ZipArchive(ZipBuilder(items: [.init("charts/", "x")]).build())
        }
    }

    @Test func aNameThatIsNotUTF8IsRefused() {
        var bytes = ZipBuilder(items: [.init("a", "alpha")]).build()
        // The name is one byte in both headers; 0xFF is not valid UTF-8 anywhere.
        for i in bytes.indices where bytes[i] == UInt8(ascii: "a") { bytes[i] = 0xFF }
        #expect(throws: ZipArchive.ZipError.malformedName("<not utf-8>")) { try ZipArchive(bytes) }
    }

    @Test func tooManyEntriesIsRefused() {
        let items = (0..<(ZipArchive.Limits.entries + 1)).map { ZipBuilder.Item("f\($0)", "x") }
        #expect(throws: ZipArchive.ZipError.tooManyEntries(items.count)) {
            try ZipArchive(ZipBuilder(items: items).build())
        }
    }

    @Test func anEntryClaimingMoreThanTheCapIsRefused() {
        // A lying header: the declared size is checked before a byte is decompressed, which is
        // what stops a bomb that would otherwise be inflated to find out how big it is.
        var item = ZipBuilder.Item("a", "alpha")
        item.uncompressedOverride = UInt32(ZipArchive.Limits.entrySize) + 1
        #expect(throws: ZipArchive.ZipError.entryTooLarge("a", ZipArchive.Limits.entrySize + 1)) {
            try ZipArchive(ZipBuilder(items: [item]).build())
        }
    }

    @Test func entriesSummingPastTheArchiveCapAreRefused() {
        // Each entry is under the per-entry cap; together they are not.
        let per = UInt32(ZipArchive.Limits.entrySize)
        let items = (0..<3).map { i -> ZipBuilder.Item in
            var item = ZipBuilder.Item("f\(i)", "x")
            item.uncompressedOverride = per
            return item
        }
        #expect(throws: ZipArchive.ZipError.archiveTooLarge(UInt64(per) * 3)) {
            try ZipArchive(ZipBuilder(items: items).build())
        }
    }

    @Test func aWrongCRCIsRefused() throws {
        var item = ZipBuilder.Item("a", "alpha")
        item.crcOverride = 0xDEAD_BEEF
        let zip = try ZipArchive(ZipBuilder(items: [item]).build())
        #expect(throws: ZipArchive.ZipError.corrupt("a")) { try zip.data(named: "a") }
    }

    @Test func aLocalHeaderOffsetPointingAtNothingIsRefused() throws {
        var item = ZipBuilder.Item("a", "alpha")
        item.localOffsetOverride = 3
        let zip = try ZipArchive(ZipBuilder(items: [item]).build())
        #expect(throws: ZipArchive.ZipError.corrupt("a")) { try zip.data(named: "a") }
    }

    @Test func aDeclaredSizeTheDeflateStreamCannotFillIsRefused() throws {
        // The stream really holds five bytes; the header says fifty. `compression_decode_buffer`
        // reports what it wrote, and the mismatch is the refusal.
        var item = ZipBuilder.Item("a", "alpha", deflate: true)
        item.uncompressedOverride = 50
        let zip = try ZipArchive(ZipBuilder(items: [item]).build())
        #expect(throws: ZipArchive.ZipError.corrupt("a")) { try zip.data(named: "a") }
    }

    // MARK: CRC-32

    @Test func crc32MatchesTheKnownVector() {
        #expect(CRC32.compute(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.compute(Data()) == 0)
    }
}

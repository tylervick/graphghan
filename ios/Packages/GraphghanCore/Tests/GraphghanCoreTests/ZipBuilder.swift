import Compression
import Foundation
@testable import GraphghanCore

/// Builds zip archives byte by byte, including ones no correct writer would produce, so every
/// refusal in `ZipArchive` has an archive that provokes it. Test-only.
struct ZipBuilder {
    struct Item {
        var name: String
        var bytes: Data
        var deflate = false
        /// Written into both headers in place of the real method.
        var methodOverride: UInt16?
        /// OR-ed into the general-purpose flags of both headers.
        var flags: UInt16 = 0
        /// Written into the central directory in place of the real CRC.
        var crcOverride: UInt32?
        /// Written into the central directory in place of the real uncompressed size.
        var uncompressedOverride: UInt32?
        /// Written into the central directory in place of the real local-header offset.
        var localOffsetOverride: UInt32?

        init(_ name: String, _ bytes: Data, deflate: Bool = false) {
            self.name = name
            self.bytes = bytes
            self.deflate = deflate
        }

        init(_ name: String, _ text: String, deflate: Bool = false) {
            self.init(name, Data(text.utf8), deflate: deflate)
        }
    }

    var items: [Item] = []
    /// Written into the EOCD in place of the real entry count.
    var entryCountOverride: UInt16?
    var diskNumber: UInt16 = 0
    /// Appended after the EOCD, e.g. a zip64 locator.
    var prefixEOCDWith: Data?
    var comment = Data()

    func build() -> Data {
        var out = Data()
        var central = Data()
        for item in items {
            let payload = item.deflate ? ZipBuilder.deflate(item.bytes) : item.bytes
            let method = item.methodOverride ?? (item.deflate ? 8 : 0)
            let crc = item.crcOverride ?? CRC32.compute(item.bytes)
            let uncompressed = item.uncompressedOverride ?? UInt32(item.bytes.count)
            let offset = item.localOffsetOverride ?? UInt32(out.count)
            let name = Data(item.name.utf8)

            out += le32(0x0403_4b50)
            out += le16(20) + le16(item.flags) + le16(method)
            out += le16(0) + le16(0x0021)  // 1980-01-01
            out += le32(crc) + le32(UInt32(payload.count)) + le32(uncompressed)
            out += le16(UInt16(name.count)) + le16(0)
            out += name
            out += payload

            central += le32(0x0201_4b50)
            central += le16(20) + le16(20) + le16(item.flags) + le16(method)
            central += le16(0) + le16(0x0021)
            central += le32(crc) + le32(UInt32(payload.count)) + le32(uncompressed)
            central += le16(UInt16(name.count)) + le16(0) + le16(0)
            central += le16(0) + le16(0) + le32(0o644 << 16) + le32(offset)
            central += name
        }
        let directoryOffset = UInt32(out.count)
        out += central
        if let prefix = prefixEOCDWith { out += prefix }
        let count = entryCountOverride ?? UInt16(items.count)
        out += le32(0x0605_4b50)
        out += le16(diskNumber) + le16(diskNumber) + le16(count) + le16(count)
        out += le32(UInt32(central.count)) + le32(directoryOffset)
        out += le16(UInt16(comment.count)) + comment
        return out
    }

    static func stored(_ pairs: [(String, String)]) -> Data {
        ZipBuilder(items: pairs.map { Item($0.0, $0.1) }).build()
    }

    static func deflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        // Deflate can expand incompressible input; give the buffer room and refuse to guess if it
        // still does not fit, which for the test's inputs it never does.
        var out = Data(count: data.count * 2 + 64)
        let written = out.withUnsafeMutableBytes { destination -> Int in
            let dst = destination.bindMemory(to: UInt8.self).baseAddress!
            return data.withUnsafeBytes { source -> Int in
                let src = source.bindMemory(to: UInt8.self).baseAddress!
                return compression_encode_buffer(dst, destination.count, src, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        precondition(written > 0, "deflate failed for \(data.count) bytes")
        return out.prefix(written)
    }

    private func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
    private func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)])
    }
}

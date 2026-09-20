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

    /// Written as appends rather than one chain of `+`: a long chain of `Data + Data` is a
    /// type-checker timeout waiting to happen, and the app tests' equivalent hit one on CI.
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

            // The fields a local and a central header share, in the same order in both.
            var common = Data()
            ZipBuilder.append16(&common, 20)      // version needed
            ZipBuilder.append16(&common, item.flags)
            ZipBuilder.append16(&common, method)
            ZipBuilder.append16(&common, 0)       // time
            ZipBuilder.append16(&common, 0x0021)  // date: 1980-01-01
            ZipBuilder.append32(&common, crc)
            ZipBuilder.append32(&common, UInt32(payload.count))
            ZipBuilder.append32(&common, uncompressed)
            ZipBuilder.append16(&common, UInt16(name.count))
            ZipBuilder.append16(&common, 0)       // extra length

            ZipBuilder.append32(&out, 0x0403_4b50)
            out.append(common)
            out.append(name)
            out.append(payload)

            ZipBuilder.append32(&central, 0x0201_4b50)
            ZipBuilder.append16(&central, 20)     // version made by
            central.append(common)
            ZipBuilder.append16(&central, 0)      // comment length
            ZipBuilder.append16(&central, 0)      // disk start
            ZipBuilder.append16(&central, 0)      // internal attributes
            ZipBuilder.append32(&central, 0o644 << 16)
            ZipBuilder.append32(&central, offset)
            central.append(name)
        }
        let directoryOffset = UInt32(out.count)
        out.append(central)
        if let prefix = prefixEOCDWith { out.append(prefix) }
        let count = entryCountOverride ?? UInt16(items.count)
        ZipBuilder.append32(&out, 0x0605_4b50)
        ZipBuilder.append16(&out, diskNumber)
        ZipBuilder.append16(&out, diskNumber)
        ZipBuilder.append16(&out, count)
        ZipBuilder.append16(&out, count)
        ZipBuilder.append32(&out, UInt32(central.count))
        ZipBuilder.append32(&out, directoryOffset)
        ZipBuilder.append16(&out, UInt16(comment.count))
        out.append(comment)
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

    static func append16(_ data: inout Data, _ v: UInt16) {
        data.append(UInt8(v & 0xFF))
        data.append(UInt8(v >> 8 & 0xFF))
    }

    static func append32(_ data: inout Data, _ v: UInt32) {
        append16(&data, UInt16(v & 0xFFFF))
        append16(&data, UInt16(v >> 16 & 0xFFFF))
    }
}

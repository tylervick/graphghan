import CoreGraphics
import SwiftUI
import Testing
import UIKit

/// Minimal snapshot testing: render with ImageRenderer at 2x, compare to a PNG under
/// Tests/__Snapshots__. Three modes (compare/render/record) via GRAPHGHAN_SNAPSHOTS -- see `Mode`.
/// A missing reference in compare mode is recorded and the test fails once, so the file gets
/// committed and reviewed. Rendering is deterministic on one simulator model and OS. `render` mode
/// has no default output directory -- GRAPHGHAN_SNAPSHOT_OUT must be set, or it throws, so an
/// accidental `GRAPHGHAN_SNAPSHOTS=render` run can never silently overwrite committed references.
@MainActor
enum Snapshots {
    enum Mode: String { case compare, render, record }

    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        return url.appendingPathComponent("__Snapshots__", isDirectory: true)
    }()

    /// GRAPHGHAN_SNAPSHOTS selects the mode; GRAPHGHAN_SNAPSHOT_OUT the directory renders go to in `render` mode.
    /// xcodebuild forwards TEST_RUNNER_-prefixed variables into the test host, which is how CI sets them.
    static func mode(_ environment: [String: String]) -> Mode {
        Mode(rawValue: environment["GRAPHGHAN_SNAPSHOTS"] ?? "") ?? .compare
    }

    /// `render` mode has no safe default: falling back to `directory` (`__Snapshots__`) would let an
    /// accidental `GRAPHGHAN_SNAPSHOTS=render` run overwrite committed references. So the output
    /// directory must be named explicitly via GRAPHGHAN_SNAPSHOT_OUT; an unset or empty value throws.
    static func outputDirectory(_ environment: [String: String]) throws -> URL {
        guard let path = environment["GRAPHGHAN_SNAPSHOT_OUT"], !path.isEmpty else { throw SnapshotError.missingOutputDirectory }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Returns true when the rendering matches the reference (compare), was written (record), or rendered at the
    /// reference size (render). Records and returns false when a reference is missing in compare mode.
    static func assert(_ view: some View, named name: String, size: CGSize, tolerance: Double = 0.005,
                       environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Bool {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.uiImage, let png = image.pngData() else { throw SnapshotError.renderFailed(name) }
        let reference = directory.appendingPathComponent("\(name).png")
        let mode = mode(environment)

        switch mode {
        case .record:
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: reference)
            return true
        case .render:
            let out = try outputDirectory(environment)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try png.write(to: out.appendingPathComponent("\(name).png"))
            guard FileManager.default.fileExists(atPath: reference.path),
                  let expected = UIImage(data: try Data(contentsOf: reference))?.cgImage, let actual = image.cgImage else { return true }
            guard expected.width == actual.width, expected.height == actual.height else {
                Issue.record("\(name): size \(actual.width)x\(actual.height) != \(expected.width)x\(expected.height)")
                return false
            }
            return true
        case .compare:
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: reference.path) else {
                try png.write(to: reference)
                Issue.record("Recorded new snapshot \(name).png; re-run to compare.")
                return false
            }
            guard let expected = UIImage(data: try Data(contentsOf: reference))?.cgImage, let actual = image.cgImage else { throw SnapshotError.renderFailed(name) }
            guard expected.width == actual.width, expected.height == actual.height else {
                try png.write(to: directory.appendingPathComponent("\(name).actual.png"))
                Issue.record("\(name): size \(actual.width)x\(actual.height) != \(expected.width)x\(expected.height)")
                return false
            }
            let diff = differingFraction(expected, actual)
            if diff > tolerance {
                try png.write(to: directory.appendingPathComponent("\(name).actual.png"))
                Issue.record("\(name): \(Int(diff * 1000)) per mille of pixels differ (see \(name).actual.png)")
                return false
            }
            return true
        }
    }

    private static func pixels(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private static func differingFraction(_ a: CGImage, _ b: CGImage) -> Double {
        guard let pa = pixels(a), let pb = pixels(b), pa.count == pb.count else { return 1 }
        var differing = 0
        let count = pa.count / 4
        for i in 0..<count {
            let o = i * 4
            if abs(Int(pa[o]) - Int(pb[o])) > 8 || abs(Int(pa[o + 1]) - Int(pb[o + 1])) > 8 || abs(Int(pa[o + 2]) - Int(pb[o + 2])) > 8 { differing += 1 }
        }
        return Double(differing) / Double(max(1, count))
    }

    enum SnapshotError: Error { case renderFailed(String), missingOutputDirectory }
}

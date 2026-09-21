import Foundation

/// One grid found on an image (`rasterchart.Region`). `xs`/`ys` are the fitted line positions in
/// pixels; `noise` is the mean colour spread inside the sampled cell centres.
public struct Region: Sendable, Equatable {
    public let xs: [Double]
    public let ys: [Double]
    public var noise: Double
    public var warnings: [String]

    public init(xs: [Double], ys: [Double], noise: Double = 0, warnings: [String] = []) {
        self.xs = xs
        self.ys = ys
        self.noise = noise
        self.warnings = warnings
    }

    public var cols: Int { xs.count - 1 }
    public var rows: Int { ys.count - 1 }
    public var cells: Int { cols * rows }
    public var bbox: (Int, Int, Int, Int) { (Int(xs[0]), Int(ys[0]), Int(xs[xs.count - 1]), Int(ys[ys.count - 1])) }
    public var pitch: (Double, Double) { ((xs[xs.count - 1] - xs[0]) / Double(cols), (ys[ys.count - 1] - ys[0]) / Double(rows)) }

    public func describe() -> String {
        let b = bbox
        let p = pitch
        return "\(cols)x\(rows) cells at (\(b.0), \(b.1))-(\(b.2), \(b.3)), pitch \(String(format: "%.1f", p.0))x\(String(format: "%.1f", p.1)) px, noise \(String(format: "%.1f", noise))"
    }
}

public enum GridReaderError: Error, Equatable {
    case tooLarge(width: Int, height: Int)
}

/// The grid reader (`rasterchart.py` `find_regions` and its helpers): lines by their edges over
/// long straight runs, a lattice fitted from the pitch, cells sampled at their centres.
public enum GridReader {
    public static let edgeThreshold = 16   // EDGE_THRESHOLD
    public static let minLinePx = 40       // MIN_LINE_PX
    public static let minLines = 5         // MIN_LINES
    public static let centreFraction = 0.4 // CENTRE_FRACTION
    public static let maxNoise = 12.0      // MAX_NOISE
    public static let maxSilent = 40       // MAX_SILENT
    public static let maxPixels = 40_000_000 // MAX_PIXELS

    static func pyRound(_ x: Double) -> Int { Int(x.rounded(.toNearestOrEven)) }

    // MARK: edges

    /// Vertical edges: (h, w-1), True where a channel steps by more than the threshold between
    /// x and x+1 (`ex`); horizontal edges transposed: (w, h-1) (`ey.T`), so both masks run down
    /// axis 0 along the line and index the candidate position on axis 1.
    static func edges(_ img: GridImage) -> (ex: Mask, eyT: Mask) {
        let w = img.width, h = img.height, t = edgeThreshold
        var ex = Mask(rows: h, cols: w - 1)
        var eyT = Mask(rows: w, cols: h - 1)
        img.rgb.withUnsafeBufferPointer { p in
            ex.bits.withUnsafeMutableBufferPointer { exb in
                for y in 0..<h {
                    let row = y * w * 3
                    for x in 0..<(w - 1) {
                        let i = row + x * 3
                        let d = max(abs(Int(p[i]) - Int(p[i + 3])), abs(Int(p[i + 1]) - Int(p[i + 4])), abs(Int(p[i + 2]) - Int(p[i + 5])))
                        if d > t { exb[y * (w - 1) + x] = true }
                    }
                }
            }
            eyT.bits.withUnsafeMutableBufferPointer { eyb in
                for y in 0..<(h - 1) {
                    let row = y * w * 3, next = (y + 1) * w * 3
                    for x in 0..<w {
                        let i = row + x * 3, j = next + x * 3
                        let d = max(abs(Int(p[i]) - Int(p[j])), abs(Int(p[i + 1]) - Int(p[j + 1])), abs(Int(p[i + 2]) - Int(p[j + 2])))
                        if d > t { eyb[x * (h - 1) + y] = true }
                    }
                }
            }
        }
        return (ex, eyT)
    }

    /// Rows `range` of a mask, every column (`edges[a:b, :]`).
    static func rows(_ m: Mask, _ range: Range<Int>) -> Mask {
        let lo = max(0, range.lowerBound), hi = min(m.rows, range.upperBound)
        return Mask(rows: max(0, hi - lo), cols: m.cols, bits: Array(m.bits[(lo * m.cols)..<(hi * m.cols)]))
    }

    /// True where any pixel within r columns is True (`_window_max`, along axis 1).
    static func windowMax(_ m: Mask, _ r: Int) -> Mask {
        var out = m
        let rows = m.rows, cols = m.cols
        m.bits.withUnsafeBufferPointer { src in
            out.bits.withUnsafeMutableBufferPointer { dst in
                for y in 0..<rows {
                    let row = y * cols
                    for x in 0..<cols where !src[row + x] {
                        for s in 1...r where (x - s >= 0 && src[row + x - s]) || (x + s < cols && src[row + x + s]) { dst[row + x] = true; break }
                    }
                }
            }
        }
        return out
    }

    // MARK: lattice fitting

    /// Fit the line positions along axis 1 of `edges` (`_refine_axis`): snap each seed to the
    /// nearest edge-density peak, keep the lattice most seeds agree on, walk outward one pitch at a
    /// time while a thin line is there and the cells it adds are flat colour, then lay every
    /// interior line on the fitted pitch. `bandNoise(a, b)` is the (mean, median) colour spread of
    /// the strip a..b on this axis.
    static func refineAxis(_ edges: Mask, seeds: [Double], pitch: Double, bandNoise: (Double, Double) -> (Double, Double)) -> [Double]? {
        let span = edges.rows, n = edges.cols
        guard span > 0, n > 0 else { return nil }
        let wide = windowMax(edges, 2)
        var density = [Double](repeating: 0, count: n)
        var raw = [Double](repeating: 0, count: n)
        wide.bits.withUnsafeBufferPointer { wb in
            edges.bits.withUnsafeBufferPointer { eb in
                for y in 0..<span { for x in 0..<n {
                    if wb[y * n + x] { density[x] += 1 }
                    if eb[y * n + x] { raw[x] += 1 }
                } }
            }
        }
        for x in 0..<n { density[x] /= Double(span); raw[x] /= Double(span) }
        let longest = GridLines.longestRuns(wide, bridge: max(1, min(GridLines.bridge, Int(pitch / 12))))
        let rSeed = max(2, Int(pitch / 4))
        let rNext = max(2, Int(pitch / 8))

        /// The centre of the densest plateau within r of `at`.
        func peak(_ at: Double, _ r: Int) -> Int? {
            let lo = Int(max(0, at - Double(r))), hi = Int(min(Double(n), at + Double(r) + 1))
            guard hi > lo else { return nil }
            let top = density[lo..<hi].max()!
            let plateau = (lo..<hi).filter { density[$0] >= top - 1e-9 }
            let mean = Double(plateau.reduce(0, +)) / Double(plateau.count)
            return pyRound(mean)
        }

        /// A grid line is a narrow density peak; text is dense for a whole glyph height.
        func thin(_ x: Int) -> Bool {
            var lo = max(0, x - 2), hi = min(n, x + 3)
            var top = lo
            for i in lo..<hi where raw[i] > raw[top] { top = i }
            let half = 0.5 * raw[top]
            guard half > 0 else { return false }
            lo = top
            while lo > 0, raw[lo - 1] >= half { lo -= 1 }
            hi = top
            while hi < n - 1, raw[hi + 1] >= half { hi += 1 }
            return Double(hi - lo + 1) <= max(6, 0.3 * pitch)
        }

        var found = Set<Int>()
        for s in seeds { if let p = peak(s, rSeed), thin(p) { found.insert(p) } }
        let sortedFound = found.sorted()
        guard sortedFound.count >= 2 else { return nil }

        func onLattice(_ x: Int, _ anchor: Int) -> Bool {
            let k = Double(x - anchor) / pitch
            return abs(k - k.rounded(.toNearestOrEven)) <= 0.25
        }
        var anchor = sortedFound[0], anchorCount = -1
        for a in sortedFound {
            let c = sortedFound.filter { onLattice($0, a) }.count
            if c > anchorCount { anchor = a; anchorCount = c }
        }
        let base = GridLines.median(sortedFound.filter { onLattice($0, anchor) }.map { density[$0] })
        guard base > 0 else { return nil }

        func present(_ x: Int) -> Bool {
            density[x] >= 0.3 * base && Double(longest[x]) >= 1.5 * pitch && thin(x)
        }

        /// From the anchor outward, one lattice step at a time (position, lattice index) pairs.
        func walk(_ direction: Int) -> [(Int, Int)] {
            var committed = [(anchor, 0)]
            var pending: [(Int, Int)] = []
            var last = Double(anchor)
            var k = 0
            var step = pitch
            while true {
                k += direction
                let expected = last + Double(direction) * step
                guard let p = peak(expected, rNext), p > 0, p < n - 1 else { break }
                if present(p) {
                    committed += pending + [(p, k)]
                    pending = []
                    last = Double(p)
                    let (x0, k0) = committed[0], (x1, k1) = committed[committed.count - 1]
                    if abs(k1 - k0) >= 3 { step = abs(Double(x1 - x0) / Double(k1 - k0)) }
                } else {
                    let (lo, hi) = direction > 0 ? (last, Double(p)) : (Double(p), last)
                    if bandNoise(lo, hi).0 > maxNoise { break }
                    pending.append((pyRound(expected), k))
                    last = expected
                    if pending.count > maxSilent { break }
                }
            }
            return committed
        }

        var pairSet = Set<[Int]>()
        for (x, k) in walk(-1) + walk(1) { pairSet.insert([x, k]) }
        let pairs = pairSet.sorted { $0[0] != $1[0] ? $0[0] < $1[0] : $0[1] < $1[1] }
        let xs = pairs.map { Double($0[0]) }
        let ks = pairs.map { Double($0[1] - pairs[0][1]) }
        guard Set(ks).count >= 2 else { return nil }
        // np.polyfit(ks, xs, 1): least squares slope and intercept.
        let m = Double(ks.count)
        let sk = ks.reduce(0, +), sx = xs.reduce(0, +)
        let skk = ks.reduce(0) { $0 + $1 * $1 }, skx = zip(ks, xs).reduce(0) { $0 + $1.0 * $1.1 }
        let slope = (m * skx - sk * sx) / (m * skk - sk * sk)
        let intercept = (sx - slope * sk) / m
        let count = Int(ks[ks.count - 1])
        guard count >= minLines - 1 else { return nil }
        return (0...count).map { intercept + slope * Double($0) }
    }

    /// Grey spread of the cell centres in a one-cell-thick strip, as (mean, median) over the
    /// cells (`_band_noise`). `band(t, i)` reads the strip: `t` across its thickness (0..<thickness),
    /// `i` along its length (0..<length); cells lie along the length at `pitch`.
    static func bandNoise(thickness: Int, length: Int, pitch: Double, band: (Int, Int) -> Float) -> (Double, Double) {
        let c0 = Int(Double(thickness) * (0.5 - centreFraction / 2))
        let c1 = max(Int(Double(thickness) * (0.5 + centreFraction / 2)), Int(Double(thickness) * 0.5) + 1)
        let n = max(1, Int(Double(length) / pitch))
        var spreads: [Double] = []
        for k in 0..<n {
            let a = Int(Double(k) * pitch + pitch * (0.5 - centreFraction / 2))
            let b = max(a + 1, Int(Double(k) * pitch + pitch * (0.5 + centreFraction / 2)))
            var values: [Double] = []
            for t in c0..<min(c1, thickness) { for i in a..<min(b, length) { values.append(Double(band(t, i))) } }
            spreads.append(std(values))
        }
        guard !spreads.isEmpty else { return (0, 0) }
        return (spreads.reduce(0, +) / Double(spreads.count), GridLines.median(spreads))
    }

    /// numpy's std: population standard deviation; 0 for nothing.
    static func std(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let mean = v.reduce(0, +) / Double(v.count)
        return (v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(v.count)).squareRoot()
    }

    static func overlap(_ a: Region, _ b: Region) -> Double {
        let (ax0, ay0, ax1, ay1) = a.bbox, (bx0, by0, bx1, by1) = b.bbox
        let w = max(0, min(ax1, bx1) - max(ax0, bx0)), h = max(0, min(ay1, by1) - max(ay0, by0))
        return Double(w * h) / Double(max(1, min((ax1 - ax0) * (ay1 - ay0), (bx1 - bx0) * (by1 - by0))))
    }

    // MARK: regions

    /// Every grid on the image, largest first (`find_regions`).
    public static func findRegions(_ img: GridImage) throws -> [Region] {
        guard img.width * img.height <= maxPixels else { throw GridReaderError.tooLarge(width: img.width, height: img.height) }
        guard img.width >= 2, img.height >= 2 else { return [] }
        let grey = img.grey()
        let w = img.width, h = img.height
        let (ex, eyT) = edges(img)
        let minPx = max(minLinePx, min(h, w) / 40)
        let colLines = GridLines.lines(ex, minPx: minPx)    // centre x, y-segments
        let rowLines = GridLines.lines(eyT, minPx: minPx)   // centre y, x-segments
        var regions: [Region] = []
        for cols in GridLines.clusters(colLines) {
            guard cols.count >= 3 else { continue }
            let x0 = cols[0].centre, x1 = cols[cols.count - 1].centre
            let rowsHere = rowLines.filter { GridLines.fits($0, lo: x0, hi: x1) }
            guard rowsHere.count >= 3 else { continue }
            let y0 = rowsHere[0].centre, y1 = rowsHere[rowsHere.count - 1].centre
            let colsHere = cols.filter { GridLines.fits($0, lo: y0, hi: y1) }
            guard let px = GridLines.pitch(colsHere.map(\.centre)), let py = GridLines.pitch(rowsHere.map(\.centre)) else { continue }
            // gray[y0:y1, a:b].T: thickness b-a across x, length y1-y0 down y.
            func colNoise(_ a: Double, _ b: Double, _ ya: Double, _ yb: Double) -> (Double, Double) {
                let (ia, ib, iy0, iy1) = (Int(a), Int(b), Int(ya), Int(yb))
                return bandNoise(thickness: max(0, ib - ia), length: max(0, iy1 - iy0), pitch: py) { t, i in grey[(iy0 + i) * w + ia + t] }
            }
            guard var xs = refineAxis(rows(ex, Int(y0)..<(Int(y1) + 1)), seeds: colsHere.map(\.centre), pitch: px, bandNoise: { colNoise($0, $1, y0, y1) }) else { continue }
            // gray[a:b, xs0:xs-1]: thickness b-a down y, length along x.
            let xsLo = Int(xs[0]), xsHi = Int(xs[xs.count - 1])
            func rowNoise(_ a: Double, _ b: Double) -> (Double, Double) {
                let (ia, ib) = (Int(a), Int(b))
                return bandNoise(thickness: max(0, ib - ia), length: max(0, xsHi - xsLo), pitch: px) { t, i in grey[(ia + t) * w + xsLo + i] }
            }
            guard let ys = refineAxis(rows(eyT, xsLo..<(xsHi + 1)), seeds: rowsHere.map(\.centre), pitch: py, bandNoise: rowNoise) else { continue }
            let ys0 = ys[0], ys1 = ys[ys.count - 1]
            if let again = refineAxis(rows(ex, Int(ys0)..<(Int(ys1) + 1)), seeds: xs, pitch: px, bandNoise: { colNoise($0, $1, ys0, ys1) }) { xs = again }
            var region = Region(xs: xs, ys: ys)
            region.noise = cellNoise(img, region, grey: grey)
            if region.noise > maxNoise { continue }  // a photo or a textured fabric, not a chart
            if regions.contains(where: { overlap(region, $0) > 0.5 && $0.cells >= region.cells }) { continue }
            regions = regions.filter { overlap(region, $0) <= 0.5 }
            regions.append(region)
        }
        return regions.sorted { $0.cells > $1.cells }
    }

    // MARK: sampling

    /// The pixel rectangle at the centre of each cell: (row j, col i, y0..<y1, x0..<x1) (`_patches`).
    static func patches(_ region: Region) -> [(j: Int, i: Int, y0: Int, y1: Int, x0: Int, x1: Int)] {
        var out: [(Int, Int, Int, Int, Int, Int)] = []
        let f0 = 0.5 - centreFraction / 2, f1 = 0.5 + centreFraction / 2
        for j in 0..<region.rows {
            let cy0 = region.ys[j], cy1 = region.ys[j + 1]
            let my0 = pyRound(cy0 + (cy1 - cy0) * f0)
            let my1 = max(my0 + 1, pyRound(cy0 + (cy1 - cy0) * f1))
            for i in 0..<region.cols {
                let cx0 = region.xs[i], cx1 = region.xs[i + 1]
                let mx0 = pyRound(cx0 + (cx1 - cx0) * f0)
                let mx1 = max(mx0 + 1, pyRound(cx0 + (cx1 - cx0) * f1))
                out.append((j, i, my0, my1, mx0, mx1))
            }
        }
        return out
    }

    /// Median RGB of the centre of every cell, rows × cols (`read_region`; a median of an even
    /// count is the mean of the two middles, then truncated to a byte as numpy's uint8 cast does).
    public static func readRegion(_ img: GridImage, _ region: Region) -> [[(UInt8, UInt8, UInt8)]] {
        var out = [[(UInt8, UInt8, UInt8)]](repeating: [(UInt8, UInt8, UInt8)](repeating: (0, 0, 0), count: region.cols), count: region.rows)
        for p in patches(region) {
            var r: [Double] = [], g: [Double] = [], b: [Double] = []
            for y in max(0, p.y0)..<min(img.height, p.y1) { for x in max(0, p.x0)..<min(img.width, p.x1) {
                let i = (y * img.width + x) * 3
                r.append(Double(img.rgb[i])); g.append(Double(img.rgb[i + 1])); b.append(Double(img.rgb[i + 2]))
            } }
            guard !r.isEmpty else { continue }
            out[p.j][p.i] = (UInt8(Int(GridLines.median(r))), UInt8(Int(GridLines.median(g))), UInt8(Int(GridLines.median(b))))
        }
        return out
    }

    /// Mean median-absolute-deviation of grey inside the cell centres, over up to 400 cells
    /// (`cell_noise`): a symbol's strokes over a flat cell are ignored, a photo deviates everywhere.
    public static func cellNoise(_ img: GridImage, _ region: Region) -> Double {
        cellNoise(img, region, grey: img.grey())
    }

    static func cellNoise(_ img: GridImage, _ region: Region, grey: [Float], sample: Int = 400) -> Double {
        let all = patches(region)
        let step = max(1, all.count / sample)
        var spreads: [Double] = []
        var k = 0
        while k < all.count {
            let p = all[k]
            var values: [Double] = []
            for y in max(0, p.y0)..<min(img.height, p.y1) { for x in max(0, p.x0)..<min(img.width, p.x1) { values.append(Double(grey[y * img.width + x])) } }
            if !values.isEmpty {
                let m = GridLines.median(values)
                spreads.append(GridLines.median(values.map { abs($0 - m) }))
            }
            k += step
        }
        return spreads.isEmpty ? 0 : spreads.reduce(0, +) / Double(spreads.count)
    }
}

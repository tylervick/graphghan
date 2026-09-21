import Foundation

public enum GridColoursError: Error, Equatable {
    /// A cell farther than the allowed distance from every palette colour (`snap_to_palette`);
    /// column and row are 1-based from the top-left, distance rounded.
    case foreignColour(column: Int, row: Int, hex: String, nearest: String, distance: Int)
    /// A palette hex that is not `#rrggbb`, or no palette at all: nothing to snap to.
    case badPalette(String)
}

/// The colour half of `rasterchart.py`: Lab distances, snapping, greedy clustering, names.
public enum GridColours {
    typealias RGB = (UInt8, UInt8, UInt8)
    typealias Lab = (Double, Double, Double)

    static let colourNames: [(String, (Double, Double, Double))] = [
        ("white", (255, 255, 255)), ("cream", (245, 235, 210)), ("black", (0, 0, 0)), ("charcoal", (50, 50, 55)),
        ("grey", (140, 140, 140)), ("silver", (200, 200, 200)), ("red", (200, 30, 30)), ("orange", (240, 130, 30)),
        ("yellow", (240, 210, 40)), ("gold", (215, 165, 30)), ("green", (40, 140, 60)), ("dark green", (25, 80, 50)),
        ("teal", (30, 140, 140)), ("blue", (40, 90, 200)), ("navy", (25, 40, 90)), ("purple", (110, 50, 140)),
        ("pink", (240, 170, 200)), ("brown", (120, 80, 50)), ("tan", (200, 170, 130)), ("sage", (120, 160, 140)),
        ("olive", (110, 120, 50)), ("mint", (170, 230, 200)), ("aqua", (160, 220, 225)), ("sky", (140, 190, 240)),
        ("lavender", (190, 170, 220)), ("maroon", (110, 30, 40)), ("beige", (225, 210, 180)),
    ]

    /// sRGB 0..255 to CIE Lab, D65 (`_to_lab`).
    static func lab(_ rgb: (Double, Double, Double)) -> Lab {
        func lin(_ v: Double) -> Double { let c = v / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin(rgb.0), g = lin(rgb.1), b = lin(rgb.2)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 1.0
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    static func lab(_ c: RGB) -> Lab { lab((Double(c.0), Double(c.1), Double(c.2))) }

    static func distance(_ a: Lab, _ b: Lab) -> Double {
        ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
    }

    public static func hex(_ c: (UInt8, UInt8, UInt8)) -> String { String(format: "#%02x%02x%02x", c.0, c.1, c.2) }

    public static func rgb(_ hex: String) -> (UInt8, UInt8, UInt8)? {
        guard hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff))
    }

    /// Nearest palette entry per cell in Lab; a cell farther than `maxDelta` is refused by name.
    public static func snapToPalette(_ samples: [[(UInt8, UInt8, UInt8)]], hexes: [String], maxDelta: Double = 25) throws -> [[UInt8]] {
        guard !hexes.isEmpty else { throw GridColoursError.badPalette("no palette colours") }
        var pal: [Lab] = []
        for h in hexes {
            guard let c = rgb(h) else { throw GridColoursError.badPalette("\(h) is not #rrggbb") }
            pal.append(lab(c))
        }
        var out: [[UInt8]] = []
        var worst = (d: -1.0, x: 0, y: 0, hex: "", nearest: 0)
        for (y, row) in samples.enumerated() {
            var idx: [UInt8] = []
            for (x, c) in row.enumerated() {
                let l = lab(c)
                var best = 0, bestD = Double.infinity
                for (k, p) in pal.enumerated() { let d = distance(l, p); if d < bestD { bestD = d; best = k } }
                idx.append(UInt8(best))
                if bestD > worst.d { worst = (bestD, x, y, hex(c), best) }
            }
            out.append(idx)
        }
        if worst.d > maxDelta {
            throw GridColoursError.foreignColour(column: worst.x + 1, row: worst.y + 1, hex: worst.hex, nearest: hexes[worst.nearest], distance: Int(worst.d.rounded()))
        }
        return out
    }

    /// Greedy clustering in Lab by frequency (`cluster_palette`): codes by cell count, a tiny
    /// cluster near a big one folded in with a warning, a colour on almost no cells warned about.
    public static func clusterPalette(_ samples: [[(UInt8, UInt8, UInt8)]], radius: Double = 6) -> (cells: [[UInt8]], hexes: [String], warnings: [String]) {
        // np.unique(flat, axis=0): distinct colours in lexicographic order, with counts.
        var counts: [UInt32: Int] = [:]
        for row in samples { for c in row { counts[UInt32(c.0) << 16 | UInt32(c.1) << 8 | UInt32(c.2), default: 0] += 1 } }
        let colours = counts.keys.sorted()
        let count = colours.map { counts[$0]! }
        func rgbOf(_ k: UInt32) -> RGB { (UInt8((k >> 16) & 0xff), UInt8((k >> 8) & 0xff), UInt8(k & 0xff)) }
        let labs = colours.map { lab(rgbOf($0)) }
        // np.argsort(-counts): by count descending, ties in index order (a stable sort).
        let order = colours.indices.sorted { count[$0] != count[$1] ? count[$0] > count[$1] : $0 < $1 }
        var centres: [Lab] = []
        var members: [[Int]] = []
        var assign = [Int](repeating: 0, count: colours.count)
        for k in order {
            if !centres.isEmpty {
                var j = 0, best = Double.infinity
                for (i, c) in centres.enumerated() { let d = distance(c, labs[k]); if d < best { best = d; j = i } }
                if best <= radius { assign[k] = j; members[j].append(k); continue }
            }
            centres.append(labs[k])
            members.append([k])
            assign[k] = centres.count - 1
        }
        var warnings: [String] = []
        var totals = members.map { $0.reduce(0) { $0 + count[$1] } }
        let totalCells = samples.reduce(0) { $0 + $1.count }
        let threshold = 0.005 * Double(totalCells)
        for j in members.indices.sorted(by: { totals[$0] < totals[$1] }) {
            if Double(totals[j]) >= threshold || members[j].isEmpty { continue }
            let others = members.indices.filter { $0 != j && !members[$0].isEmpty && Double(totals[$0]) >= threshold }
            // The nearest big cluster: `others` is non-empty here, so the minimum exists.
            guard let k = others.min(by: { distance(centres[$0], centres[j]) < distance(centres[$1], centres[j]) }) else { continue }
            if distance(centres[k], centres[j]) <= 2 * radius {
                guard let first = members[j].first, let rep = members[k].max(by: { count[$0] < count[$1] }) else { continue }
                warnings.append("\(totals[j]) cell(s) of \(hex(rgbOf(colours[first]))) folded into \(hex(rgbOf(colours[rep]))) (a watermark or symbol tinted them)")
                members[k] += members[j]
                totals[k] += totals[j]
                members[j] = []
                totals[j] = 0
            }
        }
        let keep = members.indices.filter { !members[$0].isEmpty }
        members = keep.map { members[$0] }
        totals = keep.map { totals[$0] }
        for (newJ, m) in members.enumerated() { for i in m { assign[i] = newJ } }
        // Each cluster's colour is its most frequent member (the first, on a tie); every cluster
        // kept above has at least one member.
        let reps = members.map { m in m.max { count[$0] != count[$1] ? count[$0] < count[$1] : $0 > $1 } ?? 0 }
        let rank = members.indices.sorted { totals[$0] != totals[$1] ? totals[$0] > totals[$1] : $0 < $1 }
        var remap = [Int](repeating: 0, count: members.count)
        for (new, old) in rank.enumerated() { remap[old] = new }
        var lookup: [UInt32: UInt8] = [:]
        for (k, c) in colours.enumerated() { lookup[c] = UInt8(remap[assign[k]]) }
        let cells = samples.map { row in
            row.map { c -> UInt8 in
                // `colours` holds every distinct sample, so every cell's colour is in the lookup.
                guard let i = lookup[UInt32(c.0) << 16 | UInt32(c.1) << 8 | UInt32(c.2)] else { preconditionFailure("a sampled colour is not among the distinct colours") }
                return i
            }
        }
        let hexes = rank.map { hex(rgbOf(colours[reps[$0]])) }
        for (new, old) in rank.enumerated() where Double(totals[old]) < max(2, 0.001 * Double(totalCells)) {
            warnings.append("colour \(hexes[new]) covers only \(totals[old]) cell(s); a grid line or symbol may have bled in")
        }
        return (cells, hexes, warnings)
    }

    /// The nearest named colour (`name_colour`); nil for a hex that is not `#rrggbb`.
    public static func nameColour(_ hexString: String) -> String? {
        guard let c = rgb(hexString) else { return nil }
        let l = lab(c)
        var best = colourNames[0]
        for candidate in colourNames.dropFirst() where distance(lab(candidate.1), l) < distance(lab(best.1), l) { best = candidate }
        return best.0
    }

    /// A, B, ..., Z, AA, AB, ...: 1-3 letters (`importers._code`).
    public static func code(_ i: Int) -> String {
        var letters = ""
        var n = i + 1
        while n > 0 {
            let r = (n - 1) % 26
            letters = String(UnicodeScalar(UInt8(65 + r))) + letters
            n = (n - 1) / 26
        }
        return letters
    }
}

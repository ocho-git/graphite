// Canvas2D.swift: drawing from 2D vector shapes instead of a 3D model, through the same pencil: filled regions give
// the tone the hatching reads (shade them as lit from the upper left), outlines and veins go through drawChains (the
// same smoothing, wobble, taper and weights as traced contours). Shapes painted later cover earlier ones: an outline is
// dropped wherever a later shape lies over it. Good for magnified details: a leaf's veins, a feather, a scale.
import CoreGraphics
import Foundation

public final class Canvas2D {
    public let w: Int, h: Int
    public var tone: [Float], id: [Int32], cover: [Float]
    public var lines: [(pts: [V2], wts: [Double], owner: Int32, closed: Bool)] = []
    public var dots: [(V2, Double, Double)] = []
    public var nextPart = 1
    /// The kind given to shapes that name none.
    public var defaultKind: Int
    /// Stipple density by region (default: none).
    public var stipple: (Int32) -> Double
    public let style: Style

    public init(_ w: Int, _ h: Int, defaultKind: Int = 0, style: Style = .standard, stipple: @escaping (Int32) -> Double = { _ in 0 }) {
        self.w = w; self.h = h; self.defaultKind = defaultKind; self.style = style; self.stipple = stipple
        tone = Array(repeating: 0, count: w * h); id = Array(repeating: 0, count: w * h); cover = Array(repeating: 0, count: w * h)
    }

    /// Paints a region; `shade` gives its tone at a point (0 paper … 1 dark). Returns its id.
    @discardableResult public func fill(_ poly: [V2], kind: Int? = nil, shade: (V2) -> Double) -> Int32 {
        let me = SurfaceID.make(nextPart, kind ?? defaultKind)
        nextPart += 1
        fillPolygon(poly, w: w, h: h) { x, y, c in
            let i = y * self.w + x
            if c >= 0.5 { self.id[i] = me; self.tone[i] = Float(clampd(shade(V2(Double(x) + 0.5, Double(y) + 0.5)), 0, 1)) }
            self.cover[i] = max(self.cover[i], Float(c))
        }
        return me
    }
    /// A region with its outline.
    @discardableResult public func shape(_ poly: [V2], weight: Double = 1.0, kind: Int? = nil, shade: (V2) -> Double) -> Int32 {
        let me = fill(poly, kind: kind, shade: shade)
        line(poly, weight: weight, owner: me, closed: true)
        return me
    }
    /// Leaves a thin band as paper (a pale vein on a dark leaf).
    public func reserve(_ pts: [V2], width: Double) {
        let d = densePolyline(pts, step: 1)
        for p in d {
            let r = Int(width.rounded(.up))
            for dy in -r...r { for dx in -r...r {
                let x = Int(p.x) + dx, y = Int(p.y) + dy
                if x >= 0, y >= 0, x < w, y < h, Double(dx * dx + dy * dy) <= width * width { tone[y * w + x] = 0 }
            } }
        }
    }
    /// A line (weight as a contour's); `owner` is the region it outlines, so later shapes over it hide it.
    public func line(_ pts: [V2], weight: Double, owner: Int32 = 0, closed: Bool = false, taper: Bool = false) {
        var p = pts
        if closed, let f = p.first { p.append(f) }
        let d = densePolyline(p, step: 1)
        var wts = d.map { _ in weight }
        if taper { for i in 0..<wts.count { wts[i] = weight * mixd(1, 0.35, Double(i) / Double(max(wts.count - 1, 1))) } }
        lines.append((d, wts, owner, closed))
    }
    public func dot(_ c: V2, r: Double, press: Double) { dots.append((c, r, press)) }

    /// Draws everything in graphite.
    public func render(seed: Double) -> CGImage { draw(seed: seed).image() }

    /// Draws everything onto a sheet.
    public func draw(seed: Double) -> Sheet {
        var rng = Rng(UInt64(seed * 997))
        let t1 = ToneMap(w: w, h: h, tone: tone, cover: cover, id: id)
        let sheet = Sheet(w: w, h: h, seed: seed, style: style)
        drawHatching(t1, on: sheet, rng: &rng)
        drawStipple(t1, on: sheet, seed: seed, density: { id, _ in self.stipple(id) })
        var chains: [Chain] = []
        for l in lines {
            // drop the parts that a later (front) shape covers
            var run: [V2] = [], rw: [Double] = []
            func flush() { if run.count >= 4 { chains.append(Chain(pts: run, weight: rw, closed: false)) }; run = []; rw = [] }
            for (i, p) in l.pts.enumerated() {
                let x = Int(p.x), y = Int(p.y)
                var covered = false
                if l.owner != 0, x >= 0, y >= 0, x < w, y < h {
                    let o = id[y * w + x]
                    covered = o != 0 && SurfaceID.part(o) > SurfaceID.part(l.owner)
                }
                if covered { flush() } else { run.append(p); rw.append(l.wts[i]) }
            }
            if l.closed && run.count == l.pts.count { chains.append(Chain(pts: run, weight: rw, closed: true)) } else { flush() }
        }
        drawChains(chains, on: sheet, tone: t1, ss: 1, rng: &rng)
        for (c, r, p) in dots { sheet.dot(c, r, p) }
        return sheet
    }
}

/// Points along a polyline about `step` apart (its corners kept).
public func densePolyline(_ p: [V2], step: Double) -> [V2] {
    guard p.count >= 2 else { return p }
    var out: [V2] = [p[0]]
    for i in 1..<p.count {
        let a = p[i - 1], b = p[i]
        let n = max(Int((len2(b - a) / step).rounded(.up)), 1)
        for k in 1...n { out.append(a + (b - a) * (Double(k) / Double(n))) }
    }
    return out
}

// MARK: - Helpers for flat studies

/// The tone across a lit cylinder or blade: light on the upper-left edge, darker toward the lower right.
public func shadeAcross(_ c: V2, _ n: V2, half: Double, lo: Double, hi: Double) -> (V2) -> Double {
    return { p in
        let s = clampd(dot2(p - c, n) / max(half, 1e-6), -1, 1)   // −1 the lit edge, +1 the shaded edge
        return mixd(lo, hi, sstep(-0.3, 1.0, s))
    }
}
/// Of a shape's two sides along direction d, the one away from the light (upper left): a unit normal toward it.
public func shadedSide(_ d: V2) -> V2 {
    var n = V2(-d.y, d.x)
    if dot2(n, V2(0.62, 0.78)) < 0 { n = -n }
    return n
}
/// A blade (needle, leaf, petal) along a centre curve: half-width w(t) from base to tip, as a closed outline.
public func blade(_ centre: [V2], width: (Double) -> Double) -> [V2] {
    let n = centre.count
    var left: [V2] = [], right: [V2] = []
    for i in 0..<n {
        let a = centre[max(i - 1, 0)], b = centre[min(i + 1, n - 1)]
        let d = norm2(b - a)
        let nn = V2(-d.y, d.x)
        let t = Double(i) / Double(n - 1)
        left.append(centre[i] + nn * width(t)); right.append(centre[i] - nn * width(t))
    }
    return left + right.reversed()
}
/// A curve from p along d, bending by `bend` radians over its length (with an optional wave).
public func curve(_ p: V2, _ d: V2, len: Double, bend: Double, n: Int = 40, wave: Double = 0) -> [V2] {
    var out = [p], q = p, dd = norm2(d)
    for i in 1...n {
        let t = Double(i) / Double(n)
        dd = rot2(dd, bend / Double(n) + wave * cos(t * 6.3) / Double(n))
        q = q + dd * (len / Double(n))
        out.append(q)
    }
    return out
}
/// An ellipse as a polygon.
public func ellipsePoly(_ c: V2, _ rx: Double, _ ry: Double, rot: Double = 0, n: Int = 60) -> [V2] {
    (0..<n).map { i in let a = Double(i) / Double(n) * 2 * Double.pi; return c + rot2(V2(cos(a) * rx, sin(a) * ry), rot) }
}

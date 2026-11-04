// Sheet.swift: graphite on paper. The sheet holds how much graphite each pixel has taken (0 … 1); strokes deposit it
// through the paper's tooth, and one stroke never darkens a pixel twice where it overlaps itself.
import Foundation

public final class Sheet {
    public let w: Int, h: Int
    public let style: Style
    /// Graphite per pixel, 0 … 1.
    public var acc: [Float]
    /// The paper's grain per pixel, 0 … 1.
    public var grain: [Float]
    public var base: [Float], smax: [Float], sid: [Int32]
    public var cur: Int32 = 0
    /// Coloured drawings (the style has `colour`): what each pixel's pencils absorb, three floats a pixel (red, green,
    /// blue); empty in graphite. Graphite still counts in `acc`, so every layer fills the paper's tooth.
    public var absorb: [Float]
    /// Coloured drawings: each region's own pencil (nil: the style's fallback), and the pencil in hand.
    public var palette: ((Int32) -> Pigment?)? = nil
    public var ink: Pigment? = nil
    public var isColour: Bool { style.colour != nil }

    /// A blank sheet; `seed` places the paper's grain.
    public init(w: Int, h: Int, seed: Double, style: Style = .standard) {
        self.w = w; self.h = h; self.style = style
        acc = Array(repeating: 0, count: w * h); base = acc; smax = acc
        sid = Array(repeating: -1, count: w * h)
        absorb = style.colour == nil ? [] : Array(repeating: 0, count: w * h * 3)
        var grain = [Float](repeating: 0, count: w * h)
        let gs = style.paper.grainScale
        grain.withUnsafeMutableBufferPointer { gB in
            let gP = gB.baseAddress!
            DispatchQueue.concurrentPerform(iterations: h) { y in
                for x in 0..<w {
                    // fine grain with a faint drag along the stroke direction
                    let p = V2(Double(x), Double(y)) / gs
                    var g = 0.55 * vnoise(p / 1.15 + seed) + 0.30 * vnoise(p / 2.9 + 17 + seed) + 0.15 * vnoise(V2(p.x / 7.0 + p.y / 11.0, p.y / 1.7 - p.x / 2.4) + 3)
                    g = clampd((g - 0.22) / 0.56, 0, 1)
                    gP[y * w + x] = Float(g)
                }
            }
        }
        self.grain = grain
    }

    /// Starts a new stroke: what it deposits from now on never darkens a pixel twice.
    public func begin() { cur += 1 }

    /// The pencil an ink is for a region (coloured drawings).
    public func pigment(_ ink: Ink, _ id: Int32) -> Pigment {
        let C = style.colour ?? Style.Colour()
        switch ink {
        case .local(let k):
            let own = (id > 0 ? palette?(id) : nil) ?? C.fallback
            return k == 1 ? own : own.deepened(k)
        case .shade: return C.shade
        case .fixed(let p): return p
        }
    }

    /// The pencil in hand's absorbance (the style's fallback when none is).
    @inline(__always) func inkAbsorbance() -> (Float, Float, Float) {
        let a = (ink ?? style.colour?.fallback ?? Pigment(0.23, 0.24, 0.23)).absorbance
        return (Float(a.0), Float(a.1), Float(a.2))
    }

    /// Lays graphite v (0 … 1) on a pixel, as part of the current stroke.
    @inline(__always) public func deposit(_ x: Int, _ y: Int, _ v: Float) {
        guard x >= 0, y >= 0, x < w, y < h, v > 0.002 else { return }
        let i = y * w + x
        if sid[i] != cur { sid[i] = cur; base[i] = acc[i]; smax[i] = v }
        else if v > smax[i] { smax[i] = v } else { return }
        let was = acc[i]
        acc[i] = base[i] + smax[i] * (1 - base[i])
        if !absorb.isEmpty {
            let a = inkAbsorbance(), d = acc[i] - was
            absorb[i * 3] += d * a.0; absorb[i * 3 + 1] += d * a.1; absorb[i * 3 + 2] += d * a.2
        }
    }

    /// One pencil stroke through the points: round-capped segments whose width (px) and pressure (0 … 1) vary along
    /// it; the paper's tooth shows through light pressure.
    public func stroke(_ p: [V2], _ wid: [Double], _ pr: [Double]) {
        guard p.count >= 2 else { return }
        begin()
        let w = self.w, h = self.h, cur = self.cur
        let tb = style.paper.toothBase, tp = style.paper.toothPressure
        let colour = !absorb.isEmpty
        let ia = inkAbsorbance()
        absorb.withUnsafeMutableBufferPointer { abB in
        acc.withUnsafeMutableBufferPointer { aB in base.withUnsafeMutableBufferPointer { bB in smax.withUnsafeMutableBufferPointer { mB in
        sid.withUnsafeMutableBufferPointer { iB in grain.withUnsafeBufferPointer { gB in
            let accP = aB.baseAddress!, baseP = bB.baseAddress!, smaxP = mB.baseAddress!, sidP = iB.baseAddress!, grainP = gB.baseAddress!
            for i in 0..<(p.count - 1) {
                let a = p[i], b = p[i + 1]
                let ra = wid[i] / 2, rb = wid[i + 1] / 2
                // a segment through a non-finite point or width draws nothing (and must not be rasterised)
                if !(a.x.isFinite && a.y.isFinite && b.x.isFinite && b.y.isFinite && ra.isFinite && rb.isFinite) { continue }
                let rmax = max(ra, rb) + 1
                let x0 = Int((min(a.x, b.x) - rmax).rounded(.down)), x1 = Int((max(a.x, b.x) + rmax).rounded(.up))
                let y0 = Int((min(a.y, b.y) - rmax).rounded(.down)), y1 = Int((max(a.y, b.y) + rmax).rounded(.up))
                // a segment wholly off the sheet draws nothing (its clamped range would run backwards)
                if x0 > w - 1 || y0 > h - 1 || x1 < 0 || y1 < 0 { continue }
                let ba = b - a, bb = max(dot2(ba, ba), 1e-9)
                let pa = pr[i], pb = pr[i + 1]
                for y in max(y0, 0)...min(y1, h - 1) { for x in max(x0, 0)...min(x1, w - 1) {
                    let c = V2(Double(x) + 0.5, Double(y) + 0.5)
                    let t = clampd(dot2(c - a, ba) / bb, 0, 1)
                    let d = len2(c - a - ba * t)
                    let r = mixd(ra, rb, t)
                    var cov = clampd(r + 0.5 - d, 0, 1)
                    if r < 0.5 { cov *= r * 2 }
                    if cov <= 0 { continue }
                    let press = mixd(pa, pb, t)
                    let k = y * w + x
                    let g = Double(grainP[k])
                    let tooth = mixd(g, 1, clampd(tb + tp * press, 0, 1))
                    let v = Float(cov * press * tooth)
                    // deposit
                    guard v > 0.002 else { continue }
                    if sidP[k] != cur { sidP[k] = cur; baseP[k] = accP[k]; smaxP[k] = v }
                    else if v > smaxP[k] { smaxP[k] = v } else { continue }
                    let was = accP[k]
                    accP[k] = baseP[k] + smaxP[k] * (1 - baseP[k])
                    if colour {
                        // the pencil in hand takes its share of the light by what it added (a filled tooth takes little)
                        let d = accP[k] - was
                        abB[k * 3] += d * ia.0; abB[k * 3 + 1] += d * ia.1; abB[k * 3 + 2] += d * ia.2
                    }
                } }
            }
        } } } } } }
    }

    /// A dot of radius r (px).
    public func dot(_ c: V2, _ r: Double, _ press: Double) { stroke([c, c + V2(0.01, 0.01)], [r * 2, r * 2], [press, press]) }

    /// A closed stroke round a small outline (a flower, a leaf): one width, one pressure, no wobble.
    public func closedStroke(_ poly: [V2], width: Double, press: Double) {
        guard poly.count >= 3 else { return }
        var p = poly; p.append(poly[0])
        stroke(p, p.map { _ in width }, p.map { _ in press })
    }

    /// Multiplies the graphite by a mask (one value per pixel).
    public func applyMask(_ m: [Float]) {
        for i in 0..<(w * h) { acc[i] *= m[i] }
        if !absorb.isEmpty { for i in 0..<(w * h) { absorb[i * 3] *= m[i]; absorb[i * 3 + 1] *= m[i]; absorb[i * 3 + 2] *= m[i] } }
    }

    /// Fades the drawing out in a loose circle of radius R round the sheet's centre (a detail's frame).
    public func fadeCircle(radius R: Double) {
        let c = V2(Double(w) / 2, Double(h) / 2)
        for y in 0..<h { for x in 0..<w {
            let d = V2(Double(x) + 0.5, Double(y) + 0.5) - c
            let a = atan2(d.y, d.x)
            let edge = R * (0.96 + 0.06 * (vnoise(V2(a * 1.6 + 7, 2)) - 0.5) * 2 + 0.025 * (vnoise(V2(a * 6.0, 9)) - 0.5) * 2)
            let f = 1 - sstep(edge * 0.90, edge, len2(d))
            acc[y * w + x] *= Float(f)
            if !absorb.isEmpty { let i = (y * w + x) * 3; absorb[i] *= Float(f); absorb[i + 1] *= Float(f); absorb[i + 2] *= Float(f) }
        } }
    }

    /// A loose vignette: 1 inside an irregular rounded oblong (insets as shares of the sheet), falling to 0 at its edge.
    public func vignetteMask(inset: (l: Double, r: Double, t: Double, b: Double)) -> [Float] {
        let W = w, H = h
        var m = [Float](repeating: 1, count: W * H)
        let cx = Double(W) * (0.5 + (inset.l - inset.r) / 2), cy = Double(H) * (0.5 + (inset.t - inset.b) / 2)
        let ax = Double(W) * (0.5 - (inset.l + inset.r) / 2), ay = Double(H) * (0.5 - (inset.t + inset.b) / 2)
        for y in 0..<H { for x in 0..<W {
            let u = (Double(x) + 0.5 - cx) / ax, v = (Double(y) + 0.5 - cy) / ay
            let r = pow(pow(abs(u), 4.5) + pow(abs(v), 4.5), 1 / 4.5)
            let a = atan2(v, u)
            let edge = 1.0 + 0.035 * (vnoise(V2(a * 2.2 + 4, 1.3)) - 0.5) * 2 + 0.015 * (vnoise(V2(a * 9, 7.1)) - 0.5) * 2
            m[y * W + x] = Float(1 - sstep(edge - 0.11, edge, r))
        } }
        return m
    }
}

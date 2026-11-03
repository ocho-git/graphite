// Strokes3D.swift: what is finer than the marcher can resolve (twigs, needles, veins, fin rays, a flower) drawn as
// strokes and marks in 3D: projected through the view's camera and hidden wherever the geometry buffer holds a nearer
// surface.
import Foundation

// MARK: - Pencil marks in 3D

/// A pencil stroke along 3D points, as wide as the thing it draws (its world radius, kept within pxMin … pxMax).
public struct Stroke3D {
    public var pts: [V3]
    /// World radius per point.
    public var rad: [Double]
    /// Pressure per point.
    public var pr: [Double]
    public var pxMin: Double, pxMax: Double
    /// Depth tolerance (world units): how far behind a surface a point may lie and still be drawn.
    public var tol: Double
    /// The hand's wobble across the line (px).
    public var wobble: Double
    /// Pressure gained in the shade it crosses (0 … 1).
    public var shade: Double
    public init(pts: [V3], rad: [Double], pr: [Double], pxMin: Double = 0.8, pxMax: Double = 2.4, tol: Double = 0.010, wobble: Double = 0.35, shade: Double = 0) {
        self.pts = pts; self.rad = rad; self.pr = pr; self.pxMin = pxMin; self.pxMax = pxMax; self.tol = tol; self.wobble = wobble; self.shade = shade
    }
}

/// Is a world point seen? Off the buffer and on paper count as seen; else it must lie no more than `tol` behind the
/// surface the buffer holds there.
@inlinable @inline(__always) public func visible(_ P: V3, _ s: V2, _ cam: Camera, _ g: GBuffer, tol: Double) -> Bool {
    let gx = Int(s.x * Double(g.ss)), gy = Int(s.y * Double(g.ss))
    guard gx >= 0, gy >= 0, gx < g.w, gy < g.h else { return true }
    let k = gy * g.w + gx
    if g.id[k] == 0 { return true }
    return Double(g.depth[k]) >= len3(P - cam.pos) - tol
}

/// Draws 3D strokes: resampled every ~3 px so they wobble and are hidden piece by piece.
public func drawStrokes3D(_ strokes: [Stroke3D], _ cam: Camera, _ g: GBuffer, on sheet: Sheet, tone t1: ToneMap, rng: inout Rng) {
    for s in strokes {
        guard s.pts.count >= 2 else { continue }
        // resample in 3D so long segments still wobble and test their visibility along the way
        var P: [V3] = [], R: [Double] = [], Q: [Double] = []
        for i in 0..<(s.pts.count - 1) {
            let a = s.pts[i], b = s.pts[i + 1]
            let la = cam.project(a), lb = cam.project(b)
            let n = max(Int((len2(lb - la) / 3.0).rounded(.up)), 1)
            for k in 0..<n {
                let t = Double(k) / Double(n)
                P.append(a + (b - a) * t); R.append(mixd(s.rad[i], s.rad[i + 1], t)); Q.append(mixd(s.pr[i], s.pr[i + 1], t))
            }
        }
        P.append(s.pts.last!); R.append(s.rad.last!); Q.append(s.pr.last!)
        let seedA = rng.range(0, 1000)
        var run: [V2] = [], ws: [Double] = [], prs: [Double] = []
        func flush() { if run.count >= 2 { sheet.stroke(run, ws, prs) }; run = []; ws = []; prs = [] }
        var arc = 0.0
        var prev: V2? = nil
        for i in 0..<P.count {
            let s2 = cam.project(P[i])
            if let pv = prev { arc += len2(s2 - pv) }
            prev = s2
            if !visible(P[i], s2, cam, g, tol: s.tol) { flush(); continue }
            let z = dot3(P[i] - cam.pos, cam.fwd)
            let wpx = clampd(2 * R[i] * cam.f / max(z, 1e-6), s.pxMin, s.pxMax)
            var q = s2
            if s.wobble > 0 {
                // a hand's wobble across the line
                let a = P[max(i - 1, 0)], b = P[min(i + 1, P.count - 1)]
                let d = norm2(cam.project(b) - cam.project(a))
                q += V2(-d.y, d.x) * ((vnoise(V2(arc / 30, seedA)) - 0.5) * 2 * s.wobble)
            }
            run.append(q); ws.append(wpx)
            prs.append(clampd(Q[i] * (1 + s.shade * t1.at(s2)), 0, 1))
        }
        flush()
    }
}

// MARK: - Lines in 3D drawn as contours

/// A 3D curve drawn with the contours' pencil (weights as the contours' weights).
public struct Curve3D {
    public var pts: [V3]
    /// One weight for the whole curve, or one per point.
    public var weights: [Double]
    public var closed: Bool
    /// Parts the curve lies on: they hide it only with 4 × the tolerance; nearer parts still do.
    public var on: Set<Int>
    public init(pts: [V3], weight: Double, closed: Bool = false, on: Set<Int> = []) {
        self.pts = pts; self.weights = [weight]; self.closed = closed; self.on = on
    }
    public init(pts: [V3], weights: [Double], closed: Bool = false, on: Set<Int> = []) {
        self.pts = pts; self.weights = weights; self.closed = closed; self.on = on
    }
    @inlinable public func weight(_ i: Int) -> Double { weights.count == 1 ? weights[0] : weights[i] }
}

/// How a 3D curve is sampled before its visibility is tested.
public enum CurveSampling {
    /// Every `px` pixels on the picture.
    case pixels(Double)
    /// Every `step` world units.
    case world(Double)
}

/// Draws 3D curves as contour chains: sampled, split where hidden (by more than `tolerance`), each visible run of at
/// least `minRun` points drawn with drawChains. Points off the buffer count as `offBuffer`.
public func drawCurves3D(_ curves: [Curve3D], _ cam: Camera, _ g: GBuffer, on sheet: Sheet, tone t1: ToneMap, rng: inout Rng,
                         sampling: CurveSampling = .pixels(0.7), tolerance: Double = 0.003, offBuffer: Bool = false,
                         minRun: Int = 4, smooth: Bool = true) {
    drawChains(curveChains(curves, cam, g, sampling: sampling, tolerance: tolerance, offBuffer: offBuffer, minRun: minRun),
               on: sheet, tone: t1, ss: g.ss, rng: &rng, smooth: smooth)
}

/// The visible runs of 3D curves as chains (sample units).
public func curveChains(_ curves: [Curve3D], _ cam: Camera, _ g: GBuffer, sampling: CurveSampling = .pixels(0.7), tolerance eps: Double = 0.003,
                        offBuffer: Bool = false, minRun: Int = 4) -> [Chain] {
    var chains: [Chain] = []
    let ss = Double(g.ss)
    func seen(_ p: V3, _ on: Set<Int>) -> Bool {
        let s = cam.project(p)
        let gx = Int(s.x * ss), gy = Int(s.y * ss)
        guard gx >= 0, gy >= 0, gx < g.w, gy < g.h else { return offBuffer }
        let k = gy * g.w + gx
        let id = g.id[k]
        if id == 0 { return true }
        if on.contains(SurfaceID.part(id)) { return Double(g.depth[k]) > cam.depth(p) - eps * 4 }
        return Double(g.depth[k]) > cam.depth(p) - eps
    }
    for c in curves {
        guard c.pts.count >= 2 else { continue }
        var dense: [V3] = [], dw: [Double] = []
        let n0 = c.pts.count
        let pts = c.closed ? c.pts + [c.pts[0]] : c.pts
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let wa = c.weight(i % n0), wb = c.weight((i + 1) % n0)
            let n: Int
            switch sampling {
            case .pixels(let px): n = max(Int(len2(cam.project(b) - cam.project(a)) / px), 1)
            case .world(let step): n = max(Int((len3(b - a) / step).rounded(.up)), 1)
            }
            for k in 0..<n { let t = Double(k) / Double(n); dense.append(a + (b - a) * t); dw.append(mixd(wa, wb, t)) }
        }
        dense.append(pts.last!); dw.append(c.weight((pts.count - 1) % n0))
        var run: [V2] = [], rw: [Double] = []
        func flush() {
            if run.count >= minRun { chains.append(Chain(pts: run, weight: rw, closed: false)) }
            run = []; rw = []
        }
        for (i, p) in dense.enumerated() {
            if seen(p, c.on) { run.append(cam.project(p) * ss); rw.append(dw[i]) } else { flush() }
        }
        if c.closed && run.count == dense.count {
            chains.append(Chain(pts: run, weight: rw, closed: true)); run = []; rw = []
        }
        flush()
    }
    return chains
}

// MARK: - Flat marks in 3D: flowers, leaves, buds

public enum MarkShape { case rosette, double, palmate, lance, bud, disc }

/// A small flat mark lying in a plane in 3D (a blossom, a leaf): outlined, optionally filled, optionally keeping the
/// hatching off it.
public struct Mark3D {
    /// Centre (lance: its base).
    public var c: V3
    /// The plane: u and v scaled by the half-size (lance: u along the leaf).
    public var u: V3, v: V3
    public var shape: MarkShape
    public var lobes: Int
    /// Outline pressure (0: none), fill pressure, outline width (px).
    public var line: Double, fill: Double, width: Double
    /// Keeps the hatching off it (left as paper).
    public var reserve: Bool
    public var tol: Double
    public init(c: V3, u: V3, v: V3, shape: MarkShape, lobes: Int = 5, line: Double = 0.5, fill: Double = 0, reserve: Bool = false,
                tol: Double = 0.012, width: Double = 0.9) {
        self.c = c; self.u = u; self.v = v; self.shape = shape; self.lobes = lobes; self.line = line; self.fill = fill
        self.reserve = reserve; self.tol = tol; self.width = width
    }
}

/// The outline of a mark in its own plane (unit half-size), counter-clockwise.
public func markOutline(_ m: Mark3D, seed: Double) -> [V2] {
    var out: [V2] = []
    switch m.shape {
    case .rosette, .double:
        // n rounded petals, pinched between them
        let n = 40
        let rot = seed * 6.2831853
        for i in 0..<n {
            let th = Double(i) / Double(n) * 2 * Double.pi
            let lobe = pow(abs(cos(Double(m.lobes) * (th + rot) / 2)), 0.55)
            let r = 0.52 + 0.48 * lobe
            out.append(V2(cos(th), sin(th)) * r)
        }
    case .disc, .bud:
        let n = m.shape == .bud ? 14 : 18
        for i in 0..<n {
            let th = Double(i) / Double(n) * 2 * Double.pi
            out.append(V2(cos(th) * (m.shape == .bud ? 0.75 : 1), sin(th)))
        }
    case .palmate:
        // a maple-like leaf: lobes cut two thirds in, pointed tips
        let L: [Double] = m.lobes == 5 ? [0.45, 0.8, 1.0, 0.8, 0.45] : [0.45, 0.76, 0.93, 1.0, 0.93, 0.76, 0.45]
        let k = L.count
        let span = m.lobes == 5 ? 2.6 : 3.4
        var pts: [V2] = [V2(0, -0.08)]
        for i in 0..<k {
            let a = -span / 2 + span * Double(i) / Double(k - 1)
            let tip = V2(sin(a), cos(a)) * L[i]
            if i > 0 {
                let am = a - span / Double(k - 1) / 2
                pts.append(V2(sin(am), cos(am)) * 0.33)
            }
            let side = V2(cos(a), -sin(a)) * 0.07 * L[i]
            pts.append(tip * 0.55 - side)
            pts.append(tip)
            pts.append(tip * 0.55 + side)
        }
        out = pts
    case .lance:
        // base at 0, tip at +1 along u; widest a third of the way, a drawn-out tip
        var left: [V2] = [], right: [V2] = []
        let n = 12
        for i in 0...n {
            let t = Double(i) / Double(n)
            let w = sin(Double.pi * pow(t, 0.62)) * (1 - 0.25 * t)
            left.append(V2(t, w)); right.append(V2(t, -w))
        }
        out = left + right.reversed()
    }
    return out
}

/// A mark as it lands in the picture (only the visible ones).
public struct ProjectedMark { public var poly: [V2]; public var inner: [V2]?; public var mark: Mark3D }

public func projectMarks(_ marks: [Mark3D], _ cam: Camera, _ g: GBuffer) -> [ProjectedMark] {
    var out: [ProjectedMark] = []
    for (mi, m) in marks.enumerated() {
        let c2 = cam.project(m.c)
        if !visible(m.c, c2, cam, g, tol: m.tol) { continue }
        let seed = hash21(V2(Double(mi) * 0.37, 1.7))
        let o = markOutline(m, seed: seed)
        let poly = o.map { cam.project(m.c + m.u * $0.x + m.v * $0.y) }
        var inner: [V2]? = nil
        if m.shape == .double {
            inner = markOutline(m, seed: seed + 0.1).map { cam.project(m.c + m.u * ($0.x * 0.55) + m.v * ($0.y * 0.55)) }
        }
        out.append(ProjectedMark(poly: poly, inner: inner, mark: m))
    }
    return out
}

/// Keeps the hatching off the marks that ask for it (call before the hatching).
public func reserveMarks(_ pm: [ProjectedMark], in t1: inout ToneMap) {
    let W = t1.w, H = t1.h
    for m in pm where m.mark.reserve {
        fillPolygon(m.poly, w: W, h: H) { x, y, c in t1.tone[y * W + x] *= Float(1 - c) }
    }
}

/// Draws the marks: their fill, their outline (and a double flower's inner ring), a flower's eye.
public func drawMarks(_ pm: [ProjectedMark], _ cam: Camera, on sheet: Sheet) {
    let W = sheet.w, H = sheet.h
    for m in pm {
        if m.mark.fill > 0 {
            sheet.begin()
            let f = m.mark.fill
            fillPolygon(m.poly, w: W, h: H) { x, y, c in
                let gr = Double(sheet.grain[y * W + x])
                sheet.deposit(x, y, Float(c * f * (0.75 + 0.25 * gr)))
            }
        }
        if m.mark.line > 0 { sheet.closedStroke(m.poly, width: m.mark.width, press: m.mark.line) }
        if let inner = m.inner, m.mark.line > 0 { sheet.closedStroke(inner, width: m.mark.width * 0.9, press: m.mark.line * 0.85) }
        if m.mark.shape == .rosette || m.mark.shape == .double {
            sheet.dot(cam.project(m.mark.c), 0.7, m.mark.line * 0.9)
        }
    }
}

// MARK: - Polygons on the sheet

/// Even-odd scanline fill: calls `f(x, y, coverage)` for every pixel inside (coverage 0 … 1 from 2 × 2 samples).
public func fillPolygon(_ poly: [V2], w: Int, h: Int, _ f: (Int, Int, Double) -> Void) {
    guard poly.count >= 3 else { return }
    let ys = poly.map { $0.y }, xs = poly.map { $0.x }
    let y0 = max(Int(ys.min()!.rounded(.down)), 0), y1 = min(Int(ys.max()!.rounded(.up)), h - 1)
    let x0 = max(Int(xs.min()!.rounded(.down)), 0), x1 = min(Int(xs.max()!.rounded(.up)), w - 1)
    if y0 > y1 || x0 > x1 { return }
    var cov = [Double](repeating: 0, count: (x1 - x0 + 1) * (y1 - y0 + 1))
    let cw = x1 - x0 + 1
    for y in y0...y1 {
        for sub in 0..<2 {
            let sy = Double(y) + 0.25 + 0.5 * Double(sub)
            var xsCross: [Double] = []
            for i in 0..<poly.count {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                if (a.y <= sy && b.y > sy) || (b.y <= sy && a.y > sy) {
                    xsCross.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
                }
            }
            xsCross.sort()
            var k = 0
            while k + 1 < xsCross.count {
                let xa = xsCross[k], xb = xsCross[k + 1]
                let lo = max(Int(xa.rounded(.down)), x0), hi = min(Int(xb.rounded(.up)), x1)
                if lo > hi { k += 2; continue }
                for x in lo...hi {
                    for subx in 0..<2 {
                        let sx = Double(x) + 0.25 + 0.5 * Double(subx)
                        if sx >= xa && sx < xb { cov[(y - y0) * cw + x - x0] += 0.25 }
                    }
                }
                k += 2
            }
        }
    }
    for y in y0...y1 { for x in x0...x1 { let c = cov[(y - y0) * cw + x - x0]; if c > 0 { f(x, y, min(c, 1)) } } }
}

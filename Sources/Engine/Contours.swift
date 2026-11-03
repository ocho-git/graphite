// Contours.swift: lines are traced as chains of "cracks" between neighbouring samples that show different regions,
// each crack weighted (silhouettes heavy, occluding edges strong, creases by their fold angle, drawn features by kind),
// then smoothed into a hand's line.
import Foundation

/// A traced line: points in sample units (the drawing's pixels × ss) and a weight per point (0 … ~1.1).
public struct Chain {
    public var pts: [V2]
    public var weight: [Double]
    public var closed: Bool
    public init(pts: [V2], weight: [Double], closed: Bool) { self.pts = pts; self.weight = weight; self.closed = closed }
}

/// The boundary between two neighbouring samples.
public struct Edge {
    public let a: Int32, b: Int32
    public let depthA: Double, depthB: Double
    public let normalA: V3, normalB: V3
    /// How sharply the surface folds across it (0 flat … 2 opposite).
    @inlinable public var fold: Double { 1 - dot3(normalA, normalB) }
}

/// The weight of a crease that folds by `fold` (1 − cos of the angle): none below a slight fold, rising with it.
@inlinable @inline(__always) public func creaseWeight(_ fold: Double) -> Double { fold > 0.012 ? 0.32 + 0.45 * sstep(0.02, 0.35, fold) : 0 }

/// The usual rules for weighing edges, with tables by kind (SurfaceID.kind):
///   - masked samples draw nothing; a kind in `unlined` (a cast shadow) has no outline but against the subject;
///   - a silhouette against the paper: `silhouette[kind]` (default 1);
///   - against what is seen through an opening (`throughKind`): `throughRim` if the other side is one of `darkRim`
///     (the opening's inside), else `throughEdge`;
///   - an occluding edge (a depth jump over `depthGap`): `occluding`;
///   - the subject's own edge weight (Subject.edgeWeight), if it has one;
///   - else a crease by its fold, at least `partEdge` between parts, at least `floor[kind]` next to a kind.
public struct ContourRules {
    public var depthGap: Double = 0.012
    public var silhouette: [Int: Double] = [:]
    public var unlined: Set<Int> = []
    public var throughKind: Int? = nil
    public var darkRim: Set<Int> = []
    public var throughRim: Double = 0.55, throughEdge: Double = 0.8
    public var occluding: Double = 0.9
    public var partEdge: Double = 0.55
    public var floor: [Int: Double] = [:]
    /// The subject's own rule, consulted after the depth test.
    public var edge: ((Int32, Int32) -> Double?)? = nil
    public init() {}

    @inlinable public func weight(_ e: Edge) -> Double {
        let A = e.a, B = e.b
        if A < 0 || B < 0 { return 0 }
        let kA = SurfaceID.kind(A), kB = SurfaceID.kind(B)
        let uA = A != 0 && unlined.contains(kA), uB = B != 0 && unlined.contains(kB)
        if uA || uB {
            if A == 0 || B == 0 || (uA && uB) { return 0 }
            return 1.0
        }
        if A == 0 || B == 0 { return silhouette[A == 0 ? kB : kA] ?? 1.0 }
        if let tk = throughKind, kA == tk || kB == tk {
            let other = kA == tk ? kB : kA
            return darkRim.contains(other) ? throughRim : throughEdge
        }
        if abs(e.depthA - e.depthB) > depthGap { return occluding }
        if let f = edge, let w = f(A, B) { return w }
        var w = creaseWeight(e.fold)
        if SurfaceID.part(A) != SurfaceID.part(B) { w = max(w, partEdge) }
        if let f = floor[kA] { w = max(w, f) }
        if let f = floor[kB] { w = max(w, f) }
        return w
    }
}

/// Traces the region boundaries of a geometry buffer into chains, weighing each crack with `weight`.
public func traceContours(_ g: GBuffer, weight: (Edge) -> Double) -> [Chain] {
    let w = g.w, h = g.h
    let vw = w + 1
    struct Crack { var v0: Int32; var v1: Int32; var a: Int32; var b: Int32; var key: UInt64 }
    var cracks: [Crack] = []
    cracks.reserveCapacity(200_000)
    @inline(__always) func key(_ x: Int32, _ y: Int32) -> UInt64 { let lo = min(x, y), hi = max(x, y); return UInt64(UInt32(bitPattern: lo)) << 32 | UInt64(UInt32(bitPattern: hi)) }
    g.id.withUnsafeBufferPointer { id in
        for y in 0..<h { for x in 0..<w {
            let i = y * w + x
            if x + 1 < w, id[i] != id[i + 1] {
                cracks.append(Crack(v0: Int32(y * vw + x + 1), v1: Int32((y + 1) * vw + x + 1), a: Int32(i), b: Int32(i + 1), key: key(id[i], id[i + 1])))
            }
            if y + 1 < h, id[i] != id[i + w] {
                cracks.append(Crack(v0: Int32((y + 1) * vw + x), v1: Int32((y + 1) * vw + x + 1), a: Int32(i), b: Int32(i + w), key: key(id[i], id[i + w])))
            }
        } }
    }
    // vertex → cracks (two linked lists: cracks starting there, cracks ending there)
    var head = [Int32](repeating: -1, count: vw * (h + 1))
    var nextA = [Int32](repeating: -1, count: cracks.count), nextB = [Int32](repeating: -1, count: cracks.count)
    for (ci, c) in cracks.enumerated() { nextA[ci] = head[Int(c.v0)]; head[Int(c.v0)] = Int32(ci) }
    var head2 = [Int32](repeating: -1, count: vw * (h + 1))
    for (ci, c) in cracks.enumerated() { nextB[ci] = head2[Int(c.v1)]; head2[Int(c.v1)] = Int32(ci) }
    var used = [Bool](repeating: false, count: cracks.count)
    /// At vertex v, among the cracks with key k: how many are unused (and the first of them), and how many in all.
    func around(_ v: Int32, _ k: UInt64) -> (cand: Int, first: Int32, all: Int) {
        var cand = 0, all = 0, first: Int32 = -1
        var c = head[Int(v)]
        while c >= 0 { if cracks[Int(c)].key == k { all += 1; if !used[Int(c)] { if cand == 0 { first = c }; cand += 1 } }; c = nextA[Int(c)] }
        c = head2[Int(v)]
        while c >= 0 { if cracks[Int(c)].key == k { all += 1; if !used[Int(c)] { if cand == 0 { first = c }; cand += 1 } }; c = nextB[Int(c)] }
        return (cand, first, all)
    }
    func crackWeight(_ c: Crack) -> Double {
        let ia = Int(c.a), ib = Int(c.b)
        return weight(Edge(a: g.id[ia], b: g.id[ib], depthA: Double(g.depth[ia]), depthB: Double(g.depth[ib]), normalA: g.nrm[ia], normalB: g.nrm[ib]))
    }
    @inline(__always) func vpos(_ v: Int32) -> V2 { V2(Double(Int(v) % vw), Double(Int(v) / vw)) }
    var chains: [Chain] = []
    for ci in 0..<cracks.count where !used[ci] {
        used[ci] = true
        let k = cracks[ci].key
        var verts: [Int32] = [cracks[ci].v0, cracks[ci].v1]
        var ws: [Double] = [crackWeight(cracks[ci])]
        var closed = false
        for dirForward in [true, false] {
            while true {
                let v = dirForward ? verts.last! : verts.first!
                let (cand, first, all) = around(v, k)
                if cand != 1 || all > 2 { break }
                let c = cracks[Int(first)]
                used[Int(first)] = true
                let other = c.v0 == v ? c.v1 : c.v0
                if dirForward { verts.append(other); ws.append(crackWeight(c)) } else { verts.insert(other, at: 0); ws.insert(crackWeight(c), at: 0) }
                if other == (dirForward ? verts.first! : verts.last!) { closed = true; break }
            }
            if closed { break }
        }
        if verts.count < 4 { continue }
        let mean = ws.reduce(0, +) / Double(ws.count)
        if mean < 0.05 { continue }
        // vertex weights (cracks sit between vertices)
        var vw8 = [Double](repeating: 0, count: verts.count)
        for i in 0..<verts.count { vw8[i] = (ws[max(i - 1, 0)] + ws[min(i, ws.count - 1)]) / 2 }
        chains.append(Chain(pts: verts.map(vpos), weight: vw8, closed: closed))
    }
    return chains
}

/// Traces the region boundaries with the usual rules.
public func traceContours(_ g: GBuffer, rules: ContourRules) -> [Chain] { traceContours(g, weight: rules.weight) }

/// Gaussian smoothing along a chain (ends pinned unless closed) so the pixel staircase becomes a drawn line.
public func smoothChain(_ c: Chain, sigma: Double) -> Chain {
    let n = c.pts.count
    let r = Int((sigma * 2.5).rounded(.up))
    var kernel: [Double] = []
    for i in -r...r { kernel.append(exp(-Double(i * i) / (2 * sigma * sigma))) }
    var out = c
    for i in 0..<n {
        if !c.closed {
            let m = min(i, n - 1 - i)            // pinned ends: shrink the window near them
            let rr = min(r, m)
            if rr == 0 { continue }
            var s = V2(0, 0), ws = 0.0, wsum = 0.0, wt = 0.0
            for j in -rr...rr { let k = kernel[j + r]; s += c.pts[i + j] * k; ws += k; wsum += c.weight[i + j] * k; wt += k }
            out.pts[i] = s / ws; out.weight[i] = wsum / wt
        } else {
            var s = V2(0, 0), ws = 0.0, wsum = 0.0
            for j in -r...r { let k = kernel[j + r]; let q = ((i + j) % (n - 1) + (n - 1)) % (n - 1); s += c.pts[q] * k; ws += k; wsum += c.weight[q] * k }
            out.pts[i] = s / ws; out.weight[i] = wsum / ws
        }
    }
    return out
}

/// Resamples a polyline (and a value along it) at an even step.
public func resample(_ pts: [V2], _ vals: [Double], step: Double) -> ([V2], [Double]) {
    guard pts.count >= 2 else { return (pts, vals) }
    var cum = [0.0]
    for i in 1..<pts.count { cum.append(cum.last! + len2(pts[i] - pts[i - 1])) }
    let total = cum.last!
    if total < 1e-6 { return ([pts[0]], [vals[0]]) }
    let n = max(Int((total / step).rounded()), 1)
    var op: [V2] = [], ov: [Double] = []
    var j = 0
    for k in 0...n {
        let s = total * Double(k) / Double(n)
        while j < pts.count - 2 && cum[j + 1] < s { j += 1 }
        let seg = max(cum[j + 1] - cum[j], 1e-9)
        let t = clampd((s - cum[j]) / seg, 0, 1)
        op.append(pts[j] + (pts[j + 1] - pts[j]) * t)
        ov.append(mixd(vals[j], vals[j + 1], t))
    }
    return (op, ov)
}

// Render.swift: ray-marches a subject into a geometry buffer: per sample its region, depth, normal, tone, stipple and
// fills. The tone is the light's tone (Lambert from the light, soft cast shadows, contact occlusion) turned into the
// drawn tone by the surface's material.
import Foundation

/// The soft shadow and occlusion are the costly part of a sample; samples of one drawn pixel can share them.
public enum ShadeSharing {
    /// Every sample shades itself.
    case none
    /// One sample per drawn pixel shades; the others borrow its tone when they show the same region.
    case perPixel
    /// Within a drawn pixel, samples on the same part share the shadow and occlusion of the first one.
    case perPart
    /// Within a drawn pixel, a sample shares the last lit sample's shadow and occlusion if it is on the same part and
    /// its normal is within the given cosine.
    case byNormal(Double)
}

/// A subject's cast shadow on the ground plane, for views from above: rays that miss the subject but meet the ground
/// within `reach` (plan distance from the subject's centre) record the shadow as region `id`, hatched but unlined.
public struct GroundShadow {
    public var z: Double
    public var reach: Double
    public var id: Int32
    public var strength: Double
    public var minimum: Double
    public init(z: Double, reach: Double, id: Int32, strength: Double = 0.58, minimum: Double = 0.04) {
        self.z = z; self.reach = reach; self.id = id; self.strength = strength; self.minimum = minimum
    }
}

public struct RenderOptions {
    public var march: MarchSettings
    public var sharing: ShadeSharing
    public var groundShadow: GroundShadow?
    /// Lambert only: no shadows or occlusion (a quick framing pass).
    public var lightOnly: Bool
    /// Only this rectangle of samples (x0, y0, x1, y1; x1 and y1 exclusive), nil for all.
    public var region: (Int, Int, Int, Int)?
    /// The tone of what is seen through an opening when its material sets none.
    public var throughTone: Double

    public init(march: MarchSettings = MarchSettings(), sharing: ShadeSharing = .none, groundShadow: GroundShadow? = nil,
                lightOnly: Bool = false, region: (Int, Int, Int, Int)? = nil, throughTone: Double = 0.62) {
        self.march = march; self.sharing = sharing; self.groundShadow = groundShadow; self.lightOnly = lightOnly
        self.region = region; self.throughTone = throughTone
    }
}

/// Fills the geometry buffer `g` with the subject seen by `cam`, lit by the unit vector `light` (toward the light).
@inlinable public func render<S: Subject>(_ s: S, camera cam: Camera, into g: GBuffer, light: V3, options o: RenderOptions = RenderOptions()) {
    s.willRender(unit: o.march.unit, camera: cam, light: light)
    switch o.sharing {
    case .none, .perPixel: renderSamples(s, cam, g, light, o)
    case .perPart, .byNormal: renderBlocks(s, cam, g, light, o)
    }
}

/// What one sample's ray meets.
public struct SampleHit {
    public var t: Double
    public var part: Int
    public var p: V3
    public var n: V3
    public var surface: Surface
    @inlinable public init(t: Double, part: Int, p: V3, n: V3, surface: Surface) { self.t = t; self.part = part; self.p = p; self.n = n; self.surface = surface }
}

/// Marches one sample's ray: the nearest of the marched hit and any exact hit, with its normal facing the eye.
@inlinable @inline(__always) public func traceSample<S: Subject>(_ s: S, _ ro: V3, _ rd: V3, _ o: RenderOptions) -> SampleHit? {
    let hit = march(s, ro, rd, o.march)
    if let e = s.exactHit(ro, rd, tMax: hit?.0 ?? 1e18) {
        var n = e.normal
        if dot3(n, rd) > 0 { n = -n }
        return SampleHit(t: e.t, part: e.part, p: ro + rd * e.t, n: n, surface: e.surface)
    }
    guard let (t, i) = hit else { return nil }
    let p = ro + rd * t
    var n = s.normal(i, p, step: 0.00025 * o.march.unit)
    if dot3(n, rd) > 0 { n = -n }
    return SampleHit(t: t, part: i, p: p, n: n, surface: s.surface(i, p, n))
}

/// The light's tone at a hit, computing the shadow only where the light reaches.
@inlinable @inline(__always) public func shadeHit<S: Subject>(_ s: S, _ p: V3, _ n: V3, _ light: V3, _ o: RenderOptions) -> Double {
    let diff = max(dot3(n, light), 0)
    if o.lightOnly { return clampd((1 - (0.2 + 0.8 * diff) - 0.18) / 0.74, 0, 1) }
    let sh = diff > 0 ? softShadow(s, p + n * 0.002 * o.march.unit, light, o.march) : 0
    let ao = ambientOcclusion(s, p, n, o.march)
    return litTone(diffuse: diff, shadow: sh, occlusion: ao)
}

/// A ray that missed: what is seen through an opening, the cast shadow on the ground, or paper.
@inlinable @inline(__always) public func missSample<S: Subject>(_ s: S, _ ro: V3, _ rd: V3, _ light: V3, _ o: RenderOptions, _ k: Int,
                                                         _ idP: UnsafeMutablePointer<Int32>, _ dP: UnsafeMutablePointer<Float>,
                                                         _ nP: UnsafeMutablePointer<V3>, _ tP: UnsafeMutablePointer<Float>,
                                                         _ sP: UnsafeMutablePointer<Float>, _ thP: UnsafeMutablePointer<Float>) {
    if let id = s.missID(ro, rd) {
        let m = s.material(id, ro, -rd)
        idP[k] = id; dP[k] = 1e6; nP[k] = -rd; tP[k] = Float(m.fixedTone ?? o.throughTone); sP[k] = 0; thP[k] = Float(m.throughFill)
    } else if let gs = o.groundShadow, rd.z < -1e-6 {
        let tg = (gs.z - ro.z) / rd.z
        let pg = ro + rd * tg
        let b = s.bounds
        let centre = (b.lo + b.hi) / 2
        if len2(V2(pg.x - centre.x, pg.y - centre.y)) < gs.reach {
            let occ = 1 - softShadow(s, pg + V3(0, 0, 0.0015 * o.march.unit), light, o.march)
            if occ > gs.minimum {
                idP[k] = gs.id; dP[k] = Float(tg); nP[k] = V3(0, 0, 1); tP[k] = Float(occ * gs.strength); sP[k] = 0
            }
        }
    }
}

/// .none and .perPixel: one pass over every sample (in parallel rows), and for .perPixel a second pass where the
/// samples that did not shade borrow their pixel's tone or shade themselves.
@inlinable public func renderSamples<S: Subject>(_ s: S, _ cam: Camera, _ g: GBuffer, _ light: V3, _ o: RenderOptions) {
    let ss = Double(g.ss), B = g.ss
    let perPixel: Bool = { if case .perPixel = o.sharing { return B > 1 } else { return false } }()
    let (x0, y0, x1, y1) = o.region ?? (0, 0, g.w, g.h)
    g.id.withUnsafeMutableBufferPointer { idB in
    g.depth.withUnsafeMutableBufferPointer { dB in
    g.nrm.withUnsafeMutableBufferPointer { nB in
    g.tone.withUnsafeMutableBufferPointer { tB in
    g.stipple.withUnsafeMutableBufferPointer { sB in
    g.fill.withUnsafeMutableBufferPointer { fB in
    g.through.withUnsafeMutableBufferPointer { thB in
        let idP = idB.baseAddress!, dP = dB.baseAddress!, nP = nB.baseAddress!, tP = tB.baseAddress!
        let sP = sB.baseAddress!, fP = fB.baseAddress!, thP = thB.baseAddress!
        let gw = g.w
        DispatchQueue.concurrentPerform(iterations: max(y1 - y0, 0)) { yy in
            let y = y0 + yy
            for x in x0..<x1 {
                let (ro, rd) = cam.ray((Double(x) + 0.5) / ss, (Double(y) + 0.5) / ss)
                let k = y * gw + x
                guard let h = traceSample(s, ro, rd, o) else {
                    missSample(s, ro, rd, light, o, k, idP, dP, nP, tP, sP, thP)
                    continue
                }
                let m = h.surface.material
                idP[k] = h.surface.id; dP[k] = Float(h.t); nP[k] = h.n
                sP[k] = Float(m.stipple); fP[k] = Float(m.fill); thP[k] = Float(m.throughFill)
                if let f = m.fixedTone { tP[k] = Float(f); continue }
                if perPixel && (x % B != 0 || y % B != 0) { tP[k] = -1; continue }
                tP[k] = Float(m.tone(lit: shadeHit(s, h.p, h.n, light, o)))
            }
        }
        guard perPixel else { return }
        DispatchQueue.concurrentPerform(iterations: max(y1 - y0, 0)) { yy in
            let y = y0 + yy
            for x in x0..<x1 {
                let k = y * gw + x
                guard tP[k] < 0 else { continue }
                let k0 = (y - y % B) * gw + (x - x % B)
                if idP[k0] == idP[k] && tP[k0] >= 0 { tP[k] = tP[k0]; continue }
                let (ro, rd) = cam.ray((Double(x) + 0.5) / ss, (Double(y) + 0.5) / ss)
                let p = ro + rd * Double(dP[k])
                let n = nP[k]
                let m = s.material(idP[k], p, n)
                tP[k] = Float(m.tone(lit: shadeHit(s, p, n, light, o)))
            }
        }
    } } } } } } }
}

/// .perPart and .byNormal: drawn pixels in parallel; within one, its samples in order (rows, then columns), sharing
/// the shadow and occlusion as the mode says.
@inlinable public func renderBlocks<S: Subject>(_ s: S, _ cam: Camera, _ g: GBuffer, _ light: V3, _ o: RenderOptions) {
    let ss = Double(g.ss), B = g.ss
    var cosLimit = 2.0
    if case .byNormal(let c) = o.sharing { cosLimit = c }
    let byNormal = cosLimit <= 1
    g.id.withUnsafeMutableBufferPointer { idB in
    g.depth.withUnsafeMutableBufferPointer { dB in
    g.nrm.withUnsafeMutableBufferPointer { nB in
    g.tone.withUnsafeMutableBufferPointer { tB in
    g.stipple.withUnsafeMutableBufferPointer { sB in
    g.fill.withUnsafeMutableBufferPointer { fB in
    g.through.withUnsafeMutableBufferPointer { thB in
        let idP = idB.baseAddress!, dP = dB.baseAddress!, nP = nB.baseAddress!, tP = tB.baseAddress!
        let sP = sB.baseAddress!, fP = fB.baseAddress!, thP = thB.baseAddress!
        let gw = g.w
        DispatchQueue.concurrentPerform(iterations: g.h / B) { by in
            for bx in 0..<(gw / B) {
                var hits: [(Int, SampleHit)] = []
                hits.reserveCapacity(B * B)
                for j in 0..<B { for i0 in 0..<B {
                    let x = bx * B + i0, y = by * B + j
                    let (ro, rd) = cam.ray((Double(x) + 0.5) / ss, (Double(y) + 0.5) / ss)
                    let k = y * gw + x
                    guard let h = traceSample(s, ro, rd, o) else {
                        missSample(s, ro, rd, light, o, k, idP, dP, nP, tP, sP, thP)
                        continue
                    }
                    let m = h.surface.material
                    idP[k] = h.surface.id; dP[k] = Float(h.t); nP[k] = h.n
                    sP[k] = Float(m.stipple); fP[k] = Float(m.fill); thP[k] = Float(m.throughFill)
                    hits.append((k, h))
                } }
                // shading, in sample order
                var cacheParts: [Int] = [], cacheV: [(Double, Double)] = []
                var shared: (part: Int, n: V3, sh: Double, ao: Double)? = nil
                for (k, h) in hits {
                    let m = h.surface.material
                    if let f = m.fixedTone { tP[k] = Float(f); continue }
                    let n = h.n, p = h.p
                    let diff = max(dot3(n, light), 0)
                    var shadeTone: Double
                    if o.lightOnly {
                        shadeTone = clampd((1 - (0.2 + 0.8 * diff) - 0.18) / 0.74, 0, 1)
                    } else {
                        var sh = 0.0, ao = 1.0
                        if byNormal {
                            if let s0 = shared, s0.part == h.part, dot3(s0.n, n) > cosLimit {
                                sh = s0.sh; ao = s0.ao
                            } else {
                                sh = diff > 0 ? softShadow(s, p + n * 0.002 * o.march.unit, light, o.march) : 0
                                ao = ambientOcclusion(s, p, n, o.march)
                                if diff > 0 { shared = (h.part, n, sh, ao) }
                            }
                        } else if let ci = cacheParts.firstIndex(of: h.part) {
                            (sh, ao) = cacheV[ci]
                        } else {
                            sh = softShadow(s, p + n * 0.002 * o.march.unit, light, o.march)
                            ao = ambientOcclusion(s, p, n, o.march)
                            cacheParts.append(h.part); cacheV.append((sh, ao))
                        }
                        if diff <= 0 { sh = 0 }
                        shadeTone = litTone(diffuse: diff, shadow: sh, occlusion: ao)
                    }
                    tP[k] = Float(m.tone(lit: shadeTone))
                }
            }
        }
    } } } } } } }
}

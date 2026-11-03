// March.swift: sphere tracing, the soft shadow and the contact occlusion. Their tolerances are world lengths at the
// reference scale (a subject about 1.3 units across drawn about 800 px tall); `unit` scales all of them together, so a
// pebble or a garden is marched and shaded at the same pixel scale.
import Foundation

public struct MarchSettings {
    /// World size of the reference pixel scale (1: the reference).
    public var unit: Double
    /// Steps per ray before it gives up.
    public var maxSteps: Int
    /// The share of the distance stepped (below 1 for distance fields that are bounds, not exact).
    public var stepScale: Double
    /// Margin round the subject's bounds (absolute world units).
    public var boxPad: Double
    /// Steps of the soft-shadow ray.
    public var shadowSteps: Int

    public init(unit: Double = 1, maxSteps: Int = 500, stepScale: Double = 0.85, boxPad: Double = 0.01, shadowSteps: Int = 160) {
        self.unit = unit; self.maxSteps = maxSteps; self.stepScale = stepScale; self.boxPad = boxPad; self.shadowSteps = shadowSteps
    }
}

/// The first hit along a ray before tMax: its distance along the ray and the part hit.
@inlinable public func march<S: Subject>(_ s: S, _ ro: V3, _ rd: V3, _ m: MarchSettings, tMax: Double = .infinity) -> (Double, Int)? {
    let b = s.bounds
    let lo = b.lo - m.boxPad, hi = b.hi + m.boxPad
    guard let (t0, t1) = rayBox(ro, rd, lo, hi) else { return nil }
    var t = t0
    let tEnd = min(t1, tMax)
    let eps = 0.0002 * m.unit, minStep = 0.00005 * m.unit
    for _ in 0..<m.maxSteps {
        if t > tEnd { return nil }
        let (d, i) = s.sceneSDF(ro + rd * t)
        if d < eps && i >= 0 { return (t, i) }
        t += max(d * m.stepScale, minStep)
    }
    return nil
}

/// How much of the light reaches ro along rd: 0 in full shadow … 1 lit, with a soft penumbra.
@inlinable public func softShadow<S: Subject>(_ s: S, _ ro: V3, _ rd: V3, _ m: MarchSettings) -> Double {
    var res = 1.0, t = 0.004 * m.unit
    let b = s.bounds
    let lo = b.lo - m.boxPad, hi = b.hi + m.boxPad
    guard let (_, t1) = rayBox(ro, rd, lo, hi) else { return 1 }
    let eps = 0.0002 * m.unit
    for _ in 0..<m.shadowSteps {
        let (d, i) = s.shadowSDF(ro + rd * t)
        if d < eps && i >= 0 { return 0 }
        if i >= 0 { res = min(res, 9 * d / t) }    // a distance that only bounds empty space casts no penumbra
        t += clampd(d * 0.9, 0.0015 * m.unit, 0.05 * m.unit)
        if t > t1 { break }
    }
    return clampd(res, 0, 1)
}

/// Contact occlusion at p (normal n): 0 in a tight crease … 1 in the open.
@inlinable public func ambientOcclusion<S: Subject>(_ s: S, _ p: V3, _ n: V3, _ m: MarchSettings) -> Double {
    var occ = 0.0, w = 1.0
    for i in 1...5 {
        let h = 0.009 * Double(i) * m.unit
        occ += (h - s.occlusionSDF(p + n * h).0) * w
        w *= 0.6
    }
    return clampd(1 - occ * 9 / m.unit, 0, 1)
}

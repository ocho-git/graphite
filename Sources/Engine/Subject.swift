// Subject.swift: what a model must answer for the pencil to draw it. A subject is a signed-distance scene split into
// parts (the marcher reports which part it hit); each hit point belongs to a drawn region (lines are drawn between
// regions) and has a material (its tone).
import Foundation

public protocol Subject: AnyObject {
    /// The box that holds everything the marcher can hit.
    var bounds: (lo: V3, hi: V3) { get }
    /// The distance to the nearest surface and the part it belongs to (-1 for none).
    func sceneSDF(_ p: V3) -> (Double, Int)
    /// One part's own distance (its normal is taken from it).
    func partSDF(_ i: Int, _ p: V3) -> Double
    /// The drawn region of a hit on part i (an id, see SurfaceID). n is the normal, facing the eye.
    func subID(_ i: Int, _ p: V3, _ n: V3) -> Int32
    /// The material of a region at a point (default: plain).
    func material(_ id: Int32, _ p: V3, _ n: V3) -> Material

    // Optional: each has a default.

    /// Region and material in one go (default: subID, then material). Override when both come from one computation.
    func surface(_ i: Int, _ p: V3, _ n: V3) -> Surface
    /// The surface normal of part i at p (default: central differences of partSDF, step h).
    func normal(_ i: Int, _ p: V3, step h: Double) -> V3
    /// What casts shadows (default: sceneSDF).
    func shadowSDF(_ p: V3) -> (Double, Int)
    /// What occludes in the contact shading (default: sceneSDF).
    func occlusionSDF(_ p: V3) -> (Double, Int)
    /// A ray that hits nothing but still shows something: seen through an opening to the far side (default: nil).
    /// Its material's fixed tone (default 0.62) is used; give it a `throughFill`.
    func missID(_ ro: V3, _ rd: V3) -> Int32?
    /// Exact surfaces the marcher should not step to (thin planes, a wing): the nearest such hit before tMax.
    func exactHit(_ ro: V3, _ rd: V3, tMax: Double) -> ExactHit?
    /// How many parts there are (ground strokes look at parts 0 ..< partCount).
    var partCount: Int { get }
    /// A ground plane that takes the subject's cast shadow in views from above (nil: none).
    var groundZ: Double? { get }
    /// Does part i stand on the ground (a short stroke goes under it in an elevation)?
    func grounded(_ i: Int) -> Bool
    /// Where a grounded part's foot is, if it can be hidden behind another part (a leg behind a leg): the ground
    /// stroke is left out when the foot is not where the part's lowest visible pixel is.
    func groundFoot(_ i: Int) -> V3?
    /// The contour weight between two regions, nil for the drawing's rules.
    func edgeWeight(_ a: Int32, _ b: Int32) -> Double?
    /// Called before each render with the drawing's world unit (world size of a pixel, relative to the reference), the
    /// camera and the light: a subject that needs them while it is sampled keeps them.
    func willRender(unit: Double, camera: Camera, light: V3)
}

/// An exact hit (a plane, a disc) found before the marcher's.
public struct ExactHit {
    public var t: Double
    public var normal: V3
    public var surface: Surface
    /// The part number it counts as (for shading caches and ground strokes).
    public var part: Int
    public init(t: Double, normal: V3, surface: Surface, part: Int) { self.t = t; self.normal = normal; self.surface = surface; self.part = part }
}

extension Subject {
    public func material(_ id: Int32, _ p: V3, _ n: V3) -> Material { .plain }
    @inlinable public func surface(_ i: Int, _ p: V3, _ n: V3) -> Surface {
        let id = subID(i, p, n)
        return Surface(id, material(id, p, n))
    }
    @inlinable public func normal(_ i: Int, _ p: V3, step h: Double) -> V3 {
        let e = h
        let dx = partSDF(i, p + V3(e, 0, 0)) - partSDF(i, p - V3(e, 0, 0))
        let dy = partSDF(i, p + V3(0, e, 0)) - partSDF(i, p - V3(0, e, 0))
        let dz = partSDF(i, p + V3(0, 0, e)) - partSDF(i, p - V3(0, 0, e))
        return norm3(V3(dx, dy, dz))
    }
    @inlinable public func shadowSDF(_ p: V3) -> (Double, Int) { sceneSDF(p) }
    @inlinable public func occlusionSDF(_ p: V3) -> (Double, Int) { sceneSDF(p) }
    public func missID(_ ro: V3, _ rd: V3) -> Int32? { nil }
    public func exactHit(_ ro: V3, _ rd: V3, tMax: Double) -> ExactHit? { nil }
    public var partCount: Int { 0 }
    public var groundZ: Double? { nil }
    public func grounded(_ i: Int) -> Bool { false }
    public func groundFoot(_ i: Int) -> V3? { nil }
    public func edgeWeight(_ a: Int32, _ b: Int32) -> Double? { nil }
    public func willRender(unit: Double, camera: Camera, light: V3) {}
}

/// A subject made of closures: the quickest way to draw one shape. Parts are numbered in the order given.
public final class ShapeSubject: Subject {
    public struct Part {
        public var lo: V3, hi: V3
        public var sdf: (V3) -> Double
        public var region: (V3, V3) -> Int32
        public var material: (Int32, V3, V3) -> Material
        public var grounded: Bool
        public init(lo: V3, hi: V3, grounded: Bool = false, sdf: @escaping (V3) -> Double,
                    region: ((V3, V3) -> Int32)? = nil, material: ((Int32, V3, V3) -> Material)? = nil) {
            self.lo = lo; self.hi = hi; self.sdf = sdf; self.grounded = grounded
            self.region = region ?? { _, _ in 0 }
            self.material = material ?? { _, _, _ in .plain }
        }
    }
    public private(set) var parts: [Part] = []
    public private(set) var lo = V3(repeating: 1e9), hi = V3(repeating: -1e9)
    public var groundPlane: Double? = 0
    public init() {}
    /// Adds a part; a region closure returning 0 gets the part's own default region (part i, kind 0).
    @discardableResult public func add(_ p: Part) -> Int {
        parts.append(p)
        lo = V3(min(lo.x, p.lo.x), min(lo.y, p.lo.y), min(lo.z, p.lo.z)); hi = V3(max(hi.x, p.hi.x), max(hi.y, p.hi.y), max(hi.z, p.hi.z))
        return parts.count - 1
    }
    public var bounds: (lo: V3, hi: V3) { (lo, hi) }
    public var partCount: Int { parts.count }
    public var groundZ: Double? { groundPlane }
    public func sceneSDF(_ p: V3) -> (Double, Int) {
        var best = 1e9, idx = -1
        for i in 0..<parts.count {
            if boxDist(p, parts[i].lo, parts[i].hi) >= best { continue }
            let d = parts[i].sdf(p)
            if d < best { best = d; idx = i }
        }
        return (best, idx)
    }
    public func partSDF(_ i: Int, _ p: V3) -> Double { parts[i].sdf(p) }
    public func subID(_ i: Int, _ p: V3, _ n: V3) -> Int32 {
        let r = parts[i].region(p, n)
        return r == 0 ? SurfaceID.make(i, 0) : r
    }
    public func material(_ id: Int32, _ p: V3, _ n: V3) -> Material {
        let i = SurfaceID.part(id)
        return i >= 0 && i < parts.count ? parts[i].material(id, p, n) : .plain
    }
    public func grounded(_ i: Int) -> Bool { parts[i].grounded }
}

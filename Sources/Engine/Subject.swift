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

/// A subject made of closures: the quickest way to write one shape, a few parts, no class. Parts are numbered in the
/// order given; add them all before drawing. It draws close to the speed of a class subject (see README,
/// Performance); keep the closures' captures strong (`[unowned x]` or `[weak x]` costs a reference count on every
/// call, from every thread).
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

    /// One part's closures, kept alive by the subject (`owners`).
    @usableFromInline final class Closures {
        @usableFromInline let sdf: (V3) -> Double
        @usableFromInline let region: (V3, V3) -> Int32
        @usableFromInline let material: (Int32, V3, V3) -> Material
        init(_ p: Part) { sdf = p.sdf; region = p.region; material = p.material }
    }
    /// A part as the march reads it: its box and its closures, unretained.
    @usableFromInline struct Slot {
        @usableFromInline var lo: V3, hi: V3
        @usableFromInline var closures: Unmanaged<Closures>
    }
    /// The slots, in plain memory behind a `let` pointer. A render calls the distance millions of times from every
    /// core. Read from the parts array, each call retained and released the array's buffer and the closure's context;
    /// those shared reference counts, bounced between the cores, made a ShapeSubject about 100 times slower than the
    /// same shape as a class. Read from here, a call costs no reference count and no exclusivity check.
    @usableFromInline struct Table {
        @usableFromInline var count: Int
        @usableFromInline var slots: UnsafeMutablePointer<Slot>?
    }
    @usableFromInline let table: UnsafeMutablePointer<Table>
    private var owners: [Closures] = []

    public private(set) var parts: [Part] = []
    public private(set) var lo = V3(repeating: 1e9), hi = V3(repeating: -1e9)
    public var groundPlane: Double? = 0
    public init() {
        table = .allocate(capacity: 1)
        table.initialize(to: Table(count: 0, slots: nil))
    }
    deinit {
        table.pointee.slots?.deallocate()
        table.deinitialize(count: 1)
        table.deallocate()
    }
    /// Adds a part; a region closure returning 0 gets the part's own default region (part i, kind 0). Not while the
    /// subject is being drawn.
    @discardableResult public func add(_ p: Part) -> Int {
        parts.append(p)
        lo = V3(min(lo.x, p.lo.x), min(lo.y, p.lo.y), min(lo.z, p.lo.z)); hi = V3(max(hi.x, p.hi.x), max(hi.y, p.hi.y), max(hi.z, p.hi.z))
        let c = Closures(p)
        owners.append(c)
        let n = parts.count
        let slots = UnsafeMutablePointer<Slot>.allocate(capacity: n)
        if let old = table.pointee.slots { slots.initialize(from: old, count: n - 1); old.deallocate() }
        (slots + (n - 1)).initialize(to: Slot(lo: p.lo, hi: p.hi, closures: Unmanaged.passUnretained(c)))
        table.pointee = Table(count: n, slots: slots)
        return n - 1
    }
    public var bounds: (lo: V3, hi: V3) { (lo, hi) }
    public var partCount: Int { parts.count }
    public var groundZ: Double? { groundPlane }
    @inlinable public func sceneSDF(_ p: V3) -> (Double, Int) {
        var best = 1e9, idx = -1
        let t = table.pointee
        guard let s = t.slots else { return (best, idx) }
        for i in 0..<t.count {
            let slot = s[i]
            if boxDist(p, slot.lo, slot.hi) >= best { continue }
            let d = slot.closures._withUnsafeGuaranteedRef { $0.sdf(p) }
            if d < best { best = d; idx = i }
        }
        return (best, idx)
    }
    @inlinable public func partSDF(_ i: Int, _ p: V3) -> Double {
        table.pointee.slots![i].closures._withUnsafeGuaranteedRef { $0.sdf(p) }
    }
    @inlinable public func subID(_ i: Int, _ p: V3, _ n: V3) -> Int32 {
        let r = table.pointee.slots![i].closures._withUnsafeGuaranteedRef { $0.region(p, n) }
        return r == 0 ? SurfaceID.make(i, 0) : r
    }
    @inlinable public func material(_ id: Int32, _ p: V3, _ n: V3) -> Material {
        let i = SurfaceID.part(id)
        let t = table.pointee
        return i >= 0 && i < t.count ? t.slots![i].closures._withUnsafeGuaranteedRef { $0.material(id, p, n) } : .plain
    }
    public func grounded(_ i: Int) -> Bool { parts[i].grounded }
}

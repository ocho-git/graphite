// SDF.swift: a small library of signed-distance primitives and operators to build subjects from. Distances are
// negative inside, positive outside. 3D primitives are centred at the origin unless they take end points; move and turn
// the point instead of the shape (rotX/rotY/rotZ, or a frame of your own).
import Foundation

// MARK: - 3D primitives

@inlinable public func sdSphere(_ p: V3, _ r: Double) -> Double { len3(p) - r }

/// An ellipsoid with radii r (iq's bound: exact near the surface, a slight underestimate away from it).
@inlinable public func sdEllipsoid(_ p: V3, _ r: V3) -> Double {
    let k0 = len3(p / r), k1 = len3(p / (r * r))
    return k1 < 1e-12 ? -min(r.x, min(r.y, r.z)) : k0 * (k0 - 1) / k1
}

/// A box of half-size b.
@inlinable public func sdBox(_ p: V3, _ b: V3) -> Double {
    let q = V3(abs(p.x), abs(p.y), abs(p.z)) - b
    return len3(V3(max(q.x, 0), max(q.y, 0), max(q.z, 0))) + min(max(q.x, max(q.y, q.z)), 0)
}

/// A box of half-size b with its edges rounded by r.
@inlinable public func sdRoundBox(_ p: V3, _ b: V3, _ r: Double) -> Double { sdBox(p, b - r) - r }

/// A capsule from a to b, radius r.
@inlinable public func sdCapsule(_ p: V3, _ a: V3, _ b: V3, _ r: Double) -> Double {
    let pa = p - a, ba = b - a
    let h = clampd(dot3(pa, ba) / max(dot3(ba, ba), 1e-12), 0, 1)
    return len3(pa - ba * h) - r
}

/// The position along a segment a→b (0…1) nearest to p.
@inlinable public func segT(_ p: V3, _ a: V3, _ b: V3) -> Double {
    let ba = b - a; return clampd(dot3(p - a, ba) / max(dot3(ba, ba), 1e-12), 0, 1)
}

/// A tapered tube (iq's exact round cone): radius r1 at a, r2 at b, rounded ends. Good for limbs, stems, branches.
@inlinable public func sdRoundCone(_ p: V3, _ a: V3, _ b: V3, _ r1: Double, _ r2: Double) -> Double {
    let ba = b - a
    let l2 = dot3(ba, ba), rr = r1 - r2, a2 = l2 - rr * rr, il2 = 1 / max(l2, 1e-12)
    let pa = p - a
    let y = dot3(pa, ba), z = y - l2
    let xv = pa * l2 - ba * y
    let x2 = dot3(xv, xv), y2 = y * y * l2, z2 = z * z * l2
    let k = (rr >= 0 ? 1.0 : -1.0) * rr * rr * x2
    if (z >= 0 ? 1.0 : -1.0) * a2 * z2 > k { return (x2 + z2).squareRoot() * il2 - r2 }
    if (y >= 0 ? 1.0 : -1.0) * a2 * y2 < k { return (x2 + y2).squareRoot() * il2 - r1 }
    return ((max(x2 * a2 * il2, 0)).squareRoot() + y * rr) * il2 - r1
}

/// A capsule whose radius runs linearly from ra to rb (approximate; fine for thin parts: legs, toes, twigs).
@inlinable public func sdTaperedCapsule(_ p: V3, _ a: V3, _ b: V3, _ ra: Double, _ rb: Double) -> Double {
    let pa = p - a, ba = b - a
    let h = clampd(dot3(pa, ba) / max(dot3(ba, ba), 1e-12), 0, 1)
    return len3(pa - ba * h) - mixd(ra, rb, h)
}

/// A tapered cylinder cut flat at both ends (a sawn post, a pruned twig): radius ra at a, rb at b.
@inlinable public func sdCappedCone(_ p: V3, _ a: V3, _ b: V3, _ ra: Double, _ rb: Double) -> Double {
    let ba = b - a, L = len3(ba), d = ba / L
    let pa = p - a
    let u = dot3(pa, d)
    let rho = len3(pa - d * u)
    let dx = rho - mixd(ra, rb, clampd(u / L, 0, 1)), dy = max(-u, u - L)
    return min(max(dx, dy), 0) + len2(V2(max(dx, 0), max(dy, 0)))
}

/// A torus round the z axis: ring radius R, tube radius r.
@inlinable public func sdTorus(_ p: V3, _ R: Double, _ r: Double) -> Double { len2(V2(len2(V2(p.x, p.y)) - R, p.z)) - r }

/// A plane through the point `o` with the unit normal n (negative below).
@inlinable public func sdPlane(_ p: V3, _ o: V3, _ n: V3) -> Double { dot3(p - o, n) }

/// A vertical prism: the 2D distance `d2` of its plan, from height z0 to z1 (exact at the edges).
@inlinable public func extrude(_ d2: Double, _ z: Double, _ z0: Double, _ z1: Double) -> Double {
    let dz = max(z0 - z, z - z1)
    return len2(V2(max(d2, 0), max(dz, 0))) + min(max(d2, dz), 0)
}

/// A vertical regular prism (or a cylinder when sides < 3): apothem, rounded corners, from z0 to z1.
@inlinable public func sdPrism(_ p: V3, sides: Int, apothem: Double, corner: Double = 0, z0: Double, z1: Double) -> Double {
    extrude(sdRegularPolygon(V2(p.x, p.y), sides: sides, apothem: apothem, corner: corner), p.z, z0, z1)
}

// MARK: - 2D shapes (for plans, profiles and flat studies)

/// Folds a plan point into the first sector of a regular polygon (x along the face normal).
@inlinable public func polygonFold(_ q: V2, _ sides: Int) -> V2 {
    if sides < 3 { return V2(len2(q), 0) }
    let sector = 2 * Double.pi / Double(sides)
    let a = atan2(q.y, q.x)
    let f = a - (a / sector).rounded() * sector
    let r = len2(q)
    return V2(r * cos(f), r * sin(f))
}

/// A regular polygon (a circle when sides < 3) with a face on the +x axis, its corners rounded by `corner`.
@inlinable public func sdRegularPolygon(_ q: V2, sides: Int, apothem: Double, corner: Double = 0) -> Double {
    if sides < 3 { return len2(q) - apothem }
    let f = polygonFold(q, sides)
    let r = apothem - corner
    let h = r * tan(Double.pi / Double(sides))
    let d = f.x > r ? len2(V2(f.x - r, max(abs(f.y) - h, 0))) : f.x - r
    return d - corner
}

/// An ellipse with radii r (2D bound, as sdEllipsoid).
@inlinable public func sdEllipse(_ p: V2, _ r: V2) -> Double {
    let k0 = len2(p / r), k1 = len2(p / (r * r))
    return k1 < 1e-12 ? -min(r.x, r.y) : k0 * (k0 - 1) / k1
}

/// A rectangle of half-size b with corners rounded by r.
@inlinable public func sdRoundRect(_ p: V2, _ b: V2, _ r: Double) -> Double {
    let k = V2(abs(p.x), abs(p.y)) - b + r
    return len2(V2(max(k.x, 0), max(k.y, 0))) + min(max(k.x, k.y), 0) - r
}

/// A closed polygon through `v` (negative inside).
public func sdPolygon(_ p: V2, _ v: [V2]) -> Double {
    var dd = 1e18, s = 1.0
    let n = v.count
    var j = n - 1
    for i in 0..<n {
        let e = v[j] - v[i], w = p - v[i]
        let b = w - e * clampd(dot2(w, e) / max(dot2(e, e), 1e-18), 0, 1)
        dd = min(dd, dot2(b, b))
        let c1 = p.y >= v[i].y, c2 = p.y < v[j].y, c3 = e.x * w.y > e.y * w.x
        if (c1 && c2 && c3) || (!c1 && !c2 && !c3) { s = -s }
        j = i
    }
    return s * dd.squareRoot()
}

// MARK: - Operators

/// Smooth union (polynomial smooth minimum): the two shapes melt into each other over about k.
@inlinable @inline(__always) public func smoothUnion(_ a: Double, _ b: Double, _ k: Double) -> Double {
    let h = clampd(0.5 + 0.5 * (b - a) / k, 0, 1); return mixd(b, a, h) - k * h * (1 - h)
}
/// Smooth intersection (polynomial smooth maximum).
@inlinable @inline(__always) public func smoothIntersection(_ a: Double, _ b: Double, _ k: Double) -> Double { -smoothUnion(-a, -b, k) }
/// Smooth subtraction: a with b carved out, the cut's edge softened over k.
@inlinable @inline(__always) public func smoothSubtraction(_ a: Double, _ b: Double, _ k: Double) -> Double { smoothIntersection(a, -b, k) }
/// The same smooth minimum in its quadratic form (k <= 0: a plain min); used by the primitive scene's groups.
@inlinable @inline(__always) public func smoothUnionQuadratic(_ a: Double, _ b: Double, _ k: Double) -> Double {
    if k <= 0 { return min(a, b) }
    let h = max(k - abs(a - b), 0) / k
    return min(a, b) - h * h * k * 0.25
}
/// An intersection whose convex edge is rounded with radius r (a worn arris, a bullnose).
@inlinable @inline(__always) public func roundedIntersection(_ a: Double, _ b: Double, _ r: Double) -> Double {
    min(max(a, b), 0) + len2(V2(max(a + r, 0), max(b + r, 0))) - r
}
/// A shell of thickness t round a surface (a cup's wall, a bowl).
@inlinable @inline(__always) public func shell(_ d: Double, _ t: Double) -> Double { abs(d) - t / 2 }

// MARK: - Curves

/// A closed Catmull-Rom spline through the control points, `per` samples per span.
public func closedSpline(_ c: [V2], per: Int = 8) -> [V2] {
    var out: [V2] = []
    let n = c.count
    for i in 0..<n {
        let p0 = c[(i - 1 + n) % n], p1 = c[i], p2 = c[(i + 1) % n], p3 = c[(i + 2) % n]
        for k in 0..<per {
            let t = Double(k) / Double(per), t2 = t * t, t3 = t2 * t
            out.append(((p1 * 2) + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5)
        }
    }
    return out
}

/// An open Catmull-Rom spline through the points (ends repeated).
public func openSpline(_ c: [V2], per: Int = 8) -> [V2] {
    guard c.count >= 2 else { return c }
    var out: [V2] = []
    let n = c.count
    for i in 0..<(n - 1) {
        let p0 = c[max(i - 1, 0)], p1 = c[i], p2 = c[i + 1], p3 = c[min(i + 2, n - 1)]
        for k in 0..<per {
            let t = Double(k) / Double(per), t2 = t * t, t3 = t2 * t
            out.append(((p1 * 2) + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5)
        }
    }
    out.append(c[n - 1])
    return out
}

/// openSpline in 3D.
public func openSpline3(_ c: [V3], per: Int = 8) -> [V3] {
    guard c.count >= 2 else { return c }
    var out: [V3] = []
    let n = c.count
    for i in 0..<(n - 1) {
        let p0 = c[max(i - 1, 0)], p1 = c[i], p2 = c[i + 1], p3 = c[min(i + 2, n - 1)]
        for k in 0..<per {
            let t = Double(k) / Double(per), t2 = t * t, t3 = t2 * t
            out.append(((p1 * 2) + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5)
        }
    }
    out.append(c[n - 1])
    return out
}

/// The bounding box of a set of 2D points.
public func bounds2(_ v: [V2]) -> (V2, V2) {
    var lo = V2(1e18, 1e18), hi = V2(-1e18, -1e18)
    for p in v { lo = V2(min(lo.x, p.x), min(lo.y, p.y)); hi = V2(max(hi.x, p.x), max(hi.y, p.y)) }
    return (lo, hi)
}

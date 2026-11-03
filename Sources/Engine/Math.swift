// Math.swift: the small math every part of the engine shares: vectors, smooth steps, value noise and a seeded random
// generator. Everything is Double and deterministic: the same seed gives the same drawing, bit for bit.
import Foundation

public typealias V2 = SIMD2<Double>
public typealias V3 = SIMD3<Double>

@inlinable @inline(__always) public func clampd(_ x: Double, _ a: Double, _ b: Double) -> Double { x < a ? a : (x > b ? b : x) }
/// Hermite smooth step from a to b (b may be below a: the step then falls).
@inlinable @inline(__always) public func sstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clampd((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)
}
@inlinable @inline(__always) public func mixd(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
@inlinable @inline(__always) public func sq(_ x: Double) -> Double { x * x }
@inlinable @inline(__always) public func len2(_ v: V2) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }
@inlinable @inline(__always) public func len3(_ v: V3) -> Double { (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot() }
@inlinable @inline(__always) public func dot2(_ a: V2, _ b: V2) -> Double { a.x * b.x + a.y * b.y }
@inlinable @inline(__always) public func dot3(_ a: V3, _ b: V3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
@inlinable @inline(__always) public func norm2(_ v: V2) -> V2 { v / max(len2(v), 1e-12) }
@inlinable @inline(__always) public func norm3(_ v: V3) -> V3 { v / max(len3(v), 1e-12) }
@inlinable @inline(__always) public func cross3(_ a: V3, _ b: V3) -> V3 {
    V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}
@inlinable @inline(__always) public func fract(_ x: Double) -> Double { x - x.rounded(.down) }
/// Rotates a 2D point by `a` radians (counter-clockwise).
@inlinable @inline(__always) public func rot2(_ p: V2, _ a: Double) -> V2 {
    let c = cos(a), s = sin(a); return V2(c * p.x - s * p.y, s * p.x + c * p.y)
}
@inlinable @inline(__always) public func rotX(_ p: V3, _ a: Double) -> V3 { let c = cos(a), s = sin(a); return V3(p.x, c * p.y - s * p.z, s * p.y + c * p.z) }
@inlinable @inline(__always) public func rotY(_ p: V3, _ a: Double) -> V3 { let c = cos(a), s = sin(a); return V3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z) }
@inlinable @inline(__always) public func rotZ(_ p: V3, _ a: Double) -> V3 { let c = cos(a), s = sin(a); return V3(c * p.x - s * p.y, s * p.x + c * p.y, p.z) }
/// Rotates v about the unit axis k by angle a (Rodrigues).
@inlinable @inline(__always) public func rotAxis(_ v: V3, _ k: V3, _ a: Double) -> V3 {
    let c = cos(a), s = sin(a); return v * c + cross3(k, v) * s + k * (dot3(k, v) * (1 - c))
}
/// A unit vector perpendicular to n.
@inlinable public func perp3(_ n: V3) -> V3 { abs(n.z) < 0.9 ? norm3(cross3(n, V3(0, 0, 1))) : norm3(cross3(n, V3(1, 0, 0))) }
/// Two unit vectors perpendicular to `d` and to each other.
@inlinable public func basis(_ d: V3) -> (V3, V3) {
    let a = abs(d.z) < 0.9 ? V3(0, 0, 1) : V3(1, 0, 0)
    let e1 = norm3(cross3(d, a))
    return (e1, cross3(d, e1))
}

// MARK: - Hashes and value noise

@inlinable @inline(__always) public func hash21(_ p: V2) -> Double { fract(sin(p.x * 127.1 + p.y * 311.7) * 43758.5453123) }
@inlinable @inline(__always) public func hash31(_ p: V3) -> Double { fract(sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453123) }

/// Smooth 2D value noise in 0…1 (quintic fade).
@inlinable @inline(__always) public func vnoise(_ p: V2) -> Double {
    let i = V2(p.x.rounded(.down), p.y.rounded(.down)), f = p - i
    let u = f * f * f * (f * (f * 6 - 15) + 10)
    let a = hash21(i), b = hash21(i + V2(1, 0)), c = hash21(i + V2(0, 1)), d = hash21(i + V2(1, 1))
    return mixd(mixd(a, b, u.x), mixd(c, d, u.x), u.y)
}

/// Smooth 3D value noise in 0…1 (quintic fade).
@inlinable @inline(__always) public func vnoise3(_ p: V3) -> Double {
    let i = V3(p.x.rounded(.down), p.y.rounded(.down), p.z.rounded(.down)), f = p - i
    let u = f * f * f * (f * (f * 6 - 15) + 10)
    let a = hash31(i), b = hash31(i + V3(1, 0, 0)), c = hash31(i + V3(0, 1, 0)), d = hash31(i + V3(1, 1, 0))
    let e = hash31(i + V3(0, 0, 1)), f2 = hash31(i + V3(1, 0, 1)), g = hash31(i + V3(0, 1, 1)), h = hash31(i + V3(1, 1, 1))
    let x0 = mixd(mixd(a, b, u.x), mixd(c, d, u.x), u.y), x1 = mixd(mixd(e, f2, u.x), mixd(g, h, u.x), u.y)
    return mixd(x0, x1, u.z)
}

// MARK: - Random numbers

/// A seeded generator (splitmix64). Every hand-like irregularity of the drawing comes from one of these, so a seed
/// fixes the drawing.
public struct Rng {
    public var s: UInt64
    @inlinable public init(_ seed: UInt64) { s = seed &* 0x9E3779B97F4A7C15 &+ 0x1234567 }
    @inlinable public mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// Uniform in 0 ..< 1.
    @inlinable public mutating func uni() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// Uniform in a ..< b.
    @inlinable public mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * uni() }
    /// Standard normal (Box–Muller).
    @inlinable public mutating func gauss() -> Double { let u = max(uni(), 1e-12), v = uni(); return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v) }
    @inlinable public mutating func chance(_ p: Double) -> Bool { uni() < p }
}

// MARK: - Boxes and rays

/// The parameter range where a ray crosses an axis-aligned box (nil: it misses).
@inlinable @inline(__always) public func rayBox(_ ro: V3, _ rd: V3, _ lo: V3, _ hi: V3) -> (Double, Double)? {
    let inv = V3(1 / rd.x, 1 / rd.y, 1 / rd.z)
    let t0 = (lo - ro) * inv, t1 = (hi - ro) * inv
    let tmin = max(min(t0.x, t1.x), min(t0.y, t1.y), min(t0.z, t1.z))
    let tmax = min(max(t0.x, t1.x), max(t0.y, t1.y), max(t0.z, t1.z))
    return tmax >= max(tmin, 0) ? (max(tmin, 0), tmax) : nil
}

/// Distance from a point to an axis-aligned box (0 inside).
@inlinable @inline(__always) public func boxDist(_ p: V3, _ lo: V3, _ hi: V3) -> Double {
    let dx = max(lo.x - p.x, 0, p.x - hi.x), dy = max(lo.y - p.y, 0, p.y - hi.y), dz = max(lo.z - p.z, 0, p.z - hi.z)
    return (dx * dx + dy * dy + dz * dz).squareRoot()
}

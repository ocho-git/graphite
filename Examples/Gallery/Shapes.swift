// Shapes.swift: what the gallery's subjects are built from: lathe profiles (turned vessels, a chess piece), turned
// frames, points on a sphere, and settling one object onto others (a pile of pebbles).
import Foundation

/// A radius profile r(z) over 0…H: a Catmull-Rom curve through radii at evenly spaced heights, with its slope.
struct Profile {
    let rs: [Double]
    let H: Double
    init(height: Double, knots n: Int, _ f: (Double) -> Double) {
        rs = (0..<n).map { f(Double($0) / Double(n - 1)) }
        H = height
    }
    @inline(__always) func at(_ z: Double) -> (r: Double, dr: Double) {
        let n = rs.count
        let h = H / Double(n - 1)
        let zc = clampd(z, 0, H)
        var i = Int(zc / h)
        if i >= n - 1 { i = n - 2 }
        let u = zc / h - Double(i)
        let p0 = rs[max(i - 1, 0)], p1 = rs[i], p2 = rs[i + 1], p3 = rs[min(i + 2, n - 1)]
        let a = 2 * p1, b = p2 - p0
        let c = 2 * p0 - 5 * p1 + 4 * p2 - p3
        let d = 3 * p1 - p0 - 3 * p2 + p3
        let r = 0.5 * (a + u * (b + u * (c + u * d)))
        let dr = 0.5 * (b + u * (2 * c + u * 3 * d)) / h
        return (max(r, 0.01), dr)
    }
    /// A safe outer radius (the curve may overshoot its knots a little).
    var maxR: Double { (rs.max() ?? 0) * 1.15 + 0.02 }
}

/// A solid of revolution round the z axis from z0 to z0 + H (the side's distance corrected for its slope).
@inline(__always) func latheSolid(_ p: V3, _ pr: Profile, z0: Double = 0) -> Double {
    let rho = len2(V2(p.x, p.y)), z = p.z - z0
    let (r, dr) = pr.at(z)
    let side = (rho - r) / (1 + dr * dr).squareRoot()
    let dz = max(-z, z - pr.H)
    return len2(V2(max(side, 0), max(dz, 0))) + min(max(side, dz), 0)
}

/// A turned vessel: the solid hollowed out above its floor, open at the top, the rim rounded.
@inline(__always) func vessel(_ p: V3, _ pr: Profile, wall: Double, floor: Double, z0: Double = 0) -> Double {
    let outer = latheSolid(p, pr, z0: z0)
    let rho = len2(V2(p.x, p.y)), z = p.z - z0
    let (r, dr) = pr.at(z)
    let side = (rho - (r - wall)) / (1 + dr * dr).squareRoot()
    let dz = floor - z
    let inner = len2(V2(max(side, 0), max(dz, 0))) + min(max(side, dz), 0)
    return roundedIntersection(outer, -inner, wall * 0.35)
}

/// Unit vectors spread over a sphere (Fibonacci).
func fibSphere(_ n: Int) -> [V3] {
    let g = Double.pi * (3 - 5.0.squareRoot())
    return (0..<n).map { i in
        let z = 1 - 2 * (Double(i) + 0.5) / Double(n)
        let r = (1 - z * z).squareRoot()
        let a = g * Double(i)
        return V3(r * cos(a), r * sin(a), z)
    }
}

/// Lowers an object (points on its surface, relative to its origin) at plan position xy onto the ground (z = 0) and
/// whatever `existing` describes: the lowest origin height at which none of its points is inside.
func settle(_ pts: [V3], xy: V2, existing: (V3) -> Double) -> Double {
    let lowest = pts.map(\.z).min() ?? 0
    func collides(_ z: Double) -> Bool { pts.contains { existing(V3(xy.x + $0.x, xy.y + $0.y, z + $0.z)) < -0.003 } }
    var lo = -lowest
    if !collides(lo) { return lo }
    var hi = lo + 3
    for _ in 0..<32 {
        let m = (lo + hi) / 2
        if collides(m) { lo = m } else { hi = m }
    }
    return hi
}

/// A turned frame: yaw about z, then a tilt about the turned x axis; or any axis with a spin about it.
struct Frame {
    var ex: V3, ey: V3, ez: V3
    init(yaw: Double, tilt: Double = 0) {
        ex = V3(cos(yaw), sin(yaw), 0)
        let ey0 = V3(-sin(yaw), cos(yaw), 0)
        ey = ey0 * cos(tilt) + V3(0, 0, 1) * sin(tilt)
        ez = cross3(ex, ey)
    }
    init(axis: V3, spin: Double) {
        ez = norm3(axis)
        let (a, b) = basis(ez)
        ex = a * cos(spin) + b * sin(spin)
        ey = cross3(ez, ex)
    }
    @inline(__always) func local(_ d: V3) -> V3 { V3(dot3(d, ex), dot3(d, ey), dot3(d, ez)) }
    @inline(__always) func world(_ q: V3) -> V3 { ex * q.x + ey * q.y + ez * q.z }
}

/// The box round a turned box of half-size h.
func turnedBox(_ c: V3, _ f: Frame, _ h: V3, pad: Double = 0.02) -> (V3, V3) {
    var e = V3(0, 0, 0)
    for k in 0..<3 { e[k] = abs(f.ex[k]) * h.x + abs(f.ey[k]) * h.y + abs(f.ez[k]) * h.z + pad }
    return (c - e, c + e)
}

/// One of the items, picked with the generator.
func choose<T>(_ a: [T], _ rng: inout Rng) -> T { a[min(Int(rng.uni() * Double(a.count)), a.count - 1)] }

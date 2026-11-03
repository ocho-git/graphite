// Nature.swift: mushrooms (gills and spots are regions), a boulder with its stones (faceted or rounded, sometimes
// mossy), a pile of pebbles settled one on another, and a cluster of crystals on a rock, each crystal a single region
// whose facets are drawn as creases.
import Foundation

// MARK: - Mushrooms

enum ShroomKind: Int { case stem = 0, cap, gill, spot, under }

func makeMushrooms(_ rng: inout Rng) -> Piece {
    let s = ShapeSubject()
    let count = 1 + Int(rng.uni() * 3)
    let spotted = rng.chance(0.45)
    let capValue = spotted ? rng.range(0.35, 0.55) : rng.range(0.05, 0.4)
    for j in 0..<count {
        let scale = j == 0 ? 1.0 : rng.range(0.45, 0.8)
        let base = j == 0 ? V2(0, 0) : V2(rng.range(-0.38, 0.38), rng.range(-0.3, 0.3))
        let hs = rng.range(0.4, 0.75) * scale, rs = rng.range(0.045, 0.085) * scale
        let R = rng.range(0.2, 0.36) * scale, Hc = R * rng.range(0.35, 0.85)
        let lean = V2(rng.range(-0.2, 0.2), rng.range(-0.2, 0.2)) * hs
        let b0 = V3(base.x, base.y, 0), top = V3(base.x + lean.x, base.y + lean.y, hs)
        let mid = (b0 + top) / 2 + V3(rng.range(-0.03, 0.03), rng.range(-0.03, 0.03), 0)
        let tilt = V3(rng.range(-0.25, 0.25), rng.range(-0.25, 0.25), 0)
        let fr = Frame(axis: norm3(V3(lean.x, lean.y, hs) / hs + tilt), spin: rng.range(0, 6.3))
        let nGills = 34 + Int(rng.uni() * 26)
        let spots: [V3] = spotted ? (0..<16).map { _ in norm3(V3(rng.gauss(), rng.gauss(), abs(rng.gauss()) + 0.5)) } : []
        let spotCos = cos(rng.range(0.12, 0.2))
        let bulb = rs * rng.range(1.1, 1.5)
        let stemPart = s.parts.count, capPart = stemPart + 1
        let lo = V3(min(b0.x, top.x), min(b0.y, top.y), 0) - bulb - 0.02
        let hi = V3(max(b0.x, top.x), max(b0.y, top.y), top.z) + bulb + 0.04
        s.add(.init(lo: lo, hi: hi, grounded: true,
                    sdf: { p in
                        let d = smoothUnion(sdRoundCone(p, b0, mid, bulb, rs), sdRoundCone(p, mid, top + fr.ez * 0.03, rs, rs * 0.85), 0.02)
                        return max(d, -p.z)
                    },
                    region: { _, _ in SurfaceID.make(stemPart, ShroomKind.stem.rawValue) },
                    material: { _, _, _ in Material(value: 0.03, stipple: 0.5) }))
        // the cap, in its own frame (z up its axis, the stem's top at the origin)
        let under: (Double) -> Double = { rho in Hc * 0.32 * sq(rho / R) }
        let capSDF: (V3) -> Double = { p in
            let q = fr.local(p - top)
            let e = sdEllipsoid(q - V3(0, 0, -0.1 * Hc), V3(R, R, Hc))
            let rho = len2(V2(q.x, q.y))
            return roundedIntersection(e, (under(rho) - q.z) / 1.15, 0.008)
        }
        let ext = R + Hc + 0.04
        s.add(.init(lo: top - ext, hi: top + ext,
                    sdf: { p in max(capSDF(p), -p.z) },
                    region: { p, n in
                        let q = fr.local(p - top)
                        let rho = len2(V2(q.x, q.y))
                        if dot3(n, fr.ez) < -0.15 && q.z < under(rho) + 0.03 * R {
                            if rho < rs * 1.5 { return SurfaceID.make(capPart, ShroomKind.under.rawValue) }
                            let a = (atan2(q.y, q.x) + Double.pi) / (2 * Double.pi)
                            return SurfaceID.make(capPart, ShroomKind.gill.rawValue, Int(a * Double(nGills)) % nGills)
                        }
                        if !spots.isEmpty {
                            let u = norm3(V3(q.x / R, q.y / R, (q.z + 0.1 * Hc) / Hc))
                            for (k, sp) in spots.enumerated() where dot3(u, sp) > spotCos {
                                return SurfaceID.make(capPart, ShroomKind.spot.rawValue, k)
                            }
                        }
                        return SurfaceID.make(capPart, ShroomKind.cap.rawValue)
                    },
                    material: { id, _, _ in
                        switch ShroomKind(rawValue: SurfaceID.kind(id)) ?? .cap {
                        case .gill: return Material(value: 0.1, minTone: 0.38, stipple: 0)
                        case .under: return Material(value: 0.1, minTone: 0.4, stipple: 0)
                        case .spot: return Material(value: -0.6, shading: 0.6, stipple: 0)
                        default: return Material(value: capValue, stipple: 0.25)
                        }
                    }))
    }
    var m = piece(s)
    m.options.rules.floor = [ShroomKind.gill.rawValue: 0.26, ShroomKind.spot.rawValue: 0.5]
    m.angles = [.front]
    m.frontEye = (0.15, 0.45)
    m.options.march.stepScale = 0.75
    return m
}

// MARK: - Boulder

func fbmRock(_ p: V3, _ seed: Double) -> Double {
    let w = p * 2.6 + seed
    return (vnoise3(w) * 2 - 1) + 0.45 * (vnoise3(w * 2.3 + 5) * 2 - 1) + 0.18 * (vnoise3(w * 5.9 + 9) * 2 - 1)
}

func rockSDF(c: V3, r: V3, yaw: Double, seed: Double, cuts: [(V3, Double)], amp: Double) -> (V3) -> Double {
    return { p in
        let q = rotZ(p - c, -yaw)
        var d = sdEllipsoid(q, r)
        for (n, o) in cuts { d = max(d, dot3(q, n) - o) }
        if d < amp * 4 { d += amp * fbmRock(p, seed) } else { d -= amp * 1.63 }
        return max(d, -p.z)
    }
}

func randomCuts(_ rng: inout Rng, _ r: V3, count: Int) -> [(V3, Double)] {
    (0..<count).map { _ in
        let n = norm3(V3(rng.gauss(), rng.gauss(), rng.gauss() * 0.6 + 0.35))
        let h = (sq(r.x * n.x) + sq(r.y * n.y) + sq(r.z * n.z)).squareRoot()
        return (n, h * rng.range(0.7, 0.9))
    }
}

func makeBoulder(_ rng: inout Rng) -> Piece {
    let s = ShapeSubject()
    let faceted = rng.chance(0.5), mossy = rng.chance(0.5)
    let rockV = rng.range(0.06, 0.3), stip = rng.range(1.1, 2.0)
    let mossKind = 1
    func addRock(_ c: V3, _ r: V3, amp: Double, cuts: Int, grounded: Bool) {
        let part = s.parts.count
        let seed = rng.range(0, 50)
        let sdf = rockSDF(c: c, r: r, yaw: rng.range(0, 6.3), seed: seed, cuts: faceted ? randomCuts(&rng, r, count: cuts) : [], amp: amp)
        let e = max(r.x, r.y, r.z) + amp * 2 + 0.02
        s.add(.init(lo: V3(c.x - e, c.y - e, 0), hi: V3(c.x + e, c.y + e, c.z + e), grounded: grounded, sdf: sdf,
                    region: { p, n in
                        if mossy && n.z > 0.35 && vnoise3(p * 5 + seed) > 0.6 { return SurfaceID.make(part, mossKind) }
                        return SurfaceID.make(part, 0)
                    },
                    material: { id, _, _ in
                        SurfaceID.kind(id) == mossKind ? Material(value: 0.32, stipple: 2.6) : Material(value: rockV, stipple: stip)
                    }))
    }
    let r = V3(rng.range(0.55, 0.75), rng.range(0.4, 0.55), rng.range(0.35, 0.55))
    let amp = rng.range(0.025, 0.05)
    addRock(V3(0, 0, r.z * rng.range(0.3, 0.6)), r, amp: amp, cuts: 4 + Int(rng.uni() * 5), grounded: true)
    let small = 2 + Int(rng.uni() * 3)
    for _ in 0..<small {
        let k = rng.range(0.14, 0.34)
        let rr = V3(r.x * k, r.y * k * rng.range(0.8, 1.2), r.z * k * rng.range(0.7, 1.1))
        let a = rng.range(-Double.pi, 0.4)   // mostly in front
        let d = r.x * rng.range(1.0, 1.25) + rr.x
        addRock(V3(cos(a) * d, sin(a) * d * 0.9, rr.z * 0.45), rr, amp: amp * k * 1.4, cuts: 4, grounded: true)
    }
    var m = piece(s)
    m.options.march.stepScale = 0.55
    m.options.march.maxSteps = 900
    m.options.rules.floor = [mossKind: 0.3]
    return m
}

// MARK: - Pebbles

func makePebbles(_ rng: inout Rng) -> Piece {
    struct Pebble { var c: V3; var f: Frame; var r: V3; var seed: Double }
    func sdf(_ pb: Pebble, _ p: V3) -> Double {
        sdEllipsoid(pb.f.local(p - pb.c), pb.r) + 0.004 * (vnoise3(p * 11 + pb.seed) * 2 - 1)
    }
    let n = 9 + Int(rng.uni() * 8)
    var sizes = (0..<n).map { _ in rng.range(0.09, 0.2) }
    sizes.sort(by: >)
    var placed: [Pebble] = []
    for a in sizes {
        let r = V3(a, a * rng.range(0.6, 0.95), a * rng.range(0.35, 0.65))
        let f = Frame(yaw: rng.range(0, 6.3), tilt: rng.range(-0.35, 0.35))
        let rad = 0.4 * rng.uni().squareRoot(), ang = rng.range(0, 6.3)
        let xy = V2(cos(ang), sin(ang)) * rad
        let pts = fibSphere(60).map { u in f.world(u * r) }
        let snapshot = placed
        let z = settle(pts, xy: xy, existing: { p in snapshot.reduce(1e9) { min($0, sdf($1, p)) } })
        placed.append(Pebble(c: V3(xy.x, xy.y, z), f: f, r: r, seed: rng.range(0, 40)))
    }
    let s = ShapeSubject()
    for (i, pb) in placed.enumerated() {
        let e = max(pb.r.x, pb.r.y, pb.r.z) + 0.015
        let lowest = fibSphere(60).map { pb.f.world($0 * pb.r).z }.min()! + pb.c.z
        let value = rng.range(-0.15, 0.5), stip = rng.range(0.2, 2.0)
        let vein = rng.chance(0.3)
        let vn = norm3(V3(rng.gauss(), rng.gauss(), rng.gauss())), vo = rng.range(-0.3, 0.3) * pb.r.y, vw = rng.range(0.01, 0.02)
        s.add(.init(lo: pb.c - e, hi: pb.c + e, grounded: lowest < 0.01,
                    sdf: { p in sdf(pb, p) },
                    region: { p, _ in
                        if vein && abs(dot3(pb.f.local(p - pb.c), vn) - vo) < vw { return SurfaceID.make(i, 1) }
                        return SurfaceID.make(i, 0)
                    },
                    material: { id, _, _ in SurfaceID.kind(id) == 1 ? Material(value: -0.6, stipple: 0) : Material(value: value, stipple: stip) }))
    }
    var m = piece(s)
    m.options.rules.floor = [1: 0.35]
    m.options.march.stepScale = 0.8
    return m
}

// MARK: - Crystals

func makeCrystals(_ rng: inout Rng) -> Piece {
    let s = ShapeSubject()
    let baseSeed = rng.range(0, 40)
    let baseR = V3(rng.range(0.38, 0.5), rng.range(0.32, 0.45), rng.range(0.14, 0.22))
    let rock = rockSDF(c: V3(0, 0, baseR.z * 0.35), r: baseR, yaw: rng.range(0, 6.3), seed: baseSeed, cuts: [], amp: 0.03)
    s.add(.init(lo: V3(-baseR.x - 0.08, -baseR.x - 0.08, 0), hi: V3(baseR.x + 0.08, baseR.x + 0.08, baseR.z * 1.4 + 0.08), grounded: true,
                sdf: rock, material: { _, _, _ in Material(value: 0.3, stipple: 1.8) }))
    let count = 5 + Int(rng.uni() * 5)
    let smoky = rng.chance(0.4)
    for k in 0..<count {
        let lead = k == 0
        let o = V3(rng.range(-0.18, 0.18), rng.range(-0.15, 0.15), baseR.z * 0.5)
        let tilt = lead ? rng.range(0, 0.15) : rng.range(0.25, 0.8)
        let az = rng.range(0, 6.3)
        let axis = norm3(V3(cos(az) * sin(tilt), sin(az) * sin(tilt), cos(tilt)))
        let L = lead ? rng.range(0.75, 1.05) : rng.range(0.3, 0.75)
        let w = L * rng.range(0.1, 0.17)
        let th = w * rng.range(1.0, 1.7)
        let f = Frame(axis: axis, spin: rng.range(0, 6.3))
        let nn = (th * th + w * w).squareRoot()
        let part = s.parts.count
        let tipEnd = o + axis * L
        let e = w * 1.3 + 0.03
        let lo = V3(min(o.x, tipEnd.x), min(o.y, tipEnd.y), min(o.z, tipEnd.z)) - e - V3(0, 0, 0.25)
        let hi = V3(max(o.x, tipEnd.x), max(o.y, tipEnd.y), max(o.z, tipEnd.z)) + e
        let dark = smoky && k % 3 == 1
        s.add(.init(lo: lo, hi: hi,
                    sdf: { p in
                        let q = f.local(p - o)
                        let fo = polygonFold(V2(q.x, q.y), 6)
                        let d = max(fo.x - w, (fo.x * th + (q.z - L) * w) / nn, -(q.z + 0.25))
                        return max(d, -p.z)
                    },
                    region: { _, _ in SurfaceID.make(part, 2) },      // one region: its facets are creases
                    material: { _, _, _ in dark ? Material(value: 0.45, stipple: 0) : Material(value: 0.0, shading: 0.85, stipple: 0) }))
    }
    var m = piece(s)
    m.options.march.stepScale = 0.7
    m.options.rules.creaseAngle = 30
    return m
}

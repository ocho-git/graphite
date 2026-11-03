// PrimitiveScene.swift: a subject built from many simple primitives: tapered round cones (wood, stems, culms),
// ellipsoids (foliage masses, buds) and tori (rings, nodes), gathered into groups. A group is one smooth union (a trunk
// and its limbs grow into each other without a seam; a foliage pad is one cloud, roughened by noise); groups meet with
// a plain min, so a line is drawn where one stands in front of another. A uniform grid keeps the march fast with
// thousands of primitives. What is finer than the pencil (twigs, needles, flowers) goes in as 3D strokes and marks.
import Foundation

public enum PrimitiveKind: UInt8 { case cone, ellip, torus }

public struct Primitive {
    public var kind: PrimitiveKind
    /// cone: its two ends; ellipsoid / torus: the centre (a).
    public var a: V3, b: V3
    /// cone: radii at a and b; torus: ring and tube radius.
    public var ra: Double, rb: Double
    /// Ellipsoid / torus frame (the torus's axis is ez).
    public var ex: V3, ey: V3, ez: V3
    /// Ellipsoid radii.
    public var r: V3
    public var group: Int32
    /// Its drawn region.
    public var id: Int32
    /// The most it blends into its group (a twig never swells).
    public var kmax: Double
    public init(kind: PrimitiveKind, a: V3, b: V3 = V3(0, 0, 0), ra: Double = 0, rb: Double = 0, ex: V3 = V3(1, 0, 0), ey: V3 = V3(0, 1, 0),
                ez: V3 = V3(0, 0, 1), r: V3 = V3(1, 1, 1), group: Int32 = 0, id: Int32 = 0, kmax: Double = 1e9) {
        self.kind = kind; self.a = a; self.b = b; self.ra = ra; self.rb = rb; self.ex = ex; self.ey = ey; self.ez = ez; self.r = r
        self.group = group; self.id = id; self.kmax = kmax
    }
}

/// How a group's primitives join, and what finishes its surface.
public struct PrimitiveGroup {
    /// Smooth-union radius.
    public var k: Double
    /// Surface noise (foliage clouds): amplitude and frequency.
    public var amp: Double, freq: Double
    public var seed: Double
    /// A flattened underside (pine pads, maple fans) at floorZ, blended over floorK.
    public var floorZ: Double, floorK: Double
    /// Nothing below the ground (z = 0).
    public var clip: Bool
    /// Gets a ground stroke in an elevation.
    public var grounded: Bool
    /// Cut flat above (a topped culm).
    public var ceilZ: Double
    public init(k: Double = 0, amp: Double = 0, freq: Double = 1, seed: Double = 0, floorZ: Double = -1e9, floorK: Double = 0, clip: Bool = true,
                grounded: Bool = false, ceilZ: Double = 1e9) {
        self.k = k; self.amp = amp; self.freq = freq; self.seed = seed; self.floorZ = floorZ; self.floorK = floorK; self.clip = clip
        self.grounded = grounded; self.ceilZ = ceilZ
    }
}

/// iq's exact round cone: a capsule whose radius runs from r1 at a to r2 at b.
@inlinable @inline(__always) public func roundCone(_ p: V3, _ a: V3, _ b: V3, _ r1: Double, _ r2: Double) -> Double {
    let ba = b - a
    let l2 = max(dot3(ba, ba), 1e-14)
    let rr = r1 - r2
    let a2 = l2 - rr * rr
    let il2 = 1.0 / l2
    let pa = p - a
    let y = dot3(pa, ba)
    let z = y - l2
    let xv = pa * l2 - ba * y
    let x2 = dot3(xv, xv)
    let y2 = y * y * l2
    let z2 = z * z * l2
    let k = (rr > 0 ? 1.0 : rr < 0 ? -1.0 : 0) * rr * rr * x2
    if (z > 0 ? 1.0 : z < 0 ? -1.0 : 0) * a2 * z2 > k { return (x2 + z2).squareRoot() * il2 - r2 }
    if (y > 0 ? 1.0 : y < 0 ? -1.0 : 0) * a2 * y2 < k { return (x2 + y2).squareRoot() * il2 - r1 }
    return ((max(x2 * a2 * il2, 0)).squareRoot() + y * rr) * il2 - r1
}

@inlinable @inline(__always) public func primSDF(_ q: Primitive, _ p: V3) -> Double {
    switch q.kind {
    case .cone:
        return roundCone(p, q.a, q.b, q.ra, q.rb)
    case .ellip:
        let d = p - q.a
        let l = V3(dot3(d, q.ex), dot3(d, q.ey), dot3(d, q.ez))
        let k0 = len3(l / q.r), k1 = len3(l / (q.r * q.r))
        if k1 < 1e-12 { return -min(q.r.x, q.r.y, q.r.z) }
        return k0 * (k0 - 1) / k1
    case .torus:
        let d = p - q.a
        let l = V3(dot3(d, q.ex), dot3(d, q.ey), dot3(d, q.ez))
        return len2(V2(len2(V2(l.x, l.y)) - q.ra, l.z)) - q.rb
    }
}

public func primBounds(_ q: Primitive) -> (V3, V3) {
    switch q.kind {
    case .cone:
        let r = max(q.ra, q.rb)
        return (V3(min(q.a.x, q.b.x), min(q.a.y, q.b.y), min(q.a.z, q.b.z)) - r, V3(max(q.a.x, q.b.x), max(q.a.y, q.b.y), max(q.a.z, q.b.z)) + r)
    case .ellip:
        // the exact box of a turned ellipsoid
        var e = V3(0, 0, 0)
        for k in 0..<3 {
            let rx = q.ex[k] * q.r.x, ry = q.ey[k] * q.r.y, rz = q.ez[k] * q.r.z
            e[k] = (rx * rx + ry * ry + rz * rz).squareRoot()
        }
        return (q.a - e, q.a + e)
    case .torus:
        let r = q.ra + q.rb
        return (q.a - r, q.a + r)
    }
}

// MARK: - The builder

public final class PrimitiveBuilder {
    public var prims: [Primitive] = []
    public var groups: [PrimitiveGroup] = []
    public var strokes: [Stroke3D] = []
    public var marks: [Mark3D] = []
    /// Tubes thinner than this (world radius) become 3D strokes instead of cones.
    public var minTubeR = 0.0
    /// Pressure and depth tolerance of those strokes.
    public var twigPr = 0.62
    public var twigTol = 0.010

    public init() {}

    @discardableResult public func group(_ g: PrimitiveGroup) -> Int32 { groups.append(g); return Int32(groups.count - 1) }

    public func cone(_ a: V3, _ b: V3, _ ra: Double, _ rb: Double, g: Int32, id: Int32) {
        prims.append(Primitive(kind: .cone, a: a, b: b, ra: ra, rb: rb, group: g, id: id, kmax: 0.5 * min(ra, rb)))
    }
    public func ellip(_ c: V3, _ r: V3, ex: V3 = V3(1, 0, 0), ey: V3 = V3(0, 1, 0), g: Int32, id: Int32) {
        let ez = cross3(ex, ey)
        prims.append(Primitive(kind: .ellip, a: c, ex: ex, ey: ey, ez: ez, r: r, group: g, id: id))
    }
    public func torus(_ c: V3, axis: V3, R: Double, r: Double, g: Int32, id: Int32) {
        let (e1, e2) = basis(axis)
        prims.append(Primitive(kind: .torus, a: c, ra: R, rb: r, ex: e1, ey: e2, ez: norm3(axis), group: g, id: id))
    }

    /// A tube along a polyline: cones where it is thick enough to draw two edges, a pencil stroke where it is not.
    public func tube(_ pts: [V3], _ rads: [Double], g: Int32, id: Int32, pr: Double? = nil, forceStroke: Bool = false) {
        guard pts.count >= 2 else { return }
        var sp: [V3] = [], sr: [Double] = []
        func flush() {
            if sp.count >= 2 {
                strokes.append(Stroke3D(pts: sp, rad: sr, pr: sr.map { _ in pr ?? twigPr }, tol: twigTol))
            }
            sp = []; sr = []
        }
        for i in 0..<(pts.count - 1) {
            let thick = !forceStroke && max(rads[i], rads[i + 1]) >= minTubeR
            if thick {
                flush()
                cone(pts[i], pts[i + 1], rads[i], rads[i + 1], g: g, id: id)
            } else {
                if sp.isEmpty { sp.append(pts[i]); sr.append(rads[i]) }
                sp.append(pts[i + 1]); sr.append(rads[i + 1])
            }
        }
        flush()
    }

    /// Scales everything about the origin (build in metres, draw at the reference scale).
    public func scale(_ k: Double) {
        for i in prims.indices {
            prims[i].a *= k; prims[i].b *= k; prims[i].ra *= k; prims[i].rb *= k; prims[i].r *= k
            if prims[i].kmax < 1e8 { prims[i].kmax *= k }
        }
        for i in groups.indices {
            groups[i].k *= k; groups[i].amp *= k; groups[i].freq /= k
            if groups[i].floorZ > -1e8 { groups[i].floorZ *= k }
            groups[i].floorK *= k
            if groups[i].ceilZ < 1e8 { groups[i].ceilZ *= k }
        }
        for i in strokes.indices {
            strokes[i].pts = strokes[i].pts.map { $0 * k }; strokes[i].rad = strokes[i].rad.map { $0 * k }
        }
        for i in marks.indices { marks[i].c *= k; marks[i].u *= k; marks[i].v *= k }
    }

    /// Mirrors left for right (x → −x about the origin).
    public func mirrorX() {
        func r(_ v: V3) -> V3 { V3(-v.x, v.y, v.z) }
        for i in prims.indices {
            prims[i].a = r(prims[i].a)
            if prims[i].kind == .cone { prims[i].b = r(prims[i].b) }
            prims[i].ex = r(prims[i].ex); prims[i].ey = r(prims[i].ey); prims[i].ez = r(prims[i].ez)
        }
        for i in strokes.indices { strokes[i].pts = strokes[i].pts.map(r) }
        for i in marks.indices { marks[i].c = r(marks[i].c); marks[i].u = r(marks[i].u); marks[i].v = r(marks[i].v) }
    }

    /// Turns everything about the z axis through the origin.
    public func rotateZ(_ a: Double) {
        let c = cos(a), s = sin(a)
        func r(_ v: V3) -> V3 { V3(c * v.x - s * v.y, s * v.x + c * v.y, v.z) }
        for i in prims.indices {
            prims[i].a = r(prims[i].a)
            if prims[i].kind == .cone { prims[i].b = r(prims[i].b) }
            prims[i].ex = r(prims[i].ex); prims[i].ey = r(prims[i].ey); prims[i].ez = r(prims[i].ez)
        }
        for i in strokes.indices { strokes[i].pts = strokes[i].pts.map(r) }
        for i in marks.indices { marks[i].c = r(marks[i].c); marks[i].u = r(marks[i].u); marks[i].v = r(marks[i].v) }
    }

    /// Moves everything by o.
    public func translate(_ o: V3) {
        for i in prims.indices { prims[i].a += o; if prims[i].kind == .cone { prims[i].b += o } }
        for i in groups.indices {
            if groups[i].floorZ > -1e8 { groups[i].floorZ += o.z }
            if groups[i].ceilZ < 1e8 { groups[i].ceilZ += o.z }
        }
        for i in strokes.indices { strokes[i].pts = strokes[i].pts.map { $0 + o } }
        for i in marks.indices { marks[i].c += o }
    }

    /// The box round everything (primitives, strokes, marks).
    public func extent() -> (V3, V3) {
        var lo = V3(repeating: 1e9), hi = V3(repeating: -1e9)
        for q in prims { let (a, b) = primBounds(q); lo = pointwiseMin(lo, a); hi = pointwiseMax(hi, b) }
        for s in strokes { for p in s.pts { lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p) } }
        for m in marks { lo = pointwiseMin(lo, m.c); hi = pointwiseMax(hi, m.c) }
        return (lo, hi)
    }

    /// Points that bound what a view will draw (for framing), clipped to the ground.
    public func framePoints() -> [V3] {
        var out: [V3] = []
        let dirs: [V3] = {
            var d: [V3] = []
            for i in -1...1 { for j in -1...1 { for k in -1...1 where i != 0 || j != 0 || k != 0 { d.append(norm3(V3(Double(i), Double(j), Double(k)))) } } }
            return d
        }()
        for q in prims {
            switch q.kind {
            case .cone:
                for e in [q.a, q.b] { let r = e == q.a ? q.ra : q.rb; for d in dirs { out.append(e + d * r) } }
            case .ellip:
                for d in dirs { out.append(q.a + q.ex * (d.x * q.r.x) + q.ey * (d.y * q.r.y) + q.ez * (d.z * q.r.z)) }
            case .torus:
                for d in dirs { out.append(q.a + q.ex * (d.x * (q.ra + q.rb)) + q.ey * (d.y * (q.ra + q.rb)) + q.ez * (d.z * q.rb)) }
            }
        }
        for s in strokes { out += s.pts }
        for m in marks { out += [m.c + m.u, m.c - m.u, m.c + m.v, m.c - m.v] }
        return out.map { V3($0.x, $0.y, max($0.z, 0)) }
    }
}

// MARK: - The scene: primitives in a grid

public final class PrimitiveScene: Subject {
    public let prims: [Primitive]
    public let groups: [PrimitiveGroup]
    public let lo: V3, hi: V3
    public let nx: Int, ny: Int, nz: Int
    public let cell: Double, margin: Double
    public let start: [Int32], items: [Int32]
    public let materialFn: (Int32, V3) -> Material
    public let idFn: ((Primitive, V3) -> Int32)?

    /// `material(id, p)` gives each region's material; `region(prim, p)` may split a primitive's surface into regions
    /// (default: the primitive's own id).
    public init(_ b: PrimitiveBuilder, material: @escaping (Int32, V3) -> Material, region: ((Primitive, V3) -> Int32)? = nil) {
        // primitives ordered by group, so a cell's list visits each group in one run
        let order = b.prims.indices.sorted { b.prims[$0].group < b.prims[$1].group }
        prims = order.map { b.prims[$0] }
        groups = b.groups
        materialFn = material; idFn = region
        var plo = V3(repeating: 1e9), phi = V3(repeating: -1e9)
        var bounds: [(V3, V3)] = []
        for q in prims {
            let G = groups[Int(q.group)]
            var (a, c) = primBounds(q)
            a -= G.amp + G.k; c += G.amp + G.k
            bounds.append((a, c)); plo = pointwiseMin(plo, a); phi = pointwiseMax(phi, c)
        }
        if prims.isEmpty { plo = V3(-1, -1, -1); phi = V3(1, 1, 1) }
        let ext = phi - plo
        let c = max(ext.x, ext.y, ext.z) / 60
        let mg = max(1.6 * c, 0.05)
        cell = c; margin = mg
        lo = plo - mg; hi = phi + mg
        let e2 = hi - lo
        nx = max(Int((e2.x / c).rounded(.up)), 1); ny = max(Int((e2.y / c).rounded(.up)), 1); nz = max(Int((e2.z / c).rounded(.up)), 1)
        var lists = [[Int32]](repeating: [], count: nx * ny * nz)
        for (i, (a, b2)) in bounds.enumerated() {
            let x0 = max(Int(((a.x - mg - lo.x) / c).rounded(.down)), 0), x1 = min(Int(((b2.x + mg - lo.x) / c).rounded(.down)), nx - 1)
            let y0 = max(Int(((a.y - mg - lo.y) / c).rounded(.down)), 0), y1 = min(Int(((b2.y + mg - lo.y) / c).rounded(.down)), ny - 1)
            let z0 = max(Int(((a.z - mg - lo.z) / c).rounded(.down)), 0), z1 = min(Int(((b2.z + mg - lo.z) / c).rounded(.down)), nz - 1)
            if x0 > x1 || y0 > y1 || z0 > z1 { continue }
            for z in z0...z1 { for y in y0...y1 { for x in x0...x1 { lists[(z * ny + y) * nx + x].append(Int32(i)) } } }
        }
        var st: [Int32] = [0], it: [Int32] = []
        for l in lists { it += l; st.append(Int32(it.count)) }
        start = st; items = it
    }

    public var bounds: (lo: V3, hi: V3) { (lo, hi) }

    @inlinable @inline(__always) public func cellOf(_ p: V3) -> Int {
        let x = min(max(Int((p.x - lo.x) / cell), 0), nx - 1)
        let y = min(max(Int((p.y - lo.y) / cell), 0), ny - 1)
        let z = min(max(Int((p.z - lo.z) / cell), 0), nz - 1)
        return (z * ny + y) * nx + x
    }

    /// A group's smoothly united distance, finished with its noise, its flat underside and the ground clip.
    @inlinable @inline(__always) public func finish(_ g: Int, _ d0: Double, _ p: V3) -> Double {
        let G = groups[g]
        var d = d0
        if G.amp > 0 {
            if d < G.amp * 3 {
                let n = vnoise3(p * G.freq + G.seed) * 0.7 + vnoise3(p * (G.freq * 2.3) - G.seed) * 0.3
                d = (d + G.amp * (2 * n - 1)) * 0.8
            } else { d -= G.amp }
        }
        if G.floorZ > -1e8 { d = -smoothUnionQuadratic(-d, -(G.floorZ - p.z), G.floorK) }
        if G.clip { d = max(d, -p.z) }
        if G.ceilZ < 1e8 { d = max(d, p.z - G.ceilZ) }
        return d
    }

    /// (distance, index of the nearest primitive of the nearest group); the index is -1 where the distance only bounds
    /// empty space (nothing within `margin`).
    @inlinable @inline(__always) public func sceneSDF(_ p: V3) -> (Double, Int) {
        let bd = boxDist(p, lo, hi)
        if bd > 0 { return (bd + margin, -1) }
        let c = cellOf(p)
        var best = margin, bi = -1
        var cur: Int32 = -1, gd = 1e9, gp = -1, gpd = 1e9
        var j = Int(start[c])
        let e = Int(start[c + 1])
        while j < e {
            let pi = Int(items[j])
            let q = prims[pi]
            let d = primSDF(q, p)
            if q.group != cur {
                if cur >= 0 { let f = finish(Int(cur), gd, p); if f < best { best = f; bi = gp } }
                cur = q.group; gd = d; gp = pi; gpd = d
            } else {
                if d < gpd { gpd = d; gp = pi }
                gd = smoothUnionQuadratic(gd, d, min(groups[Int(cur)].k, q.kmax))
            }
            j += 1
        }
        if cur >= 0 { let f = finish(Int(cur), gd, p); if f < best { best = f; bi = gp } }
        return (best, bi)
    }

    @inlinable @inline(__always) public func groupSDF(_ g: Int32, _ p: V3) -> Double {
        let c = cellOf(p)
        var gd = 1e9
        var j = Int(start[c])
        let e = Int(start[c + 1])
        let k = groups[Int(g)].k
        while j < e {
            let q = prims[Int(items[j])]
            if q.group == g { gd = smoothUnionQuadratic(gd, primSDF(q, p), min(k, q.kmax)) }
            j += 1
        }
        return finish(Int(g), gd, p)
    }

    public func partSDF(_ i: Int, _ p: V3) -> Double { groupSDF(prims[i].group, p) }

    /// The normal of the group primitive i belongs to.
    public func normal(_ i: Int, _ p: V3) -> V3 { normal(i, p, step: 0.00025) }
    public func normal(_ i: Int, _ p: V3, step e: Double) -> V3 {
        let g = prims[i].group
        let dx = groupSDF(g, p + V3(e, 0, 0)) - groupSDF(g, p - V3(e, 0, 0))
        let dy = groupSDF(g, p + V3(0, e, 0)) - groupSDF(g, p - V3(0, e, 0))
        let dz = groupSDF(g, p + V3(0, 0, e)) - groupSDF(g, p - V3(0, 0, e))
        return norm3(V3(dx, dy, dz))
    }

    public func subID(_ i: Int, _ p: V3) -> Int32 { idFn?(prims[i], p) ?? prims[i].id }
    public func subID(_ i: Int, _ p: V3, _ n: V3) -> Int32 { subID(i, p) }
    public func material(_ id: Int32, _ p: V3, _ n: V3) -> Material { materialFn(id, p) }
}

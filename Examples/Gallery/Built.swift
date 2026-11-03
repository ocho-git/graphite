// Built.swift: a lighthouse (with a ringed close-up of its lantern), an arcade of columns and arches, and a stack of
// books and boxes. Courses, voussoirs, bands, windows and labels are regions.
import Foundation

// MARK: - Lighthouse

enum LHKind: Int { case stone = 0, course, light, dark, door, window, gallery, glass, roof }

func makeLighthouse(_ rng: inout Rng) -> Piece {
    let s = ShapeSubject()
    let pz = 0.12, Ht = rng.range(1.3, 1.8)
    let r0 = rng.range(0.25, 0.31), r1 = r0 * rng.range(0.6, 0.75)
    let striped = rng.chance(0.7), bands = 2 + Int(rng.uni() * 3)
    let doorAz = -Double.pi / 2 + rng.range(-0.6, 0.6)
    let windows: [(Double, Double)] = (0..<(2 + Int(rng.uni() * 2))).map { k in
        (rng.range(-Double.pi, Double.pi), pz + (Ht - pz) * (0.32 + 0.22 * Double(k)))
    }
    let gR = r1 + 0.1, lR = r1 * 0.7, lH = 0.22
    let lz0 = Ht + 0.04, lz1 = lz0 + lH, roofTop = lz1 + rng.range(0.12, 0.22)
    func wrap(_ a: Double) -> Double { atan2(sin(a), cos(a)) }
    let stone: (Int32, V3, V3) -> Material = { _, _, _ in Material(value: 0.08, stipple: 1.5) }
    // 0: an octagonal plinth in two courses
    let pa = r0 + 0.13
    s.add(.init(lo: V3(-pa - 0.05, -pa - 0.05, 0), hi: V3(pa + 0.05, pa + 0.05, pz + 0.01), grounded: true,
                sdf: { p in sdPrism(p, sides: 8, apothem: pa, corner: 0.01, z0: 0, z1: pz) },
                region: { p, _ in SurfaceID.make(0, p.z < pz * 0.5 ? LHKind.stone.rawValue : LHKind.course.rawValue) },
                material: stone))
    // 1: the tower, striped, with a door and windows
    s.add(.init(lo: V3(-r0 - 0.02, -r0 - 0.02, pz - 0.02), hi: V3(r0 + 0.02, r0 + 0.02, Ht + 0.02),
                sdf: { p in sdCappedCone(p, V3(0, 0, pz - 0.01), V3(0, 0, Ht + 0.005), r0, r1) },
                region: { p, _ in
                    let a = atan2(p.y, p.x), rho = len2(V2(p.x, p.y))
                    if p.z < pz + 0.3 && abs(wrap(a - doorAz)) * rho < 0.07 { return SurfaceID.make(1, LHKind.door.rawValue) }
                    for (k, w) in windows.enumerated() where abs(wrap(a - w.0)) * rho < 0.035 && abs(p.z - w.1) < 0.055 {
                        return SurfaceID.make(1, LHKind.window.rawValue, k)
                    }
                    if striped {
                        let band = Int((p.z - pz) / (Ht - pz) * Double(2 * bands))
                        return SurfaceID.make(1, band % 2 == 0 ? LHKind.light.rawValue : LHKind.dark.rawValue, band)
                    }
                    return SurfaceID.make(1, LHKind.light.rawValue)
                },
                material: { id, _, _ in
                    switch LHKind(rawValue: SurfaceID.kind(id)) ?? .light {
                    case .door: return Material(value: 0.7, stipple: 0)
                    case .window: return .opening
                    case .dark: return Material(value: 0.5, stipple: 0.1)
                    default: return Material(value: 0.0, stipple: 0.3)
                    }
                }))
    // 2: the gallery with its railing
    let rr = gR - 0.012
    s.add(.init(lo: V3(-gR - 0.02, -gR - 0.02, Ht - 0.01), hi: V3(gR + 0.02, gR + 0.02, Ht + 0.16),
                sdf: { p in
                    var d = sdPrism(p, sides: 0, apothem: gR, corner: 0.005, z0: Ht, z1: Ht + 0.04)
                    d = min(d, sdTorus(p - V3(0, 0, Ht + 0.13), rr, 0.008))
                    let f = polygonFold(V2(p.x, p.y), 14)
                    return min(d, sdCapsule(V3(f.x, f.y, p.z), V3(rr, 0, Ht + 0.04), V3(rr, 0, Ht + 0.13), 0.0065))
                },
                region: { _, _ in SurfaceID.make(2, LHKind.gallery.rawValue) },
                material: { _, _, _ in Material(value: 0.35, stipple: 0) }))
    // 3: the lantern: eight panes, a glazing bar across
    s.add(.init(lo: V3(-lR - 0.03, -lR - 0.03, lz0 - 0.01), hi: V3(lR + 0.03, lR + 0.03, lz1 + 0.01),
                sdf: { p in sdPrism(p, sides: 8, apothem: lR, corner: 0.004, z0: lz0, z1: lz1) },
                region: { p, _ in
                    let sector = Int(((atan2(p.y, p.x) + Double.pi) / (2 * Double.pi) * 8).rounded()) % 8
                    return SurfaceID.make(3, LHKind.glass.rawValue, sector * 2 + (p.z > (lz0 + lz1) / 2 ? 1 : 0))
                },
                material: { _, _, _ in Material(value: 0.55, stipple: 0) }))
    // 4: the roof and its finial
    s.add(.init(lo: V3(-lR - 0.06, -lR - 0.06, lz1 - 0.01), hi: V3(lR + 0.06, lR + 0.06, roofTop + 0.06),
                sdf: { p in min(sdCappedCone(p, V3(0, 0, lz1), V3(0, 0, roofTop), lR + 0.04, 0.015), sdSphere(p - V3(0, 0, roofTop + 0.02), 0.03)) },
                region: { _, _ in SurfaceID.make(4, LHKind.roof.rawValue) },
                material: { _, _, _ in Material(value: 0.45, stipple: 0.1) }))
    var m = piece(s)
    m.options.rules.floor = [LHKind.course.rawValue: 0.3, LHKind.light.rawValue: 0.35, LHKind.dark.rawValue: 0.35,
                             LHKind.door.rawValue: 0.6, LHKind.window.rawValue: 0.6, LHKind.glass.rawValue: 0.3]
    m.closeUp = (V3(0, 0, (lz0 + lz1) / 2 + 0.02), gR * 1.3, "the lantern")
    return m
}

// MARK: - Arcade

enum ArchKind: Int { case step = 0, column, block, vous, key, course, cornice }

func makeArcade(_ rng: inout Rng) -> Piece {
    let s = ShapeSubject()
    let nA = 1 + Int(rng.uni() * 3)
    let rc = rng.range(0.055, 0.08), span = rng.range(0.4, 0.62), hc = rng.range(0.6, 0.9)
    let pitch = span + 2 * rc, W = Double(nA) * pitch
    let xs = (0...nA).map { -W / 2 + Double($0) * pitch }
    let zs = 0.16, zi = zs + 0.05 + hc + 0.07
    let ro = pitch / 2 - rc * 1.3
    let fluted = rng.chance(0.6)
    let bx = W / 2 + rc * 1.5, by = rc * 1.5
    let ztop = zi + ro + 0.16
    // 0: the stylobate, two steps
    s.add(.init(lo: V3(-bx - 0.2, -by - 0.2, 0), hi: V3(bx + 0.2, by + 0.2, zs + 0.01), grounded: true,
                sdf: { p in
                    min(sdRoundBox(p - V3(0, 0, 0.04), V3(bx + 0.16, by + 0.18, 0.04), 0.006),
                        sdRoundBox(p - V3(0, 0, 0.12), V3(bx + 0.08, by + 0.1, 0.04), 0.006))
                },
                material: { _, _, _ in Material(value: 0.08, stipple: 1.4) }))
    // the columns
    for x in xs {
        let part = s.parts.count
        s.add(.init(lo: V3(x - rc * 1.6, -rc * 1.6, zs - 0.01), hi: V3(x + rc * 1.6, rc * 1.6, zi + 0.01),
                    sdf: { p in
                        let q = p - V3(x, 0, 0)
                        var d = sdBox(q - V3(0, 0, zs + 0.02), V3(rc * 1.4, rc * 1.4, 0.02))
                        d = min(d, sdTorus(q - V3(0, 0, zs + 0.05), rc * 1.02, 0.018))
                        let rho = len2(V2(q.x, q.y))
                        let t = clampd((q.z - zs) / hc, 0, 1)
                        var r = rc * (1 - 0.12 * t)
                        if fluted { r -= 0.006 * (0.5 + 0.5 * cos(16 * atan2(q.y, q.x))) }
                        d = min(d, extrude((rho - r) * 0.85, q.z, zs + 0.04, zs + 0.05 + hc))
                        d = min(d, sdTorus(q - V3(0, 0, zs + 0.05 + hc - 0.005), rc * 0.98, 0.022))
                        return min(d, sdBox(q - V3(0, 0, zi - 0.025), V3(rc * 1.45, rc * 1.45, 0.025)))
                    },
                    region: { _, _ in SurfaceID.make(part, ArchKind.column.rawValue) },
                    material: { _, _, _ in Material(value: 0.03, stipple: 0.6) }))
    }
    // the arched block over them: voussoirs round each arch, courses in the spandrels
    let centres = (0..<nA).map { (xs[$0] + xs[$0 + 1]) / 2 }
    let blockPart = s.parts.count
    s.add(.init(lo: V3(-bx - 0.02, -by - 0.02, zi - 0.01), hi: V3(bx + 0.02, by + 0.02, ztop + 0.01),
                sdf: { p in
                    var d = sdBox(p - V3(0, 0, (zi + ztop) / 2), V3(bx, by, (ztop - zi) / 2))
                    for c in centres { d = max(d, -(len2(V2(p.x - c, p.z - zi)) - ro)) }
                    return d
                },
                region: { p, _ in
                    var c = centres[0]
                    for cc in centres where abs(p.x - cc) < abs(p.x - c) { c = cc }
                    let rho = len2(V2(p.x - c, p.z - zi))
                    if rho < ro + 0.13 {
                        let k = min(Int(atan2(max(p.z - zi, 0), p.x - c) / (Double.pi / 9)), 8)
                        return SurfaceID.make(blockPart, k == 4 ? ArchKind.key.rawValue : ArchKind.vous.rawValue, k)
                    }
                    return SurfaceID.make(blockPart, ArchKind.course.rawValue, Int((p.z - zi) / 0.085))
                },
                material: { id, _, _ in
                    SurfaceID.kind(id) == ArchKind.key.rawValue ? Material(value: 0.18, stipple: 1.2) : Material(value: 0.06, stipple: 1.0)
                }))
    let corn = s.parts.count
    s.add(.init(lo: V3(-bx - 0.08, -by - 0.08, ztop - 0.01), hi: V3(bx + 0.08, by + 0.08, ztop + 0.07),
                sdf: { p in sdRoundBox(p - V3(0, 0, ztop + 0.028), V3(bx + 0.04, by + 0.04, 0.028), 0.006) },
                region: { _, _ in SurfaceID.make(corn, ArchKind.cornice.rawValue) },
                material: { _, _, _ in Material(value: 0.1, stipple: 0.8) }))
    var m = piece(s)
    m.options.rules.floor = [ArchKind.vous.rawValue: 0.3, ArchKind.key.rawValue: 0.35, ArchKind.course.rawValue: 0.22]
    m.options.march.stepScale = 0.8
    return m
}

// MARK: - Books and boxes

func makeBooks(_ rng: inout Rng) -> Piece {
    let s = ShapeSubject()
    let n = 3 + Int(rng.uni() * 5)
    var z = 0.0
    for i in 0..<n {
        let isBook = rng.chance(0.75)
        let hx = rng.range(0.2, 0.38), hy = rng.range(0.14, 0.26)
        let hz = isBook ? rng.range(0.022, 0.06) : rng.range(0.05, 0.12)
        let f = Frame(yaw: rng.range(-0.4, 0.4) + (rng.chance(0.3) ? Double.pi / 2 : 0))
        let c = V3(rng.range(-0.05, 0.05), rng.range(-0.05, 0.05), z + hz)
        z += 2 * hz
        let (lo, hi) = turnedBox(c, f, V3(hx, hy, hz) + 0.01)
        let coverV = rng.range(0.1, 0.65)
        if isBook {
            let ct = min(0.008, hz * 0.3), inset = 0.012
            let pagesC = V3((ct - inset) / 2, 0, 0), pagesH = V3(hx - ct / 2 - inset / 2, hy - inset, hz - ct)
            let label = rng.chance(0.6), labelY = rng.range(-0.3, 0.3) * hy
            let parts: (V3) -> (Double, Double) = { q in
                let top = sdBox(q - V3(0, 0, hz - ct / 2), V3(hx, hy, ct / 2))
                let bot = sdBox(q - V3(0, 0, -hz + ct / 2), V3(hx, hy, ct / 2))
                let spine = sdRoundBox(q - V3(-hx + ct / 2, 0, 0), V3(ct / 2 + 0.002, hy, hz), 0.004)
                return (min(top, bot, spine), sdBox(q - pagesC, pagesH))
            }
            s.add(.init(lo: lo, hi: hi, grounded: i == 0,
                        sdf: { p in let (a, b) = parts(f.local(p - c)); return min(a, b) },
                        region: { p, _ in
                            let q = f.local(p - c)
                            let (cover, pages) = parts(q)
                            if pages < cover { return SurfaceID.make(i, 1) }
                            if label && q.x < -hx + 0.003 && abs(q.z) < hz * 0.45 && abs(q.y - labelY) < hy * 0.22 { return SurfaceID.make(i, 2) }
                            return SurfaceID.make(i, 0)
                        },
                        material: { id, _, _ in
                            switch SurfaceID.kind(id) {
                            case 1: return Material(value: -0.4, shading: 0.8, stipple: 0)
                            case 2: return Material(value: -0.3, stipple: 0)
                            default: return Material(value: coverV, stipple: 0.2)
                            }
                        }))
        } else {
            let lidH = min(hz * 0.5, rng.range(0.03, 0.06))
            s.add(.init(lo: lo, hi: hi, grounded: i == 0,
                        sdf: { p in
                            let q = f.local(p - c)
                            return min(sdRoundBox(q, V3(hx, hy, hz), 0.01),
                                       sdRoundBox(q - V3(0, 0, hz - lidH / 2 + 0.003), V3(hx + 0.006, hy + 0.006, lidH / 2), 0.008))
                        },
                        material: { _, _, _ in Material(value: coverV * 0.4, stipple: 0.8) }))
        }
    }
    var m = piece(s)
    m.options.rules.floor = [2: 0.4]
    return m
}

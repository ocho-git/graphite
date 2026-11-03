// Turned.swift: lathe-turned subjects with profiles drawn from a seed: a vase, a bottle and a bowl (glazed vessels, the
// glaze stopping in a wavy line above the bare foot, sometimes a band), and a chess piece.
import Foundation

enum VesselKind: Int { case clay = 0, glaze, band, inside, cork }

func makeVessel(_ rng: inout Rng, shape: String) -> Piece {
    var prof: Profile
    var wall = 0.035, floorZ = 0.06
    switch shape {
    case "bottle":
        let H = rng.range(1.1, 1.5)
        let body = rng.range(0.22, 0.32), neck = rng.range(0.065, 0.095)
        let shoulder = rng.range(0.42, 0.66), soft = rng.range(0.1, 0.28), lip = rng.range(0.008, 0.02)
        prof = Profile(height: H, knots: 18) { t in
            var r = mixd(body, neck, sstep(shoulder, shoulder + soft, t))
            if t > 0.96 { r += lip }
            if t < 0.03 { r *= 0.93 }
            return r
        }
        wall = 0.022; floorZ = 0.05
    case "bowl":
        let H = rng.range(0.28, 0.45)
        let foot = rng.range(0.16, 0.25), rim = rng.range(0.5, 0.68), pw = rng.range(0.45, 1.0)
        prof = Profile(height: H, knots: 12) { t in
            t < 0.08 ? foot : foot * 0.9 + (rim - foot * 0.9) * pow((t - 0.08) / 0.92, pw)
        }
        wall = 0.03; floorZ = 0.045
    default:
        let H = rng.range(0.9, 1.4)
        let base = rng.range(0.15, 0.25), belly = rng.range(0.06, 0.22), tb = rng.range(0.25, 0.55), wb = rng.range(0.16, 0.32)
        let neckT = rng.range(0.72, 0.9), neckR = rng.range(0.09, 0.17), lip = rng.range(0.02, 0.12)
        prof = Profile(height: H, knots: 13) { t in
            var r = base + belly * exp(-sq((t - tb) / wb))
            r = mixd(r, neckR, sstep(tb + wb * 0.5, neckT, t))
            return r + lip * sstep(neckT, 1, t)
        }
    }
    let pr = prof
    let H = pr.H, R = pr.maxR
    let glaze = H * rng.range(0.1, 0.45), gf = Double(3 + Int(rng.uni() * 5)), gph = rng.range(0, 6)
    let hasBand = rng.chance(0.6)
    let bandZ = H * rng.range(0.55, 0.85), bandW = rng.range(0.012, 0.035), bandWave = rng.chance(0.4) ? rng.range(0.01, 0.03) : 0
    let glazeV = rng.range(0.12, 0.5), clayV = rng.range(-0.1, 0.12)
    let w = wall, fl = floorZ
    let s = ShapeSubject()
    s.add(.init(lo: V3(-R, -R, 0), hi: V3(R, R, H + 0.01), grounded: true,
                sdf: { p in vessel(p, pr, wall: w, floor: fl) },
                region: { p, _ in
                    let rho = len2(V2(p.x, p.y))
                    if rho < pr.at(p.z).r - w * 0.5 && p.z > fl * 0.5 { return SurfaceID.make(0, VesselKind.inside.rawValue) }
                    let a = atan2(p.y, p.x)
                    if p.z < glaze + 0.025 * sin(a * gf + gph) + 0.01 * sin(a * 13 + 1) { return SurfaceID.make(0, VesselKind.clay.rawValue) }
                    if hasBand && abs(p.z - bandZ - bandWave * sin(a * 9)) < bandW { return SurfaceID.make(0, VesselKind.band.rawValue) }
                    return SurfaceID.make(0, VesselKind.glaze.rawValue)
                },
                material: { id, _, _ in
                    switch VesselKind(rawValue: SurfaceID.kind(id)) ?? .clay {
                    case .clay: return Material(value: clayV, stipple: 1.5)
                    case .glaze: return Material(value: glazeV, stipple: 0.1)
                    case .band: return Material(value: min(glazeV + 0.3, 0.85), stipple: 0)
                    case .inside: return Material(value: 0.15, minTone: 0.2, stipple: 0)
                    case .cork: return Material(value: 0.2, stipple: 2)
                    }
                }))
    if shape == "bottle" && rng.chance(0.6) {
        let rn = pr.at(H - 0.03).r - w
        s.add(.init(lo: V3(-rn - 0.03, -rn - 0.03, H - 0.1), hi: V3(rn + 0.03, rn + 0.03, H + 0.12),
                    sdf: { p in sdCappedCone(p, V3(0, 0, H - 0.08), V3(0, 0, H + 0.08), rn - 0.004, rn + 0.012) },
                    region: { _, _ in SurfaceID.make(1, VesselKind.cork.rawValue) },
                    material: { _, _, _ in Material(value: 0.2, stipple: 2) }))
    }
    var m = piece(s)
    m.options.march.stepScale = 0.75
    m.options.rules.floor = [VesselKind.inside.rawValue: 0.5]     // the inner rim
    return m
}

func makeChess(_ rng: inout Rng) -> Piece {
    let kind = choose(["pawn", "rook", "bishop", "queen", "king"], &rng)
    let dark = rng.chance(0.5)
    let Hb = kind == "pawn" ? rng.range(0.5, 0.62) : rng.range(0.78, 1.0)
    let baseR = rng.range(0.29, 0.35), neckR = rng.range(0.075, 0.1)
    let collarR = neckR + rng.range(0.05, 0.08)
    let prof = Profile(height: Hb, knots: 30) { t in
        let z = t * Hb
        if z < 0.06 { return baseR }
        if z < 0.1 { return baseR * 0.9 }
        if z < 0.15 { return baseR * 0.84 }
        if z < Hb - 0.11 {
            let u = (z - 0.15) / (Hb - 0.26)
            return neckR + (baseR * 0.62 - neckR) * sq(1 - u)
        }
        if z < Hb - 0.05 { return collarR }
        return neckR * 1.1
    }
    let top = Hb
    let head: (V3) -> Double
    switch kind {
    case "pawn":
        let r = rng.range(0.12, 0.16)
        head = { p in sdSphere(p - V3(0, 0, top + r * 0.75), r) }
    case "rook":
        let R = collarR + 0.03, h = rng.range(0.18, 0.24)
        head = { p in
            var d = sdCappedCone(p, V3(0, 0, top - 0.02), V3(0, 0, top + h), R * 0.85, R)
            d = max(d, -sdCappedCone(p, V3(0, 0, top + h - 0.05), V3(0, 0, top + h + 0.1), R - 0.045, R - 0.045))
            let f = polygonFold(V2(p.x, p.y), 4)
            return max(d, -sdBox(V3(f.x - R, f.y, p.z - top - h), V3(0.08, 0.028, 0.045)))
        }
    case "bishop":
        head = { p in
            var d = sdEllipsoid(p - V3(0, 0, top + 0.16), V3(0.12, 0.12, 0.19))
            d = max(d, -sdBox(rotX(p - V3(0, 0.06, top + 0.25), 0.7), V3(0.2, 0.013, 0.09)))
            return min(d, sdSphere(p - V3(0, 0, top + 0.38), 0.035))
        }
    default:   // queen or king: a flaring crown
        let king = kind == "king"
        let R = collarR + 0.05
        head = { p in
            var d = sdCappedCone(p, V3(0, 0, top - 0.02), V3(0, 0, top + 0.22), neckR * 1.2, R)
            if king {
                d = min(d, sdBox(p - V3(0, 0, top + 0.33), V3(0.024, 0.024, 0.09)))
                return min(d, sdBox(p - V3(0, 0, top + 0.36), V3(0.075, 0.024, 0.024)))
            }
            let f = polygonFold(V2(p.x, p.y), 8)
            d = smoothSubtraction(d, sdSphere(V3(f.x - R, f.y, p.z - top - 0.24), 0.05), 0.01)
            return min(d, sdSphere(p - V3(0, 0, top + 0.25), 0.055))
        }
    }
    let s = ShapeSubject()
    let R = max(baseR, collarR + 0.1) + 0.04
    s.add(.init(lo: V3(-R, -R, 0), hi: V3(R, R, Hb + 0.5), grounded: true,
                sdf: { p in smoothUnion(latheSolid(p, prof), head(p), 0.015) },
                material: { _, _, _ in dark ? Material(value: 0.62, stipple: 0.05) : Material(value: 0.03, stipple: 0.12) }))
    var m = piece(s)
    m.options.march.stepScale = 0.75
    return m
}

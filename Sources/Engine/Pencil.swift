// Pencil.swift: the passes that draw a tone map and its chains in graphite: lines, hatching, stipple, fills and the
// ground stroke. Each reads its look from the sheet's style.
import Foundation

/// Draws chains (traced contours, or any line given as a chain) as a hand would: smoothed, resampled, pressed harder
/// where they border shade, split into overlapping strokes with a wobble and tapered ends. Chain points are in sample
/// units (the drawing's pixels × ss); `smooth: false` keeps lines that are already smooth as they are.
public func drawChains(_ chains: [Chain], on sheet: Sheet, tone t1: ToneMap, ss: Int, rng: inout Rng, smooth: Bool = true) {
    let L = sheet.style.line
    for c0 in chains {
        let c = smooth ? smoothChain(c0, sigma: Double(ss) * L.smoothing) : c0
        let scaled = c.pts.map { $0 / Double(ss) }
        var (pts, ws) = resample(scaled, c.weight, step: L.step)
        if pts.count < 3 { continue }
        var length = 0.0
        for i in 1..<pts.count { length += len2(pts[i] - pts[i - 1]) }
        if length < L.minLength { continue }
        // normals
        var nrm = [V2](repeating: V2(0, 0), count: pts.count)
        for i in 0..<pts.count {
            let a = pts[max(i - 1, 0)], b = pts[min(i + 1, pts.count - 1)]
            let d = norm2(b - a)
            nrm[i] = V2(-d.y, d.x)
        }
        // shade side: lines bordering shade are pressed harder
        for i in 0..<pts.count {
            let side = max(t1.at(pts[i] + nrm[i] * L.shadeProbe), t1.at(pts[i] - nrm[i] * L.shadeProbe))
            ws[i] *= L.shadeBase + L.shadeGain * side
        }
        // split long lines into hand-length strokes that overlap a little
        var start = 0
        while start < pts.count - 1 {
            let want = Int(rng.range(L.strokeMin, L.strokeMax) / L.step)
            var end = min(start + want, pts.count - 1)
            if pts.count - 1 - end < L.minTail { end = pts.count - 1 }
            let seedA = rng.range(0, 1000), seedB = rng.range(0, 1000)
            var sp: [V2] = [], sw: [Double] = [], sr: [Double] = []
            let n = end - start
            for k in 0...n {
                let i = start + k
                let s = Double(k) * L.step
                let fromStart = s, fromEnd = Double(n - k) * L.step
                let wob = (vnoise(V2(s / L.wobbleLength, seedA)) - 0.5) * L.wobble + (vnoise(V2(s / L.tremorLength, seedB)) - 0.5) * L.tremor
                sp.append(pts[i] + nrm[i] * wob)
                let ramp = (c.closed && start == 0 && end == pts.count - 1) ? 1.0
                    : min(1, L.startFloor + L.startGain * sstep(0, L.startLength, fromStart)) * min(1, L.endFloor + L.endGain * sstep(0, L.endLength, fromEnd))
                let wgt = ws[i]
                let press = clampd(wgt * ramp * (L.flutterBase + L.flutterGain * vnoise(V2(s / L.flutterLength, seedA + 5))), 0, 1)
                sr.append(L.pressureMin + L.pressureRange * press)
                sw.append(L.widthMin + L.widthRange * clampd(wgt, 0, L.widthCap) * (0.75 + 0.25 * ramp))
            }
            sheet.stroke(sp, sw, sr)
            start = end - (end < pts.count - 1 ? L.overlap : 0)
            if end == pts.count - 1 { break }
        }
    }
}

/// Hatching: for each layer, parallel lines across the sheet; along each, dashes wherever the tone reaches the layer's
/// threshold, broken where the region changes, pressed harder in deeper shade.
public func drawHatching(_ t1: ToneMap, on sheet: Sheet, rng: inout Rng) {
    let H = sheet.style.hatching
    let W = Double(t1.w), Hh = Double(t1.h)
    for L in H.layers {
        let a = L.angle * Double.pi / 180
        let dir = V2(cos(a), -sin(a)), nr = V2(-dir.y, dir.x)
        let corners = [V2(0, 0), V2(W, 0), V2(0, Hh), V2(W, Hh)]
        let os = corners.map { dot2($0, nr) }, ss = corners.map { dot2($0, dir) }
        var o = os.min()! + L.phase * L.spacing
        while o < os.max()! {
            let oj = o + rng.range(-H.lineJitter, H.lineJitter)
            var s = ss.min()!
            let sEnd = ss.max()!
            // (the scan coordinate s is negative over part of the sheet: "in a run" is a flag, not a sentinel value)
            var inRun = false, runStart = 0.0, runID: Int32 = 0
            func emitRun(_ s0: Double, _ s1: Double) {
                var pos = s0 + rng.range(0, H.startJitter)
                while pos < s1 - H.minDash {
                    let len = rng.range(H.dashMin, H.dashMax)
                    let e = min(pos + len, s1 - rng.range(0, H.endJitter))
                    if e - pos >= H.minDash {
                        let tilt = rng.range(-H.tilt, H.tilt), shift = rng.range(-H.shift, H.shift), bow = rng.range(-H.bow, H.bow)
                        let d2 = rot2(dir, tilt)
                        let mid = nr * (oj + shift) + dir * ((pos + e) / 2)
                        let half = (e - pos) / 2
                        let n = max(Int((e - pos) / 2), 2)
                        var p: [V2] = [], w: [Double] = [], pr: [Double] = []
                        for k in 0...n {
                            let u = Double(k) / Double(n) * 2 - 1
                            let q = mid + d2 * (u * half) + nr * (bow * (1 - u * u))
                            let tone = t1.at(q)
                            let level = sstep(L.threshold, L.threshold + H.ramp, tone)
                            let taper = min(1, (1 - abs(u)) * 4 + 0.25)
                            p.append(q); w.append(L.width * (0.8 + 0.3 * taper))
                            pr.append((L.pressureMin + (L.pressureMax - L.pressureMin) * level) * taper * (tone > L.threshold - H.cutoff ? 1 : 0))
                        }
                        sheet.stroke(p, w, pr)
                    }
                    pos = e + rng.range(H.gapMin, H.gapMax)
                }
            }
            while s <= sEnd {
                let p = nr * oj + dir * s
                let inside = p.x >= 0 && p.y >= 0 && p.x < W && p.y < Hh
                let id = inside ? t1.idAt(p) : 0
                let ok = inside && id != 0 && t1.at(p) >= L.threshold
                if ok && inRun && id != runID { emitRun(runStart, s); runStart = s; runID = id }
                else if ok && !inRun { inRun = true; runStart = s; runID = id }
                else if !ok && inRun { emitRun(runStart, s); inRun = false }
                s += 1
            }
            if inRun { emitRun(runStart, sEnd) }
            o += L.spacing
        }
    }
}

/// The stipple: sparse dots and short flecks, clustered, a little denser in the shade. `density(id, pixel)` gives the
/// factor for a fully covered pixel (≤ 0: none); by default the tone map's own stipple channel.
public func drawStipple(_ t1: ToneMap, on sheet: Sheet, seed: Double, density: ((Int32, Int) -> Double)? = nil) {
    let S = sheet.style.stipple
    for y in 0..<t1.h { for x in 0..<t1.w {
        let i = y * t1.w + x
        let id = t1.id[i]
        guard id != 0, t1.cover[i] > 0.99 else { continue }
        let factor = density?(id, i) ?? Double(t1.stipple[i])
        if factor <= 0 { continue }
        let p = V2(Double(x), Double(y))
        let cluster = sstep(0.35, 0.8, vnoise(p / S.clusterSize + seed) * 0.7 + vnoise(p / S.grainSize - seed) * 0.3)
        let dens = S.density * (S.shadeBase + Double(t1.tone[i]) * S.shadeGain) * (S.clusterBase + S.clusterGain * cluster) * factor
        let r = hash21(p * 0.731 + seed * 1.37)
        if r < dens {
            let h2 = hash21(p * 1.913 - seed)
            let c = p + V2(0.5, 0.5) + V2(hash21(p + 3.1), hash21(p - 7.7)) - 0.5
            if h2 < S.dots {
                sheet.dot(c, S.dotRadius + S.dotRadiusGain * h2, S.dotPressure + S.dotPressureGain * hash21(p + 11))
            } else {   // a short fleck
                let a = hash21(p + 5) * Double.pi
                let d = V2(cos(a), sin(a)) * (1 + 1.5 * hash21(p + 9))
                sheet.stroke([c - d, c + d], [0.9, 0.7], [0.32, 0.22])
            }
        }
    } }
}

/// The soft graphite fill of openings (and the lighter fill of what is seen through them), from the buffer's fill
/// channels, under the hatching. `extra` adds a fill per drawn pixel (its maximum is taken); `scale` scales it all.
public func drawOpenings(_ g: GBuffer, on sheet: Sheet, scale: Double = 1, extra: [Float]? = nil) {
    let F = sheet.style.fill
    sheet.begin()
    let ss = g.ss
    for y in 0..<sheet.h { for x in 0..<sheet.w {
        var c = 0.0, t = 0.0
        for j in 0..<ss { for i in 0..<ss {
            let k = (y * ss + j) * g.w + x * ss + i
            guard g.id[k] > 0 else { continue }
            c += Double(g.fill[k]); t += Double(g.through[k])
        } }
        c /= Double(ss * ss); t /= Double(ss * ss)
        if let e = extra { c = max(c, Double(e[y * sheet.w + x])) }
        if c + t > 0 {
            let gr = Double(sheet.grain[y * sheet.w + x])
            sheet.deposit(x, y, Float((c * (F.opening + F.openingGrain * gr) + t * (F.through + F.throughGrain * gr)) * scale))
        }
    } }
}

/// A soft fill on dark surfaces too narrow for the hatching to darken (black bamboo): `amount(id)` per region, laid
/// as cover × amount × smoothstep(0.4, 0.95, tone).
public func drawToneFill(_ t1: ToneMap, on sheet: Sheet, amount: (Int32) -> Double) {
    sheet.begin()
    for y in 0..<t1.h { for x in 0..<t1.w {
        let i = y * t1.w + x
        let id = t1.id[i]
        guard id != 0 else { continue }
        let f = amount(id)
        if f <= 0 { continue }
        let gr = Double(sheet.grain[i])
        sheet.deposit(x, y, Float(Double(t1.cover[i]) * f * sstep(0.4, 0.95, Double(t1.tone[i])) * (0.75 + 0.25 * gr)))
    } }
}

/// The short ground stroke (two passes) from x0 to x1 at height y (drawn pixels), never over a region `blocked` says
/// stands in front.
public func groundStroke(on sheet: Sheet, _ g: GBuffer, x0: Double, x1: Double, y: Double, blocked: (Int32) -> Bool, rng: inout Rng, press: Double = 1) {
    let G = sheet.style.ground
    let len = x1 - x0
    guard len > 2 else { return }
    let n = max(Int(len / 1.5), 2)
    let seedA = rng.range(0, 1000)
    for pass in 0..<2 {
        let a0 = x0 + (pass == 0 ? 0 : len * rng.range(0.08, 0.2)), a1 = x1 - (pass == 0 ? 0 : len * rng.range(0.15, 0.35))
        var p: [V2] = [], w: [Double] = [], pr: [Double] = []
        for k in 0...n {
            let u = Double(k) / Double(n)
            let x = mixd(a0, a1, u)
            let yy = y + (vnoise(V2(x / G.swayLength, seedA + Double(pass) * 9)) - 0.5) * G.sway + Double(pass) * 1.2 + (u - 0.5) * 0.8
            let q = V2(x, yy)
            let gx = Int(q.x * Double(g.ss)), gy = Int(q.y * Double(g.ss))
            var isBlocked = false
            if gx >= 0, gy >= 0, gx < g.w, gy < g.h {
                let id = g.id[gy * g.w + gx]
                if id > 0 && blocked(id) { isBlocked = true }
            }
            let taper = sstep(0, 0.12, u) * sstep(0, 0.2, 1 - u)
            p.append(q); w.append(G.width - 0.3 * Double(pass)); pr.append(isBlocked ? 0 : (G.pressure + G.pressureGain * taper) * (pass == 0 ? 1 : 0.6) * press)
        }
        sheet.stroke(p, w, pr)
    }
}

/// Where a set of regions meets the ground in the picture: the lowest sample row they show, and their extent across
/// the rows within `rows` samples above it. In drawn pixels: (x0, x1, y) with y just below the lowest row.
public func footprint(_ g: GBuffer, rows: Int, _ member: (Int32) -> Bool) -> (x0: Double, x1: Double, y: Double, lowRow: Int)? {
    var maxY = -1
    var lo = Int.max, hi = Int.min
    for y in stride(from: g.h - 1, through: 0, by: -1) {
        var rlo = Int.max, rhi = Int.min
        for x in 0..<g.w where member(g.id[y * g.w + x]) { rlo = min(rlo, x); rhi = max(rhi, x) }
        if rlo <= rhi {
            if maxY < 0 { maxY = y }
            if y >= maxY - rows { lo = min(lo, rlo); hi = max(hi, rhi) } else { break }
        }
    }
    guard maxY >= 0 else { return nil }
    let ss = Double(g.ss)
    return (Double(lo) / ss, Double(hi) / ss, Double(maxY + 1) / ss, maxY)
}

/// A ground stroke under a footprint, reaching a little past it on each side (as the field guide draws it).
public func groundStroke(on sheet: Sheet, _ g: GBuffer, under f: (x0: Double, x1: Double, y: Double), padScale: Double = 1,
                         blocked: (Int32) -> Bool, rng: inout Rng, press: Double = 1) {
    let pad = max((f.x1 - f.x0) * 0.22, 9) * padScale
    groundStroke(on: sheet, g, x0: f.x0 - pad * rng.range(0.8, 1.3), x1: f.x1 + pad * rng.range(0.9, 1.5), y: f.y + 0.6,
                 blocked: blocked, rng: &rng, press: press)
}

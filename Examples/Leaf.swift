// Leaf.swift: a close study of one leaf, drawn from 2D vector shapes instead of a 3D model, through the same pencil:
// the blade is a filled region shaded across (light from the upper left, a fold along the midrib), its edge toothed;
// the petiole and midrib are regions of their own; the veins are lines; a little damage, a gall, a drop of shade.
import CoreGraphics
import Foundation

func drawLeaf(into out: String) -> [(String, CGImage)] {
    let W = 1000, H = 1100
    let cv = Canvas2D(W, H, stipple: { _ in 0 })
    var rng = Rng(5)
    // the midrib: a gentle curve from the stalk to the tip
    let base = V2(430, 930), tip = V2(610, 120)
    let rib = curve(base, tip - base, len: len2(tip - base), bend: 0.32, n: 60)
    // the blade: half-widths along the rib (widest below the middle), the edge finely toothed
    func halfWidth(_ t: Double) -> Double {
        let w = 300 * pow(sin(Double.pi * pow(t, 0.75)), 1.1) * (1 - 0.15 * t)
        let tooth = 1 - 0.035 * abs(sin(t * 46 * Double.pi))
        return max(w * tooth, 0.5)
    }
    let outline = blade(rib, width: halfWidth)
    // shaded as a shallow V: the half away from the light darker, each half lighter toward its edge
    let leaf = cv.shape(outline, weight: 1.0, kind: 1) { q in
        let (p, d) = nearestOnPolyline(rib, q)
        let n = V2(-d.y, d.x)
        let side = dot2(q - p, n)
        let away = dot2(n, V2(0.62, 0.78)) * side > 0
        let w = max(len2(q - p) / 300, 0)
        return (away ? 0.56 : 0.24) - 0.12 * w
    }
    // the petiole
    let stalk = curve(base + V2(-20, 160), base - (base + V2(-20, 160)), len: 175, bend: -0.2, n: 20)
    cv.shape(blade(stalk) { t in 13 - 4 * t }, weight: 0.9, kind: 2, shade: shadeAcross(stalk[10], shadedSide(norm2(base - stalk[0])), half: 12, lo: 0.25, hi: 0.7))
    // the midrib, raised and pale
    cv.reserve(rib.dropLast(4).map { $0 }, width: 3)
    cv.line(Array(rib.dropLast(3)), weight: 0.62, taper: true)
    // the veins: alternate, curving toward the tip, each with a few veinlets
    for k in 0..<9 {
        let t = 0.10 + Double(k) * 0.088
        let (p, d) = alongPolyline(rib, t)
        for side in [-1.0, 1.0] {
            let tt = t + (side > 0 ? 0.025 : 0)
            let n = V2(-d.y, d.x) * side
            let reach = halfWidth(tt) * 0.92
            let v = curve(p + d * (side > 0 ? 18 : 0), norm2(n * 0.78 + d * 0.62), len: reach, bend: -side * 0.55, n: 24)
            cv.line(v, weight: 0.42, owner: leaf, taper: true)
            for j in 1...3 {
                let (q, e) = alongPolyline(v, 0.25 * Double(j))
                let m = V2(-e.y, e.x) * (j % 2 == 0 ? 1 : -1)
                cv.line(curve(q, norm2(m + e * 0.4), len: rng.range(25, 45), bend: 0.3, n: 8), weight: 0.24, owner: leaf, taper: true)
            }
        }
    }
    // a gall near the edge and a nibbled notch
    let g = V2(700, 560)
    cv.shape(ellipsePoly(g, 24, 19, rot: 0.4), weight: 0.8, kind: 3) { q in 0.62 * sstep(-1, 1, dot2(q - g, V2(0.62, 0.78)) / 24) + 0.2 }
    cv.dot(g + V2(-7, -6), r: 2.2, press: 0.5)
    let sheet = cv.draw(seed: 3)
    let (img, _) = sheet.trimmed()
    save(img, "\(out)/leaf-study")
    return [("leaf-study", img)]
}

/// The point of a polyline at a share f of its length, and its direction there.
func alongPolyline(_ p: [V2], _ f: Double) -> (V2, V2) {
    var c = [0.0]
    for i in 1..<p.count { c.append(c.last! + len2(p[i] - p[i - 1])) }
    let s = f * c.last!
    var i = 0
    while i < p.count - 2 && c[i + 1] < s { i += 1 }
    let t = clampd((s - c[i]) / max(c[i + 1] - c[i], 1e-9), 0, 1)
    return (p[i] + (p[i + 1] - p[i]) * t, norm2(p[i + 1] - p[i]))
}

/// The nearest point of a polyline to q, and the direction there.
func nearestOnPolyline(_ p: [V2], _ q: V2) -> (V2, V2) {
    var best = (p[0], norm2(p[1] - p[0])), bd = 1e18
    for i in 0..<(p.count - 1) {
        let a = p[i], b = p[i + 1], ba = b - a
        let t = clampd(dot2(q - a, ba) / max(dot2(ba, ba), 1e-12), 0, 1)
        let c = a + ba * t
        let d = len2(q - c)
        if d < bd { bd = d; best = (c, norm2(ba)) }
    }
    return best
}

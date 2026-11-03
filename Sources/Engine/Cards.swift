// Cards.swift: thin parts (leaves, petals, blades of grass) as small 3D triangle grids rasterised straight into the
// geometry buffer (region, depth, normal, tone), so the same contour tracer, hatching and stipple draw them as they
// draw the marched surfaces.
import Foundation

/// One triangle with smooth normals, its region and material, and its own contact shade (1 open … 0 enclosed).
public struct Card {
    public var a: V3, b: V3, c: V3
    public var na: V3, nb: V3, nc: V3
    public var id: Int32
    public var material: Material
    public var ao: Double
    /// A glossy leaf leaves the sun's streak as paper (0 … 1).
    public var gloss: Double
    public init(a: V3, b: V3, c: V3, na: V3, nb: V3, nc: V3, id: Int32, material: Material = .plain, ao: Double = 1, gloss: Double = 0) {
        self.a = a; self.b = b; self.c = c; self.na = na; self.nb = nb; self.nc = nc; self.id = id; self.material = material
        self.ao = ao; self.gloss = gloss
    }
}

/// Triangulates a surface given as a grid of points P[i][j] (i along, j across). `look(i, j)` gives the region and
/// material of the quad (i, j) … (i + 1, j + 1).
public func cardGrid(_ P: [[V3]], ao: Double = 1, gloss: Double = 0, look: (Int, Int) -> (Int32, Material)) -> [Card] {
    var out: [Card] = []
    let nu = P.count
    guard nu >= 2 else { return out }
    let nv = P[0].count
    guard nv >= 2 else { return out }
    var N = [[V3]](repeating: [V3](repeating: V3(0, 0, 1), count: nv), count: nu)
    for i in 0..<nu { for j in 0..<nv {
        var du = P[min(i + 1, nu - 1)][j] - P[max(i - 1, 0)][j]
        var dv = P[i][min(j + 1, nv - 1)] - P[i][max(j - 1, 0)]
        if len3(du) < 1e-9 { du = P[min(i + 1, nu - 1)][nv / 2] - P[max(i - 1, 0)][nv / 2] }
        if len3(dv) < 1e-9 {   // a pointed tip or base: borrow the neighbouring row's across direction
            let k = i < nu / 2 ? min(i + 1, nu - 1) : max(i - 1, 0)
            dv = P[k][min(j + 1, nv - 1)] - P[k][max(j - 1, 0)]
        }
        N[i][j] = norm3(cross3(du, dv))
    } }
    for i in 0..<(nu - 1) { for j in 0..<(nv - 1) {
        let (id, m) = look(i, j)
        let a = P[i][j], b = P[i + 1][j], c = P[i + 1][j + 1], d = P[i][j + 1]
        if len3(cross3(b - a, c - a)) > 1e-14 {
            out.append(Card(a: a, b: b, c: c, na: N[i][j], nb: N[i + 1][j], nc: N[i + 1][j + 1], id: id, material: m, ao: ao, gloss: gloss))
        }
        if len3(cross3(c - a, d - a)) > 1e-14 {
            out.append(Card(a: a, b: c, c: d, na: N[i][j], nb: N[i + 1][j + 1], nc: N[i][j + 1], id: id, material: m, ao: ao, gloss: gloss))
        }
    } }
    return out
}

/// Rasterises cards into the buffer with a depth test (the first card drawn wins a tie). `shadow(centre, normal)`
/// gives each card the light reaching it (1 for none), e.g. from the marched masses: `softShadow(subject, …)`.
public func rasterizeCards(_ cards: [Card], _ cam: Camera, into g: GBuffer, light: V3, shadow: ((V3, V3) -> Double)? = nil) {
    let ss = Double(g.ss)
    var shadowOf = [Float](repeating: 1, count: cards.count)
    if let sf = shadow {
        shadowOf.withUnsafeMutableBufferPointer { sB in
            let sP = sB.baseAddress!
            DispatchQueue.concurrentPerform(iterations: (cards.count + 255) / 256) { blk in
                for k in (blk * 256)..<min(blk * 256 + 256, cards.count) {
                    let t = cards[k]
                    let c = (t.a + t.b + t.c) / 3
                    var n = norm3(t.na + t.nb + t.nc)
                    if dot3(n, light) < 0 { n = -n }
                    sP[k] = Float(sf(c, n))
                }
            }
        }
    }
    for (k, t) in cards.enumerated() {
        let pa = cam.project(t.a) * ss, pb = cam.project(t.b) * ss, pc = cam.project(t.c) * ss
        let da = len3(t.a - cam.pos), db = len3(t.b - cam.pos), dc = len3(t.c - cam.pos)
        let area = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x)
        if abs(area) < 1e-9 { continue }
        let x0 = max(Int(min(pa.x, pb.x, pc.x).rounded(.down)), 0), x1 = min(Int(max(pa.x, pb.x, pc.x).rounded(.up)), g.w - 1)
        let y0 = max(Int(min(pa.y, pb.y, pc.y).rounded(.down)), 0), y1 = min(Int(max(pa.y, pb.y, pc.y).rounded(.up)), g.h - 1)
        if x0 > x1 || y0 > y1 { continue }
        let m = t.material
        let sh = Double(shadowOf[k])
        for y in y0...y1 { for x in x0...x1 {
            let q = V2(Double(x) + 0.5, Double(y) + 0.5)
            let w0 = ((pb.x - q.x) * (pc.y - q.y) - (pb.y - q.y) * (pc.x - q.x)) / area
            let w1 = ((pc.x - q.x) * (pa.y - q.y) - (pc.y - q.y) * (pa.x - q.x)) / area
            let w2 = 1 - w0 - w1
            if w0 < -1e-9 || w1 < -1e-9 || w2 < -1e-9 { continue }
            let d = w0 * da + w1 * db + w2 * dc
            let i = y * g.w + x
            if Float(d) >= g.depth[i] { continue }
            var n = norm3(t.na * w0 + t.nb * w1 + t.nc * w2)
            let p = t.a * w0 + t.b * w1 + t.c * w2
            if dot3(n, p - cam.pos) > 0 { n = -n }
            g.id[i] = t.id; g.depth[i] = Float(d); g.nrm[i] = n
            g.stipple[i] = Float(m.stipple); g.fill[i] = Float(m.fill); g.through[i] = Float(m.throughFill)
            var tone: Double
            if let f = m.fixedTone { tone = f } else {
                let diff = max(dot3(n, light), 0)
                tone = m.tone(lit: litTone(diffuse: diff, shadow: sh, occlusion: t.ao))
                if t.gloss > 0 {   // a glossy leaf: the sun's streak left as paper
                    let hv = norm3(light + norm3(cam.pos - p))
                    let spec = pow(max(dot3(n, hv), 0), 22) * sh
                    tone *= 1 - min(1, t.gloss * spec * 1.8)
                }
            }
            g.tone[i] = Float(tone)
        } }
    }
}

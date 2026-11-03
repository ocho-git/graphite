// Mug.swift: a stoneware mug, dipped in glaze, as a subject: two parts (the body and the handle), four drawn regions
// (the bare clay, the glaze, the glazed inside, the handle) and their materials. This is the whole of what a subject
// has to say; the engine frames, marches, shades and draws it.
import CoreGraphics

final class Mug: Subject {
    // sizes in world units (any unit works: the drawing scales its tolerances to the view)
    let R = 0.40           // outer radius
    let H = 0.95           // height
    let wall = 0.045       // wall thickness
    let base = 0.075       // floor thickness
    let glazeLine = 0.30   // the dipped glaze stops this high above the foot (with a wavy, dripping edge)

    /// The drawn regions' kinds (any numbers below 64).
    enum Kind: Int { case clay = 0, glaze, inside, handle }

    var bounds: (lo: V3, hi: V3) { (V3(-R - 0.02, -R - 0.02, 0), V3(R + 0.36, R + 0.02, H + 0.02)) }
    var partCount: Int { 2 }
    var groundZ: Double? { 0 }
    func grounded(_ i: Int) -> Bool { i == 0 }

    /// The body: a rounded cylinder, hollowed out above its floor, the rim rounded.
    func body(_ p: V3) -> Double {
        let rho = len2(V2(p.x, p.y))
        // a slight belly: the wall swells 2 % at mid-height
        let r = R * (1 + 0.02 * sin(Double.pi * clampd(p.z / H, 0, 1)))
        let rr = 0.035
        let q = V2(rho - (r - rr), abs(p.z - H / 2) - (H / 2 - rr))
        let outer = len2(V2(max(q.x, 0), max(q.y, 0))) + min(max(q.x, q.y), 0) - rr
        // the cavity: open at the top, its floor's corner rounded
        let ri = 0.05
        let qi = V2(rho - (r - wall - ri), (base + ri) - p.z)
        let inner = len2(V2(max(qi.x, 0), max(qi.y, 0))) + min(max(qi.x, qi.y), 0) - ri
        return roundedIntersection(outer, -inner, 0.014)
    }

    /// The handle: half a torus standing beside the body, a little taller than wide, flattened across.
    func handle(_ p: V3) -> Double {
        let c = V3(R + 0.06, 0, H * 0.54)
        let q = p - c
        let ring = len2(V2(q.x, q.z / 1.22)) - 0.215
        let d = len2(V2(ring, q.y * 1.35)) - 0.042
        return max(d, R - 0.03 - p.x)      // only the half outside the body
    }

    func sceneSDF(_ p: V3) -> (Double, Int) {
        let b = body(p), h = handle(p)
        return b < h ? (b, 0) : (h, 1)
    }
    func partSDF(_ i: Int, _ p: V3) -> Double { i == 0 ? body(p) : handle(p) }

    func subID(_ i: Int, _ p: V3, _ n: V3) -> Int32 {
        if i == 1 { return SurfaceID.make(1, Kind.handle.rawValue) }
        let rho = len2(V2(p.x, p.y))
        if rho < R - wall * 0.5 && p.z > base * 0.5 { return SurfaceID.make(0, Kind.inside.rawValue) }
        let a = atan2(p.y, p.x)
        let edge = glazeLine + 0.025 * sin(a * 5) + 0.012 * sin(a * 13 + 1)
        return SurfaceID.make(0, p.z < edge ? Kind.clay.rawValue : Kind.glaze.rawValue)
    }

    func material(_ id: Int32, _ p: V3, _ n: V3) -> Material {
        switch Kind(rawValue: SurfaceID.kind(id)) ?? .clay {
        case .clay: return Material(value: 0.04, stipple: 1.6)               // bare stoneware: pale, speckled
        case .glaze, .handle: return Material(value: 0.30, stipple: 0.12)    // a mid-dark glaze
        case .inside: return Material(value: 0.30, minTone: 0.3, stipple: 0)
        }
    }
}

func drawMug(into out: String) -> [(String, CGImage)] {
    let mug = Mug()
    var o = SketchOptions()
    o.seed = 11
    // front: a level eye a little above the rim, the handle to the right
    let front = drawView(mug, .elevation(az: -Double.pi / 2, eyeZ: 1.25, dist: 4.5), o)
    o.seed = 12
    let side = drawView(mug, .elevation(az: -0.25, eyeZ: 1.25, dist: 4.5), o)
    // from above: a parallel view with the cast shadow on the table
    var oa = o
    oa.seed = 13; oa.groundShadow = true; oa.groundStrokes = false; oa.groundReach = 1.2
    let above = drawView(mug, .plan(up: Double.pi / 2), oa)
    // a closer study of where the handle meets the body, ringed on the front view
    o.seed = 14
    let joint = drawDetail(mug, parent: front, target: V3(mug.R + 0.02, -0.02, mug.H * 0.54 + 0.24), radius: 0.16, o)
    print(String(format: "  mug: handle joint ringed at (%.3f, %.3f), r %.3f of the front view", joint.at[0], joint.at[1], joint.r))
    let items = [("mug-front", front.image), ("mug-side", side.image), ("mug-above", above.image), ("mug-handle", joint.image)]
    for (name, img) in items { save(img, "\(out)/\(name)") }
    return items
}

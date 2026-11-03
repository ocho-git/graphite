// Tree.swift: a small broadleaf tree grown by a brancher, on the primitive scene: the trunk and limbs are tapered
// cones in one smoothly united group (so they grow into each other without a seam), each leaf cluster an ellipsoid
// cloud of its own (so a line is drawn where one stands in front of another), the twigs too thin for the marcher drawn
// as 3D pencil strokes, hidden behind whatever stands in front of them.
import CoreGraphics
import Foundation

enum TreeKind: Int { case bark = 0, leaves }

/// Grows a limb from `from` along `dir`: a slightly wandering tube that forks two or three ways until it is a twig,
/// then carries a leaf cluster.
func grow(_ b: PrimitiveBuilder, from: V3, dir: V3, length: Double, radius: Double, depth: Int, wood: Int32, rng: inout Rng) {
    var pts = [from], rads = [radius]
    var p = from, d = norm3(dir)
    let steps = 5
    for k in 1...steps {
        // a little wander, and a gentle pull upward toward the light
        d = norm3(d + V3(rng.range(-0.18, 0.18), rng.range(-0.18, 0.18), rng.range(-0.05, 0.12)) + V3(0, 0, 0.06))
        p += d * (length / Double(steps))
        pts.append(p); rads.append(radius * (1 - 0.32 * Double(k) / Double(steps)))
    }
    b.tube(pts, rads, g: wood, id: SurfaceID.make(0, TreeKind.bark.rawValue))
    if depth == 0 {
        // a leaf cluster: a soft cloud round the twig's end, a little flattened
        let g = b.group(PrimitiveGroup(k: 0.08, amp: 0.035, freq: 7, seed: rng.range(0, 100)))
        let c = p + d * 0.05 + V3(0, 0, 0.04)
        let r = rng.range(0.20, 0.30)
        b.ellip(c, V3(r, r * 0.95, r * 0.72), g: g, id: SurfaceID.make(Int(g), TreeKind.leaves.rawValue))
        if rng.chance(0.7) {
            let off = V3(rng.range(-0.18, 0.18), rng.range(-0.18, 0.18), rng.range(-0.06, 0.10))
            b.ellip(c + off, V3(r, r, r * 0.7) * 0.75, g: g, id: SurfaceID.make(Int(g), TreeKind.leaves.rawValue))
        }
        return
    }
    let forks = depth >= 3 ? 2 : (rng.chance(0.4) ? 3 : 2)
    let (e1, e2) = basis(d)
    let turn = rng.range(0, 2 * Double.pi)
    for f in 0..<forks {
        let a = turn + 2 * Double.pi * Double(f) / Double(forks) + rng.range(-0.3, 0.3)
        let spread = rng.range(0.42, 0.68)
        let nd = norm3(d * cos(spread) + (e1 * cos(a) + e2 * sin(a)) * sin(spread))
        grow(b, from: p, dir: nd, length: length * rng.range(0.66, 0.80), radius: radius * rng.range(0.60, 0.70), depth: depth - 1,
             wood: wood, rng: &rng)
    }
}

func drawTree(into out: String) -> [(String, CGImage)] {
    let b = PrimitiveBuilder()
    b.minTubeR = 0.012                      // thinner than this: a pencil stroke, not a tube
    b.twigPr = 0.55
    let wood = b.group(PrimitiveGroup(k: 0.04, grounded: true))
    var rng = Rng(7)
    // the trunk: a short flared base, then the brancher
    b.cone(V3(0, 0, -0.05), V3(0, 0, 0.35), 0.16, 0.12, g: wood, id: SurfaceID.make(0, TreeKind.bark.rawValue))
    grow(b, from: V3(0, 0, 0.3), dir: V3(0.08, 0.02, 1), length: 1.15, radius: 0.12, depth: 5, wood: wood, rng: &rng)
    // build at any size; draw at the reference scale (largest extent 1.3) so the strokes' depth tolerance fits
    let (lo, hi) = b.extent()
    b.scale(1.3 / max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))
    let tree = PrimitiveScene(b, material: { id, _ in
        SurfaceID.kind(id) == TreeKind.leaves.rawValue ? Material(value: 0.16, stipple: 0.3) : Material(value: 0.28, stipple: 0.8)
    })
    var o = SketchOptions()
    o.seed = 21
    o.groundStrokes = false
    o.rules.silhouette = [TreeKind.leaves.rawValue: 0.6]
    o.rules.partEdge = 0.4
    let height = tree.hi.z
    let side = drawView(tree, .elevation(az: -Double.pi / 2, eyeZ: height * 0.3, dist: 4 * height), o) { cam, g, sheet, rng in
        // the twigs, and a short ground stroke under the trunk
        drawStrokes3D(b.strokes, cam, g, on: sheet, tone: ToneMap(g), rng: &rng)
        if let f = footprint(g, rows: 3 * g.ss, { $0 > 0 && SurfaceID.kind($0) == TreeKind.bark.rawValue }) {
            groundStroke(on: sheet, g, under: (f.x0, f.x1, f.y), padScale: 2, blocked: { SurfaceID.kind($0) != TreeKind.bark.rawValue }, rng: &rng)
        }
    }
    print("  tree: \(b.prims.count) primitives, \(b.strokes.count) twig strokes")
    writePNG(side.image, to: "\(out)/tree.png")
    return [("tree", side.image)]
}

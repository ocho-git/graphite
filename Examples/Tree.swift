// Tree.swift: a small broadleaf tree grown by the library's Brancher, on the primitive scene: the trunk and limbs are
// tapered cones in one smoothly united group (so they grow into each other without a seam), each leaf cluster an
// ellipsoid cloud of its own (so a line is drawn where one stands in front of another), the twigs too thin for the
// marcher drawn as 3D pencil strokes, hidden behind whatever stands in front of them.
import CoreGraphics
import Foundation

enum TreeKind: Int { case bark = 0, leaves }

func drawTree(into out: String) -> [(String, CGImage)] {
    let b = PrimitiveBuilder()
    b.minTubeR = 0.012                      // thinner than this: a pencil stroke, not a tube
    b.twigPr = 0.55
    let wood = b.group(PrimitiveGroup(k: 0.04, grounded: true))
    var rng = Rng(7)
    // the trunk: a short flared base, then the brancher (the library's, with its defaults)
    b.cone(V3(0, 0, -0.05), V3(0, 0, 0.35), 0.16, 0.12, g: wood, id: SurfaceID.make(0, TreeKind.bark.rawValue))
    let brancher = Brancher(bark: SurfaceID.make(0, TreeKind.bark.rawValue), leaf: { g in SurfaceID.make(Int(g), TreeKind.leaves.rawValue) })
    brancher.grow(b, from: V3(0, 0, 0.3), dir: V3(0.08, 0.02, 1), length: 1.15, radius: 0.12, depth: 5, wood: wood, rng: &rng)
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
    save(side.image, "\(out)/tree")
    return [("tree", side.image)]
}

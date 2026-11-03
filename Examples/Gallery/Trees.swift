// Trees.swift: a tree grown by the library's Brancher with its knobs drawn from a seed: how far the forks spread, how
// the limbs shorten and thin, how much they wander and reach for the light, how often they fork three ways, the size
// and flatness of the leaf clouds. Its twigs are 3D pencil strokes, hidden behind whatever stands in front of them.
import Foundation

enum TreePart: Int { case bark = 0, leaves }

func makeTree(_ rng: inout Rng) -> Piece {
    let b = PrimitiveBuilder()
    b.minTubeR = 0.012
    b.twigPr = 0.55
    let wood = b.group(PrimitiveGroup(k: 0.04, grounded: true))
    var br = Brancher(bark: SurfaceID.make(0, TreePart.bark.rawValue), leaf: { g in SurfaceID.make(Int(g), TreePart.leaves.rawValue) })
    let s0 = rng.range(0.2, 0.6)
    br.spread = (s0, s0 + rng.range(0.1, 0.45))
    br.lengthRatio = (rng.range(0.58, 0.7), rng.range(0.72, 0.86))
    br.radiusRatio = (rng.range(0.55, 0.62), rng.range(0.64, 0.72))
    br.wander = rng.range(0.06, 0.3)
    br.pull = rng.range(-0.06, 0.14)
    br.threeWays = rng.range(0, 0.6)
    var leaves = Brancher.Leaves()
    leaves.size = (rng.range(0.12, 0.2), rng.range(0.22, 0.34))
    let flat = rng.range(0.5, 0.9)
    leaves.shape = V3(1, 0.95, flat)
    leaves.secondShape = V3(1, 1, flat)
    leaves.second = rng.range(0.2, 0.9)
    br.leaves = leaves
    let depth = 4 + Int(rng.uni() * 3)
    let lean = V3(rng.range(-0.3, 0.3), rng.range(-0.2, 0.2), 1)
    b.cone(V3(0, 0, -0.05), V3(0, 0, 0.35), 0.16, 0.12, g: wood, id: SurfaceID.make(0, TreePart.bark.rawValue))
    br.grow(b, from: V3(0, 0, 0.3), dir: lean, length: rng.range(0.9, 1.35), radius: 0.12, depth: depth, wood: wood, rng: &rng)
    let (lo, hi) = b.extent()
    b.scale(1.3 / max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))
    let leafV = rng.range(0.08, 0.3), barkV = rng.range(0.2, 0.4)
    let tree = PrimitiveScene(b, material: { id, _ in
        SurfaceID.kind(id) == TreePart.leaves.rawValue ? Material(value: leafV, stipple: 0.3) : Material(value: barkV, stipple: 0.8)
    })
    var m = piece(tree)
    m.options.groundStrokes = false
    m.options.rules.silhouette = [TreePart.leaves.rawValue: 0.6]
    m.options.rules.partEdge = 0.4
    m.extras = { fromAbove in
        return { cam, g, sheet, rng in
            drawStrokes3D(b.strokes, cam, g, on: sheet, tone: ToneMap(g), rng: &rng)
            if fromAbove { return }
            if let f = footprint(g, rows: 3 * g.ss, { $0 > 0 && SurfaceID.kind($0) == TreePart.bark.rawValue }) {
                groundStroke(on: sheet, g, under: (f.x0, f.x1, f.y), padScale: 2, blocked: { SurfaceID.kind($0) != TreePart.bark.rawValue }, rng: &rng)
            }
        }
    }
    return m
}

// Brancher.swift: grows a branching tree on a PrimitiveBuilder. From a start, a limb is a slightly wandering tube that
// tapers as it rises, then forks two or three ways, again and again, until its twigs carry leaf clusters. The limbs go
// into one wood group (smoothly united, so they grow into each other without a seam); each leaf cluster is a soft,
// noisy cloud in a group of its own (so a line is drawn where one stands in front of another); tubes thinner than the
// builder's `minTubeR` become 3D pencil strokes. Every irregularity comes from the Rng it is given: a seed fixes the
// tree. The defaults grow the example tree (Examples/Tree.swift).
import Foundation

public struct Brancher {
    /// Segments per limb.
    public var steps = 5
    /// Each segment turns a little: sideways by up to ±`wander` (x and y), up or down by `rise` (lo … hi), and up by a
    /// steady `pull` toward the light (before the direction is normalised).
    public var wander = 0.18
    public var rise: (lo: Double, hi: Double) = (-0.05, 0.12)
    public var pull = 0.06
    /// The share of its starting radius a limb has lost at its end.
    public var taper = 0.32
    /// A limb forks two ways from depth `twoWaysFrom` up; below that, three ways with the chance `threeWays`.
    public var twoWaysFrom = 3
    public var threeWays = 0.4
    /// The angle between a fork and its parent (radians), and the jitter (±, radians) round the forks' even turn.
    public var spread: (lo: Double, hi: Double) = (0.42, 0.68)
    public var forkJitter = 0.3
    /// A fork's length and radius, as shares of its parent's.
    public var lengthRatio: (lo: Double, hi: Double) = (0.66, 0.80)
    public var radiusRatio: (lo: Double, hi: Double) = (0.60, 0.70)

    /// The leaf cluster at a twig's end: a cloud in a group of its own.
    public struct Leaves {
        /// The group's smooth union, surface noise amplitude and frequency.
        public var k = 0.08, amp = 0.035, freq = 7.0
        /// Its centre: `ahead` past the twig's end along it, `up` above.
        public var ahead = 0.05, up = 0.04
        /// Its size r (lo … hi), and its radii as shares of r.
        public var size: (lo: Double, hi: Double) = (0.20, 0.30)
        public var shape = V3(1, 0.95, 0.72)
        /// A second cloud beside it, with this chance: offset by up to ±`offset` across and `offsetZ` (lo … hi) up,
        /// its radii `secondShape` × `secondScale` × r.
        public var second = 0.7
        public var offset = 0.18
        public var offsetZ: (lo: Double, hi: Double) = (-0.06, 0.10)
        public var secondShape = V3(1, 1, 0.7), secondScale = 0.75
        public init() {}
    }
    /// The leaf clusters (nil: bare twigs).
    public var leaves: Leaves? = Leaves()
    /// Called at each twig's end instead of the leaf cluster, when set: the builder, the end, the twig's direction.
    public var tip: ((PrimitiveBuilder, V3, V3, inout Rng) -> Void)? = nil

    /// The bark's region, and a leaf cluster's region from its group.
    public var bark: Int32
    public var leaf: (Int32) -> Int32

    public init(bark: Int32, leaf: @escaping (Int32) -> Int32) { self.bark = bark; self.leaf = leaf }

    /// Grows a limb from `from` along `dir` into the group `wood`, `depth` forkings deep, and everything above it.
    public func grow(_ b: PrimitiveBuilder, from: V3, dir: V3, length: Double, radius: Double, depth: Int, wood: Int32, rng: inout Rng) {
        var pts = [from], rads = [radius]
        var p = from, d = norm3(dir)
        for k in 1...steps {
            d = norm3(d + V3(rng.range(-wander, wander), rng.range(-wander, wander), rng.range(rise.lo, rise.hi)) + V3(0, 0, pull))
            p += d * (length / Double(steps))
            pts.append(p); rads.append(radius * (1 - taper * Double(k) / Double(steps)))
        }
        b.tube(pts, rads, g: wood, id: bark)
        if depth == 0 {
            if let t = tip { t(b, p, d, &rng) } else if let L = leaves { cluster(b, L, end: p, dir: d, rng: &rng) }
            return
        }
        let forks = depth >= twoWaysFrom ? 2 : (rng.chance(threeWays) ? 3 : 2)
        let (e1, e2) = basis(d)
        let turn = rng.range(0, 2 * Double.pi)
        for f in 0..<forks {
            let a = turn + 2 * Double.pi * Double(f) / Double(forks) + rng.range(-forkJitter, forkJitter)
            let s = rng.range(spread.lo, spread.hi)
            let nd = norm3(d * cos(s) + (e1 * cos(a) + e2 * sin(a)) * sin(s))
            let l = length * rng.range(lengthRatio.lo, lengthRatio.hi)
            let r = radius * rng.range(radiusRatio.lo, radiusRatio.hi)
            grow(b, from: p, dir: nd, length: l, radius: r, depth: depth - 1, wood: wood, rng: &rng)
        }
    }

    /// A leaf cluster at a twig's end.
    func cluster(_ b: PrimitiveBuilder, _ L: Leaves, end p: V3, dir d: V3, rng: inout Rng) {
        let g = b.group(PrimitiveGroup(k: L.k, amp: L.amp, freq: L.freq, seed: rng.range(0, 100)))
        let c = p + d * L.ahead + V3(0, 0, L.up)
        let r = rng.range(L.size.lo, L.size.hi)
        b.ellip(c, V3(r * L.shape.x, r * L.shape.y, r * L.shape.z), g: g, id: leaf(g))
        if rng.chance(L.second) {
            let off = V3(rng.range(-L.offset, L.offset), rng.range(-L.offset, L.offset), rng.range(L.offsetZ.lo, L.offsetZ.hi))
            b.ellip(c + off, V3(r * L.secondShape.x, r * L.secondShape.y, r * L.secondShape.z) * L.secondScale, g: g, id: leaf(g))
        }
    }
}

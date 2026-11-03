// Piece.swift: a gallery subject made from a seed: the subject itself (any kind, behind closures), its own drawing
// options, extras and close-up, and the view and light the seed picks for it.
import CoreGraphics
import Foundation

/// A subject ready to draw, whatever its type.
struct Piece {
    var bounds: (lo: V3, hi: V3)
    var options = SketchOptions()
    var draw: (View, SketchOptions, V3?, Extras?) -> Drawing
    var detail: (Drawing, V3, Double, SketchOptions) -> CGImage
    /// Pencil work of its own after the contours (a tree's twigs), given whether the view is from above.
    var extras: ((Bool) -> Extras?)? = nil
    /// A ringed close-up: the point, its radius (world) and what it shows.
    var closeUp: (target: V3, radius: Double, what: String)? = nil
    /// The views its seed may pick, and a front view's eye height as shares of its height.
    var angles: [Angle] = Angle.allCases
    var frontEye: (Double, Double) = (0.5, 1.05)
    /// A cast shadow on the ground in views from above.
    var planShadow = true
}

func piece<S: Subject>(_ s: S) -> Piece {
    Piece(bounds: s.bounds,
          draw: { v, o, light, ex in drawView(s, v, o, light: light, extras: ex) },
          detail: { parent, t, r, o in drawDetail(s, parent: parent, target: t, radius: r, o).image })
}

enum Angle: String, CaseIterable {
    case front = "front"
    case threeQuarter = "three-quarter"
    case littleAbove = "a little from above"
    case above = "from above"
}

/// A view and a light picked by a seed.
struct Pick {
    var angle: Angle
    var view: View
    /// −1 upper left … +1 upper right.
    var lateral: Double
    /// How high the light stands (elevations and three-quarter views).
    var lightUp: Double
}

func pickView(_ rng: inout Rng, lo: V3, hi: V3, angles: [Angle], frontEye: (Double, Double) = (0.5, 1.05)) -> Pick {
    let size = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
    let height = max(hi.z, 0.2)
    let a = choose(angles, &rng)
    let side: Double = rng.chance(0.5) ? 1 : -1
    let dist = size * rng.range(3.6, 5.0)
    let view: View
    switch a {
    case .front:
        view = .elevation(az: -Double.pi / 2 + rng.range(-0.25, 0.25), eyeZ: height * rng.range(frontEye.0, frontEye.1), dist: dist)
    case .threeQuarter:
        view = .threeQuarter(az: -Double.pi / 2 + side * rng.range(0.55, 0.95), elev: rng.range(14, 26), dist: dist)
    case .littleAbove:
        view = .threeQuarter(az: -Double.pi / 2 + rng.range(-0.45, 0.45), elev: rng.range(30, 48), dist: dist)
    case .above:
        view = .plan(up: Double.pi / 2 + rng.range(-0.6, 0.6))
    }
    return Pick(angle: a, view: view, lateral: rng.range(-1, 1), lightUp: rng.range(0.5, 0.85))
}

/// The light for a view, swung from the upper left of the picture (lateral −1) to the upper right (+1).
func swungLight(_ v: View, _ b: (lo: V3, hi: V3), lateral: Double, up: Double) -> V3 {
    let (cam, toEye, _) = viewCamera(v, lo: b.lo, hi: b.hi)
    if cam.ortho { return norm3(cam.right * (0.32 * lateral) + cam.up * 0.27 + V3(0, 0, 1)) }
    let horiz = norm3(V3(toEye.x, toEye.y, 0))
    return norm3(cam.right * (0.62 * lateral) + horiz * 0.5 + V3(0, 0, up))
}

/// A loose pencil ring round a world point (where a close-up is taken), drawn as one overlapping stroke.
func ringExtras(target: V3, radius: Double) -> Extras {
    return { cam, _, sheet, rng in
        let c = cam.project(target)
        let r = radius * cam.scaleAt(target)
        let a0 = rng.range(0, 2 * Double.pi), ph = rng.range(0, 10)
        let n = 160
        var pts: [V2] = [], w: [Double] = [], pr: [Double] = []
        for k in 0...n {
            let u = Double(k) / Double(n)
            let a = a0 + u * (2 * Double.pi + 0.45)
            let rr = r * (1 + 0.035 * sin(2 * a + ph) + 0.012 * sin(7 * a + ph * 2)) + 4 * u
            pts.append(c + V2(cos(a), sin(a)) * rr)
            w.append(1.5)
            pr.append(0.62 * sstep(0, 0.05, u) * sstep(0, 0.08, 1 - u) + 0.05)
        }
        sheet.stroke(pts, w, pr)
    }
}

func combine(_ a: Extras?, _ b: Extras?) -> Extras? {
    guard let a else { return b }
    guard let b else { return a }
    return { cam, g, sheet, rng in a(cam, g, sheet, &rng); b(cam, g, sheet, &rng) }
}

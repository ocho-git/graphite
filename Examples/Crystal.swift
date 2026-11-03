// Crystal.swift: a quartz crystal drawn as a single region, to show creases. Lines are traced where the region
// changes, so a faceted shape that is one region draws only its outline; with `ContourRules.creaseAngle` set, the
// edges where its faces meet are traced too. The crystal is a ShapeSubject of one part: a six-sided prism, a little
// irregular, with a pointed termination, leaning, cut by the ground.
import CoreGraphics
import Foundation

/// The crystal's distance (a bound: the largest of its faces' plane distances, which is exact on the faces).
func crystal(_ q: V3) -> Double {
    // into the crystal's frame: it leans 8° toward +x and is turned a little about its own axis
    let p = rotZ(rotY(q, -0.14), 0.3)
    var d = -p.z - 0.12                                            // a base below the ground (the ground cuts it)
    let apothem: [Double] = [0.15, 0.175, 0.16, 0.14, 0.17, 0.155]
    let twist: [Double] = [0.02, -0.03, 0.0, 0.04, -0.02, 0.01]
    let apex: [Double] = [1.3, 1.27, 1.31, 1.26, 1.29, 1.28]
    for k in 0..<6 {
        let a = Double(k) * Double.pi / 3 + twist[k]
        let h = V2(cos(a), sin(a))
        d = max(d, dot2(V2(p.x, p.y), h) - apothem[k])          // the prism's side
        // the termination: a face 52° to the axis through (nearly) one apex
        let n = V3(h.x * 0.79, h.y * 0.79, 0.62)
        d = max(d, dot3(p - V3(0, 0, apex[k]), n))
    }
    return max(d, -q.z)
}

func drawCrystal(into out: String) -> [(String, CGImage)] {
    let s = ShapeSubject()
    s.add(.init(lo: V3(-0.3, -0.3, 0), hi: V3(0.5, 0.3, 1.35), grounded: true, sdf: crystal,
                material: { _, _, _ in Material(value: 0.06, stipple: 0) }))
    var o = SketchOptions()
    o.seed = 31
    o.march.stepScale = 0.8
    let view = View.threeQuarter(az: -1.95, elev: 20, dist: 5.5)
    let plain = drawView(s, view, o)                        // one region: the outline only
    o.rules.creaseAngle = 30                                // and where the faces meet
    let creased = drawView(s, view, o)
    let items = [("crystal", plain.image), ("crystal-creases", creased.image)]
    for (name, img) in items { writePNG(img, to: "\(out)/\(name).png") }
    return items
}

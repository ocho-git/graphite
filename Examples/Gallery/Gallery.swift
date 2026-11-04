// Gallery.swift: subjects the engine was never tuned for, each built from a seed (its proportions, its regions, its
// view and the side its light comes from), drawn into output/gallery/ with a contact sheet; and one of them drawn in
// four styles.
import CoreGraphics
import Foundation

struct GalleryEntry {
    var name: String
    var caption: String
    var seed: UInt64
    var build: (inout Rng) -> Piece
    /// A view of its own in place of the one its seed picks (the seed still picks the light).
    var view: ((Piece) -> View)? = nil
}

/// A three-quarter view round the subject's front, `turn` radians to the side, from `elev` degrees up.
func threeQuarter(_ m: Piece, turn: Double, elev: Double, dist: Double = 4.2) -> View {
    let size = max(m.bounds.hi.x - m.bounds.lo.x, m.bounds.hi.y - m.bounds.lo.y, m.bounds.hi.z - m.bounds.lo.z)
    return .threeQuarter(az: -Double.pi / 2 + turn, elev: elev, dist: size * dist)
}

let galleryEntries: [GalleryEntry] = [
    GalleryEntry(name: "lighthouse", caption: "a lighthouse", seed: 276203, build: makeLighthouse),
    GalleryEntry(name: "arcade", caption: "an arcade", seed: 787420, build: makeArcade),
    GalleryEntry(name: "crystals", caption: "crystals, creased", seed: 642986, build: makeCrystals,
                 view: { threeQuarter($0, turn: 0.35, elev: 40) }),
    GalleryEntry(name: "mushrooms", caption: "mushrooms", seed: 174374, build: makeMushrooms),
    GalleryEntry(name: "vase", caption: "a glazed vase", seed: 712646, build: { makeVessel(&$0, shape: "vase") }),
    GalleryEntry(name: "bottle", caption: "a corked bottle", seed: 48203, build: { makeVessel(&$0, shape: "bottle") }),
    GalleryEntry(name: "bowl", caption: "a bowl", seed: 453992, build: { makeVessel(&$0, shape: "bowl") },
                 view: { threeQuarter($0, turn: 0.6, elev: 32) }),
    GalleryEntry(name: "queen", caption: "a chess queen", seed: 923282, build: makeChess),
    GalleryEntry(name: "books", caption: "a stack of books", seed: 986086, build: makeBooks),
    GalleryEntry(name: "pebbles", caption: "a pile of pebbles", seed: 55353, build: makePebbles),
    GalleryEntry(name: "boulder", caption: "a boulder and stones", seed: 738548, build: makeBoulder),
    GalleryEntry(name: "tree", caption: "a tree", seed: 4242, build: makeTree,
                 view: { threeQuarter($0, turn: 0.5, elev: 12, dist: 4) }),
]

/// Draws one entry (and its close-up, if it has one).
func drawEntry(_ e: GalleryEntry, style: Style? = nil, palette: ((Int32) -> Pigment?)? = nil) -> [(name: String, caption: String, image: CGImage)] {
    var rng = Rng(e.seed)
    let m = e.build(&rng)
    let pk = pickView(&rng, lo: m.bounds.lo, hi: m.bounds.hi, angles: m.angles, frontEye: m.frontEye)
    let view = e.view?(m) ?? pk.view
    var o = m.options
    o.seed = e.seed % 100_000 + 1
    if let s = style { o.style = s }
    o.palette = palette
    var fromAbove = false
    if case .plan = view { fromAbove = true }
    if fromAbove {
        o.groundStrokes = false
        if m.planShadow {
            o.groundShadow = true
            o.groundReach = 0.8 * max(m.bounds.hi.x - m.bounds.lo.x, m.bounds.hi.y - m.bounds.lo.y)
        }
    }
    let light = swungLight(view, m.bounds, lateral: pk.lateral, up: pk.lightUp)
    var extras = m.extras?(fromAbove)
    if let c = m.closeUp { extras = combine(extras, ringExtras(target: c.target, radius: c.radius)) }
    let d = m.draw(view, o, light, extras)
    if let err = d.error { print("  \(e.name): \(err)") }
    var out = [(e.name, e.caption, d.image)]
    if let c = m.closeUp, style == nil {
        out.append(("\(e.name)-\(c.what.replacingOccurrences(of: "the ", with: ""))", "\(e.caption): \(c.what)", m.detail(d, c.target, c.radius, o)))
    }
    return out
}

func drawGallery(into out: String) -> [(String, CGImage)] {
    let dir = out + "/gallery"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var cells: [(label: String, image: CGImage)] = []
    for e in galleryEntries {
        let t0 = Date()
        let drawn = drawEntry(e)
        for d in drawn { save(d.image, "\(dir)/\(d.name)") }
        cells.append((drawn[0].caption, drawn[0].image))
        print(String(format: "  %@: %.1f s", e.name, Date().timeIntervalSince(t0)))
    }
    savePreview(contactSheet(cells, cell: 290, columns: 4), "\(out)/gallery", long: nil)
    return []
}

// MARK: - Styles

/// Bold, even lines and sparse hatching, on smooth paper.
func inkStyle() -> Style {
    var s = Style()
    s.pencil.gamma = 0.8; s.pencil.opacity = 0.96
    s.paper.toothBase = 0.65
    s.line.widthMin = 1.0; s.line.widthRange = 2.6; s.line.widthCap = 1.3
    s.line.pressureMin = 0.5; s.line.pressureRange = 0.9
    s.line.wobble = 0.6; s.line.tremor = 0.12
    s.line.strokeMin = 120; s.line.strokeMax = 320
    s.hatching.layers = [
        Style.HatchLayer(angle: 55, spacing: 11, phase: 0, threshold: 0.4, pressureMin: 0.3, pressureMax: 0.55, width: 1.1),
        Style.HatchLayer(angle: -32, spacing: 11, phase: 0.3, threshold: 0.75, pressureMin: 0.35, pressureMax: 0.6, width: 1.1),
    ]
    s.hatching.dashMin = 30; s.hatching.dashMax = 80
    s.stipple.density = 0.004
    return s
}

/// A light, quick hand: faint, short, wandering strokes on rough paper.
func sketchyStyle() -> Style {
    var s = Style()
    s.pencil.opacity = 0.75
    s.paper.toothBase = 0.12; s.paper.toothPressure = 0.45
    s.line.widthMin = 0.5; s.line.widthRange = 1.1
    s.line.pressureMin = 0.12; s.line.pressureRange = 0.5
    s.line.wobble = 3.0; s.line.wobbleLength = 26; s.line.tremor = 0.8; s.line.tremorLength = 5
    s.line.strokeMin = 25; s.line.strokeMax = 80; s.line.overlap = 4
    s.hatching.layers = s.hatching.layers.map { l in var l = l; l.pressureMin *= 0.7; l.pressureMax *= 0.7; return l }
    s.hatching.tilt = 0.1; s.hatching.shift = 1.6; s.hatching.bow = 1.8; s.hatching.lineJitter = 1.6
    s.hatching.dashMin = 8; s.hatching.dashMax = 26; s.hatching.gapMin = 3; s.hatching.gapMax = 9
    return s
}

/// Closer, earlier hatching with a third direction.
func denseStyle() -> Style {
    var s = Style()
    var layers = s.hatching.layers.map { l in var l = l; l.spacing *= 0.55; l.threshold = max(l.threshold - 0.07, 0.12); return l }
    layers.append(Style.HatchLayer(angle: 10, spacing: 3.6, phase: 0.4, threshold: 0.58, pressureMin: 0.22, pressureMax: 0.45, width: 0.9))
    s.hatching.layers = layers
    s.hatching.dashMin = 24; s.hatching.dashMax = 60; s.hatching.gapMin = 1; s.hatching.gapMax = 3
    return s
}

/// The vase in four styles: the same model, view and light, four hands.
func drawStyles(into out: String) -> [(String, CGImage)] {
    let dir = out + "/gallery"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let vase = galleryEntries.first { $0.name == "vase" }!
    var cells: [(label: String, image: CGImage)] = []
    for (name, style) in [("standard", Style.standard), ("ink-like", inkStyle()), ("light and sketchy", sketchyStyle()),
                          ("dense hatching", denseStyle())] {
        let img = drawEntry(vase, style: style)[0].image
        writePNG(img, to: "\(dir)/vase-\(name.replacingOccurrences(of: " ", with: "-")).png")
        cells.append((name, img))
    }
    savePreview(contactSheet(cells, cell: 560, columns: 2), "\(out)/styles", long: nil)
    return []
}

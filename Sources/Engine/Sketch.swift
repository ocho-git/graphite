// Sketch.swift: the whole drawing in one call. A view of a subject is framed (a quick coarse pass finds it), marched
// at two samples per pixel, drawn in graphite (openings, hatching, stipple, contours, your extras, ground strokes) and
// trimmed to its ink. A detail is a closer study of a view: the same eye, a narrower field, fading out in a loose
// circle, with where to ring it on its parent.
import CoreGraphics
import Foundation

/// Where the eye is.
public enum View {
    /// A level eye at height eyeZ, `dist` world units from the subject's centre, looking from plan angle `az`
    /// (radians, 0 = from +x): an elevation, verticals upright.
    case elevation(az: Double, eyeZ: Double, dist: Double)
    /// Looking down at `elev` degrees from plan angle `az` toward the subject's centre, `dist` away.
    case threeQuarter(az: Double, elev: Double, dist: Double)
    /// Straight down, parallel projection; the plan direction `up` (radians) is the top of the picture.
    case plan(up: Double)
}

public struct SketchOptions {
    public var style: Style = .standard
    /// The contour rules (the subject's own edgeWeight is consulted after the depth test).
    public var rules = ContourRules()
    /// Kinds that never take stipple (whatever their material says): openings, paper.
    public var noStipple: Set<Int> = []
    /// A cast shadow on the subject's ground plane (Subject.groundZ) out to `groundReach` from its centre, as kind
    /// `groundShadowKind` (hatched, never outlined).
    public var groundShadow = false
    public var groundReach = 1.0
    public var groundShadowKind = 63
    /// Short strokes on the ground under the grounded parts.
    public var groundStrokes = true
    /// A grounded part's foot may hide behind another part: its stroke is left out when its foot is more than
    /// 8 px + footRadius (world) away from the part's lowest pixel.
    public var footRadius = 0.045
    /// The subject's long side on the canvas (px) before trimming.
    public var longSide = 1100.0
    /// Seeds the hand: the same seed draws the same lines.
    public var seed: UInt64 = 1
    /// How the shading is shared between samples, and the march's step limits (its unit is set per view).
    public var sharing: ShadeSharing = .perPixel
    public var march = MarchSettings()
    /// World size of a pixel at the reference scale: everything finer is scaled from it (the tolerances of the march,
    /// shadows, occlusion and contours).
    public var referencePixel = 0.0016
    /// The trim.
    public var trim: Trim = .standard
    public init() {}
}

/// A drawn view: the image (trimmed), the camera that drew it, its frame on the canvas, and where the eye was.
public struct Drawing {
    public var cam: Camera
    public var image: CGImage
    /// The trimmed image's frame on the canvas (top-left origin).
    public var crop: CGRect
    public var toEye: V3
    /// Where a world point lands on the trimmed image, normalised 0 … 1 (x right, y down).
    public func normalised(_ p: V3) -> V2 {
        let s = cam.project(p)
        return V2((s.x - crop.minX) / crop.width, (s.y - crop.minY) / crop.height)
    }
}

/// The light from the upper left of the picture, a little toward the eye.
public func lightFor(right: V3, toEye: V3, up: V3) -> V3 { norm3(right * -0.62 + toEye * 0.50 + up * 0.62) }

/// The camera, the direction to the eye and the light for a view of a subject with these bounds.
public func viewCamera(_ v: View, lo: V3, hi: V3) -> (Camera, V3, V3) {
    let c = (lo + hi) / 2
    switch v {
    case let .elevation(az, eyeZ, dist):
        let toEye = V3(cos(az), sin(az), 0)
        let cam = Camera(pos: V3(c.x, c.y, 0) + toEye * dist + V3(0, 0, eyeZ), fwd: -toEye, right: V3(-sin(az), cos(az), 0), up: V3(0, 0, 1))
        return (cam, toEye, lightFor(right: cam.right, toEye: toEye, up: V3(0, 0, 1)))
    case let .threeQuarter(az, elev, dist):
        let e = elev * Double.pi / 180
        let dir = V3(cos(az) * cos(e), sin(az) * cos(e), sin(e))
        let right = V3(-sin(az), cos(az), 0)
        let fwd = -dir
        let up = V3(right.y * fwd.z - right.z * fwd.y, right.z * fwd.x - right.x * fwd.z, right.x * fwd.y - right.y * fwd.x)
        let cam = Camera(pos: c + dir * dist, fwd: fwd, right: right, up: norm3(up))
        let horiz = V3(cos(az), sin(az), 0)
        return (cam, dir, lightFor(right: right, toEye: horiz, up: V3(0, 0, 1)))
    case let .plan(upAng):
        let U = V3(cos(upAng), sin(upAng), 0)
        let fwd = V3(0, 0, -1)
        let right = V3(fwd.y * U.z - fwd.z * U.y, fwd.z * U.x - fwd.x * U.z, fwd.x * U.y - fwd.y * U.x)
        var cam = Camera(pos: V3(c.x, c.y, hi.z + 2), fwd: fwd, right: right, up: U)
        cam.ortho = true
        // light from the upper left of the picture, ~68° high: shadows fall short, to the lower right
        return (cam, V3(0, 0, 1), norm3(right * -0.32 + U * 0.27 + V3(0, 0, 1.0)))
    }
}

/// The light a view was drawn with (recomputed from its camera, as viewCamera made it).
public func viewLight(_ d: Drawing) -> V3 {
    let cam = d.cam
    if cam.ortho { return norm3(cam.right * -0.32 + cam.up * 0.27 + V3(0, 0, 1.0)) }
    let horiz = norm3(V3(d.toEye.x, d.toEye.y, 0))
    return lightFor(right: cam.right, toEye: horiz, up: V3(0, 0, 1))
}

/// Extra pencil work on a view, after the contours (a subject's own marks: scrolls, banks and water, twigs).
public typealias Extras = (Camera, GBuffer, Sheet, inout Rng) -> Void

/// The render options a sketch uses at a given unit.
public func renderOptions<S: Subject>(_ s: S, _ o: SketchOptions, unit: Double) -> RenderOptions {
    var m = o.march
    m.unit = unit
    var gs: GroundShadow? = nil
    if o.groundShadow, let gz = s.groundZ { gs = GroundShadow(z: gz, reach: o.groundReach, id: SurfaceID.make(s.partCount, o.groundShadowKind)) }
    return RenderOptions(march: m, sharing: o.sharing, groundShadow: gs)
}

/// Draws one view of a subject.
public func drawView<S: Subject>(_ s: S, _ view: View, _ o: SketchOptions = SketchOptions(), extras: Extras? = nil) -> Drawing {
    let b = s.bounds
    var (cam, toEye, light) = viewCamera(view, lo: b.lo, hi: b.hi)
    let size = max(b.hi.x - b.lo.x, b.hi.y - b.lo.y, b.hi.z - b.lo.z)
    let centre = (b.lo + b.hi) / 2
    // framing pass on a coarse buffer (cast shadows included: they are part of the drawing)
    let N = 240
    let pxPerWorld = Double(N) / (size * 1.9)
    cam.f = cam.ortho ? pxPerWorld : pxPerWorld * max(dot3(centre - cam.pos, cam.fwd), 1e-3)
    cam.cx = Double(N) / 2; cam.cy = Double(N) / 2
    let pc = cam.project(centre)
    cam.cx += Double(N) / 2 - pc.x; cam.cy += Double(N) / 2 - pc.y
    var unit = (1 / cam.scaleAt(centre)) / o.referencePixel
    let gc = GBuffer(w: N, h: N, ss: 1)
    render(s, camera: cam, into: gc, light: light, options: renderOptions(s, o, unit: unit))
    var bx0 = 1e9, bx1 = -1e9, by0 = 1e9, by1 = -1e9
    for y in 0..<N { for x in 0..<N where gc.id[y * N + x] != 0 {
        bx0 = min(bx0, Double(x)); bx1 = max(bx1, Double(x + 1)); by0 = min(by0, Double(y)); by1 = max(by1, Double(y + 1))
    } }
    // image-plane extent (u right, v up), independent of f
    let u0 = (bx0 - cam.cx) / cam.f, u1 = (bx1 - cam.cx) / cam.f
    let v0 = (cam.cy - by1) / cam.f, v1 = (cam.cy - by0) / cam.f
    let k = o.longSide / max(u1 - u0, v1 - v0)
    let margin = o.longSide * 0.09
    let W = Int(((u1 - u0) * k + 2 * margin).rounded()), H = Int(((v1 - v0) * k + 2 * margin).rounded())
    cam.f = k
    cam.cx = margin - u0 * k
    cam.cy = margin + v1 * k
    unit = (1 / cam.scaleAt(centre)) / o.referencePixel
    let ss = 2
    let g = GBuffer(w: W * ss, h: H * ss, ss: ss)
    render(s, camera: cam, into: g, light: light, options: renderOptions(s, o, unit: unit))
    let sheet = pencil(s, cam, g, o, unit: unit, extras: extras)
    let (img, crop) = sheet.trimmed(o.trim)
    return Drawing(cam: cam, image: img, crop: crop, toEye: toEye)
}

/// A closer study of `parent`: the same eye, a field `radius` world units round `target`, drawn on a 1000 px canvas
/// and fading out in a loose circle. Returns the image and its ring on the parent: centre `at` (normalised to the
/// parent's image) and radius `r` (a share of the parent's width).
public func drawDetail<S: Subject>(_ s: S, parent: Drawing, target: V3, radius: Double, _ o: SketchOptions = SketchOptions(),
                                   extras: Extras? = nil) -> (image: CGImage, at: [Double], r: Double) {
    var cam = parent.cam
    let S0 = cam.scaleAt(target)
    let R = 470.0, C = 1000
    let mag = R / (radius * S0)
    cam.f *= mag
    cam.cx = 0; cam.cy = 0
    let pt = cam.project(target)
    cam.cx = Double(C) / 2 - pt.x; cam.cy = Double(C) / 2 - pt.y
    let unit = (1 / cam.scaleAt(target)) / o.referencePixel
    let light = viewLight(parent)
    let ss = 2
    let g = GBuffer(w: C * ss, h: C * ss, ss: ss)
    render(s, camera: cam, into: g, light: light, options: renderOptions(s, o, unit: unit))
    let sheet = pencil(s, cam, g, o, unit: unit, extras: extras)
    sheet.fadeCircle(radius: R)
    let (img, _) = sheet.trimmed(o.trim)
    let pp = parent.cam.project(target)
    let at = [(pp.x - parent.crop.minX) / parent.crop.width, (pp.y - parent.crop.minY) / parent.crop.height]
    return (img, at, radius * S0 / parent.crop.width)
}

/// The standard passes over a rendered buffer: openings, hatching, stipple, contours, extras, ground strokes.
public func pencil<S: Subject>(_ s: S, _ cam: Camera, _ g: GBuffer, _ o: SketchOptions, unit: Double, extras: Extras? = nil) -> Sheet {
    let W = g.w / g.ss, H = g.h / g.ss, ss = g.ss
    var rng = Rng(o.seed &* 7919 &+ 17)
    let sheet = Sheet(w: W, h: H, seed: Double(o.seed % 97) * 0.37 + 3, style: o.style)
    let t1 = ToneMap(g)
    drawOpenings(g, on: sheet, scale: pow(min(unit, 1), 0.7))
    drawHatching(t1, on: sheet, rng: &rng)
    let skip = o.noStipple, gsKind = o.groundShadow ? o.groundShadowKind : -1
    drawStipple(t1, on: sheet, seed: Double(o.seed % 89) * 0.53 + 1) { id, i in
        let k = SurfaceID.kind(id)
        return skip.contains(k) || k == gsKind ? 0 : Double(t1.stipple[i])
    }
    var rules = o.rules
    rules.depthGap *= unit
    if o.groundShadow { rules.unlined.insert(o.groundShadowKind) }
    if rules.edge == nil { rules.edge = { a, b in s.edgeWeight(a, b) } }
    drawChains(traceContours(g, rules: rules), on: sheet, tone: t1, ss: ss, rng: &rng)
    extras?(cam, g, sheet, &rng)
    if o.groundStrokes { drawGroundStrokes(s, cam, g, sheet, footRadius: o.footRadius, rng: &rng) }
    return sheet
}

/// A short stroke under each grounded part (its lowest visible edge), never over another part; none where the frame
/// cuts the part (a detail) or where its foot is hidden.
public func drawGroundStrokes<S: Subject>(_ s: S, _ cam: Camera, _ g: GBuffer, _ sheet: Sheet, footRadius: Double = 0.045, rng: inout Rng) {
    let ss = g.ss
    for i in 0..<s.partCount where s.grounded(i) {
        guard let f = footprint(g, rows: 3 * ss, { $0 > 0 && SurfaceID.part($0) == i }) else { continue }
        if f.lowRow >= g.h - 2 * ss { continue }      // cut by the frame: it does not stand there
        if let footPt = s.groundFoot(i) {
            let tol = 8 + footRadius * cam.scaleAt(footPt)
            if abs(cam.project(footPt).y - f.y) > tol { continue }
        }
        groundStroke(on: sheet, g, under: (f.x0, f.x1, f.y), blocked: { SurfaceID.part($0) != i }, rng: &rng)
    }
}

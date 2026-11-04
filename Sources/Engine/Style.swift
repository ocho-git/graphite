// Style.swift: everything that sets the look of the pencil, in one value. `Style.standard` is the default look
// (graphite #3a3d3a, five hatch layers at 55° and −32°, a hand's wobble on every line); change a copy to make
// another.
import Foundation

public struct Style {
    /// The pencil's colour and how deposited graphite turns into ink: alpha = clamp(pow(graphite, gamma) × opacity).
    public struct Pencil {
        public var red: Double, green: Double, blue: Double
        public var opacity: Double
        public var gamma: Double
        public init(red: Double = 0x3a, green: Double = 0x3d, blue: Double = 0x3a, opacity: Double = 0.9, gamma: Double = 0.92) {
            self.red = red; self.green = green; self.blue = blue; self.opacity = opacity; self.gamma = gamma
        }
    }

    /// The paper's tooth: light strokes only touch its peaks. Graphite deposited = coverage × pressure × tooth, with
    /// tooth = mix(grain, 1, clamp(toothBase + toothPressure × pressure)). toothBase 1 makes a smooth paper.
    public struct Paper {
        public var toothBase: Double
        public var toothPressure: Double
        /// Size of the grain (1: about a pixel).
        public var grainScale: Double
        public init(toothBase: Double = 0.3, toothPressure: Double = 0.55, grainScale: Double = 1) {
            self.toothBase = toothBase; self.toothPressure = toothPressure; self.grainScale = grainScale
        }
    }

    /// Lines: traced contours and every curve drawn like one. A chain is smoothed, resampled, split into hand-length
    /// strokes that overlap a little, wobbled, tapered at its ends, pressed harder where it borders shade.
    public struct Line {
        /// Gaussian smoothing of the pixel staircase (sigma, in samples).
        public var smoothing: Double = 1.15
        /// Resampling step (px).
        public var step: Double = 1.2
        /// Chains shorter than this are left out (px).
        public var minLength: Double = 2.5
        /// Stroke lengths: a hand draws a long edge in pieces of strokeMin … strokeMax px, overlapping by `overlap`
        /// points; a remainder shorter than `minTail` points joins the last piece.
        public var strokeMin: Double = 70, strokeMax: Double = 190
        public var overlap: Int = 2, minTail: Int = 25
        /// The hand's wobble across the line: a slow sway (amplitude, wavelength in px) and a quick tremor.
        public var wobble: Double = 1.1, wobbleLength: Double = 38
        public var tremor: Double = 0.3, tremorLength: Double = 6.5
        /// Shade side: a line bordering shade (probed `shadeProbe` px each side) is pressed harder: × (shadeBase + shadeGain × tone).
        public var shadeProbe: Double = 2.5, shadeBase: Double = 0.82, shadeGain: Double = 0.38
        /// Taper: pressure ramps in from startFloor (+ startGain) over startLength px and out over endLength px.
        public var startFloor: Double = 0.45, startGain: Double = 0.55, startLength: Double = 7
        public var endFloor: Double = 0.35, endGain: Double = 0.65, endLength: Double = 10
        /// Pressure flutter along the stroke: × (flutterBase + flutterGain × noise), wavelength flutterLength px.
        public var flutterBase: Double = 0.92, flutterGain: Double = 0.16, flutterLength: Double = 21
        /// Pressure = pressureMin + pressureRange × weight; width = widthMin + widthRange × weight × (0.75 + 0.25 × ramp).
        public var pressureMin: Double = 0.2, pressureRange: Double = 0.78
        public var widthMin: Double = 0.6, widthRange: Double = 1.55
        /// Weights above this are clamped for the width.
        public var widthCap: Double = 1.1
        public init() {}
    }

    /// One layer of hatching: parallel strokes at `angle` degrees (counter-clockwise from the right), `spacing` px
    /// apart, laid wherever the tone reaches `threshold`; their pressure grows from pressureMin to pressureMax over the
    /// next `ramp` of tone.
    public struct HatchLayer {
        public var angle: Double, spacing: Double, phase: Double, threshold: Double
        public var pressureMin: Double, pressureMax: Double, width: Double
        /// The pencil this layer lays in a coloured drawing (ignored in graphite).
        public var ink: Ink
        public init(angle: Double, spacing: Double, phase: Double, threshold: Double, pressureMin: Double, pressureMax: Double, width: Double,
                    ink: Ink = .local(1)) {
            self.angle = angle; self.spacing = spacing; self.phase = phase; self.threshold = threshold
            self.pressureMin = pressureMin; self.pressureMax = pressureMax; self.width = width; self.ink = ink
        }
    }

    public struct Hatching {
        public var layers: [HatchLayer] = [
            HatchLayer(angle: 55, spacing: 6.2, phase: 0.0, threshold: 0.24, pressureMin: 0.20, pressureMax: 0.42, width: 1.0),
            HatchLayer(angle: 55, spacing: 6.2, phase: 0.5, threshold: 0.48, pressureMin: 0.24, pressureMax: 0.46, width: 1.0),
            HatchLayer(angle: -32, spacing: 6.0, phase: 0.2, threshold: 0.66, pressureMin: 0.26, pressureMax: 0.50, width: 1.0),
            HatchLayer(angle: 55, spacing: 6.2, phase: 0.25, threshold: 0.80, pressureMin: 0.30, pressureMax: 0.55, width: 1.05),
            HatchLayer(angle: -32, spacing: 6.0, phase: 0.7, threshold: 0.90, pressureMin: 0.32, pressureMax: 0.58, width: 1.05),
        ]
        /// Each line's offset jitter (± px).
        public var lineJitter: Double = 0.6
        /// Dash lengths (px), the gap between dashes, how far a run may start late or end early, the shortest dash.
        public var dashMin: Double = 14, dashMax: Double = 40
        public var gapMin: Double = 1.5, gapMax: Double = 5
        public var startJitter: Double = 2.5, endJitter: Double = 1.2
        public var minDash: Double = 3
        /// A dash's tilt (radians), sideways shift and bow (px).
        public var tilt: Double = 0.035, shift: Double = 0.5, bow: Double = 0.6
        /// Pressure ramp over this much tone above a layer's threshold; a dash fades where the tone drops `cutoff` below it.
        public var ramp: Double = 0.22, cutoff: Double = 0.04
        /// Turn the layers' angles with the light: by as much as a view's light, seen in the picture, turns away from
        /// its own light at the upper left (drawView and drawDetail given a `light:`). Off: the angles stay put.
        public var followLight: Bool = false
        public init() {}
    }

    /// The speckle on stone-like surfaces: dots and short flecks, clustered, a little denser in the shade.
    public struct Stipple {
        /// Dots per pixel at density factor 1: density × (shadeBase + shadeGain × tone) × (clusterBase + clusterGain × cluster).
        public var density: Double = 0.010
        public var shadeBase: Double = 0.35, shadeGain: Double = 1.1
        public var clusterBase: Double = 0.25, clusterGain: Double = 1.2
        /// Cluster noise sizes (px).
        public var clusterSize: Double = 13, grainSize: Double = 4.5
        /// The share of marks that are dots (the rest are flecks).
        public var dots: Double = 0.75
        /// Dot radius base + gain × random, pressure base + gain × random.
        public var dotRadius: Double = 0.45, dotRadiusGain: Double = 0.45
        public var dotPressure: Double = 0.35, dotPressureGain: Double = 0.35
        public init() {}
    }

    /// Soft fills under the hatching: openings, and what is seen through them.
    public struct Fill {
        public var opening: Double = 0.42, openingGrain: Double = 0.22
        public var through: Double = 0.2, throughGrain: Double = 0.14
        public init() {}
    }

    /// The short stroke on the ground under whatever stands on it.
    public struct Ground {
        public var width: Double = 1.6
        public var pressure: Double = 0.3, pressureGain: Double = 0.6
        public var sway: Double = 1.4, swayLength: Double = 30
        public init() {}
    }

    /// Coloured pencils: which pencil each pass lays, where the drawing's palette (SketchOptions.palette) gives each
    /// region its own colour. nil, the default: graphite.
    public struct Colour {
        /// The pencil for regions the palette leaves out.
        public var fallback = Pigment(0.55, 0.53, 0.50)
        /// The cool pencil laid over the shade (`Ink.shade`).
        public var shade = Pigment(0.50, 0.46, 0.66)
        /// Lines: the region's own pencil deepened, with this share of the shade pencil mixed in.
        public var line: Ink = .local(2.6)
        public var lineShade: Double = 0.25
        public var stipple: Ink = .local(2.2)
        public var opening: Ink = .local(2.4)
        /// The ground strokes' pencil.
        public var ground = Pigment(0.62, 0.56, 0.48)
        public init() {}
    }

    public var pencil = Pencil()
    public var colour: Colour? = nil
    public var paper = Paper()
    public var line = Line()
    public var hatching = Hatching()
    public var stipple = Stipple()
    public var fill = Fill()
    public var ground = Ground()

    public init() {}

    /// The default look.
    public static let standard = Style()

    /// Coloured pencils on a toothy paper: the region's own colour laid in one direction over the whole of it (paper
    /// left at the brightest lights), deepened and crossed by a cool shade pencil where the light falls away, lines in
    /// a deeper shade of their region. Give the drawing a palette (SketchOptions.palette).
    public static let colouredPencil: Style = {
        var s = Style()
        s.colour = Colour()
        s.paper.toothBase = 0.18; s.paper.toothPressure = 0.5; s.paper.grainScale = 1.25
        s.line.widthMin = 0.7; s.line.widthRange = 1.4
        s.line.pressureMin = 0.34; s.line.pressureRange = 0.72
        s.hatching.layers = [
            HatchLayer(angle: 58, spacing: 2.8, phase: 0.0, threshold: -0.02, pressureMin: 0.24, pressureMax: 0.58, width: 1.7, ink: .local(1)),
            HatchLayer(angle: 58, spacing: 2.8, phase: 0.5, threshold: 0.28, pressureMin: 0.16, pressureMax: 0.52, width: 1.6, ink: .local(1)),
            HatchLayer(angle: -30, spacing: 3.2, phase: 0.2, threshold: 0.44, pressureMin: 0.14, pressureMax: 0.50, width: 1.5, ink: .shade),
            HatchLayer(angle: 58, spacing: 2.9, phase: 0.25, threshold: 0.60, pressureMin: 0.18, pressureMax: 0.56, width: 1.5, ink: .local(1.8)),
            HatchLayer(angle: -30, spacing: 3.2, phase: 0.7, threshold: 0.78, pressureMin: 0.22, pressureMax: 0.60, width: 1.5, ink: .local(2.6)),
        ]
        s.hatching.ramp = 0.5
        s.hatching.dashMin = 30; s.hatching.dashMax = 90; s.hatching.gapMin = 1; s.hatching.gapMax = 3.5
        s.hatching.lineJitter = 0.5
        s.stipple.density = 0.006
        return s
    }()
}

/// A coloured pencil: its colour laid at full pressure on white paper (sRGB, 0 … 1). Layers mix as pigments do:
/// each absorbs its share of the light (yellow over blue is green, a pencil over itself deepens).
public struct Pigment {
    public var r: Double, g: Double, b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    /// From a hex number, 0xRRGGBB.
    public init(hex: Int) { self.init(Double((hex >> 16) & 255) / 255, Double((hex >> 8) & 255) / 255, Double(hex & 255) / 255) }
    /// How much of each channel's light a full layer takes (−ln of the colour).
    @inlinable public var absorbance: (Double, Double, Double) {
        (-log(max(r, 0.02)), -log(max(g, 0.02)), -log(max(b, 0.02)))
    }
    /// The same pencil laid k times over.
    public func deepened(_ k: Double) -> Pigment { Pigment(pow(max(r, 0.02), k), pow(max(g, 0.02), k), pow(max(b, 0.02), k)) }
    /// Mixed with another pencil (t of it), as the two would layer.
    public func mixed(_ o: Pigment, _ t: Double) -> Pigment {
        let a = absorbance, c = o.absorbance
        return Pigment(exp(-(a.0 * (1 - t) + c.0 * t)), exp(-(a.1 * (1 - t) + c.1 * t)), exp(-(a.2 * (1 - t) + c.2 * t)))
    }
}

/// Which pencil a pass lays in a coloured drawing.
public enum Ink {
    /// The region's own colour (from the palette), laid k times over.
    case local(Double)
    /// The style's shade pencil.
    case shade
    /// A pencil of its own.
    case fixed(Pigment)
}

// Surface.swift: what a pixel of the geometry buffer shows. Its region id decides where lines go (a contour is drawn
// wherever two neighbouring pixels show different regions); its material decides how dark it is drawn.

/// Region ids: 32-bit numbers packing a part, a kind and an index, `(part + 1) << 12 | kind << 6 | index`.
/// 0 is the paper (nothing there); a negative id is masked out (outside a detail's window: no line, no tone).
/// Any other packing works as well, as long as different regions get different ids; the packing only matters to the
/// helpers that read a part or a kind back (contour rules, ground strokes).
public enum SurfaceID {
    public static let paper: Int32 = 0
    public static let masked: Int32 = -1
    /// part ≥ 0, kind 0 ..< 64, index (wrapped to 0 ..< 64).
    @inlinable @inline(__always) public static func make(_ part: Int, _ kind: Int, _ index: Int = 0) -> Int32 {
        Int32((part + 1) << 12 | kind << 6 | (index & 63))
    }
    @inlinable @inline(__always) public static func part(_ id: Int32) -> Int { Int(id >> 12) - 1 }
    @inlinable @inline(__always) public static func kind(_ id: Int32) -> Int { Int((id >> 6) & 63) }
    @inlinable @inline(__always) public static func index(_ id: Int32) -> Int { Int(id & 63) }
}

/// How a surface is drawn. The renderer works out the light's tone at a point (0 lit … 1 deep shade, the light from the
/// upper left with soft shadows and contact occlusion); the material turns it into the drawn tone:
///   - `fixedTone`: a set tone whatever the light (an opening 0.97, white paper 0, an eye);
///   - otherwise the light's tone is scaled by `shading` (how much shade shows on it: a thin wing takes little), then
///     the surface's own `value` darkens it (0 white … 1 black: `1 − (1 − tone)(1 − value)`), or, when negative, keeps
///     it paler (`tone × (1 + value)`: bleached wood stays light in the shade);
///   - clamped to `minTone … maxTone` (an underside is never lighter than 0.7).
/// `stipple` scales the speckle (0 none, 1 granite), `fill` lays a soft graphite fill under the hatching (openings, a
/// pupil: 1 = as dark as the lantern's firebox), `throughFill` a lighter one (what is seen through an opening).
public struct Material {
    public var value: Double
    public var shading: Double
    public var fixedTone: Double?
    public var minTone: Double
    public var maxTone: Double
    public var stipple: Double
    public var fill: Double
    public var throughFill: Double

    @inlinable public init(value: Double = 0, shading: Double = 1, fixedTone: Double? = nil, minTone: Double = 0, maxTone: Double = 1,
                           stipple: Double = 1, fill: Double = 0, throughFill: Double = 0) {
        self.value = value; self.shading = shading; self.fixedTone = fixedTone; self.minTone = minTone; self.maxTone = maxTone
        self.stipple = stipple; self.fill = fill; self.throughFill = throughFill
    }

    /// A plain surface: drawn as the light falls on it.
    public static let plain = Material()
    /// An opening (the inside of a cup, a lantern's window): dark, filled, never stippled.
    public static let opening = Material(fixedTone: 0.97, stipple: 0, fill: 1)

    /// The drawn tone for the light's tone `t`.
    @inlinable @inline(__always) public func tone(lit t: Double) -> Double {
        if let f = fixedTone { return f }
        let s = t * shading
        var v: Double
        if value > 0 { v = 1 - (1 - s) * (1 - value) } else if value < 0 { v = s * (1 + value) } else { v = s }
        if v < minTone { v = minTone }
        if v > maxTone { v = maxTone }
        return v
    }
}

/// A region and its material.
public struct Surface {
    public var id: Int32
    public var material: Material
    @inlinable public init(_ id: Int32, _ material: Material = .plain) { self.id = id; self.material = material }
}

/// The light's tone at a point: Lambert from the light, softened cast shadows (sh 0 … 1 lit) and contact occlusion
/// (ao 0 … 1 open), mapped so a fully lit face is white and a face turned away is a mid-dark grey.
@inlinable @inline(__always) public func litTone(diffuse diff: Double, shadow sh: Double, occlusion ao: Double) -> Double {
    var lit = 0.2 + 0.8 * diff * (0.32 + 0.68 * sh)
    lit *= 0.55 + 0.45 * ao
    return clampd((1 - lit - 0.18) / 0.74, 0, 1)
}

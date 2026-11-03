// GBuffer.swift: the geometry buffer the marcher fills (ss × ss samples per drawn pixel) and the tone map the pencil
// reads (one value per drawn pixel).
import Foundation

public final class GBuffer {
    public let w: Int, h: Int, ss: Int
    /// Region id per sample (0 paper, negative masked).
    public var id: [Int32]
    /// Distance along the sample's ray.
    public var depth: [Float]
    /// Surface normal, facing the eye.
    public var nrm: [V3]
    /// Drawn tone 0 … 1.
    public var tone: [Float]
    /// Stipple density factor.
    public var stipple: [Float]
    /// Opening fill (0 … 1) and the lighter fill of what is seen through an opening.
    public var fill: [Float]
    public var through: [Float]

    /// A buffer of w × h samples; ss is how many samples run across one drawn pixel.
    public init(w: Int, h: Int, ss: Int) {
        self.w = w; self.h = h; self.ss = ss
        let n = w * h
        id = Array(repeating: 0, count: n); depth = Array(repeating: 1e9, count: n)
        nrm = Array(repeating: V3(0, 0, 0), count: n); tone = Array(repeating: 0, count: n)
        stipple = Array(repeating: 0, count: n); fill = Array(repeating: 0, count: n); through = Array(repeating: 0, count: n)
    }

    /// Masks out every sample outside a hand-drawn round window (centre and radius in drawn pixels): the region id
    /// becomes SurfaceID.masked, so contours, hatching and stipple stop along a slightly ragged circle.
    public func cutWindow(centre c: V2, radius r: Double, seed: Double, ragged: (Double, Double) = (0.045, 0.018)) {
        for y in 0..<h { for x in 0..<w {
            let p = V2((Double(x) + 0.5) / Double(ss), (Double(y) + 0.5) / Double(ss)) - c
            let a = atan2(p.y, p.x)
            let rr = r * (1 + ragged.0 * (vnoise(V2(a * 2.2 + 7, seed)) - 0.5) * 2 + ragged.1 * (vnoise(V2(a * 9, seed + 3)) - 0.5) * 2)
            let k = y * w + x
            if len2(p) > rr && id[k] != 0 { id[k] = SurfaceID.masked; fill[k] = 0; through[k] = 0 }
        } }
    }

    /// The drawn pixel's tone map (see ToneMap).
    public func toneMap() -> ToneMap { ToneMap(self) }

    /// Is a world point seen (not behind a nearer surface)? `s` is its projection; off the buffer counts as
    /// `offBuffer`; paper as seen.
    @inlinable public func isVisible(_ P: V3, at s: V2, _ cam: Camera, tolerance: Double, offBuffer: Bool = true) -> Bool {
        let gx = Int(s.x * Double(ss)), gy = Int(s.y * Double(ss))
        guard gx >= 0, gy >= 0, gx < w, gy < h else { return offBuffer }
        let k = gy * w + gx
        if id[k] == 0 { return true }
        return Double(depth[k]) >= cam.depth(P) - tolerance
    }
}

/// One value per drawn pixel: the mean tone of its samples, how much of it is covered, the region at its centre and
/// the mean stipple factor of its covered samples. The pencil reads this.
public struct ToneMap {
    public let w: Int, h: Int
    public var tone: [Float], cover: [Float], id: [Int32], stipple: [Float]

    public init(w: Int, h: Int, tone: [Float], cover: [Float], id: [Int32], stipple: [Float]? = nil) {
        self.w = w; self.h = h; self.tone = tone; self.cover = cover; self.id = id
        self.stipple = stipple ?? Array(repeating: 0, count: w * h)
    }

    /// Averages a geometry buffer down to drawn pixels (masked samples count as paper).
    public init(_ g: GBuffer) {
        let W = g.w / g.ss, H = g.h / g.ss
        w = W; h = H
        var tone = [Float](repeating: 0, count: W * H), cover = tone, stip = tone
        var ids = [Int32](repeating: 0, count: W * H)
        let ss = g.ss
        g.id.withUnsafeBufferPointer { idB in g.tone.withUnsafeBufferPointer { tB in g.stipple.withUnsafeBufferPointer { sB in
            for y in 0..<H { for x in 0..<W {
                var s: Float = 0, c: Float = 0, st: Float = 0
                for j in 0..<ss { for i in 0..<ss {
                    let k = (y * ss + j) * g.w + x * ss + i
                    if idB[k] > 0 { s += tB[k]; c += 1; st += sB[k] }
                } }
                let n = Float(ss * ss)
                tone[y * W + x] = s / n
                cover[y * W + x] = c / n
                stip[y * W + x] = c > 0 ? st / c : 0
                let mid = idB[(y * ss + ss / 2) * g.w + x * ss + ss / 2]
                ids[y * W + x] = mid < 0 ? 0 : mid
            } }
        } } }
        self.tone = tone; self.cover = cover; self.id = ids; self.stipple = stip
    }

    @inlinable @inline(__always) public func at(_ p: V2) -> Double {
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < w, y < h else { return 0 }
        return Double(tone[y * w + x])
    }
    @inlinable @inline(__always) public func idAt(_ p: V2) -> Int32 {
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < w, y < h else { return 0 }
        return id[y * w + x]
    }
}

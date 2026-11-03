// Camera.swift: a pinhole camera (perspective) or a parallel one (views from above). Pixel (x, y) runs right and down
// from the top-left corner; (cx, cy) is where the view axis meets the picture; f is the focal length in pixels
// (parallel: pixels per world unit).
import Foundation

public struct Camera {
    public var pos: V3, fwd: V3, right: V3, up: V3
    public var f: Double, cx: Double, cy: Double
    /// Parallel projection: every ray runs along fwd, from the picture plane through pos.
    public var ortho: Bool

    public init(pos: V3, fwd: V3, right: V3, up: V3, f: Double = 1, cx: Double = 0, cy: Double = 0, ortho: Bool = false) {
        self.pos = pos; self.fwd = fwd; self.right = right; self.up = up; self.f = f; self.cx = cx; self.cy = cy; self.ortho = ortho
    }

    /// A perspective camera at `eye` looking at `target`, `up` drawn upward.
    public static func looking(from eye: V3, at target: V3, up: V3 = V3(0, 0, 1)) -> Camera {
        let fwd = norm3(target - eye)
        var right = cross3(fwd, up)
        if len3(right) < 1e-9 { right = V3(1, 0, 0) }
        right = norm3(right)
        return Camera(pos: eye, fwd: fwd, right: right, up: cross3(right, fwd))
    }

    /// The ray through pixel (x, y): its origin and unit direction.
    @inlinable @inline(__always) public func ray(_ x: Double, _ y: Double) -> (V3, V3) {
        if ortho { return (pos + right * ((x - cx) / f) + up * ((cy - y) / f), fwd) }
        return (pos, norm3(fwd + right * ((x - cx) / f) + up * ((cy - y) / f)))
    }
    /// The direction of the ray through pixel (x, y).
    @inlinable @inline(__always) public func direction(_ x: Double, _ y: Double) -> V3 { ray(x, y).1 }
    /// Where a world point lands in the picture.
    @inlinable @inline(__always) public func project(_ p: V3) -> V2 {
        let d = p - pos
        if ortho { return V2(cx + dot3(d, right) * f, cy - dot3(d, up) * f) }
        let z = dot3(d, fwd)
        return V2(cx + dot3(d, right) / z * f, cy - dot3(d, up) / z * f)
    }
    /// What the geometry buffer stores as the depth of p (its distance along its ray).
    @inlinable @inline(__always) public func depth(_ p: V3) -> Double { ortho ? dot3(p - pos, fwd) : len3(p - pos) }
    /// Pixels per world unit at p.
    @inlinable @inline(__always) public func scaleAt(_ p: V3) -> Double { ortho ? f : f / max(dot3(p - pos, fwd), 1e-6) }
}

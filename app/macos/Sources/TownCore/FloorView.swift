import simd

/// The office camera's math, without RealityKit: an orthographic camera looking at `target`
/// from above, tilted `pitch` radians up from the floor toward the viewer (+z), so x runs right
/// and z runs down the window. Maps world points (meters, y up) to window points (y down) and
/// back onto the floor.
public struct FloorView: Sendable, Equatable {
    public var pitch: Float
    public var target: SIMD3<Float>
    /// The visible height, in meters.
    public var scale: Float
    /// The window's size in points.
    public var size: SIMD2<Float>

    public init(pitch: Float, target: SIMD3<Float>, scale: Float, size: SIMD2<Float>) {
        self.pitch = pitch
        self.target = target
        self.scale = scale
        self.size = size
    }

    private var halfHeight: Float { scale / 2 }
    private var halfWidth: Float { halfHeight * size.x / max(1, size.y) }

    /// The window point (x right, y down) where world point `w` is drawn.
    public func screen(_ w: SIMD3<Float>) -> SIMD2<Float> {
        // Camera axes: right is +x; up is (0, cos, -sin), at right angles to the view direction.
        let d = w - target
        let vx = d.x
        let vy = cos(pitch) * d.y - sin(pitch) * d.z
        return [(vx / halfWidth + 1) / 2 * size.x, (1 - vy / halfHeight) / 2 * size.y]
    }

    /// The point on the horizontal plane at `height` drawn at window point `p`: the inverse of
    /// `screen` for points on that plane.
    public func ground(_ p: SIMD2<Float>, height: Float) -> SIMD3<Float> {
        let vx = (2 * p.x / max(1, size.x) - 1) * halfWidth
        let vy = (1 - 2 * p.y / max(1, size.y)) * halfHeight
        let dy = height - target.y
        let dz = (cos(pitch) * dy - vy) / sin(pitch)
        return [target.x + vx, height, target.z + dz]
    }
}

/// Where someone of `radius` can stand on the office floor (x, z), with furniture footprints.
public enum FloorPlan {
    public typealias Rect = (min: SIMD2<Float>, max: SIMD2<Float>)

    /// `p` moved inside a floor of `size` (from the origin), keeping `radius` from the edge.
    public static func clamp(_ p: SIMD2<Float>, size: SIMD2<Float>, radius: Float) -> SIMD2<Float> {
        simd_clamp(p, SIMD2(repeating: radius), simd_max(SIMD2(repeating: radius), size - radius))
    }

    public static func inside(_ p: SIMD2<Float>, _ r: Rect, pad: Float) -> Bool {
        p.x > r.min.x - pad && p.x < r.max.x + pad && p.y > r.min.y - pad && p.y < r.max.y + pad
    }

    /// The nearest spot to `p` on the floor and clear of `obstacles`: `p` itself when it is free,
    /// else the closest free point on rings around it, up to `reach` meters away; nil if none.
    public static func freeSpot(near p: SIMD2<Float>, size: SIMD2<Float>, obstacles: [Rect],
                                radius: Float, reach: Float = 2) -> SIMD2<Float>? {
        let start = clamp(p, size: size, radius: radius)
        func free(_ q: SIMD2<Float>) -> Bool {
            clamp(q, size: size, radius: radius) == q && !obstacles.contains { inside(q, $0, pad: radius) }
        }
        if free(start) { return start }
        var r: Float = 0.05
        while r <= reach {
            let n = max(8, Int(2 * .pi * r / 0.05))
            let ring = (0..<n).map { i -> SIMD2<Float> in
                let t = Float(i) / Float(n) * 2 * .pi
                return start + r * SIMD2(cos(t), sin(t))
            }
            if let q = ring.filter(free).min(by: { simd_distance($0, p) < simd_distance($1, p) }) { return q }
            r += 0.05
        }
        return nil
    }
}

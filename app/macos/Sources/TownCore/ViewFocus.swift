import simd

/// Where auto-scroll looks (docs/spec.md: The office window): the window-sized area with the
/// most moving characters.
public enum ViewFocus {
    /// The center of a view (`half` meters each way) holding the most movers: the current view
    /// when it already holds as many as any, else the nearest best spot. Nil when nobody moves.
    public static func bestCenter(_ movers: [SIMD2<Float>], current: SIMD2<Float>, half: SIMD2<Float>) -> SIMD2<Float>? {
        func held(_ c: SIMD2<Float>) -> [SIMD2<Float>] { movers.filter { abs($0.x - c.x) <= half.x && abs($0.y - c.y) <= half.y } }
        let here = held(current).count
        var best: SIMD2<Float>?
        var bestCount = here
        for m in movers {
            // A view around this mover, centered on the movers it holds.
            let group = held(m)
            let c = group.reduce(SIMD2<Float>.zero, +) / Float(group.count)
            let n = held(c).count
            if n > bestCount || (n == bestCount && best.map { simd_distance(c, current) < simd_distance($0, current) } == true) {
                best = c
                bestCount = n
            }
        }
        return best ?? (here > 0 ? current : nil)
    }
}

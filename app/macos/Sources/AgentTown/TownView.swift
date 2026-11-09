import AppKit
import RealityKit
import SwiftUI

/// The office window: the RealityKit scene with 2D labels drawn over it.
struct TownView: View {
    @ObservedObject var scene: TownScene
    @State private var pan: SIMD2<Float> = .zero
    @State private var camera = TownView.makeCamera()

    /// The office is shown at this size when it fits, and never smaller than `minPixelsPerMeter`.
    static let pixelsPerMeter: CGFloat = 110
    static let minPixelsPerMeter: CGFloat = 70

    static func makeCamera() -> Entity {
        let cam = Entity()
        cam.components.set(OrthographicCameraComponent())
        return cam
    }

    /// Screen size of the office at `ppm`, the floor's depth foreshortened by the camera tilt.
    private func officePixels(_ ppm: CGFloat) -> CGSize {
        CGSize(width: CGFloat(scene.officeSize.x) * ppm, height: CGFloat(scene.officeSize.y * Projector.depthFactor) * ppm)
    }

    func pixelsPerMeter(_ size: CGSize) -> CGFloat {
        let fit = officePixels(1)
        let k = min(size.width / max(1, fit.width), size.height / max(1, fit.height))
        return min(Self.pixelsPerMeter, max(Self.minPixelsPerMeter, k))
    }

    /// How far the camera may pan from the office center before showing only path.
    private func panLimit(_ size: CGSize) -> SIMD2<Float> {
        let ppm = pixelsPerMeter(size)
        let extra = officePixels(ppm)
        let x = max(0, Float((extra.width - size.width) / ppm) / 2)
        let z = max(0, Float((extra.height - size.height) / ppm) / 2 / Projector.depthFactor)
        return [x, z]
    }

    func projector(_ size: CGSize) -> Projector {
        let lim = panLimit(size)
        let p = SIMD2(min(lim.x, max(-lim.x, pan.x)), min(lim.y, max(-lim.y, pan.y)))
        return Projector.fitting(office: scene.officeSize, size: size, pixelsPerMeter: pixelsPerMeter(size), pan: p)
    }

    var body: some View {
        GeometryReader { geo in
            let proj = projector(geo.size)
            ZStack(alignment: .topLeading) {
                RealityView { content in
                    content.add(scene.root)
                    content.add(camera)
                } update: { _ in
                    proj.apply(to: camera)
                }
                .realityViewCameraControls(.none)
                TimelineView(.animation) { _ in
                    ZStack(alignment: .topLeading) {
                        CallLines(lines: scene.callLines(), projector: proj)
                        LabelOverlay(items: scene.labelItems(), projector: proj)
                    }
                }
                .allowsHitTesting(false)
            }
            .onAppear { proj.apply(to: camera) }
            .onChange(of: geo.size) { proj.apply(to: camera) }
            .onChange(of: scene.officeSize) { projector(geo.size).apply(to: camera) }
            .background(ScrollCatcher { dx, dy in
                let ppm = Float(pixelsPerMeter(geo.size))
                let lim = panLimit(geo.size)
                pan.x = min(lim.x, max(-lim.x, pan.x - Float(dx) / ppm))
                pan.y = min(lim.y, max(-lim.y, pan.y - Float(dy) / ppm / Projector.depthFactor))
            })
        }
        .background(Color(nsColor: NSColor(srgbRed: 0.957, green: 0.918, blue: 0.859, alpha: 1)))
    }
}

/// A dashed line between the two people on each call.
struct CallLines: View {
    /// The line arcs up over whoever stands between the two callers.
    static func control(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
        CGPoint(x: (p.x + q.x) / 2, y: min(p.y, q.y) - max(30, abs(q.x - p.x) * 0.18))
    }

    let lines: [(SIMD3<Float>, SIMD3<Float>)]
    let projector: Projector

    var body: some View {
        Canvas { ctx, _ in
            for (a, b) in lines {
                let (p, q) = (projector.screen(a), projector.screen(b))
                var path = Path()
                path.move(to: p)
                path.addQuadCurve(to: q, control: CallLines.control(p, q))
                ctx.stroke(path, with: .color(Tag.callColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 6]))
            }
        }
    }
}

/// Name tags, hats, tickets, badges and floor signs, at each anchor's screen position.
struct LabelOverlay: View {
    let items: [TownScene.LabelItem]
    let projector: Projector

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.id) { item in
                let p = projector.screen(item.anchor)
                VStack(spacing: 2) {
                    ForEach(Array(item.lines.enumerated()), id: \.offset) { _, line in
                        Tag(text: line.0, style: line.1)
                    }
                }
                .fixedSize()
                // Signs sit on their anchor; tags stack upward from it.
                .position(x: p.x, y: item.lines.first?.1 == .sign ? p.y : p.y - CGFloat(item.lines.count) * 9.5 - 2)
            }
        }
    }
}

struct Tag: View {
    static let callColor = Color(red: 0.95, green: 0.45, blue: 0.15)

    let text: String
    let style: TownScene.LabelItem.Style

    var body: some View {
        Text(text)
            .font(.system(size: style == .sign ? 13 : 10.5, weight: style == .name || style == .sign ? .semibold : .regular))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .foregroundStyle(Self.foreground(style))
            .background(RoundedRectangle(cornerRadius: 4).fill(Self.background(style)))
    }

    static func background(_ s: TownScene.LabelItem.Style) -> Color {
        switch s {
        case .name: Color.black.opacity(0.55)
        case .hat: Color(red: 0.98, green: 0.80, blue: 0.25)
        case .ticket: Color.white
        case .bubble: Color(red: 0.86, green: 0.15, blue: 0.15)
        case .badge: Color(red: 0.36, green: 0.30, blue: 0.75)
        case .sign: Color(red: 0.20, green: 0.24, blue: 0.30)
        case .ring: Color(red: 0.98, green: 0.55, blue: 0.20)
        }
    }

    static func foreground(_ s: TownScene.LabelItem.Style) -> Color {
        switch s {
        case .hat, .ticket: Color.black
        default: Color.white
        }
    }
}

/// Reports scroll-wheel and trackpad movement over the view.
struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            if let w = v.window, e.window == w {
                let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 10
                onScroll(e.scrollingDeltaX * k, e.scrollingDeltaY * k)
            }
            return e
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

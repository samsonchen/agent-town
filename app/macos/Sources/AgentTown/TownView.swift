import AppKit
import RealityKit
import SwiftUI

/// The building window: the RealityKit scene with 2D labels drawn over it.
struct TownView: View {
    let scene: TownScene
    @State private var scroll: Float = 0
    @State private var camera = TownView.makeCamera()

    static let pixelsPerMeter: CGFloat = 70

    static func makeCamera() -> Entity {
        let cam = Entity()
        cam.components.set(OrthographicCameraComponent())
        return cam
    }

    func projector(_ size: CGSize) -> Projector {
        let scale = Float(size.height / Self.pixelsPerMeter)
        // Keep the top of the executive floor near the top of the window, then scroll down.
        let target = SIMD3<Float>(Layout.floorWidth / 2 - 0.6, -scale * 0.42 + 3.6 - scroll, Layout.floorDepth / 2)
        return Projector(target: target, scale: scale, size: size)
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
                    LabelOverlay(items: scene.labelItems(), projector: proj)
                }
                .allowsHitTesting(false)
            }
            .onAppear { proj.apply(to: camera) }
            .onChange(of: geo.size) { proj.apply(to: camera) }
            .background(ScrollCatcher { dy in
                let maxScroll = Float(max(0, scene.floorCount - 1)) * Layout.floorSpacing
                scroll = min(maxScroll, max(0, scroll + Float(dy) / Float(Self.pixelsPerMeter)))
            })
        }
        .background(Color(nsColor: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1)))
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
                .position(x: p.x, y: p.y - CGFloat(item.lines.count) * 9)
            }
        }
    }
}

struct Tag: View {
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
        }
    }

    static func foreground(_ s: TownScene.LabelItem.Style) -> Color {
        switch s {
        case .hat, .ticket: Color.black
        default: Color.white
        }
    }
}

/// Reports scroll-wheel movement over the view.
struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            if let w = v.window, e.window == w { onScroll(e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 1 : 10)) }
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

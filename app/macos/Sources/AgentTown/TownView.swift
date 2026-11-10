import AppKit
import RealityKit
import SwiftUI

/// The office window: the RealityKit scene with 2D labels drawn over it.
struct TownView: View {
    @ObservedObject var scene: TownScene
    @State private var pan: SIMD2<Float> = .zero
    @State private var camera = TownView.makeCamera()
    /// The arrow-keys tip stays closed once the user closes it. The H tip comes back
    /// each time the CEO walks away from the seat.
    @AppStorage("tipArrowsClosed") private var arrowsTipClosed = false
    @State private var homeTipClosed = false

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

    /// Pans so the CEO stays inside the middle of the window while walking.
    private func follow(_ spot: SIMD2<Float>, size: CGSize) {
        let p = projector(size).screen([spot.x, 0.3, spot.y])
        let mx = size.width * 0.2, my = size.height * 0.2
        let dx = p.x < mx ? p.x - mx : (p.x > size.width - mx ? p.x - (size.width - mx) : 0)
        let dy = p.y < my ? p.y - my : (p.y > size.height - my ? p.y - (size.height - my) : 0)
        guard dx != 0 || dy != 0 else { return }
        let ppm = Float(pixelsPerMeter(size))
        let lim = panLimit(size)
        let x = min(lim.x, max(-lim.x, pan.x)) + Float(dx) / ppm
        let z = min(lim.y, max(-lim.y, pan.y)) + Float(dy) / ppm / Projector.depthFactor
        pan = [min(lim.x, max(-lim.x, x)), min(lim.y, max(-lim.y, z))]
    }

    @ViewBuilder private var tip: some View {
        if scene.ceoAway {
            if !homeTipClosed { TipBar(text: scene.labels.tipHome) { homeTipClosed = true } }
        } else if !arrowsTipClosed {
            TipBar(text: scene.labels.tipArrows) { arrowsTipClosed = true }
        }
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
            .onChange(of: scene.ceoSpot) { _, spot in follow(spot, size: geo.size) }
            .onChange(of: scene.ceoAway) { _, away in if away { homeTipClosed = false } }
            .overlay(alignment: .top) { tip.padding(.top, 10) }
            .background(KeyCatcher(onKey: { scene.key($0, down: $1) }, onResign: { scene.releaseKeys() }))
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
                let isSign = item.lines.first?.1 == .sign
                VStack(spacing: 2) {
                    ForEach(Array(item.lines.enumerated()), id: \.offset) { _, line in
                        Tag(text: line.0, style: line.1)
                    }
                }
                .fixedSize()
                // Signs sit on their anchor; tags stack upward from it.
                .frame(width: 0, height: 0, alignment: isSign ? .center : .bottom)
                .position(x: p.x, y: isSign ? p.y : p.y - 2)
            }
        }
    }
}

struct Tag: View {
    static let callColor = Color(red: 0.95, green: 0.45, blue: 0.15)

    let text: String
    let style: TownScene.LabelItem.Style

    /// A statement wraps at this width.
    static let statementWidth: CGFloat = 230

    var body: some View {
        if style == .statement {
            Text(text)
                .font(Font(Self.font(style)))
                .multilineTextAlignment(.leading)
                .frame(width: Self.width(text, style), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .foregroundStyle(Self.foreground(style))
                .background(RoundedRectangle(cornerRadius: 6).fill(Self.background(style)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Self.callColor, lineWidth: 1.5))
        } else {
            Text(text)
                .font(Font(Self.font(style)))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .foregroundStyle(Self.foreground(style))
                .background(RoundedRectangle(cornerRadius: 4).fill(Self.background(style)))
        }
    }

    static func font(_ s: TownScene.LabelItem.Style) -> NSFont {
        switch s {
        case .sign: .systemFont(ofSize: 13, weight: .semibold)
        case .name: .systemFont(ofSize: 10.5, weight: .semibold)
        case .statement: .systemFont(ofSize: 11)
        default: .systemFont(ofSize: 10.5)
        }
    }

    /// The text's width on one line, up to the wrap width.
    static func width(_ text: String, _ s: TownScene.LabelItem.Style) -> CGFloat {
        let w = ceil(NSAttributedString(string: text, attributes: [.font: font(s)]).size().width) + 1
        return s == .statement ? min(statementWidth, w) : w
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
        case .faint: Color.black.opacity(0.22)
        case .speech: Color.white
        case .statement: Color(red: 1, green: 0.98, blue: 0.92)
        }
    }

    static func foreground(_ s: TownScene.LabelItem.Style) -> Color {
        switch s {
        case .hat, .ticket, .speech, .statement: Color.black
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

/// The arrow keys and H, while the office window is in front.
struct KeyCatcher: NSViewRepresentable {
    let onKey: (UInt16, Bool) -> Bool
    let onResign: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { e in
            guard let w = v.window, e.window == w,
                  e.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return e }
            return onKey(e.keyCode, e.type == .keyDown) ? nil : e
        }
        context.coordinator.resign = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { n in
            if (n.object as? NSWindow) === v.window { onResign() }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
        var resign: Any?
        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
            if let r = resign { NotificationCenter.default.removeObserver(r) }
        }
    }
}

/// A tip across the top of the window, with a button to close it.
struct TipBar: View {
    let text: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
            Text(text).font(.system(size: 12, weight: .medium))
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.7)))
    }
}

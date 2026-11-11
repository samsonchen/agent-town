import AppKit
import RealityKit
import SwiftUI

/// The office window: the RealityKit scene with 2D labels drawn over it.
struct TownView: View {
    @ObservedObject var scene: TownScene
    @State private var pan: SIMD2<Float> = .zero
    @State private var camera = TownView.makeCamera()
    /// Tips show while "Show tips" is on in the menu; closing one turns it off.
    @AppStorage(Prefs.showTips) private var showTips = true
    /// "Stay on top" in the menu: the window floats above other apps' windows.
    @AppStorage(Prefs.stayOnTop) private var stayOnTop = false
    /// The window this view is in, to grow it when a block is added.
    @State private var window: NSWindow?
    /// The window's opacity from Settings; applied to this window only.
    @AppStorage(Prefs.opacity) private var opacity = 1.0

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

    /// Makes the window as tall as the office at the current width's scale, keeping its top edge
    /// where it is and staying on the screen. Runs when a block is added or removed, so a size the
    /// user dragged to holds until then. A taller office than the screen pans with the scroll wheel.
    private func fitWindow(in w: NSWindow? = nil) {
        guard let window = w ?? window, let screen = window.screen ?? NSScreen.main, !window.styleMask.contains(.fullScreen) else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let ppm = min(Self.pixelsPerMeter, max(Self.minPixelsPerMeter, content.width / CGFloat(max(1, scene.officeSize.x))))
        let chrome = window.frame.height - content.height
        let wanted = max(480, officePixels(ppm).height) + chrome
        let visible = screen.visibleFrame
        let height = min(wanted, visible.height)
        var frame = window.frame
        guard abs(frame.height - height) > 1 else { return }
        let top = min(frame.maxY, visible.maxY)
        frame.size.height = height
        frame.origin.y = max(visible.minY, top - height)
        window.setFrame(frame, display: true, animate: true)
    }

    @ViewBuilder private var tip: some View {
        if showTips {
            TipBar(text: scene.ceoAway ? scene.labels.tipHome : scene.labels.tipArrows) { showTips = false }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let proj = projector(geo.size)
            ZStack(alignment: .topLeading) {
                RealityView { content in
                    content.add(scene.root)
                    content.add(camera)
                } update: { content in
                    // Put the scene back if anything took it out of this view.
                    if scene.root.scene == nil { content.add(scene.root) }
                    if camera.scene == nil { content.add(camera) }
                    proj.apply(to: camera)
                }
                .realityViewCameraControls(.none)
                TimelineView(.animation) { _ in
                    ZStack(alignment: .topLeading) {
                        CallLines(lines: scene.callLines(), projector: proj)
                        LabelOverlay(items: scene.labelItems(), projector: proj)
                        MeterOverlay(items: scene.meterItems(), projector: proj)
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { point in
                // A click on a character sends the CEO over to talk to them.
                if let a = scene.actor(at: point, projector: proj) { scene.visit(a) }
            }
            .onAppear { proj.apply(to: camera) }
            .onChange(of: geo.size) { proj.apply(to: camera) }
            .onChange(of: scene.officeSize) {
                fitWindow()
                projector(geo.size).apply(to: camera)
            }
            .onChange(of: stayOnTop) { _, on in window?.level = on ? .floating : .normal }
            .onChange(of: scene.ceoSpot) { _, spot in follow(spot, size: geo.size) }
            .onChange(of: opacity) { _, v in window?.alphaValue = Prefs.clampOpacity(v) } // live while the slider moves
            .overlay(alignment: .bottomLeading) { tip.padding([.leading, .bottom], 12) } // clear of the context bar under a block
            .background(WindowReader { w in
                guard let w else { return }
                w.alphaValue = Prefs.clampOpacity(opacity) // also when the window opens or is made again
                guard w !== window else { return }
                window = w
                w.level = stayOnTop ? .floating : .normal
                WindowPlace.restore(w)
                fitWindow(in: w) // sessions already open when the window opens
                WindowPlace.keep(w)
            })
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

    /// Space kept between the window's top and the highest tag.
    static let topMargin: CGFloat = 6

    /// The height of a stack of tags.
    static func height(_ item: TownScene.LabelItem) -> CGFloat {
        if item.scroll { return Tag.height("n", .sign) }
        let tags = item.lines.map { Tag.height($0.0, $0.1) }.reduce(0, +)
        return tags + CGFloat(max(0, item.lines.count - 1)) * 2
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.id) { item in
                let p = projector.screen(item.anchor)
                let isSign = item.lines.first?.1 == .sign
                Group {
                    if item.scroll {
                        ScrollingSign(text: item.lines.first?.0 ?? "")
                    } else {
                        VStack(spacing: 2) {
                            ForEach(Array(item.lines.enumerated()), id: \.offset) { _, line in
                                Tag(text: line.0, style: line.1)
                            }
                        }
                    }
                }
                .fixedSize()
                // Signs sit on their anchor; tags stack upward from it.
                .frame(width: 0, height: 0, alignment: isSign ? .center : .bottom)
                // A stack over someone near the top of the window slides down to stay in view.
                .position(x: p.x, y: isSign ? p.y : max(p.y - 2, Self.height(item) + Self.topMargin))
            }
        }
    }
}

/// A block sign whose task titles are too wide: the whole sign scrolls sideways in a window
/// `Labels.titleWidth` columns wide.
struct ScrollingSign: View {
    let text: String
    /// Points per second.
    static let speed: Double = 28

    var body: some View {
        let font = Font(Tag.font(.sign))
        let window = Tag.width(String(repeating: "n", count: Labels.titleWidth), .sign)
        let loop = text + "      "
        let loopWidth = Tag.width(loop, .sign)
        TimelineView(.animation) { tl in
            let x = (tl.date.timeIntervalSinceReferenceDate * Self.speed).truncatingRemainder(dividingBy: Double(loopWidth))
            HStack(spacing: 0) {
                Text(loop).font(font).fixedSize().frame(width: loopWidth, alignment: .leading)
                Text(loop).font(font).fixedSize().frame(width: loopWidth, alignment: .leading)
            }
            .offset(x: -CGFloat(x))
            .frame(width: window, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                         .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .frame(width: window)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .foregroundStyle(Tag.foreground(.sign))
        .background(RoundedRectangle(cornerRadius: 4).fill(Tag.background(.sign)))
    }
}

/// The context bar under each project block: how full the window is, its size, model and effort.
struct MeterOverlay: View {
    let items: [TownScene.MeterItem]
    let projector: Projector

    static let barWidth: CGFloat = 96
    static let rowHeight: CGFloat = 22
    static let gap: CGFloat = 8
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

    /// Green while there is room, amber past 60%, red past 80%.
    static func color(_ f: Double) -> NSColor {
        f >= 0.8 ? NSColor(srgbRed: 0.88, green: 0.27, blue: 0.22, alpha: 1)
            : f >= 0.6 ? NSColor(srgbRed: 0.95, green: 0.65, blue: 0.18, alpha: 1)
            : NSColor(srgbRed: 0.30, green: 0.72, blue: 0.42, alpha: 1)
    }
    static let background = NSColor(srgbRed: 0.20, green: 0.24, blue: 0.30, alpha: 0.92)

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.id) { item in
                let p = projector.screen(item.anchor)
                HStack(spacing: 7) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule().fill(Color(nsColor: Self.color(item.fraction ?? 0)))
                            .frame(width: Self.barWidth * CGFloat(item.fraction ?? 0))
                    }
                    .frame(width: Self.barWidth, height: 7)
                    Text(item.text).font(Font(Self.font)).foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .frame(height: Self.rowHeight - 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: Self.background)))
                .fixedSize()
                .frame(width: 0, height: 0)
                .position(x: p.x, y: p.y + Self.gap + Self.rowHeight / 2 + CGFloat(item.row) * Self.rowHeight)
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

    /// The tag's height, a statement's wrapped lines included.
    static func height(_ text: String, _ s: TownScene.LabelItem.Style) -> CGFloat {
        let f = font(s)
        if s == .statement {
            let r = NSAttributedString(string: text, attributes: [.font: f])
                .boundingRect(with: CGSize(width: width(text, s), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
            return ceil(r.height) + 10
        }
        return ceil(f.ascender - f.descender + f.leading) + 3
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

/// A tip in the window's bottom-left corner, with a button to close it.
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
            .help(Labels.text("Close"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.7)))
    }
}

/// Hands over the NSWindow a view is in, once it is in one.
private struct WindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { found(v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { if let w = v.window { found(w) } }
    }
}

/// Keeps the office window where the user put it, across restarts of the app. The frame is saved
/// in screen coordinates (AppKit's own autosave can put it on another display of the same size).
@MainActor enum WindowPlace {
    private static var observers: [NSObjectProtocol] = []

    /// Moves the window to its saved frame, if that is still on a connected display.
    static func restore(_ w: NSWindow) {
        guard let s = UserDefaults.standard.string(forKey: Prefs.windowFrame) else { return }
        let r = NSRectFromString(s)
        guard r.width >= 200, r.height >= 200,
              NSScreen.screens.contains(where: { $0.visibleFrame.intersection(r).width >= 100 && $0.visibleFrame.intersection(r).height >= 100 })
        else { return }
        w.setFrame(r, display: true)
    }

    /// Saves the frame each time the window moves or is resized.
    static func keep(_ w: NSWindow) {
        observers.forEach(NotificationCenter.default.removeObserver)
        let save: (Notification) -> Void = { n in
            guard let w = n.object as? NSWindow, !w.styleMask.contains(.fullScreen) else { return }
            UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: Prefs.windowFrame)
        }
        observers = [NSWindow.didMoveNotification, NSWindow.didResizeNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: w, queue: .main, using: save)
        }
        UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: Prefs.windowFrame)
    }
}

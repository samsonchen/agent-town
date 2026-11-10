import AppKit
import Metal
import RealityKit
import TownCore

/// `AgentTown --demo <fixture.json> [--speed N] [--snapshot out.png --at S]`
///
/// Replays a protocol fixture into the app, with the gaps between events shortened.
/// With `--snapshot`, renders the building offscreen `S` seconds in, labels
/// included, writes a PNG and quits. Used to check scenes without a window.
@MainActor
enum Demo {
    static func events(from path: String) throws -> [TownEvent] {
        try Batch.decode(Data(contentsOf: URL(fileURLWithPath: path))).events
    }

    /// Feeds events to `store` with the original timing, each gap capped and divided by `speed`.
    static func play(_ events: [TownEvent], into store: TownStore, speed: Double) {
        Task { @MainActor in
            var last: Int64?
            for e in events {
                if let l = last {
                    let gap = min(4.0, Double(e.ts - l) / 1000) / speed
                    try? await Task.sleep(for: .seconds(gap))
                }
                last = e.ts
                store.receive(Batch(protocol: 1, events: [e]))
            }
        }
    }

    static func snapshot(scene: TownScene, at seconds: Double, to url: URL, size: CGSize = CGSize(width: 1400, height: 900)) async throws {
        let renderer = try RealityRenderer()
        let camera = Entity()
        camera.components.set(OrthographicCameraComponent())
        let view = TownView(scene: scene)
        view.projector(size).apply(to: camera)
        renderer.entities.append(scene.root)
        renderer.entities.append(camera)
        renderer.activeCamera = camera
        renderer.cameraSettings.colorBackground = .color(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1))

        // TOWN_CEO_GOTO="x,z;x,z@seconds": walk the CEO to office points, for checking the walk.
        if let spec = ProcessInfo.processInfo.environment["TOWN_CEO_GOTO"] {
            let parts = spec.split(separator: "@")
            let delay = parts.count > 1 ? Double(parts[1]) ?? 1 : 1
            let goals = parts[0].split(separator: ";").compactMap { pair -> SIMD2<Float>? in
                let v = pair.split(separator: ",").compactMap { Float($0) }
                return v.count == 2 ? [v[0], v[1]] : nil
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                for g in goals {
                    scene.walkCeo(to: g)
                    while scene.ceoTrip != nil { try? await Task.sleep(for: .milliseconds(50)) }
                }
            }
        }

        // TOWN_CLICK="x,y@seconds": click the window at that point, as a user would.
        if let spec = ProcessInfo.processInfo.environment["TOWN_CLICK"] {
            let parts = spec.split(separator: "@")
            let v = parts[0].split(separator: ",").compactMap { Double($0) }
            let delay = parts.count > 1 ? Double(parts[1]) ?? 1 : 1
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard v.count == 2 else { return }
                let hit = scene.actor(at: CGPoint(x: v[0], y: v[1]), projector: view.projector(size))
                if ProcessInfo.processInfo.environment["TOWN_DEBUG"] != nil { print("click (\(v[0]), \(v[1])) → \(hit?.id ?? "nobody")") }
                if let hit { scene.visit(hit) }
            }
        }

        // Advance the scene in real time so queued scenes and animations play.
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            try renderer.update(1.0 / 30)
            try await Task.sleep(for: .milliseconds(33))
        }

        // Frame the office as it is now (blocks may have been added since the start).
        let proj = view.projector(size)
        proj.apply(to: camera)
        let device = MTLCreateSystemDefaultDevice()!
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: Int(size.width),
                                                            height: Int(size.height), mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead, .shaderWrite]
        desc.storageMode = .shared
        let tex = device.makeTexture(descriptor: desc)!
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: tex))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            do { try renderer.updateAndRender(deltaTime: 1.0 / 30, cameraOutput: output, onComplete: { _ in done.resume() }) }
            catch { done.resume() }
        }

        if ProcessInfo.processInfo.environment["TOWN_DEBUG"] != nil {
            func walk(_ e: Entity, _ depth: Int) {
                if e.components.has(ModelComponent.self) == false, !e.name.isEmpty || depth <= 1 {
                    print(String(repeating: "  ", count: depth), e.name, e.position(relativeTo: nil))
                }
                if depth < 2 { e.children.forEach { walk($0, depth + 1) } }
            }
            walk(scene.root, 0)
            for a in scene.actors.values { print("actor", a.id, a.body.baseName ?? "-", a.root.position(relativeTo: nil), "local", a.spot, "home", a.home, "clip", a.body.currentClip ?? "-") }
            for b in scene.blocks.values { print("block", b.id, b.placed ? "shown" : "hidden") }
        }
        let w = tex.width, h = tex.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        drawCalls(scene.callLines(), projector: proj, in: ctx, height: CGFloat(h))
        drawLabels(scene.labelItems(), projector: proj, in: ctx, height: CGFloat(h))
        drawMeters(scene.meterItems(), projector: proj, in: ctx, height: CGFloat(h))
        try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
    }

    private static func drawCalls(_ lines: [(SIMD3<Float>, SIMD3<Float>)], projector: Projector, in ctx: CGContext, height: CGFloat) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(Tag.callColor).cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineDash(phase: 0, lengths: [6, 6])
        for (a, b) in lines {
            let p = projector.screen(a), q = projector.screen(b)
            let c = CallLines.control(p, q)
            ctx.move(to: CGPoint(x: p.x, y: height - p.y))
            ctx.addQuadCurve(to: CGPoint(x: q.x, y: height - q.y), control: CGPoint(x: c.x, y: height - c.y))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// The same labels as the window's overlay, drawn with AppKit for the snapshot.
    private static func drawMeters(_ items: [TownScene.MeterItem], projector: Projector, in ctx: CGContext, height: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        typealias M = MeterOverlay
        for item in items {
            let p = projector.screen(item.anchor)
            let s = NSAttributedString(string: item.text, attributes: [.font: M.font, .foregroundColor: NSColor.white])
            let ts = s.size()
            let w = 8 + M.barWidth + 7 + ceil(ts.width) + 8, h = M.rowHeight - 4
            let cy = p.y + M.gap + M.rowHeight / 2 + CGFloat(item.row) * M.rowHeight
            let rect = NSRect(x: p.x - w / 2, y: height - cy - h / 2, width: w, height: h)
            M.background.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            let bar = NSRect(x: rect.minX + 8, y: rect.midY - 3.5, width: M.barWidth, height: 7)
            NSColor.white.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 3.5, yRadius: 3.5).fill()
            let f = CGFloat(item.fraction ?? 0)
            if f > 0 {
                M.color(Double(f)).setFill()
                NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: max(7, M.barWidth * f), height: 7), xRadius: 3.5, yRadius: 3.5).fill()
            }
            s.draw(at: NSPoint(x: bar.maxX + 7, y: rect.midY - ts.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawLabels(_ items: [TownScene.LabelItem], projector: Projector, in ctx: CGContext, height: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        for item in items {
            let p = projector.screen(item.anchor)
            let isSign = item.lines.first?.1 == .sign
            // A still image cannot scroll: a scrolling sign shows its start.
            let lines = item.scroll
                ? [(Labels.clip(item.lines.first?.0 ?? "", width: Labels.titleWidth), TownScene.LabelItem.Style.sign)]
                : item.lines
            let boxes = lines.map { (text, style) -> (NSAttributedString, NSSize, NSSize, TownScene.LabelItem.Style) in
                let s = NSAttributedString(string: text, attributes: [.font: Tag.font(style), .foregroundColor: NSColor(Tag.foreground(style))])
                let size = style == .statement
                    ? s.boundingRect(with: NSSize(width: Tag.width(text, style), height: 1000), options: .usesLineFragmentOrigin).size
                    : s.size()
                let pad = style == .statement ? NSSize(width: 7, height: 5) : NSSize(width: 5, height: 1.5)
                return (s, NSSize(width: ceil(size.width), height: ceil(size.height)), pad, style)
            }
            let total = boxes.reduce(CGFloat(0)) { $0 + $1.1.height + 2 * $1.2.height } + CGFloat(max(0, boxes.count - 1)) * 2
            // As in the window, a stack near the top slides down to stay in view.
            var top = isSign ? height - p.y + total / 2 : height - max(p.y - 2, total + LabelOverlay.topMargin) + total
            for (s, size, pad, style) in boxes {
                let rect = NSRect(x: p.x - size.width / 2 - pad.width, y: top - size.height - 2 * pad.height,
                                  width: size.width + 2 * pad.width, height: size.height + 2 * pad.height)
                let shape = NSBezierPath(roundedRect: rect, xRadius: style == .statement ? 6 : 4, yRadius: style == .statement ? 6 : 4)
                NSColor(Tag.background(style)).setFill()
                shape.fill()
                if style == .statement {
                    NSColor(Tag.callColor).setStroke()
                    shape.lineWidth = 1.5
                    shape.stroke()
                }
                s.draw(with: rect.insetBy(dx: pad.width, dy: pad.height), options: .usesLineFragmentOrigin)
                top -= rect.height + 2
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

import AppKit
import Combine
import RealityKit
import TownCore

/// One character on screen, with its own queue of story actions (spec: timing rules).
@MainActor
final class Actor {
    enum Kind { case ceo, dispatcher, inspector, chief }

    let id: String
    let kind: Kind
    let body: CharacterEntity
    let block: String
    var name: String
    var hat: String?
    var ticketText: String?
    var bubble: String?
    var model: String?
    var working = false
    var activity: String?
    /// The telephone (or the Dispatcher's radio) this character uses.
    var phone: Phone?
    /// True while on a call, so a second call waits for the line.
    var onCall = false
    /// The round shadow under the feet, kept flat on the floor.
    var shadow: Entity?
    private var queue: [() async -> Void] = []
    private var running = false

    init(id: String, kind: Kind, body: CharacterEntity, block: String, name: String) {
        self.id = id; self.kind = kind; self.body = body; self.block = block; self.name = name
    }

    var root: Entity { body.root }
    var spot: SIMD2<Float> { [root.position.x, root.position.z] }

    /// A point `above` meters over the top of the head, following the character's lean.
    func head(above: Float = 0) -> SIMD3<Float> {
        root.position(relativeTo: nil) + TownScene.lean.act([0, 0.67 * Layout.characterScale + above, 0])
    }

    /// Story actions play one after another, each at full length.
    func enqueue(_ action: @escaping () async -> Void) {
        queue.append(action)
        guard !running else { return }
        running = true
        Task { @MainActor in
            while !queue.isEmpty {
                let next = queue.removeFirst()
                await next()
            }
            running = false
        }
    }

    var isBusy: Bool { running }

    /// The looping clip for standing at the desk.
    func settle() {
        guard !onCall else { return }
        if working {
            switch activity {
            case "read": body.play("holding-both")
            case "shell": body.play("interact-left")
            case "web", "mcp": body.play("holding-right")
            default: body.play("interact-right")
            }
        } else {
            body.play("idle")
        }
    }
}

/// A desk telephone (or a radio): the device on the desk and the part that is lifted to the ear.
@MainActor
final class Phone {
    let device: Entity
    let handset: Entity
    private let rest: Transform
    var ringing = false

    init(device: Entity, handset: Entity) {
        self.device = device
        self.handset = handset
        rest = handset.transform
    }

    /// The top of the device, for the ring label.
    var anchor: SIMD3<Float> { device.position(relativeTo: nil) + [0, 0.12, 0] }

    func ring(seconds: Double) async {
        ringing = true
        let base = device.transform
        let steps = Int(seconds / 0.1)
        for i in 0..<steps {
            var t = base
            t.rotation = base.rotation * simd_quatf(angle: (i % 2 == 0 ? 0.18 : -0.18), axis: [0, 1, 0])
            device.move(to: i == steps - 1 ? base : t, relativeTo: device.parent, duration: 0.09)
            try? await Task.sleep(for: .seconds(0.1))
        }
        device.transform = base
        ringing = false
    }

    /// Lifts the handset to `actor`'s ear.
    func lift(to actor: Actor) {
        guard let space = actor.root.parent else { return }
        var t = Transform(matrix: handset.transformMatrix(relativeTo: space))
        t.translation = actor.root.position + actor.root.orientation.act([0.13, 0.43, 0.06] * (Layout.characterScale / 0.75))
        t.rotation = actor.root.orientation * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        handset.move(to: t, relativeTo: space, duration: 0.3)
    }

    func hangUp() {
        handset.move(to: rest, relativeTo: handset.parent, duration: 0.3)
    }
}

/// One office block: the executive office, or a project's office.
@MainActor
final class BlockNode {
    let id: String
    let entity = Entity()
    var name: String
    /// Phones on the Chief of Staff desks, by desk slot.
    var deskPhones: [Int: Phone] = [:]
    var placed = false

    init(id: String, name: String) { self.id = id; self.name = name }
}

/// The office: blocks on one flat floor, furniture and characters, and the choreography
/// that turns building changes into scenes (spec scenes 1, 2, 8, 9, 10 in Phase 2).
@MainActor
final class TownScene: ObservableObject {
    static let executive = "executive"

    let root = Entity()
    let labels = Labels()
    var showModelBadges = false
    var onSound: ((String) -> Void)?
    /// The office size in meters (x by z), for the camera.
    @Published private(set) var officeSize = Layout.officeSize(count: 1)

    private let assets = Assets.shared
    private let ground = Entity()
    private var groundSize: SIMD2<Float> = .zero
    private var blocks: [String: BlockNode] = [:]
    private var blockOrder: [String] = []
    private var pendingRemoval: [String: Task<Void, Never>] = [:]
    private var deskSlots: [String: [String: Int]] = [:] // projectId → sessionId → slot
    private(set) var actors: [String: Actor] = [:]
    private var calls: [(Actor, Actor)] = []
    private var families: ModelFamilies?
    private var execPhones: (ceo: Phone?, dispatcher: Phone?) = (nil, nil)
    private static let blockColors: [(String, String)] = [
        ("#CDD0DA", "#C3C6D1"), // gray
        ("#B9CDE6", "#AFC4DF"), // blue
        ("#C5DCC0", "#BAD3B4"), // green
        ("#E3CDA8", "#DBC39C"), // wood
    ]

    init(families: ModelFamilies? = nil) {
        self.families = families
        addLight()
        root.addChild(ground)
        let exec = BlockNode(id: Self.executive, name: labels.executive)
        blocks[exec.id] = exec
        blockOrder = [exec.id]
        buildExecutiveBlock(exec)
        relayout()

        let ceo = makeActor(id: "ceo", kind: .ceo, base: "male-d", outfit: nil, block: exec, name: labels.ceo, at: Layout.ceoHome)
        let dispatcher = makeActor(id: "dispatcher", kind: .dispatcher, base: "female-e", outfit: nil, block: exec,
                                   name: labels.dispatcher, at: Layout.dispatcherHome)
        let inspector = makeActor(id: "inspector", kind: .inspector, base: "male-c", outfit: nil, block: exec,
                                  name: labels.inspector, at: Layout.inspectorHome)
        ceo.phone = execPhones.ceo
        dispatcher.phone = execPhones.dispatcher
        for a in [ceo, dispatcher, inspector] { a.body.play("idle") }
    }

    // MARK: Changes

    func handle(_ change: Change, building: Building) {
        switch change {
        case .blockAdded(let p):
            if let pending = pendingRemoval.removeValue(forKey: p) {
                pending.cancel() // the project came back before its block was cleared away
                blocks[p]?.name = building.blocks[p]?.name ?? p
                return
            }
            let node = BlockNode(id: p, name: building.blocks[p]?.name ?? p)
            blocks[p] = node
            blockOrder.append(p)
            let c = Self.blockColors[(blockOrder.count - 2) % Self.blockColors.count]
            buildProjectBlock(node, colors: (NSColor(hex: c.0)!, NSColor(hex: c.1)!))
            relayout()

        case .blockRemoved(let p):
            pendingRemoval[p] = Task { @MainActor [weak self] in
                // Let the last Chief of Staff walk out first.
                for _ in 0..<80 {
                    try? await Task.sleep(for: .milliseconds(150))
                    if Task.isCancelled { return }
                    if self?.actors.values.contains(where: { $0.block == p }) != true { break }
                }
                guard let self, !Task.isCancelled else { return }
                self.pendingRemoval[p] = nil
                self.blocks.removeValue(forKey: p)?.entity.removeFromParent()
                self.blockOrder.removeAll { $0 == p }
                self.deskSlots[p] = nil
                self.relayout()
            }

        case .chiefArrived(let p, let s):
            guard let node = blocks[p] else { return }
            if let name = building.blocks[p]?.name { node.name = name }
            let slot = freeSlot(p)
            deskSlots[p, default: [:]][s] = slot
            let chief = makeActor(id: s, kind: .chief, base: chiefBase(project: p),
                                  outfit: NSColor(hex: assets.characters.chiefOfStaff.color),
                                  block: node, name: labels.chiefOfStaff, at: Layout.entrance)
            chief.phone = node.deskPhones[slot]
            chief.model = building.blocks[p]?.chiefs[s]?.model
            chief.enqueue { [weak self] in
                guard let self else { return }
                await self.move(chief, to: Layout.chiefSpot(slot: slot))
                self.face(chief, toward: [0, 1])
                chief.settle()
            }

        case .chiefLeft(let p, let s):
            guard let chief = actors[s] else { return }
            deskSlots[p]?[s] = nil
            chief.working = false
            chief.enqueue { [weak self] in
                guard let self else { return }
                await self.move(chief, to: Layout.entrance)
                await self.move(chief, to: [Layout.entrance.x, -Layout.gap / 2])
                chief.root.removeFromParent()
                if self.actors[s] === chief { self.actors[s] = nil }
            }

        case .ticketSubmitted(let p, let s, let ticket):
            guard let chief = actors[s], deskSlots[p]?[s] != nil else { return }
            chief.hat = nil
            switch ticket.origin {
            case "user", "schedule":
                // The CEO (or the Dispatcher, for a schedule) phones the Chief of Staff with the ticket.
                let issuer = actors[ticket.issuer == .dispatcher ? "dispatcher" : "ceo"]!
                chief.enqueue { [weak self] in
                    guard let self else { return }
                    await self.call(from: issuer, to: chief, carrying: ticket.text)
                    chief.working = true
                    chief.settle()
                }
            default:
                // A follow-up or an untraced turn: the Chief of Staff picks it up from the inbox.
                chief.enqueue {
                    chief.body.play("pick-up", loop: false)
                    try? await Task.sleep(for: .seconds(0.8))
                    chief.ticketText = ticket.text
                    chief.working = true
                    chief.settle()
                }
            }

        case .hat(_, let s, let taskType):
            actors[s]?.hat = labels.taskType(taskType)

        case .ticketReturned(_, let s, _):
            guard let chief = actors[s] else { return }
            chief.working = true
            chief.bubble = labels.returned
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                if chief.bubble == self.labels.returned { chief.bubble = nil }
            }

        case .ticketDone(_, let s, _, let issuer, let aborted, let playSound):
            guard let chief = actors[s] else { return }
            chief.working = false
            chief.hat = nil
            if aborted {
                // Scene 9: stop working; no report call, no sound.
                chief.ticketText = nil
                chief.settle()
                return
            }
            // The Chief of Staff phones the report back to whoever issued the ticket.
            let receiver = actors[issuer == .dispatcher ? "dispatcher" : "ceo"]!
            chief.enqueue { [weak self] in
                guard let self else { return }
                await self.call(from: chief, to: receiver, carrying: nil)
                if playSound { self.onSound?("completion") }
                chief.settle()
            }

        case .activity(_, let s, let agentId, let kind):
            guard agentId == nil, let chief = actors[s] else { return }
            chief.activity = kind
            if !chief.isBusy { chief.settle() }

        case .model(_, let s, let agentId, let model):
            if agentId == nil { actors[s]?.model = model }

        default:
            break // staff, operators, schedules, approvals and messages arrive in Phases 3 and 4
        }
    }

    // MARK: Calls and motion

    /// A phone call. The caller lifts the handset, the other phone rings and is answered,
    /// they talk, and the ticket (the caller's, or `text`) passes to the callee.
    private func call(from caller: Actor, to callee: Actor, carrying text: String?) async {
        while caller.onCall || callee.onCall { try? await Task.sleep(for: .milliseconds(150)) }
        guard let out = caller.phone, let inn = callee.phone else { return }
        caller.onCall = true
        callee.onCall = true
        if let text { caller.ticketText = text }

        caller.body.play("interact-right", loop: false)
        try? await Task.sleep(for: .seconds(0.35))
        out.lift(to: caller)
        caller.body.play("holding-right")
        calls.append((caller, callee))

        await inn.ring(seconds: 1.2)
        callee.body.play("interact-right", loop: false)
        try? await Task.sleep(for: .seconds(0.35))
        inn.lift(to: callee)
        callee.body.play("holding-right")

        try? await Task.sleep(for: .seconds(1.6))
        callee.ticketText = callee.kind == .chief ? caller.ticketText : nil // the CEO and the Dispatcher just take the report
        caller.ticketText = nil

        out.hangUp()
        inn.hangUp()
        calls.removeAll { $0.0 === caller && $0.1 === callee }
        try? await Task.sleep(for: .seconds(0.3))
        caller.onCall = false
        callee.onCall = false
        caller.settle()
        callee.settle()
    }

    private func move(_ a: Actor, to p: SIMD2<Float>, speed: Float = Layout.walkSpeed) async {
        let from = a.spot
        let d = simd_distance(from, p)
        guard d > 0.01 else { return }
        face(a, toward: p - from)
        a.body.play("walk")
        var t = a.root.transform
        t.translation = [p.x, Layout.floorThickness, p.y]
        let seconds = Double(d / speed)
        a.root.move(to: t, relativeTo: a.root.parent, duration: seconds, timingFunction: .linear)
        try? await Task.sleep(for: .seconds(seconds))
        a.body.play("idle")
    }

    /// Characters lean back toward the camera so they show their fronts on the top-down map,
    /// the way Gather draws people standing up on a flat floor.
    static let lean = simd_quatf(angle: -(Projector.pitch - 0.2), axis: [1, 0, 0])

    private func face(_ a: Actor, toward dir: SIMD2<Float>) {
        guard simd_length(dir) > 0.001 else { return }
        a.root.orientation = Self.lean * simd_quatf(angle: atan2(dir.x, dir.y), axis: [0, 1, 0])
        a.shadow?.orientation = a.root.orientation.inverse
    }

    // MARK: Building

    private func makeActor(id: String, kind: Actor.Kind, base: String, outfit: NSColor?, block: BlockNode, name: String,
                           at spot: SIMD2<Float>) -> Actor {
        let body = (try? assets.character(base, outfit: outfit)) ?? CharacterEntity(model: Entity(), clips: [:])
        body.root.position = [spot.x, Layout.floorThickness, spot.y]
        body.model.scale = SIMD3(repeating: Layout.characterScale)
        // A soft round shadow under the feet.
        var shade = UnlitMaterial(applyPostProcessToneMap: false)
        shade.color = .init(tint: .black)
        shade.blending = .transparent(opacity: 0.18)
        let blob = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.16 * Layout.characterScale / 0.75),
                               materials: [shade])
        blob.position.y = 0.003
        body.root.addChild(blob)
        block.entity.addChild(body.root)
        let a = Actor(id: id, kind: kind, body: body, block: block.id, name: name)
        a.shadow = blob
        face(a, toward: [0, 1])
        actors[id] = a
        return a
    }

    private func freeSlot(_ p: String) -> Int {
        let used = Set(deskSlots[p]?.values.map { $0 } ?? [])
        return (0..<Layout.maxDesks).first { !used.contains($0) } ?? 0
    }

    /// Chiefs of Staff in one block get different base characters.
    private func chiefBase(project p: String) -> String {
        let excluded = Set(assets.characters.chiefOfStaff.exclude)
        let all = assets.characters.characters.keys.sorted().filter { !excluded.contains($0) }
        let inBlock = Set((deskSlots[p] ?? [:]).keys.compactMap { actors[$0]?.body.baseName })
        let start = abs(p.hashValue) % all.count
        for i in 0..<all.count {
            let c = all[(start + i) % all.count]
            if !inBlock.contains(c) { return c }
        }
        return all[start]
    }

    /// Places the blocks in their grid and sizes the path around them.
    private func relayout() {
        let n = blockOrder.count
        for (i, id) in blockOrder.enumerated() {
            guard let node = blocks[id] else { continue }
            let o = Layout.blockOrigin(i, count: n)
            var t = node.entity.transform
            t.translation = [o.x, 0, o.y]
            if node.placed {
                node.entity.move(to: t, relativeTo: root, duration: 0.6, timingFunction: .easeInOut)
            } else {
                node.entity.transform = t
                root.addChild(node.entity)
                node.placed = true
            }
        }
        officeSize = Layout.officeSize(count: n)
        buildGround()
    }

    private func addLight() {
        let sun = DirectionalLight()
        sun.light.intensity = 2800
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 40, depthBias: 2)
        sun.look(at: .zero, from: [-3, 10, 5], relativeTo: nil)
        root.addChild(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 1100
        fill.look(at: .zero, from: [4, 5, 9], relativeTo: nil)
        root.addChild(fill)
    }

    private static func box(_ size: SIMD3<Float>, _ color: NSColor, at p: SIMD3<Float>) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: min(0.01, size.min() / 3)),
                            materials: [SimpleMaterial(color: color, roughness: 0.8, isMetallic: false)])
        e.position = p
        return e
    }

    /// A flat tiled rectangle, drawn without lighting so it reads as a 2D map.
    private static func tiles(width: Float, depth: Float, tile: Float, colors: (NSColor, NSColor),
                              grout: NSColor? = nil, brick: Bool = false) -> ModelEntity {
        let px = 24
        let cols = max(1, Int((width / tile).rounded()))
        let rows = max(1, Int((depth / tile).rounded()) * (brick ? 2 : 1))
        let rh = brick ? px / 2 : px
        let w = cols * px, h = rows * rh
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for r in 0..<rows {
            for c in -1...cols {
                let x = c * px + (brick && r % 2 == 1 ? px / 2 : 0)
                let color = brick ? colors.0 : ((r + c + 2) % 2 == 0 ? colors.0 : colors.1)
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: x, y: r * rh, width: px, height: rh))
                if let grout {
                    ctx.setFillColor(grout.cgColor)
                    ctx.fill(CGRect(x: x, y: r * rh, width: px, height: 1))
                    ctx.fill(CGRect(x: x, y: r * rh, width: 1, height: rh))
                }
            }
        }
        // No tone mapping: the floor colors show as picked.
        var m = UnlitMaterial(applyPostProcessToneMap: false)
        if let img = ctx.makeImage(), let tex = try? TextureResource(image: img, options: .init(semantic: .color)) {
            m.color = .init(tint: .white, texture: .init(tex))
        } else {
            m.color = .init(tint: colors.0)
        }
        return ModelEntity(mesh: .generatePlane(width: width, depth: depth), materials: [m])
    }

    /// The cream brick path the blocks sit on, larger than any window shows.
    private func buildGround() {
        let size = officeSize + [40, 40]
        guard size.x > groundSize.x || size.y > groundSize.y else { return }
        groundSize = size
        ground.children.removeAll()
        let plane = Self.tiles(width: size.x, depth: size.y, tile: 0.5,
                               colors: (NSColor(hex: "#F4EADB")!, NSColor(hex: "#F4EADB")!),
                               grout: NSColor(hex: "#EADDC9")!, brick: true)
        plane.position = [officeSize.x / 2, -0.001, officeSize.y / 2]
        ground.addChild(plane)
    }

    /// The block's floor: a tiled carpet with a darker edge along the front, like a Gather room.
    private func floor(_ node: BlockNode, colors: (NSColor, NSColor)) {
        let w = Layout.blockWidth, d = Layout.blockDepth
        let carpet = Self.tiles(width: w, depth: d, tile: 0.5, colors: colors)
        carpet.position = [w / 2, Layout.floorThickness, d / 2]
        node.entity.addChild(carpet)
        let edge = colors.1.blended(withFraction: 0.35, of: .black) ?? colors.1
        node.entity.addChild(Self.box([w, Layout.floorThickness, 0.08], edge, at: [w / 2, Layout.floorThickness / 2, d + 0.04]))
    }

    /// Places a furniture model with its footprint centered on `p` (Kenney models are anchored at a corner).
    @discardableResult
    private func place(_ name: String, in f: Entity, at p: SIMD2<Float>, yaw: Float = 0, scale: Float = 1,
                       onTopOf base: Entity? = nil) -> Entity? {
        guard let model = try? assets.furniture(name) else { return nil }
        // Wrap it: the model's own root transform turns the file's axes upright and must be kept.
        let e = Entity()
        e.addChild(model)
        let k = scale * Layout.furnitureScale
        e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        e.scale = [k, k, k]
        f.addChild(e)
        let b = e.visualBounds(relativeTo: f)
        let floorY = base.map { $0.visualBounds(relativeTo: f).max.y } ?? Layout.floorThickness
        e.position = [p.x - b.center.x, floorY - b.min.y, p.y - b.center.z]
        return e
    }

    /// A desk telephone at `p` on top of `desk`.
    private func telephone(in f: Entity, at p: SIMD2<Float>, on desk: Entity) -> Phone {
        let top = desk.visualBounds(relativeTo: f).max.y
        let k = Layout.furnitureScale / 0.85
        let device = Entity()
        device.position = [p.x, top, p.y]
        device.addChild(Self.box([0.16 * k, 0.05 * k, 0.12 * k], NSColor(hex: "#B8322F")!, at: [0, 0.025 * k, 0]))
        device.addChild(Self.box([0.09 * k, 0.006 * k, 0.05 * k], NSColor(hex: "#F2EEE6")!, at: [0, 0.052 * k, 0.025 * k]))
        let handset = Self.box([0.17 * k, 0.035 * k, 0.045 * k], NSColor(hex: "#8E2321")!, at: [0, 0.07 * k, -0.03 * k])
        device.addChild(handset)
        f.addChild(device)
        return Phone(device: device, handset: handset)
    }

    private func buildExecutiveBlock(_ node: BlockNode) {
        let f = node.entity
        floor(node, colors: (NSColor(hex: "#9D9FDC")!, NSColor(hex: "#9294D4")!))
        // The CEO's corner.
        place("rugRectangle", in: f, at: [Layout.ceoDesk.x, Layout.ceoDesk.y - 0.1], scale: 0.9)
        if let desk = place("desk", in: f, at: Layout.ceoDesk) {
            place("computerScreen", in: f, at: [Layout.ceoDesk.x - 0.1, Layout.ceoDesk.y - 0.05], scale: 0.8, onTopOf: desk)
            execPhones.ceo = telephone(in: f, at: [Layout.ceoDesk.x + 0.28, Layout.ceoDesk.y + 0.02], on: desk)
        }
        place("bookcaseClosedWide", in: f, at: [Layout.ceoDesk.x, 0.18])
        place("pottedPlant", in: f, at: [0.25, 0.3])
        // Reception, where the Inspector stands.
        place("kitchenBar", in: f, at: [Layout.receptionDesk.x - 0.19, Layout.receptionDesk.y])
        place("kitchenBar", in: f, at: [Layout.receptionDesk.x + 0.19, Layout.receptionDesk.y])
        place("plantSmall1", in: f, at: [0.35, 3.6])
        place("loungeChair", in: f, at: [1.0, 3.3])
        // The Dispatcher's desk with the radio, and the schedule board behind.
        f.addChild(Self.box([1.5, 0.55, 0.04], NSColor(hex: "#2E5244")!, at: [Layout.boardCenter.x, 0.42, Layout.boardCenter.y]))
        f.addChild(Self.box([1.6, 0.05, 0.05], NSColor(hex: "#7A5A3A")!, at: [Layout.boardCenter.x, 0.16, Layout.boardCenter.y]))
        if let desk = place("desk", in: f, at: Layout.dispatcherDesk),
           let radio = place("radio", in: f, at: [Layout.dispatcherDesk.x + 0.25, Layout.dispatcherDesk.y], onTopOf: desk) {
            // The radio is lifted whole; a holder stays on the desk.
            let holder = Entity()
            holder.transform = radio.transform
            f.addChild(holder)
            radio.transform = Transform()
            holder.addChild(radio)
            execPhones.dispatcher = Phone(device: holder, handset: radio)
        }
        place("pottedPlant", in: f, at: [5.75, 0.3])
        place("plantSmall1", in: f, at: [5.7, 3.6])
    }

    private func buildProjectBlock(_ node: BlockNode, colors: (NSColor, NSColor)) {
        let f = node.entity
        floor(node, colors: colors)
        // Chief of Staff desks, each with a telephone.
        for slot in 0..<Layout.maxDesks {
            let x = Layout.deskX(slot: slot)
            guard let desk = place("desk", in: f, at: [x, Layout.deskRowZ]) else { continue }
            place("computerScreen", in: f, at: [x - 0.1, Layout.deskRowZ - 0.05], scale: 0.8, onTopOf: desk)
            node.deskPhones[slot] = telephone(in: f, at: [x + 0.28, Layout.deskRowZ + 0.02], on: desk)
        }
        // Machine room (front left) for operators.
        f.addChild(Self.box([2.6, 0.006, 1.3], NSColor(hex: "#7D8590")!, at: [1.5, Layout.floorThickness + 0.003, 3.05]))
        for i in 0..<4 { place("speaker", in: f, at: [0.6 + Float(i) * 0.55, 2.6], scale: 1.4) }
        // Resource bench (front right): a lounge.
        place("rugRound", in: f, at: [4.6, 3.0])
        place("loungeSofaLong", in: f, at: [4.6, 2.55])
        place("tableCoffee", in: f, at: [4.6, 3.15])
        place("pottedPlant", in: f, at: [5.75, 0.3])
    }

    // MARK: Labels

    struct LabelItem {
        enum Style { case name, hat, ticket, bubble, badge, sign, ring }
        let id: String
        let anchor: SIMD3<Float>
        let lines: [(String, Style)]
    }

    /// Lines between the two ends of each call in progress.
    func callLines() -> [(SIMD3<Float>, SIMD3<Float>)] {
        calls.map { (a, b) in (a.head(above: -0.15), b.head(above: -0.15))
        }
    }

    func labelItems() -> [LabelItem] {
        var items: [LabelItem] = []
        for a in actors.values {
            var lines: [(String, LabelItem.Style)] = []
            if let b = a.bubble { lines.append((b, .bubble)) }
            if let h = a.hat { lines.append((h, .hat)) }
            if let t = a.ticketText { lines.append((String(t.prefix(28)) + (t.count > 28 ? "…" : ""), .ticket)) }
            if showModelBadges, let m = a.model { lines.append((families?.label(for: m) ?? m, .badge)) }
            lines.append((a.name, .name))
            items.append(LabelItem(id: a.id, anchor: a.head(above: 0.04), lines: lines))
            if let phone = a.phone, phone.ringing {
                items.append(LabelItem(id: "ring-\(a.id)", anchor: phone.anchor, lines: [(labels.ring, .ring)]))
            }
        }
        for node in blocks.values where node.placed {
            let o = node.entity.position(relativeTo: nil)
            items.append(LabelItem(id: "block-\(node.id)", anchor: o + [Layout.blockWidth / 2, 0, 0], lines: [(node.name, .sign)]))
        }
        return items
    }
}

extension CharacterEntity {
    var baseName: String? { model.name.isEmpty ? nil : model.name }
}

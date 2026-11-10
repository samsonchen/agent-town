import AppKit
import Combine
import RealityKit
import TownCore

/// The office: blocks on one flat floor, furniture and characters, and the choreography
/// that turns building changes into scenes. Staff, operators and the bench are in
/// TownScene+Staff.swift.
@MainActor
final class TownScene: ObservableObject {
    static let executive = "executive"
    /// Characters lean back toward the camera so they show their fronts on the top-down map,
    /// the way Gather draws people standing up on a flat floor.
    static let lean = simd_quatf(angle: -(Projector.pitch - 0.2), axis: [1, 0, 0])

    let root = Entity()
    let labels = Labels()
    var showModelBadges = false
    var onSound: ((String) -> Void)?
    /// The office size in meters (x by z), for the camera.
    @Published private(set) var officeSize = Layout.officeSize(count: 1)

    let assets = Assets.shared
    /// The latest building state, for looking up roles and parents while scenes play.
    var building = Building()
    private let ground = Entity()
    private var groundSize: SIMD2<Float> = .zero
    var blocks: [String: BlockNode] = [:]
    /// The blocks on screen, executive first. A project's block is on screen only while it has work.
    var blockOrder: [String] = []
    /// Project blocks kept off-screen while their sessions have no work (spec: as few blocks as possible).
    var hidden: Set<String> = []
    var idleSince: [String: Date] = [:]
    /// When each project last had work, to choose which block stays on screen.
    var lastWork: [String: Date] = [:]
    var actors: [String: Actor] = [:]
    private var calls: [(Actor, Actor)] = []
    /// Pages in progress: the caller, the block whose bench speaker they talk through, and who is called.
    var pages: [(caller: Actor, node: BlockNode, text: String)] = []
    /// approvalId → the character waiting.
    var approvals: [String: Actor] = [:]
    private var ceoRinging = false
    var pendingCalls: [String: PendingCall] = [:]
    var nextWorkerId = 0
    private var families: ModelFamilies?
    var execPhones: (ceo: Phone?, dispatcher: Phone?) = (nil, nil)

    // The CEO under the user's control (TownScene+CEO.swift).
    /// True while the CEO is away from the desk; the tip and the phone follow it.
    @Published var ceoAway = false
    /// The CEO's position on the office floor (x, z), for the camera to follow.
    @Published var ceoSpot: SIMD2<Float> = .zero
    var heldArrows: Set<UInt16> = []
    var ceoDriver: Task<Void, Never>?
    var ceoTrip: Task<Void, Never>?
    /// Waits for the report calls to end, then walks the CEO home (ceoHomeWhenAllDone).
    var ceoHomeTask: Task<Void, Never>?
    /// The character the user clicked; the CEO talks to them once there.
    weak var ceoVisitee: Actor?
    var mobilePhone: Phone?
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
        mobilePhone = makeMobile(for: ceo)
        ceoSpot = ceo.worldSpot
        dispatcher.phone = execPhones.dispatcher
        for a in [ceo, dispatcher, inspector] { a.body.play("idle") }
        startBenchLife()
        startIdleWatch()
        startTyping()
    }

    // MARK: Changes

    func handle(_ change: Change, building: Building) {
        let wasAllDone = allWorkDone
        self.building = building
        defer { if !wasAllDone && allWorkDone { ceoHomeWhenAllDone() } }
        if let p = change.projectId, hasWork(p) {
            lastWork[p] = Date()
            if hidden.contains(p) { show(p) }
        }
        switch change {
        case .blockAdded(let p):
            let node = BlockNode(id: p, name: building.blocks[p]?.name ?? p)
            blocks[p] = node
            let c = Self.blockColors[(blocks.count - 2) % Self.blockColors.count]
            buildProjectBlock(node, colors: (NSColor(hex: c.0)!, NSColor(hex: c.1)!))
            placeNewBlock(p)
            fillBench(node)

        case .blockRemoved(let p):
            // The last session closed: the block goes at once, no one walks out.
            guard let node = blocks.removeValue(forKey: p) else { return }
            node.entity.removeFromParent()
            for (id, a) in actors where a.block == p { actors[id] = nil }
            for (id, c) in pendingCalls where c.node === node { pendingCalls[id] = nil }
            hidden.remove(p)
            idleSince[p] = nil
            lastWork[p] = nil
            if blockOrder.contains(p) {
                blockOrder.removeAll { $0 == p }
                relayout()
                keepOneProjectShown()
                ceoBackIfOfficeEmpty()
            }

        case .chiefArrived(let p, let s):
            // One Chief per session ID; a second project claiming it is ignored.
            guard let node = blocks[p], actors[s] == nil else { return }
            if let name = building.blocks[p]?.name { node.name = name }
            let slot = BlockNode.free(node.chiefSlots, below: Layout.maxDesks)
            node.chiefSlots[s] = slot
            let carriesDesk = slot > 0
            let chief = makeActor(id: s, kind: .chief, base: chiefBase(node),
                                  outfit: NSColor(hex: assets.characters.chiefOfStaff.color),
                                  block: node, name: labels.chiefOfStaff,
                                  at: carriesDesk ? Layout.entrance : Layout.chiefSpot(slot: slot))
            chief.home = Layout.chiefSpot(slot: slot)
            chief.hasComputer = true
            chief.model = building.blocks[p]?.chiefs[s]?.model
            if carriesDesk {
                // Another session in the project: its Chief walks in with a desk and a phone.
                let (kit, phone) = makeDeskKit(node, chief: true)
                carry(kit, by: chief)
                chief.enqueue { [weak self] in
                    guard let self else { return }
                    await self.walk(chief, to: chief.home)
                    await self.putDown(kit, by: chief, in: node, slot: slot)
                    chief.phone = phone
                    self.face(chief, toward: chief.homeFacing)
                    chief.settle()
                }
            } else {
                // The first Chief is already at the desk when the block shows; no walk-in.
                chief.phone = node.deskPhones[0]
                chief.settle()
            }

        case .chiefLeft(let p, let s):
            // Only this block's Chief: a session ID seen in two projects must not take the other one.
            guard let chief = actors[s], chief.block == p, let node = blocks[p] else { return }
            let slot = node.chiefSlots.removeValue(forKey: s)
            chief.working = false
            sessionEnded(s, in: node)
            actors[s] = nil
            if let slot, node.carried[slot] != nil {
                // A Chief who carried a desk in carries it out again.
                chief.enqueue { [weak self] in
                    guard let self else { return }
                    await self.walk(chief, to: Layout.chiefSpot(slot: slot))
                    await self.pickUp(by: chief, in: node, slot: slot)
                    await self.leave(chief, node)
                }
            } else {
                // The session ended: the Chief of Staff is gone at once, no walk-out.
                chief.root.removeFromParent()
            }

        case .ticketSubmitted(_, let s, let ticket):
            guard let chief = actors[s] else { return }
            chief.hat = nil
            chief.since = Date()
            switch ticket.origin {
            case "user", "schedule":
                // The CEO (or the Dispatcher, for a schedule) phones the Chief of Staff with the ticket.
                let issuer = actors[ticket.issuer == .dispatcher ? "dispatcher" : "ceo"]!
                chief.enqueue { [weak self] in
                    guard let self else { return }
                    // A short computer sound as the ticket's call rings.
                    await self.call(from: issuer, to: chief, carrying: ticket.text) { self.onSound?("dispatch") }
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

        case .ticketDone(let p, let s, _, let issuer, let aborted, let playSound):
            blocks[p]?.activeDesk[s] = nil
            guard let chief = actors[s] else { return }
            chief.working = false
            chief.hat = nil
            chief.since = nil
            if aborted {
                // Scene 9: stop working; no report call, no sound.
                chief.ticketText = nil
                chief.settle()
                return
            }
            // The Chief of Staff phones the report back to whoever issued the ticket, once the
            // desk worker who did the main loop's work has brought theirs (up to 15 seconds).
            let receiver = actors[issuer == .dispatcher ? "dispatcher" : "ceo"]!
            Task { @MainActor [weak self] in
                let until = Date().addingTimeInterval(15)
                while Date() < until, let node = self?.blocks[p],
                      node.jobs.keys.contains(where: { $0.hasPrefix("a:\(s)/desk-") }) {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                chief.enqueue { [weak self] in
                    guard let self else { return }
                    // The sound plays as the report call rings, so the call is on screen when it is heard.
                    await self.call(from: chief, to: receiver, carrying: nil) {
                        if playSound { self.onSound?("completion") }
                    }
                    chief.settle()
                }
            }

        case .activity(let p, let s, let agentId, let kind):
            guard let a = agentId.map({ worker(p, "a:\(s)/\($0)") }) ?? actors[s] else { return }
            a.activity = kind
            if let agentId, agentId.hasPrefix("desk-") { focusDesk(p, s, job: "a:\(s)/\(agentId)") }
            if !a.isBusy { a.settle() }

        case .model(let p, let s, let agentId, let model):
            (agentId.map { worker(p, "a:\(s)/\($0)") } ?? actors[s])?.model = model

        case .staffHired(let p, let s, let agentId):
            hire(p, s, job: "a:\(s)/\(agentId)")
        case .staffRole(let p, let s, let agentId, let role):
            roleDecided(p, job: "a:\(s)/\(agentId)", role: role)
        case .staffDone(let p, let s, let agentId, let status):
            jobDone(p, job: "a:\(s)/\(agentId)", status: status)
        case .taskStarted(let p, let s, let taskId):
            hire(p, s, job: "t:\(s)/\(taskId)")
        case .taskRole(let p, let s, let taskId, let role):
            roleDecided(p, job: "t:\(s)/\(taskId)", role: role)
        case .taskDone(let p, let s, let taskId, let status):
            jobDone(p, job: "t:\(s)/\(taskId)", status: status)

        case .approvalWait(let p, let s, let id, let agentId, let autoMode):
            guard let a = agentId.flatMap({ worker(p, "a:\(s)/\($0)") }) ?? actors[s] else { return }
            approvals[id] = a
            a.awaitingApproval = true
            if !a.isBusy { a.settle() }
            if !autoMode { onSound?("approval") } // in auto mode the classifier, not the user, answers
            ringCeoForApprovals()

        case .approvalEnd(_, _, let id, _):
            guard let a = approvals.removeValue(forKey: id) else { return }
            if !approvals.values.contains(where: { $0 === a }) {
                a.awaitingApproval = false
                if !a.isBusy { a.settle() }
            }

        case .message(let p, let s, let from, let to, let broadcast):
            message(p, s, from: from, to: to, broadcast: broadcast)

        case .compactStarted(let p, let s, _):
            compactStarted(p, s)
        case .compactDone(let p, let s, let outcome, let before, let after):
            compactDone(p, s, outcome: outcome, before: before, after: after)

        case .context:
            break // the bar under the block reads the building state

        case .scheduleAdded, .scheduleRemoved:
            break // the Dispatcher's board comes in Phase 4
        }
    }

    // MARK: Calls

    /// A phone call. The caller lifts the handset, the other phone rings and is answered,
    /// they talk, and the ticket (the caller's, or `text`) passes to the callee.
    /// `ringing` runs as the callee's phone starts to ring, for a sound heard while the call shows.
    func call(from caller: Actor, to callee: Actor, carrying text: String?, ringing: (() -> Void)? = nil) async {
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

        while inn.ringing { try? await Task.sleep(for: .milliseconds(100)) } // an approval ring in progress
        ringing?()
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
        syncCeoPhone()
    }

    /// The CEO's phone rings while any tool call waits for approval (spec scene 6).
    private func ringCeoForApprovals() {
        guard !ceoRinging, let ceo = actors["ceo"] else { return }
        ceoRinging = true
        Task { @MainActor in
            while !approvals.isEmpty {
                // The desk phone, or the mobile while the CEO is away.
                if !ceo.onCall, let phone = ceo.phone { await phone.ring(seconds: 1.0) }
                try? await Task.sleep(for: .seconds(0.6))
            }
            ceoRinging = false
            if !ceo.onCall && !ceo.isBusy && !ceo.steering {
                ceo.body.play("emote-yes", loop: false)
                try? await Task.sleep(for: .seconds(0.8))
                if !ceo.onCall { ceo.settle() }
            }
        }
    }

    // MARK: Motion

    func move(_ a: Actor, to p: SIMD2<Float>, speed: Float = Layout.walkSpeed) async {
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
    }

    /// Walks inside the block along the walkways.
    func walk(_ a: Actor, to dest: SIMD2<Float>) async {
        a.sitting = false
        for p in Layout.route(a.spot, dest) { await move(a, to: p) }
        a.body.play("idle")
    }

    /// Walks to the character's own spot and settles there.
    func goHome(_ a: Actor) async {
        await walk(a, to: a.home)
        face(a, toward: a.homeFacing)
        a.settle()
    }

    func face(_ a: Actor, toward dir: SIMD2<Float>) {
        guard simd_length(dir) > 0.001 else { return }
        a.root.orientation = Self.lean * simd_quatf(angle: atan2(dir.x, dir.y), axis: [0, 1, 0])
        a.shadow?.orientation = a.root.orientation.inverse
    }

    // MARK: Building

    func makeActor(id: String, kind: Actor.Kind, base: String, outfit: NSColor?, block: BlockNode, name: String,
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
        let a = Actor(id: id, kind: kind, body: body, block: block.id, name: name, home: spot)
        a.shadow = blob
        face(a, toward: [0, 1])
        actors[id] = a
        return a
    }

    /// Chiefs of Staff in one block get different base characters.
    private func chiefBase(_ node: BlockNode) -> String {
        let excluded = Set(assets.characters.chiefOfStaff.exclude)
        let all = assets.characters.characters.keys.sorted().filter { !excluded.contains($0) }
        let inBlock = Set(node.chiefSlots.keys.compactMap { actors[$0]?.body.baseName })
        let start = abs(node.id.hashValue) % all.count
        for i in 0..<all.count {
            let c = all[(start + i) % all.count]
            if !inBlock.contains(c) { return c }
        }
        return all[start]
    }

    /// Places the blocks in their grid and sizes the path around them.
    func relayout() {
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

    static func box(_ size: SIMD3<Float>, _ color: NSColor, at p: SIMD3<Float>) -> ModelEntity {
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
    func place(_ name: String, in f: Entity, at p: SIMD2<Float>, yaw: Float = 0, scale: Float = 1,
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
        if base == nil, !name.hasPrefix("rug"), let node = blocks.values.first(where: { $0.entity === f }) {
            let fb = e.visualBounds(relativeTo: f)
            node.obstacles.append((min: [fb.min.x, fb.min.z], max: [fb.max.x, fb.max.z]))
        }
        return e
    }

    /// A desk telephone at `p` on top of `desk`.
    func telephone(in f: Entity, at p: SIMD2<Float>, on desk: Entity) -> Phone {
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
        place("plantSmall1", in: f, at: [0.35, 5.0])
        place("loungeChair", in: f, at: [1.1, 4.4])
        place("loungeChair", in: f, at: [1.9, 4.4])
        place("tableCoffee", in: f, at: [1.5, 4.95], scale: 0.8)
        // The Dispatcher's desk with the radio, and the schedule board behind.
        f.addChild(Self.box([1.5, 0.55, 0.04], NSColor(hex: "#2E5244")!, at: [Layout.boardCenter.x, 0.42, Layout.boardCenter.y]))
        f.addChild(Self.box([1.6, 0.05, 0.05], NSColor(hex: "#7A5A3A")!, at: [Layout.boardCenter.x, 0.16, Layout.boardCenter.y]))
        node.obstacles.append((min: Layout.boardCenter - [0.8, 0.05], max: Layout.boardCenter + [0.8, 0.05]))
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
        place("pottedPlant", in: f, at: [6.75, 0.3])
        place("plantSmall1", in: f, at: [6.7, 5.0])
        place("bookcaseOpen", in: f, at: [6.4, 3.3], yaw: -.pi / 2)
    }

    private func buildProjectBlock(_ node: BlockNode, colors: (NSColor, NSColor)) {
        let f = node.entity
        floor(node, colors: colors)
        // One Chief of Staff desk with a telephone; the rest of the back row is open floor,
        // where a second session's Chief, or staff past the front desks, set down a desk they carry in.
        let x0 = Layout.deskX(slot: 0)
        if let desk = place("desk", in: f, at: [x0, Layout.chiefDeskZ]) {
            place("computerScreen", in: f, at: [x0 - 0.1, Layout.chiefDeskZ - 0.05], scale: 0.8, onTopOf: desk)
            node.deskPhones[0] = telephone(in: f, at: [x0 + 0.28, Layout.chiefDeskZ + 0.02], on: desk)
            node.deskTops[0] = desk.visualBounds(relativeTo: f).max.y
        }
        for slot in 0..<Layout.maxDesks {
            let x = Layout.deskX(slot: slot)
            // Staff desks.
            if let desk = place("desk", in: f, at: [x, Layout.staffDeskZ]) {
                place("laptop", in: f, at: [x, Layout.staffDeskZ - 0.03], onTopOf: desk)
            }
        }
        // Machine room (front left): racks along the back, for operators.
        f.addChild(Self.box([3.3, 0.006, 1.95], NSColor(hex: "#7D8590")!, at: [1.8, Layout.floorThickness + 0.003, 4.275]))
        for i in 0..<Layout.consoles {
            place("speaker", in: f, at: [Layout.rackX(i) - 0.15, Layout.rackZ], scale: 1.4)
            place("speaker", in: f, at: [Layout.rackX(i) + 0.15, Layout.rackZ], scale: 1.4)
        }
        // Resource bench (front right): a lounge.
        place("rugRound", in: f, at: Layout.benchCenter, scale: 1.3)
        place("loungeSofaLong", in: f, at: [Layout.benchCenter.x, 3.5])
        place("tableCoffee", in: f, at: [Layout.benchCenter.x, 4.3])
        if let table = place("sideTable", in: f, at: Layout.speakerSpot) {
            node.speaker = place("speaker", in: f, at: Layout.speakerSpot, scale: 0.8, onTopOf: table)
        }
        place("kitchenCoffeeMachine", in: f, at: [6.75, 3.45])
        place("pottedPlant", in: f, at: [6.75, 5.1])
        place("pottedPlant", in: f, at: [6.75, 0.3])
    }

    // MARK: Labels

    struct LabelItem {
        enum Style { case name, faint, hat, ticket, bubble, badge, sign, ring, speech, statement }
        let id: String
        let anchor: SIMD3<Float>
        let lines: [(String, Style)]
        /// A sign whose task titles are too wide to show whole: the whole sign scrolls.
        var scroll = false
    }

    /// Lines between the two ends of each call in progress, and from each character
    /// waiting for approval to the CEO.
    func callLines() -> [(SIMD3<Float>, SIMD3<Float>)] {
        var out = calls.map { (a, b) in (a.head(above: -0.15), b.head(above: -0.15)) }
        for page in pages {
            if let top = speakerTop(page.node) { out.append((page.caller.head(above: -0.15), top)) }
        }
        if let ceo = actors["ceo"] {
            for a in Set(approvals.values.map(\.id)).compactMap({ actors[$0] }) {
                out.append((a.head(above: -0.15), ceo.head(above: -0.15)))
            }
        }
        return out
    }

    /// The context bar under a project block: one per Chief of Staff (session) there.
    struct MeterItem {
        let id: String
        /// The middle of the block's front edge.
        let anchor: SIMD3<Float>
        /// Its place in the stack under the block, from 0.
        let row: Int
        let fraction: Double?
        let text: String
    }

    func meterItems() -> [MeterItem] {
        var out: [MeterItem] = []
        for node in blocks.values where node.placed && node.id != Self.executive {
            guard let block = building.blocks[node.id] else { continue }
            let o = node.entity.position(relativeTo: nil)
            let anchor = o + [Layout.blockWidth / 2, 0, Layout.blockDepth]
            let sessions = block.order.filter { block.chiefs[$0] != nil }
            for (row, s) in sessions.enumerated() {
                let c = block.chiefs[s]!
                var parts: [String] = []
                if sessions.count > 1, let slot = node.chiefSlots[s] { parts.append(labels.desk(slot + 1)) }
                parts.append(labels.contextLine(c.context))
                out.append(MeterItem(id: "meter-\(s)", anchor: anchor, row: row, fraction: c.context.fraction,
                                     text: parts.joined(separator: " · ")))
            }
        }
        return out
    }

    func labelItems() -> [LabelItem] {
        var items: [LabelItem] = []
        let touched = touchedByCeo()
        for a in actors.values where onScreen(a) {
            var lines: [(String, LabelItem.Style)] = []
            if a.speaking { lines.append(("• • •", .speech)) }
            if a.awaitingApproval { lines.append((labels.needsApproval, .ring)) }
            if let b = a.bubble { lines.append((b, .bubble)) }
            if let n = a.note { lines.append((n, .ticket)) }
            // The hat shows only while no staff are working (spec: hats).
            if let h = a.hat, !hasWorkingStaff(a) { lines.append((h, .hat)) }
            if let t = a.ticketText { lines.append((String(t.prefix(28)) + (t.count > 28 ? "…" : ""), .ticket)) }
            if showModelBadges, a.kind == .chief || a.job?.hasPrefix("a:") == true, let m = a.model {
                lines.append((families?.label(for: m) ?? m, .badge))
            }
            if a.kind == .worker {
                if a.job != nil {
                    lines.append((a.role.map(labels.role) ?? (a.isOperator ? labels.operatorName : labels.staff), .name))
                } else if let r = a.role {
                    lines.append((labels.role(r), .faint))
                }
            } else {
                lines.append((a.name, .name))
            }
            if a === touched {
                // Touched by the CEO: the character says how its work is going.
                lines = [(statement(for: a), .statement)] + lines.filter { $0.1 == .name || $0.1 == .faint }
            }
            if !lines.isEmpty { items.append(LabelItem(id: a.id, anchor: a.head(above: 0.04), lines: lines)) }
            if let phone = a.phone, phone.ringing {
                items.append(LabelItem(id: "ring-\(a.id)", anchor: phone.anchor, lines: [(labels.ring, .ring)]))
            }
        }
        for page in pages where !page.text.isEmpty {
            if let top = speakerTop(page.node) {
                items.append(LabelItem(id: "page-\(page.node.id)", anchor: top + [0, 0.05, 0], lines: [(page.text, .ring)]))
            }
        }
        for node in blocks.values where node.placed {
            let o = node.entity.position(relativeTo: nil)
            let sign = sign(node)
            items.append(LabelItem(id: "block-\(node.id)", anchor: o + [Layout.blockWidth / 2, 0, 0],
                                   lines: [(sign.text, .sign)], scroll: sign.scroll))
        }
        return items
    }

    /// The top of a block's bench speaker, in world space.
    func speakerTop(_ node: BlockNode) -> SIMD3<Float>? {
        guard let s = node.speaker else { return nil }
        let b = s.visualBounds(relativeTo: nil)
        return [b.center.x, b.max.y, b.center.z]
    }

    /// The block's sign: the project's name, then the title of each running task, by desk.
    /// With no name yet (only the project's ID is known), the titles alone. When the titles are
    /// wider than `Labels.titleWidth`, `scroll` is set and the whole sign scrolls.
    func sign(_ node: BlockNode) -> (text: String, scroll: Bool) {
        guard let block = building.blocks[node.id] else { return (node.name, false) }
        let titles = block.chiefs.values
            .sorted { (node.chiefSlots[$0.sessionId] ?? .max, $0.sessionId) < (node.chiefSlots[$1.sessionId] ?? .max, $1.sessionId) }
            .compactMap { $0.ticket?.title }
            .prefix(2)
        if titles.isEmpty { return (block.name, false) }
        let head = block.name != block.projectId ? block.name : ""
        let title = titles.joined(separator: " · ")
        let text = [head, title].filter { !$0.isEmpty }.joined(separator: " · ")
        return (text, Labels.displayWidth(title) > Labels.titleWidth)
    }
}

extension CharacterEntity {
    var baseName: String? { model.name.isEmpty ? nil : model.name }
}

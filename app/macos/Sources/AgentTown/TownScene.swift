import AppKit
import RealityKit
import TownCore

/// One character on screen, with its own queue of story actions (spec: timing rules).
@MainActor
final class Actor {
    enum Kind { case ceo, dispatcher, inspector, chief }

    let id: String
    let kind: Kind
    let body: CharacterEntity
    var floor: Int
    var name: String
    var hat: String?
    var ticketText: String?
    var bubble: String?
    var model: String?
    var working = false
    var activity: String?
    private var queue: [() async -> Void] = []
    private var running = false

    init(id: String, kind: Kind, body: CharacterEntity, floor: Int, name: String) {
        self.id = id; self.kind = kind; self.body = body; self.floor = floor; self.name = name
    }

    var root: Entity { body.root }
    var spot: SIMD2<Float> { [root.position.x, root.position.z] }

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
        guard !running else { return }
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

/// The 3D building: floors, furniture, characters, and the choreography that turns
/// building changes into scenes (spec scenes 1, 2, 8, 9, 10 in Phase 2).
@MainActor
final class TownScene {
    let root = Entity()
    let labels = Labels()
    var showModelBadges = false
    var onSound: ((String) -> Void)?

    private let assets = Assets.shared
    private var floorEntities: [Int: Entity] = [:]
    private var floorNames: [Int: String] = [:]
    private var floorIndex: [String: Int] = [:] // projectId → floor
    private var deskSlots: [String: [String: Int]] = [:] // projectId → sessionId → slot
    private(set) var actors: [String: Actor] = [:]
    private let shaft = Entity()
    private var families: ModelFamilies?

    init(families: ModelFamilies? = nil) {
        self.families = families
        addLight()
        root.addChild(shaft)
        buildExecutiveFloor()
        let ceo = makeActor(id: "ceo", kind: .ceo, base: "male-d", outfit: nil, floor: 0, name: labels.ceo, at: Layout.ceoHome)
        ceo.body.play("idle")
        let dispatcher = makeActor(id: "dispatcher", kind: .dispatcher, base: "female-e", outfit: nil, floor: 0,
                                   name: labels.dispatcher, at: Layout.dispatcherHome)
        dispatcher.body.play("idle")
        let inspector = makeActor(id: "inspector", kind: .inspector, base: "male-c", outfit: nil, floor: 0,
                                  name: labels.inspector, at: Layout.inspectorHome)
        inspector.body.play("idle")
        rebuildShaft()
    }

    var floorCount: Int { floorEntities.count }

    // MARK: Changes

    func handle(_ change: Change, building: Building) {
        switch change {
        case .floorAdded(let p):
            let index = floorEntities.count
            floorIndex[p] = index
            buildProjectFloor(index: index, name: building.floors[p]?.name ?? p)
            rebuildShaft()

        case .chiefArrived(let p, let s):
            guard let f = floorIndex[p] else { return }
            if let name = building.floors[p]?.name { floorNames[f] = name }
            let slot = freeSlot(p)
            deskSlots[p, default: [:]][s] = slot
            let base = chiefBase(project: p)
            let chief = makeActor(id: s, kind: .chief, base: base, outfit: NSColor(hex: assets.characters.chiefOfStaff.color),
                                  floor: f, name: labels.chiefOfStaff, at: Layout.elevatorDoor)
            chief.root.position.x = Layout.elevatorShaftX
            chief.model = building.floors[p]?.chiefs[s]?.model
            chief.enqueue { [weak self] in
                guard let self else { return }
                await self.walk(chief, to: Layout.chiefSpot(slot: slot))
                self.face(chief, toward: [0, 1])
                chief.settle()
            }

        case .chiefLeft(let p, let s):
            guard let chief = actors[s] else { return }
            deskSlots[p]?[s] = nil
            chief.working = false
            chief.enqueue { [weak self] in
                guard let self else { return }
                await self.walk(chief, to: Layout.elevatorDoor)
                await self.move(chief, to: [Layout.elevatorShaftX, Layout.elevatorDoor.y], speed: 1)
                chief.root.removeFromParent()
                if self.actors[s] === chief { self.actors[s] = nil }
            }

        case .ticketSubmitted(let p, let s, let ticket):
            guard let chief = actors[s], let slot = deskSlots[p]?[s] else { return }
            chief.hat = nil
            switch ticket.origin {
            case "user", "schedule":
                let issuer = actors[ticket.issuer == .dispatcher ? "dispatcher" : "ceo"]!
                let home = issuer.kind == .dispatcher ? Layout.dispatcherHome : Layout.ceoHome
                issuer.enqueue { [weak self] in
                    guard let self else { return }
                    issuer.ticketText = ticket.text
                    await self.travel(issuer, floor: chief.floor, to: Layout.visitorSpot(slot: slot))
                    self.face(issuer, toward: [0, -1])
                    await self.handOver(from: issuer, to: chief)
                    issuer.ticketText = nil
                    chief.ticketText = ticket.text
                    chief.working = true
                    chief.settle()
                    await self.travel(issuer, floor: 0, to: home)
                    self.face(issuer, toward: [0, 1])
                    issuer.body.play("idle")
                }
            default:
                // A follow-up or an untraced turn: the Chief of Staff picks it up from the inbox.
                chief.enqueue {
                    chief.body.play("pick-up", loop: false)
                    try? await Task.sleep(for: .seconds(0.8))
                    chief.ticketText = ticket.text
                    chief.working = true
                }
                chief.enqueue { chief.settle() }
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
            guard let chief = actors[s], let slot = deskSlots[p]?[s] else { return }
            chief.working = false
            chief.hat = nil
            if aborted {
                // Scene 9: stop working; no report trip, no sound.
                chief.ticketText = nil
                chief.settle()
                return
            }
            let target = issuer == .dispatcher ? Layout.dispatcherHandIn : Layout.ceoHandIn
            let receiver = actors[issuer == .dispatcher ? "dispatcher" : "ceo"]!
            chief.enqueue { [weak self] in
                guard let self else { return }
                await self.travel(chief, floor: 0, to: target)
                self.face(chief, toward: [0, -1])
                await self.handOver(from: chief, to: receiver)
                chief.ticketText = nil
                if playSound { self.onSound?("completion") }
                await self.travel(chief, floor: self.floorIndex[p] ?? chief.floor, to: Layout.chiefSpot(slot: slot))
                self.face(chief, toward: [0, 1])
            }
            chief.enqueue { chief.settle() }

        case .activity(_, let s, let agentId, let kind):
            guard agentId == nil, let chief = actors[s] else { return }
            chief.activity = kind
            chief.settle()

        case .model(_, let s, let agentId, let model):
            if agentId == nil { actors[s]?.model = model }

        default:
            break // staff, operators, schedules, approvals and messages arrive in Phases 3 and 4
        }
    }

    // MARK: Motion

    private func floorY(_ f: Int) -> Float { Layout.floorY(f) + Layout.slab / 2 }

    /// Walks on the current floor along the aisle.
    private func walk(_ a: Actor, to dest: SIMD2<Float>) async {
        let start = a.spot
        var points: [SIMD2<Float>] = []
        if abs(start.x - dest.x) > 0.05 {
            if abs(start.y - Layout.aisleZ) > 0.05 { points.append([start.x, Layout.aisleZ]) }
            points.append([dest.x, Layout.aisleZ])
        }
        points.append(dest)
        for p in points { await move(a, to: p) }
    }

    private func move(_ a: Actor, to p: SIMD2<Float>, speed: Float = Layout.walkSpeed) async {
        let from = a.spot
        let d = simd_distance(from, p)
        guard d > 0.01 else { return }
        face(a, toward: p - from)
        a.body.play("walk")
        var t = a.root.transform
        t.translation = [p.x, floorY(a.floor), p.y]
        let seconds = Double(d / speed)
        a.root.move(to: t, relativeTo: a.root.parent, duration: seconds, timingFunction: .linear)
        try? await Task.sleep(for: .seconds(seconds))
    }

    /// Goes to another floor by the elevator if needed, then walks to `dest`.
    private func travel(_ a: Actor, floor: Int, to dest: SIMD2<Float>) async {
        if floor != a.floor {
            await walk(a, to: Layout.elevatorDoor)
            await move(a, to: [Layout.elevatorShaftX, Layout.elevatorDoor.y], speed: 1.2)
            a.body.play("idle")
            let seconds = Layout.rideSecondsPerFloor * Double(max(1, abs(floor - a.floor)))
            var t = a.root.transform
            t.translation.y = floorY(floor)
            a.root.move(to: t, relativeTo: a.root.parent, duration: seconds, timingFunction: .easeInOut)
            try? await Task.sleep(for: .seconds(seconds))
            a.floor = floor
            await move(a, to: Layout.elevatorDoor, speed: 1.2)
        }
        await walk(a, to: dest)
        a.body.play("idle")
    }

    private func handOver(from giver: Actor, to taker: Actor) async {
        giver.body.play("interact-right", loop: false)
        if !taker.isBusy || taker.kind != .chief { taker.body.play("interact-left", loop: false) }
        try? await Task.sleep(for: .seconds(0.9))
        giver.body.play("idle")
        if taker.kind != .chief { taker.body.play("idle") } else { taker.settle() }
    }

    private func face(_ a: Actor, toward dir: SIMD2<Float>) {
        guard simd_length(dir) > 0.001 else { return }
        a.root.orientation = simd_quatf(angle: atan2(dir.x, dir.y), axis: [0, 1, 0])
    }

    // MARK: Building

    private func makeActor(id: String, kind: Actor.Kind, base: String, outfit: NSColor?, floor: Int, name: String,
                           at spot: SIMD2<Float>) -> Actor {
        let body = (try? assets.character(base, outfit: outfit)) ?? CharacterEntity(model: Entity(), clips: [:])
        body.root.position = [spot.x, floorY(floor), spot.y]
        body.model.scale = SIMD3(repeating: Layout.characterScale)
        root.addChild(body.root)
        let a = Actor(id: id, kind: kind, body: body, floor: floor, name: name)
        face(a, toward: [0, 1])
        actors[id] = a
        return a
    }

    private func freeSlot(_ p: String) -> Int {
        let used = Set(deskSlots[p]?.values.map { $0 } ?? [])
        return (0..<16).first { !used.contains($0) } ?? 0
    }

    /// Chiefs of Staff on one floor get different base characters.
    private func chiefBase(project p: String) -> String {
        let excluded = Set(assets.characters.chiefOfStaff.exclude)
        let all = assets.characters.characters.keys.sorted().filter { !excluded.contains($0) }
        let onFloor = Set((deskSlots[p] ?? [:]).keys.compactMap { actors[$0]?.body.baseName })
        let start = abs(p.hashValue) % all.count
        for i in 0..<all.count {
            let c = all[(start + i) % all.count]
            if !onFloor.contains(c) { return c }
        }
        return all[start]
    }

    private func addLight() {
        let sun = DirectionalLight()
        sun.light.intensity = 2600
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 30, depthBias: 2)
        sun.look(at: .zero, from: [4, 10, 6], relativeTo: nil)
        root.addChild(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: .zero, from: [-6, 4, 8], relativeTo: nil)
        root.addChild(fill)
    }

    private static func box(_ size: SIMD3<Float>, _ color: NSColor, at p: SIMD3<Float>) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0.02),
                            materials: [SimpleMaterial(color: color, roughness: 0.9, isMetallic: false)])
        e.position = p
        return e
    }

    private func floorBase(index: Int, color: NSColor) -> Entity {
        let f = Entity()
        f.position = [0, Layout.floorY(index), 0]
        let w = Layout.floorWidth, d = Layout.floorDepth
        f.addChild(Self.box([w, Layout.slab, d], color, at: [w / 2, 0, d / 2]))
        let wall = NSColor(srgbRed: 0.90, green: 0.89, blue: 0.86, alpha: 1)
        f.addChild(Self.box([w, 1.8, 0.1], wall, at: [w / 2, 0.9, 0.05]))
        f.addChild(Self.box([0.1, 1.8, d], wall, at: [0.05, 0.9, d / 2]))
        root.addChild(f)
        floorEntities[index] = f
        return f
    }

    /// Places a furniture model with its footprint centered on `p` (Kenney models are anchored at a corner).
    private func place(_ name: String, in f: Entity, at p: SIMD2<Float>, yaw: Float = 0, scale: Float = 1) {
        guard let model = try? assets.furniture(name) else { return }
        // Wrap it: the model's own root transform turns the file's axes upright and must be kept.
        let e = Entity()
        e.addChild(model)
        let k = scale * Layout.furnitureScale
        e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        e.scale = [k, k, k]
        f.addChild(e)
        let b = e.visualBounds(relativeTo: f)
        e.position = [p.x - b.center.x, Layout.slab / 2 - b.min.y, p.y - b.center.z]
    }

    private func buildExecutiveFloor() {
        let f = floorBase(index: 0, color: NSColor(srgbRed: 0.62, green: 0.47, blue: 0.36, alpha: 1))
        floorNames[0] = labels.locale == "zh-TW" ? "執行樓層" : "Executive floor"
        // CEO's office.
        place("desk", in: f, at: Layout.ceoDesk)
        place("computerScreen", in: f, at: [Layout.ceoDesk.x, Layout.ceoDesk.y - 0.05], scale: 0.8)
        place("bookcaseClosedWide", in: f, at: [1.4, 0.35])
        place("pottedPlant", in: f, at: [3.6, 0.5])
        place("rugRectangle", in: f, at: [2.0, 2.4])
        // Reception and the Inspector.
        place("kitchenBar", in: f, at: [Layout.receptionDesk.x - 0.37, Layout.receptionDesk.y - 0.3])
        place("kitchenBar", in: f, at: [Layout.receptionDesk.x + 0.37, Layout.receptionDesk.y - 0.3])
        place("plantSmall1", in: f, at: [6.8, 0.6])
        // Dispatcher's room with the schedule board.
        f.addChild(Self.box([2.6, 1.0, 0.06], NSColor(srgbRed: 0.18, green: 0.32, blue: 0.26, alpha: 1),
                            at: [Layout.boardCenter.x, 0.95, 0.14]))
        place("desk", in: f, at: [Layout.dispatcherHome.x, Layout.dispatcherHome.y + 0.7])
        place("radio", in: f, at: [Layout.dispatcherHome.x + 0.35, Layout.dispatcherHome.y + 0.7])
        place("pottedPlant", in: f, at: [11.4, 0.5])
    }

    private func buildProjectFloor(index: Int, name: String) {
        let f = floorBase(index: index, color: NSColor(srgbRed: 0.83, green: 0.72, blue: 0.58, alpha: 1))
        floorNames[index] = name
        // Machine room (back left) for operators.
        f.addChild(Self.box([3.0, 0.02, 2.4], NSColor(srgbRed: 0.55, green: 0.58, blue: 0.62, alpha: 1), at: [1.6, 0.07, 1.3]))
        for i in 0..<4 { place("speaker", in: f, at: [0.6 + Float(i) * 0.6, 0.35], scale: 1.5) }
        // Chief of Staff desks.
        for slot in 0..<Layout.maxDesks {
            let x = Layout.deskX(slot: slot)
            place("desk", in: f, at: [x, Layout.deskRowZ])
            place("computerScreen", in: f, at: [x, Layout.deskRowZ - 0.05], scale: 0.8)
        }
        // Resource bench (lounge, back right).
        place("rugRound", in: f, at: [10.9, 1.3])
        place("loungeSofaLong", in: f, at: [10.9, 0.75])
        place("tableCoffee", in: f, at: [10.9, 1.75])
        place("pottedPlant", in: f, at: [11.6, 2.6])
    }

    private func rebuildShaft() {
        shaft.children.removeAll()
        let floors = max(1, floorEntities.count)
        let top = Layout.floorY(0) + 2.4
        let bottom = Layout.floorY(floors - 1) - Layout.slab
        let h = top - bottom
        var glass = PhysicallyBasedMaterial()
        glass.baseColor = .init(tint: NSColor(srgbRed: 0.55, green: 0.70, blue: 0.85, alpha: 1))
        glass.blending = .transparent(opacity: 0.25)
        let column = ModelEntity(mesh: .generateBox(size: [0.9, h, 1.1]), materials: [glass])
        column.position = [Layout.elevatorShaftX, bottom + h / 2, Layout.elevatorDoor.y]
        shaft.addChild(column)
    }

    // MARK: Labels

    struct LabelItem {
        enum Style { case name, hat, ticket, bubble, badge, sign }
        let id: String
        let anchor: SIMD3<Float>
        let lines: [(String, Style)]
    }

    func labelItems() -> [LabelItem] {
        var items: [LabelItem] = []
        for a in actors.values {
            let p = a.root.position(relativeTo: nil)
            var lines: [(String, LabelItem.Style)] = []
            if let b = a.bubble { lines.append((b, .bubble)) }
            if let h = a.hat { lines.append((h, .hat)) }
            if let t = a.ticketText { lines.append((String(t.prefix(28)) + (t.count > 28 ? "…" : ""), .ticket)) }
            if showModelBadges, let m = a.model { lines.append((families?.label(for: m) ?? m, .badge)) }
            lines.append((a.name, .name))
            items.append(LabelItem(id: a.id, anchor: p + [0, 1.1, 0], lines: lines))
        }
        for (i, name) in floorNames {
            items.append(LabelItem(id: "floor-\(i)", anchor: [0.2, Layout.floorY(i) + 2.1, 0.2], lines: [(name, .sign)]))
        }
        return items
    }
}

extension CharacterEntity {
    var baseName: String? { model.name.isEmpty ? nil : model.name }
}

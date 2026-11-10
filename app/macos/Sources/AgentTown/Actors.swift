import AppKit
import RealityKit

/// One character on screen, with its own queue of story actions (spec: timing rules).
@MainActor
final class Actor {
    enum Kind { case ceo, dispatcher, inspector, chief, worker }

    let id: String
    let kind: Kind
    let body: CharacterEntity
    let block: String
    var name: String
    var hat: String?
    var ticketText: String?
    var bubble: String?
    /// A speech bubble with no text (spec scene 16).
    var speaking = false
    var model: String?
    var working = false
    /// A desk this character is carrying, held above the head.
    var carrying: Entity?
    /// A Chief of Staff whose ticket is being worked on by staff: it waits instead of typing.
    var delegating = false
    var activity: String?
    /// The telephone (or the Dispatcher's radio) this character uses.
    var phone: Phone?
    /// True while on a call, so a second call waits for the line.
    var onCall = false
    /// Waiting for the user to approve a tool call (spec scene 6).
    var awaitingApproval = false
    /// The round shadow under the feet, kept flat on the floor.
    var shadow: Entity?

    /// Where the character settles, and which way it faces there.
    var home: SIMD2<Float>
    var homeFacing: SIMD2<Float> = [0, 1]

    // Staff and operators (kind .worker).
    /// The current role, or the last one while waiting on the bench.
    var role: String?
    /// The department whose color the character wears; nil for the neutral outfit.
    var department: String?
    var outfit: String?
    var isOperator = false
    /// The job the character is on: "a:<session>/<agentId>" or "t:<session>/<taskId>".
    var job: String?
    /// True once the character has reached its desk or console for the current job.
    var atWork = false
    var waitingSince = Date()
    var sitting = false
    /// Works at a desk with a computer (types); otherwise writes.
    var hasComputer = false
    /// When the current ticket or job started, for the status the character gives the CEO.
    var since: Date?
    /// A calm status line (white), such as "Tidying notes…".
    var note: String?
    /// Tidying its notes: the conversation is being compacted.
    var compacting = false
    /// The stack of notes on the desk while compacting.
    var papers: Entity?
    /// The CEO is walking under the user's control; scenes leave its animation alone.
    var steering = false

    private var queue: [() async -> Void] = []
    private var running = false

    init(id: String, kind: Kind, body: CharacterEntity, block: String, name: String, home: SIMD2<Float>) {
        self.id = id; self.kind = kind; self.body = body; self.block = block; self.name = name; self.home = home
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

    /// The looping clip for where the character is now (spec: activities).
    func settle() {
        guard !onCall, !steering else { return }
        if awaitingApproval {
            body.play("holding-right")
        } else if compacting {
            body.play("write") // going through the notes
        } else if working && !delegating {
            if isOperator {
                // At the racks: hands on the machines.
                body.play(activity == "shell" ? "interact-left" : "interact-right")
            } else {
                // At a desk: typing at the computer (reading on screen included), else writing.
                body.play(hasComputer ? "type-right" : "write")
            }
        } else if sitting {
            body.play("sit")
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
    /// How far above the device the ring tag sits.
    var tagLift: Float = 0.12

    init(device: Entity, handset: Entity) {
        self.device = device
        self.handset = handset
        rest = handset.transform
    }

    /// The top of the device, for the ring label.
    var anchor: SIMD3<Float> { device.position(relativeTo: nil) + [0, tagLift, 0] }

    func ring(seconds: Double) async {
        guard !ringing else { return }
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

/// One office block: the executive office, or a project's office with its desks,
/// machine room and resource bench.
@MainActor
final class BlockNode {
    let id: String
    let entity = Entity()
    var name: String
    var placed = false
    /// Phones on the Chief of Staff desks, by desk slot.
    var deskPhones: [Int: Phone] = [:]
    /// sessionId → Chief of Staff desk slot.
    var chiefSlots: [String: Int] = [:]

    /// Characters waiting on the bench, and which bench spot each one has.
    var bench: [Actor] = []
    var benchSpots: [String: Int] = [:]
    /// Characters at work: actor id → staff desk slot or console slot.
    var staffSlots: [String: Int] = [:]
    var consoleSlots: [String: Int] = [:]
    /// Job key → the character doing it.
    var jobs: [String: Actor] = [:]
    /// Jobs that ended before their character got to work: job key → status.
    var pendingDone: [String: String] = [:]
    /// Messages from characters still on their way to work: job key → replays.
    var deferred: [String: [() -> Void]] = [:]
    /// The height of each Chief of Staff desk top (block-local), by desk slot.
    var deskTops: [Int: Float] = [:]
    /// The bench's speaker, for paging.
    var speaker: Entity?
    /// Desks carried into the back row: back-row slot → the desk, with its footprint.
    var carried: [Int: (desk: Entity, footprint: (min: SIMD2<Float>, max: SIMD2<Float>))] = [:]
    /// Session → the job key of the desk worker who has the main agent's work right now.
    var activeDesk: [String: String] = [:]
    /// Staff who carry in a desk because the front desks are taken: actor id → back-row slot.
    var tempSlots: [String: Int] = [:]
    /// A back-row slot with no Chief, no desk carried in and no one bringing one.
    func freeBackSlot() -> Int? {
        (1..<Layout.maxDesks).first { b in
            !chiefSlots.values.contains(b) && !tempSlots.values.contains(b) && carried[b] == nil
        }
    }
    /// Furniture footprints (block-local x and z), which the CEO walks around.
    var obstacles: [(min: SIMD2<Float>, max: SIMD2<Float>)] = []

    init(id: String, name: String) { self.id = id; self.name = name }

    static func free(_ used: [String: Int], below limit: Int = 64) -> Int {
        let taken = Set(used.values)
        return (0..<limit).first { !taken.contains($0) } ?? limit
    }
}

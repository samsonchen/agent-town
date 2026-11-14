import AppKit
import RealityKit

/// Break time on the bench (spec: break time). When a project block has had no work for a while,
/// the characters waiting on its bench start passing the time, one now and then, each for a short
/// while: juggling, a puzzle cube, tossing a ball, looking at a phone, chatting ("• • •") or dozing
/// off ("zZZ"). As soon as the block has work again, everyone stops and is ready to be called.
/// The CEO coming to talk to someone on a break ends that break: they turn to the CEO (a dozer
/// wakes with a "!"), and turn back when the CEO leaves.
extension TownScene {
    enum Pastime: String, CaseIterable { case juggle, cube, toss, phone, chat, doze }

    /// Seconds a block must have been idle before breaks start. Default 180; `-breakIdleSeconds N`
    /// shortens it to look at the breaks in a demo.
    static var breakIdleSeconds: Double {
        let d = UserDefaults.standard
        return d.object(forKey: "breakIdleSeconds") == nil ? 180 : max(1, d.double(forKey: "breakIdleSeconds"))
    }

    /// Four times a second: the CEO's visit first, then in each block idle long enough, now and then one more bench
    /// character takes a break, up to about half the bench. A block with work stops every break.
    func startBreaks() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                self.greetCeo()
                let now = Date()
                for (p, node) in self.blocks where p != Self.executive {
                    guard node.placed, self.settled(p) else {
                        self.breakIdleSince[p] = nil
                        self.stopBreaks(node)
                        continue
                    }
                    let since = self.breakIdleSince[p] ?? now
                    self.breakIdleSince[p] = since
                    guard now.timeIntervalSince(since) >= Self.breakIdleSeconds, Double.random(in: 0..<1) < 0.05 else { continue }
                    self.startBreak(in: node)
                }
            }
        }
    }

    /// Ends every break in the block at once: the next frame each character drops its props and settles.
    func stopBreaks(_ node: BlockNode) {
        for a in node.bench where a.onBreak { a.breakEnds = .distantPast }
    }

    /// The character the CEO is next to stops its break (a chat stops for both) and faces the CEO;
    /// whoever was turned to the CEO turns back once the CEO has left.
    private func greetCeo() {
        let touched = touchedByCeo()
        if let a = touched, a.kind == .worker, let node = blocks[a.block], node.bench.contains(where: { $0 === a }) {
            if a.onBreak {
                a.greetingCeo = true
                a.breakEnds = .distantPast
                if let partner = a.chatPartner, partner.onBreak {
                    partner.greetingCeo = true
                    partner.greetsAlong = a
                    partner.breakEnds = .distantPast
                }
            } else if a.greetingCeo, let ceo {
                // Both of a chat follow the CEO while they talk.
                for g in actors.values where (g === a || g.greetsAlong === a) && g.greetingCeo && !g.isBusy {
                    face(g, toward: ceo.worldSpot - g.worldSpot)
                }
            }
        }
        for a in actors.values where a.greetingCeo && a !== touched && !a.isBusy
            && (touched == nil || a.greetsAlong !== touched)
            && blocks[a.block]?.bench.contains(where: { $0 === a }) == true {
            a.greetingCeo = false
            a.greetsAlong = nil
            face(a, toward: a.homeFacing)
            a.settle()
        }
    }

    /// At the end of a break: turned to the CEO when the CEO came to talk, else back to the bench.
    private func endBreak(_ a: Actor) {
        if a.greetingCeo, let ceo, !a.sitting {
            face(a, toward: ceo.worldSpot - a.worldSpot)
        } else {
            face(a, toward: a.homeFacing)
        }
        a.settle()
    }

    private func startBreak(in node: BlockNode) {
        let touched = touchedByCeo()
        let free = node.bench.filter { !$0.isBusy && !$0.onBreak && !$0.greetingCeo && $0 !== touched }
        let busy = node.bench.count - free.count
        // Up to all but one on break; standing characters first, so dozing seats don't use every turn.
        let standing = free.filter { !$0.sitting }
        guard busy < max(1, node.bench.count - 1),
              let a = (standing.isEmpty || Double.random(in: 0..<1) < 0.25 ? free : standing).randomElement() else { return }
        // Seated characters doze; standing ones do anything, a chat only with someone else standing free.
        var choices: [Pastime] = a.sitting ? [.doze] : Pastime.allCases
        let partner = free.filter { $0 !== a && !$0.sitting }.min { simd_distance($0.spot, a.spot) < simd_distance($1.spot, a.spot) }
        if partner == nil { choices.removeAll { $0 == .chat } }
        // `-breakPastime juggle` (or cube, toss, phone, chat, doze): standing characters do only that
        // one (seated ones still doze), to look at it in a demo.
        if !a.sitting, let only = UserDefaults.standard.string(forKey: "breakPastime").flatMap(Pastime.init(rawValue:)) {
            choices = choices.filter { $0 == only }
        }
        guard let pastime = choices.randomElement() else { return }
        let length = Double.random(in: 10...25)
        if pastime == .chat, let b = partner {
            chat(a, b, for: length)
        } else {
            takeBreak(a, pastime, for: length)
        }
    }

    /// A point in front of the character's chest, in its own space (the root is not scaled).
    private static func hands(_ y: Float = 0.2, forward: Float = 0.14) -> SIMD3<Float> {
        [0, y, forward] * (Layout.characterScale / 0.75)
    }

    private func prop(_ mesh: MeshResource, _ colors: [NSColor]) -> ModelEntity {
        ModelEntity(mesh: mesh, materials: colors.map { SimpleMaterial(color: $0, roughness: 0.6, isMetallic: false) })
    }

    private func takeBreak(_ a: Actor, _ pastime: Pastime, for length: Double) {
        a.onBreak = true
        a.breakEnds = Date().addingTimeInterval(length)
        a.enqueue { [weak self] in
            guard let self else { return }
            let k = Layout.characterScale / 0.75
            var props: [ModelEntity] = []
            switch pastime {
            // Arms down (the standing pose) for all but the cube: the arms-out holding poses with
            // something dark in the hands read as aiming.
            case .juggle:
                a.body.play("idle")
                let colors: [NSColor] = [.systemRed, .systemYellow, .systemBlue]
                props = colors.map { self.prop(.generateSphere(radius: 0.045 * k), [$0]) }
            case .cube:
                a.body.play("holding-both")
                let faces: [NSColor] = [.white, .systemYellow, .systemRed, .systemOrange, .systemBlue, .systemGreen]
                props = [self.prop(.generateBox(width: 0.11 * k, height: 0.11 * k, depth: 0.11 * k, cornerRadius: 0.008, splitFaces: true), faces)]
            case .toss:
                a.body.play("idle")
                props = [self.prop(.generateSphere(radius: 0.05 * k), [NSColor(white: 0.97, alpha: 1)])]
            case .phone:
                a.body.play("idle")
                // Upright in front of the face, its light blue screen toward the eyes.
                let phone = Self.box(SIMD3<Float>(0.07, 0.12, 0.016) * k, NSColor(hex: "#3A3F4B")!, at: .zero)
                phone.addChild(Self.box(SIMD3<Float>(0.058, 0.1, 0.002) * k, NSColor(hex: "#8FD3FF")!, at: SIMD3<Float>(0, 0, -0.009) * k))
                props = [phone]
            case .doze, .chat:
                break
            }
            for e in props { a.root.addChild(e) }
            let start = Date()
            var turn = 0
            while Date() < a.breakEnds {
                let t = Float(Date().timeIntervalSince(start))
                switch pastime {
                case .juggle:
                    // Three balls on a loop over the hands, a third of a turn apart.
                    for (i, e) in props.enumerated() {
                        let phase = t * 4.2 + Float(i) * 2 * .pi / 3
                        e.position = Self.hands(0.22, forward: 0.16) + [0.14 * k * cos(phase), 0.2 * k * (1 + sin(phase)), 0]
                    }
                case .cube:
                    props[0].position = Self.hands(0.24, forward: 0.17)
                    let step = Int(t / 0.7)
                    if step != turn { // a quarter turn about a random axis, now and then
                        turn = step
                        let axis: SIMD3<Float> = [[1, 0, 0], [0, 1, 0], [0, 0, 1]].randomElement()!
                        props[0].move(to: Transform(rotation: props[0].orientation * simd_quatf(angle: .pi / 2, axis: axis),
                                                    translation: props[0].position), relativeTo: a.root, duration: 0.25)
                    }
                case .toss:
                    let h = abs(sin(t * 2.4))
                    props[0].position = Self.hands(0.22, forward: 0.14) + [0.1 * k, 0.5 * k * h, 0]
                case .phone:
                    props[0].position = Self.hands(0.4, forward: 0.13)
                    props[0].orientation = simd_quatf(angle: -0.25, axis: [1, 0, 0]) // tipped back a little, as when reading
                case .doze:
                    a.idleBubble = ["z", "zZ", "zZZ"][Int(t / 0.8) % 3]
                case .chat:
                    break
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
            for e in props { e.removeFromParent() }
            a.idleBubble = nil
            a.onBreak = false
            self.endBreak(a)
            if pastime == .doze, a.greetingCeo {
                // Woken by the CEO: a start, shown for a moment.
                a.idleBubble = "!"
                try? await Task.sleep(for: .seconds(1.2))
                a.idleBubble = nil
            }
        }
    }

    /// Two characters turn to each other and take turns saying "• • •".
    private func chat(_ a: Actor, _ b: Actor, for length: Double) {
        let ends = Date().addingTimeInterval(length)
        a.chatPartner = b
        b.chatPartner = a
        for (me, other, first) in [(a, b, true), (b, a, false)] {
            me.onBreak = true
            me.breakEnds = ends
            me.enqueue { [weak self] in
                guard let self else { return }
                self.face(me, toward: other.spot - me.spot)
                me.body.play("idle")
                let start = Date()
                // The partner's break ending (called to work, or the CEO) ends the chat for both.
                while Date() < me.breakEnds, other.onBreak {
                    let turn = Int(Date().timeIntervalSince(start) / 1.6) % 2 == 0
                    me.speaking = turn == first
                    try? await Task.sleep(for: .milliseconds(100))
                }
                me.speaking = false
                me.onBreak = false
                me.chatPartner = nil
                if other.greetingCeo { me.greetingCeo = true } // both turn to the CEO
                self.endBreak(me)
            }
        }
    }
}

import Foundation
import TownCore

extension Change {
    /// The project a change belongs to, if any.
    var projectId: String? {
        switch self {
        case .blockAdded(let p), .blockRemoved(let p), .chiefArrived(let p, _), .chiefLeft(let p, _),
             .ticketSubmitted(let p, _, _), .hat(let p, _, _), .ticketReturned(let p, _, _),
             .ticketDone(let p, _, _, _, _, _), .staffHired(let p, _, _), .staffRole(let p, _, _, _),
             .staffDone(let p, _, _, _), .taskStarted(let p, _, _), .taskRole(let p, _, _, _),
             .taskDone(let p, _, _, _), .approvalWait(let p, _, _, _, _), .approvalEnd(let p, _, _, _),
             .activity(let p, _, _, _), .message(let p, _, _, _, _), .model(let p, _, _, _),
             .compactStarted(let p, _, _), .compactDone(let p, _, _, _, _):
            return p
        case .scheduleAdded, .scheduleRemoved:
            return nil
        }
    }
}

/// Which project blocks are on screen. The office always shows the executive block and at least
/// one project block (when any session is open), so the window keeps its size. Other blocks come
/// on screen when their work begins, with their Chiefs of Staff already at their desks, and leave
/// once their work has settled. Nobody walks in or out (spec: as few blocks as possible).
extension TownScene {
    /// How long an extra block stays on screen after its work has settled.
    static let idleGrace: TimeInterval = 1.5

    /// Work in the building state: a ticket, a compaction, staff still working, operators, or approvals.
    func hasWork(_ p: String) -> Bool {
        building.blocks[p]?.chiefs.values.contains {
            $0.ticket != nil || $0.compacting || !$0.approvals.isEmpty || !$0.operators.isEmpty || $0.staff.values.contains { !$0.done }
        } ?? false
    }

    /// No work, and no one in the block still on a call, on the way somewhere, or waiting to be called.
    private func settled(_ p: String) -> Bool {
        guard let node = blocks[p], !hasWork(p), node.jobs.isEmpty else { return false }
        if pendingCalls.values.contains(where: { $0.node === node }) { return false }
        // Bench characters play idle animations through their queues; those do not count.
        return !actors.values.contains { a in
            a.block == p && (a.onCall || (a.isBusy && !node.bench.contains { $0 === a }))
        }
    }

    /// Project blocks on screen.
    var shownProjects: [String] { blockOrder.filter { $0 != Self.executive } }

    /// A new block: on screen if it is the only project, or has work; otherwise it waits off-screen.
    func placeNewBlock(_ p: String) {
        lastWork[p] = Date()
        if shownProjects.isEmpty || hasWork(p) {
            blockOrder.append(p)
        } else {
            hidden.insert(p)
        }
        relayout()
    }

    func show(_ p: String) {
        guard hidden.remove(p) != nil else { return }
        idleSince[p] = nil
        blockOrder.append(p)
        relayout()
    }

    func hide(_ p: String) {
        guard let node = blocks[p], blockOrder.contains(p) else { return }
        blockOrder.removeAll { $0 == p }
        hidden.insert(p)
        idleSince[p] = nil
        node.entity.removeFromParent()
        node.placed = false
        relayout()
    }

    /// After a block is dropped: keep one project block on screen if any session is still open.
    func keepOneProjectShown() {
        guard shownProjects.isEmpty,
              let p = hidden.max(by: { (lastWork[$0] ?? .distantPast) < (lastWork[$1] ?? .distantPast) }) else { return }
        show(p)
    }

    /// True for characters on screen.
    func onScreen(_ a: Actor) -> Bool { !hidden.contains(a.block) }

    /// Checks twice a second for extra blocks whose work is over. The block worked in most
    /// recently stays.
    func startIdleWatch() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                let now = Date()
                var ready: [String] = []
                for p in self.shownProjects {
                    if self.settled(p) {
                        let since = self.idleSince[p] ?? now
                        self.idleSince[p] = since
                        if now.timeIntervalSince(since) >= Self.idleGrace { ready.append(p) }
                    } else {
                        self.idleSince[p] = nil
                    }
                }
                ready.sort { (self.lastWork[$0] ?? .distantPast) < (self.lastWork[$1] ?? .distantPast) }
                for p in ready where self.shownProjects.count > 1 {
                    self.hide(p)
                    self.ceoBackIfOfficeEmpty()
                }
            }
        }
    }
}

extension TownScene {
    /// Typing switches hands every so often, so it reads as typing rather than tapping.
    func startTyping() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(450))
                guard let self else { return }
                for a in self.actors.values where self.onScreen(a) && !a.isBusy && !a.onCall {
                    switch a.body.currentClip {
                    case "type-right": a.body.play("type-left", transition: 0.12)
                    case "type-left": a.body.play("type-right", transition: 0.12)
                    default: break
                    }
                }
            }
        }
    }
}

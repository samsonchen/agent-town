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
             .compactStarted(let p, _, _), .compactDone(let p, _, _, _, _), .context(let p, _):
            return p
        case .scheduleAdded, .scheduleRemoved:
            return nil
        }
    }
}

/// Project blocks. Each open project has a block from the moment its first session opens until
/// its last session ends, stacked in one column under the executive block. With Settings → "Hide
/// idle offices" on, a block is on screen only while it has work: it appears when work begins and
/// leaves once everything in it has settled for the chosen number of seconds (spec: the office).
extension TownScene {
    /// Work in the building state: a ticket, a compaction, staff still working, operators, or approvals.
    func hasWork(_ p: String) -> Bool {
        building.blocks[p]?.chiefs.values.contains {
            $0.ticket != nil || $0.compacting || !$0.approvals.isEmpty || !$0.operators.isEmpty || $0.staff.values.contains { !$0.done }
        } ?? false
    }

    /// No work, and no one in the block still on a call, on the way somewhere, or waiting to be called.
    func settled(_ p: String) -> Bool {
        guard let node = blocks[p], !hasWork(p), node.jobs.isEmpty else { return false }
        if pendingCalls.values.contains(where: { $0.node === node }) { return false }
        // Bench characters play idle animations through their queues; those do not count.
        return !actors.values.contains { a in
            a.block == p && (a.onCall || (a.isBusy && !node.bench.contains { $0 === a }))
        }
    }

    /// Project blocks on screen, top to bottom.
    var shownProjects: [String] { blockOrder.filter { $0 != Self.executive } }

    /// A new block goes under the last one, unless idle offices are hidden and it has no work yet.
    func placeNewBlock(_ p: String) {
        if Prefs.hideIdleBlocks && !hasWork(p) {
            hidden.insert(p)
        } else {
            blockOrder.append(p)
            relayout()
        }
    }

    /// Brings a hidden block back, under the others.
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

    /// Called with each change: a block with work comes on screen.
    func showIfWorking(_ change: Change) {
        if let p = change.projectId, hidden.contains(p), hasWork(p) { show(p) }
    }

    /// True for characters on screen.
    func onScreen(_ a: Actor) -> Bool { !hidden.contains(a.block) }

    /// A character on screen, for auto-scroll: its position in its block and its spot on the floor.
    struct CharacterSpot {
        let id: String
        let local: SIMD3<Float>
        let floor: SIMD2<Float>
    }

    /// Every character in a shown block. The CEO while the user walks it is left out: the view
    /// already follows the CEO then.
    func characterSpots() -> [CharacterSpot] {
        actors.values.compactMap { a in
            guard onScreen(a), !a.steering, a.root.parent != nil else { return nil }
            let w = a.root.position(relativeTo: nil)
            return CharacterSpot(id: a.id, local: a.root.position, floor: [w.x, w.z])
        }
    }

    /// Twice a second: with the setting on, hides blocks settled for long enough; with it off,
    /// brings every hidden block back. No block hides while the user has walked the CEO away from
    /// the desk, so the floor never goes or slides from under the CEO.
    func startIdleWatch() {
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                guard Prefs.hideIdleBlocks else {
                    for p in self.blockOrderOfHidden() { self.show(p) }
                    self.idleSince.removeAll()
                    continue
                }
                let now = Date(), wait = Prefs.idleHideDelay
                for p in self.shownProjects {
                    guard self.settled(p) else { self.idleSince[p] = nil; continue }
                    let since = self.idleSince[p] ?? now
                    self.idleSince[p] = since
                    if now.timeIntervalSince(since) >= wait && !self.ceoAway { self.hide(p) }
                }
            }
        }
    }

    /// Hidden blocks in the order their projects opened.
    private func blockOrderOfHidden() -> [String] {
        building.blockOrder.filter { hidden.contains($0) }
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

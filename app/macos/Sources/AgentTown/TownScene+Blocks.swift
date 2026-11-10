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

/// Project blocks. Each open project has its block on screen from the moment its first session
/// opens until its last session ends, stacked in one column under the executive block.
extension TownScene {
    /// Work in the building state: a ticket, a compaction, staff still working, operators, or approvals.
    func hasWork(_ p: String) -> Bool {
        building.blocks[p]?.chiefs.values.contains {
            $0.ticket != nil || $0.compacting || !$0.approvals.isEmpty || !$0.operators.isEmpty || $0.staff.values.contains { !$0.done }
        } ?? false
    }

    /// Project blocks on screen, top to bottom.
    var shownProjects: [String] { blockOrder.filter { $0 != Self.executive } }

    /// A new block goes under the last one.
    func placeNewBlock(_ p: String) {
        blockOrder.append(p)
        relayout()
    }

    /// True for characters on screen: every block that exists is shown.
    func onScreen(_ a: Actor) -> Bool { true }
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

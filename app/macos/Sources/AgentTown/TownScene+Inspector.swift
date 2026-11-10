import Foundation
import TownCore

/// Scene 15: a hook sends the main agent back to work. The Chief of Staff phones the report in,
/// but the Inspector at reception takes the call instead of the CEO and stops it: the Inspector
/// says why (the hook's reason, when known), a "Returned" stamp shows over the Chief of Staff,
/// and the Chief of Staff goes back to work on the same ticket. A later report that gets past the
/// Inspector goes to the issuer as usual (ticketDone).
extension TownScene {
    /// How long the stamp and the Inspector's reason stay up after the call.
    static let returnedShown: TimeInterval = 4

    func ticketReturned(_ p: String, _ s: String) {
        guard let chief = actors[s], let inspector = actors["inspector"] else { return }
        chief.working = true
        let reason = building.blocks[p]?.chiefs[s]?.ticket?.returnReason
        chief.enqueue { [weak self] in
            guard let self else { return }
            let ticket = chief.ticketText
            await self.call(from: chief, to: inspector, carrying: nil)
            chief.ticketText = ticket // still the same ticket: the note stays
            chief.bubble = self.labels.returned
            let said = reason.map { Labels.clip($0.replacingOccurrences(of: "\n", with: " "), width: 40) }
            inspector.bubble = said ?? self.labels.returned
            chief.settle()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.returnedShown))
                if chief.bubble == self.labels.returned { chief.bubble = nil }
                if inspector.bubble == (said ?? self.labels.returned) { inspector.bubble = nil }
            }
        }
    }
}

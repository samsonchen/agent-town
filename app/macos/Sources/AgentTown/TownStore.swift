import Foundation
import SwiftUI
import TownCore

/// Holds the building state on the main actor. Events arrive from the server,
/// are put in order, applied, and the resulting changes go to the choreographer.
@MainActor
final class TownStore: ObservableObject {
    @Published private(set) var building = Building()
    @Published private(set) var lastEventAt: Date?
    @Published var paused = false

    var sound: SoundSettings {
        get { building.sound }
        set { building.sound = newValue }
    }

    /// Called with each change, in order.
    var onChange: ((Change) -> Void)?

    private var sequencer = Sequencer()
    private var timer: Timer?
    private var lastExpiry = Date.distantPast
    let families: ModelFamilies

    init() {
        let url = Bundle.module.resourceURL!.appending(path: "catalog/models.json")
        families = (try? ModelFamilies(json: Data(contentsOf: url))) ?? ModelFamilies(entries: [])
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func receive(_ batch: Batch) {
        let now = Self.nowMs
        for e in batch.events { apply(sequencer.push(e, nowMs: now)) }
        lastEventAt = Date()
    }

    private func tick() {
        apply(sequencer.flush(nowMs: Self.nowMs))
        if Date().timeIntervalSince(lastExpiry) > 5 {
            lastExpiry = Date()
            emit(building.expireStale(nowMs: Self.nowMs))
        }
    }

    private func apply(_ events: [TownEvent]) {
        let now = Self.nowMs
        for e in events { emit(building.apply(e, receivedMs: now)) }
    }

    private func emit(_ changes: [Change]) {
        guard !paused else { return }
        for c in changes { onChange?(c) }
    }

    static var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

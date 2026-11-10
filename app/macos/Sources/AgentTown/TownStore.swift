import Foundation
import SwiftUI
import TownCore

/// Holds the building state on the main actor. Events arrive from the server,
/// are put in order, applied, and the resulting changes go to the choreographer.
@MainActor
final class TownStore: ObservableObject {
    @Published private(set) var building = Building()
    @Published private(set) var lastEventAt: Date?

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
        for e in events {
            log("event \(e.type) seq=\(e.seq) session=\(e.sessionId.prefix(8)) project=\(e.projectId)")
            emit(building.apply(e, receivedMs: now))
        }
    }

    private func emit(_ changes: [Change]) {
        for c in changes {
            log("change \(c)")
            onChange?(c)
        }
    }

    /// TOWN_LOG=<file>: appends what arrives and what changes, for debugging the live app.
    private static let logURL = ProcessInfo.processInfo.environment["TOWN_LOG"].map { URL(fileURLWithPath: $0) }
    private func log(_ line: String) {
        guard let url = Self.logURL else { return }
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }

    static var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

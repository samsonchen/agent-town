import AppKit
import Combine
import TownCore

/// "Hide the window when no Claude Code session is open" (spec: Hide when no session is open).
/// The office window is ordered out, not closed, a few seconds after the last session closes, so a
/// Chief walking out is seen and a `/clear` does not make it blink; it comes back, without taking
/// the focus, when a session opens. "Show agent-town" in the menu keeps meaning that the user wants
/// the window: it stays on while the window is hidden this way.
@MainActor
final class WindowPresence: ObservableObject {
    static let shared = WindowPresence()

    /// The window is hidden because no session is open.
    @Published private(set) var autoHidden = false

    /// Seconds without a session before the window hides.
    static let delay: TimeInterval = 5

    private var hasSessions = false
    private var pendingHide: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    func start(store: TownStore) {
        store.$building
            .map { $0.blocks.values.contains { !$0.chiefs.isEmpty } }
            .removeDuplicates()
            .sink { [weak self] in self?.sessionsChanged($0) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in Prefs.hidesWithoutSessions }
            .removeDuplicates()
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &subscriptions)
    }

    /// The user chose "Show agent-town": show the window now, even with no session.
    func showNow() {
        pendingHide?.cancel()
        pendingHide = nil
        autoHidden = false
        window?.orderFrontRegardless()
    }

    private func sessionsChanged(_ open: Bool) {
        hasSessions = open
        evaluate()
    }

    private func evaluate() {
        let enabled = Prefs.hidesWithoutSessions
        if !enabled || hasSessions {
            pendingHide?.cancel()
            pendingHide = nil
            if autoHidden { reveal() }
            return
        }
        guard !autoHidden, pendingHide == nil else { return }
        pendingHide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.delay))
            guard !Task.isCancelled, let self else { return }
            self.pendingHide = nil
            self.hide()
        }
    }

    /// The office window, handed over by the office view once it is in one.
    weak var window: NSWindow?

    private func hide() {
        guard Prefs.hidesWithoutSessions, !hasSessions,
              Prefs.isOn(Prefs.showWindow), let w = window, w.isVisible else { return }
        autoHidden = true
        w.orderOut(nil)
    }

    private func reveal() {
        autoHidden = false
        guard Prefs.isOn(Prefs.showWindow), let w = window else { return }
        w.orderFrontRegardless()
    }
}

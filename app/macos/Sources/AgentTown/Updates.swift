import AppKit
import Combine
import SwiftUI
import TownCore
import UserNotifications

/// Tells the user about a newer agent-town or town-link (docs/spec.md: Updates). It installs
/// nothing: Homebrew, the .dmg and Claude Code's plugin commands do that.
@MainActor final class Updater: ObservableObject {
    static let shared = Updater()

    /// The newest macOS release, once a check has found one.
    @Published private(set) var newestApp: ReleaseInfo?
    /// town-link's version on `main`, once a check has read it.
    @Published private(set) var newestPlugin: String?
    /// Open sessions whose town-link is older than `newestPlugin`.
    @Published private(set) var outdatedSessions: [OutdatedSession] = []
    @Published private(set) var checking = false
    @Published private(set) var lastCheckFailed = false
    @Published private(set) var lastChecked: Date? = UserDefaults.standard.object(forKey: Prefs.lastUpdateCheck) as? Date

    /// Opens a window by id; set by the menu bar label, which has SwiftUI's openWindow.
    var openWindow: ((String) -> Void)?

    struct OutdatedSession: Equatable, Identifiable {
        let id: String
        let project: String
        /// Nil when the session sent no version (town-link 1.0.2 or older).
        let version: String?
    }

    var appUpdate: ReleaseInfo? {
        guard let r = newestApp, UpdateFeed.isOlder(AppInfo.version, than: r.version) else { return nil }
        return r
    }

    var pluginUpdate: String? { outdatedSessions.isEmpty ? nil : newestPlugin }

    var hasUpdate: Bool { appUpdate != nil || pluginUpdate != nil }

    /// Installed with Homebrew: the cask's folder is there (Apple silicon or Intel prefix).
    static var installedWithHomebrew: Bool {
        ["/opt/homebrew/Caskroom/agent-town", "/usr/local/Caskroom/agent-town"].contains {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    static let brewCommand = "brew update && brew upgrade --cask samsonchen/agent-town/agent-town"
    static let pluginCommands = ["claude plugin marketplace update agent-town", "claude plugin update town-link@agent-town"]

    private var store: TownStore?
    private var watch: AnyCancellable?
    private var timer: Timer?

    /// Starts watching the sessions' versions and, unless `automatic` is false, checks shortly
    /// after launch and then once a day while Check for updates automatically is on.
    func start(store: TownStore, automatic: Bool) {
        self.store = store
        watch = store.$pluginVersions.sink { [weak self] versions in
            Task { @MainActor in self?.refreshSessions(versions) }
        }
        if CommandLine.arguments.contains("--fake-update") {
            // To look at the notices without a release: a made-up newer app and town-link.
            newestApp = ReleaseInfo(version: "99.0.0", tag: "v99.0.0", notes: "Made-up release notes, for --fake-update.",
                                    page: AppInfo.repository.appending(path: "releases"), download: nil)
            newestPlugin = "99.0.0"
            refreshSessions(store.pluginVersions)
            return
        }
        if CommandLine.arguments.contains("--check-now") { Task { await check() } } // a real check, also in a demo
        guard automatic else { return }
        Task {
            try? await Task.sleep(for: .seconds(10))
            if Prefs.checkForUpdates { await check() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in
                let u = Updater.shared
                guard Prefs.checkForUpdates, !u.checking else { return }
                if let last = u.lastChecked, Date().timeIntervalSince(last) < 24 * 3600 { return }
                await u.check()
            }
        }
    }

    /// Reads the newest release and town-link's version from GitHub. Sends nothing about the user.
    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        async let releases = Self.fetch(UpdateFeed.releasesURL)
        async let manifest = Self.fetch(UpdateFeed.pluginManifestURL)
        let (r, m) = await (releases, manifest)
        let app = r.flatMap { UpdateFeed.newest(fromReleases: $0, tagPrefix: "v", downloadSuffix: ".dmg") }
        let plugin = m.flatMap(UpdateFeed.pluginVersion(fromManifest:))
        if let app { newestApp = app }
        if let plugin { newestPlugin = plugin }
        lastCheckFailed = app == nil || plugin == nil
        if app != nil || plugin != nil {
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Prefs.lastUpdateCheck)
        }
        refreshSessions(store?.pluginVersions ?? [:])
        notifyIfNew()
    }

    private static func fetch(_ url: URL) async -> Data? {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("agent-town/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                NSLog("agent-town: update check: %@ answered %d", url.absoluteString, status)
                return nil
            }
            return data
        } catch {
            NSLog("agent-town: update check: %@ failed: %@", url.absoluteString, "\(error)")
            return nil
        }
    }

    private func refreshSessions(_ versions: [String: String]) {
        var list: [OutdatedSession] = []
        if let newest = newestPlugin {
            for (id, v) in versions where UpdateFeed.isOlder(v.isEmpty ? nil : v, than: newest) {
                list.append(OutdatedSession(id: id, project: store?.projectName(ofSession: id) ?? id, version: v.isEmpty ? nil : v))
            }
        }
        list.sort { ($0.project, $0.id) < ($1.project, $1.id) }
        if list != outdatedSessions { outdatedSessions = list }
        notifyIfNew()
    }

    // MARK: notifications

    /// Only the packaged app can post notifications; the build folder's executable has no bundle.
    private static var canNotify: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    /// One notification per new version of each, never repeated for the same version.
    private func notifyIfNew() {
        guard Self.canNotify else { return }
        let d = UserDefaults.standard
        if let r = appUpdate, d.string(forKey: Prefs.notifiedAppVersion) != r.version {
            d.set(r.version, forKey: Prefs.notifiedAppVersion)
            post(String(format: Labels.text("agent-town %@ is available"), r.version))
        }
        if let v = pluginUpdate, d.string(forKey: Prefs.notifiedPluginVersion) != v {
            d.set(v, forKey: Prefs.notifiedPluginVersion)
            post(String(format: Labels.text("town-link %@ is available"), v))
        }
    }

    private func post(_ title: String) {
        let center = UNUserNotificationCenter.current()
        let body = Labels.text("Click to see how to update.")
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: "update-\(title)", content: content, trigger: nil))
        }
    }

    /// Clicking a notification opens the Updates window.
    static func installNotificationHandler() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
    }

    func showWindow() {
        openWindow?("updates")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        Task { @MainActor in Updater.shared.showWindow() }
        done()
    }

    /// Shown even while agent-town is the active app.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }
}

/// The menu bar icon: the system "building.2", with a dot cut into its corner while an update is
/// available. A template image, so macOS colors it for light mode, dark mode and an open menu.
enum MenuIcon {
    static func image(dot: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let base = NSImage(systemSymbolName: "building.2", accessibilityDescription: "agent-town")?
            .withSymbolConfiguration(config) ?? NSImage()
        guard dot else {
            base.isTemplate = true
            return base
        }
        let size = NSSize(width: base.size.width + 3, height: base.size.height + 2)
        let img = NSImage(size: size, flipped: false) { rect in
            base.draw(in: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height))
            let d: CGFloat = 7
            let dotRect = NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = Labels.text("agent-town: an update is available")
        return img
    }
}

/// The Updates window: what is newer and how to update it.
struct UpdatesView: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                appSection.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            } label: { Text("agent-town").font(.headline) }
            GroupBox {
                pluginSection.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            } label: { Text("town-link").font(.headline) }
            CheckRow()
        }
        .padding(20)
        .frame(width: 520, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let r = updater.appUpdate {
                Text(String(format: Labels.text("agent-town %@ is available"), r.version)).bold()
                Text(String(format: Labels.text("You have %@."), AppInfo.version)).foregroundStyle(.secondary)
                if !r.notes.isEmpty {
                    ScrollView {
                        Text(Self.markdown(r.notes)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Link(Labels.text("View release"), destination: r.page)
                if Updater.installedWithHomebrew {
                    Text(Labels.text("Installed with Homebrew. Run:"))
                    CommandRow(command: Updater.brewCommand)
                } else {
                    HStack {
                        Button(Labels.text("Download")) { NSWorkspace.shared.open(r.download ?? r.page) }
                            .keyboardShortcut(.defaultAction)
                        Spacer()
                    }
                    Text(Labels.text("Quit agent-town, open the downloaded file and drag agent-town to Applications, replacing the old copy."))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if updater.newestApp != nil {
                Text(String(format: Labels.text("agent-town %@ is up to date."), AppInfo.version))
            } else {
                Text(String(format: Labels.text("You have %@."), AppInfo.version) + " " + Labels.text("Not checked yet."))
            }
        }
    }

    @ViewBuilder private var pluginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let v = updater.pluginUpdate {
                Text(String(format: Labels.text("town-link %@ is available"), v)).bold()
                Text(Labels.text("These sessions use an older town-link:"))
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Self.groups(updater.outdatedSessions), id: \.self) { Text("• " + $0) }
                }
                ForEach(Updater.pluginCommands, id: \.self) { CommandRow(command: $0) }
                Text(Labels.text("Then restart those Claude Code sessions: a session keeps the town-link it started with."))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let v = updater.newestPlugin {
                Text(String(format: Labels.text("town-link %@ is the newest. No open session uses an older one."), v))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Labels.text("Not checked yet."))
            }
        }
    }

    /// One line per project and version: "agent-town: 1.0.2 or older (2 sessions)".
    private static func groups(_ sessions: [Updater.OutdatedSession]) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for s in sessions {
            let line = "\(s.project): \(s.version ?? Labels.text("1.0.2 or older"))"
            if counts[line] == nil { order.append(line) }
            counts[line, default: 0] += 1
        }
        return order.map { counts[$0]! > 1 ? $0 + " " + String(format: Labels.text("(%lld sessions)"), counts[$0]!) : $0 }
    }

    private static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// A command to run in Terminal, with a Copy button.
private struct CommandRow: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
            Button(copied ? Labels.text("Copied") : Labels.text("Copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            }
        }
    }
}

/// When the last check ran, with Check now. Used in the Updates window and in Settings.
struct CheckRow: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        HStack {
            Group {
                if updater.checking {
                    Text(Labels.text("Checking…"))
                } else if updater.lastCheckFailed {
                    Text(Labels.text("The last check failed. It will try again later."))
                } else if let d = updater.lastChecked {
                    Text(String(format: Labels.text("Last checked: %@"), d.formatted(date: .abbreviated, time: .shortened)))
                } else {
                    Text(Labels.text("Not checked yet."))
                }
            }
            .foregroundStyle(.secondary)
            Spacer()
            Button(Labels.text("Check now")) { Task { await updater.check() } }
                .disabled(updater.checking)
        }
    }
}

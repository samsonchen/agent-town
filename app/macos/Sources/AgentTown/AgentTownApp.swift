import AppKit
import SwiftUI
import TownCore

/// Wires the server, the building state, the scene and the sounds together.
@MainActor
final class TownApp: ObservableObject {
    static let shared = TownApp()

    let store = TownStore()
    let scene: TownScene
    private var server: LoopbackServer?
    @Published var listeningPort: Int?

    private init() {
        scene = TownScene(families: store.families)
        scene.showModelBadges = UserDefaults.standard.bool(forKey: "showModelBadges")
        store.onChange = { [weak self] change in
            guard let self else { return }
            self.scene.handle(change, building: self.store.building)
        }
        // The menu's Sound item, each sound's switch, its choice and the volume (spec: sound settings).
        scene.onSound = { name in SoundKind(rawValue: name).map(SoundPlayer.play) }
        let thresh = UserDefaults.standard.object(forKey: Prefs.completionThreshold) as? Double ?? 0
        store.sound = SoundSettings(thresholdSeconds: Prefs.clampThreshold(thresh))
    }

    func startServer() {
        let store = self.store
        let s = LoopbackServer { batch in
            Task { @MainActor in store.receive(batch) }
        }
        do {
            try s.start()
            server = s
        } catch {
            NSLog("agent-town: could not start the server: %@", "\(error)")
        }
    }

    func stopServer() { server?.stop() }
}

@main
struct AgentTownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var town = TownApp.shared

    var body: some Scene {
        // One window: the scene's entities can be in only one RealityView at a time, so a second
        // window (⌘N, the Dock icon) would take them from the first and leave it blank.
        Window("agent-town", id: "town") {
            Group {
                if CommandLine.arguments.contains("--spike") {
                    SpikeView().frame(minWidth: 900, minHeight: 600)
                } else {
                    TownView(scene: town.scene).frame(minWidth: 640, minHeight: 480)
                }
            }
            // Closing the window hides the office; the app keeps running in the menu bar.
            .onAppear { UserDefaults.standard.set(true, forKey: Prefs.showWindow) }
            .onDisappear { if !Prefs.quitting { UserDefaults.standard.set(false, forKey: Prefs.showWindow) } }
        }
        // Room for the executive strip and one project block below it.
        .defaultSize(width: 860, height: 720)
        // Opens at launch only if it was open when the app last quit.
        .defaultLaunchBehavior(Prefs.isOn(Prefs.showWindow) ? .presented : .suppressed)
        .restorationBehavior(.disabled)

        Window(Labels.text("About agent-town"), id: "about") { AboutView() }
            .windowResizability(.contentSize)
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)

        Window(Labels.text("Updates"), id: "updates") { UpdatesView() }
            .windowResizability(.contentSize)
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)

        Window(Labels.text("Settings"), id: "settings") { SettingsView() }
            .windowResizability(.contentSize)
            .defaultLaunchBehavior(.suppressed)
            .restorationBehavior(.disabled)

        // The system "building" symbol: macOS sizes it for the menu bar and colors it for light
        // mode, dark mode and an open menu.
        MenuBarExtra {
            TownMenu()
        } label: {
            LaunchOpener()
        }
    }
}

/// The menu bar icon, with a dot while an update is available. It also opens the office window at launch when it should be open but is not:
/// started at login, the app gets no window from `defaultLaunchBehavior(.presented)`, and the user
/// had to hide and show it. The label is built at launch, unlike the menu, so it can do this.
private struct LaunchOpener: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        // With a dot while an update is available (spec: Updates).
        Image(nsImage: MenuIcon.image(dot: updater.hasUpdate))
            .task {
                let args = CommandLine.arguments
                let open = openWindow
                updater.openWindow = { open(id: $0) }
                if args.contains("--settings") { openWindow(id: "settings") } // to look at Settings
                if args.contains("--updates") { openWindow(id: "updates") } // to look at the Updates window
                guard Prefs.isOn(Prefs.showWindow), !args.contains("--demo"), !args.contains("--spike") else { return }
                // Give SwiftUI the first chance to present the window itself.
                try? await Task.sleep(for: .seconds(1.5))
                let shown = NSApp.windows.contains { $0.isVisible && $0.title == "agent-town" }
                guard !shown else { return }
                openWindow(id: "town")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }

        if let out = value("--snapshot"), !args.contains("--demo") {
            // The RealityKit test scene (Phase 0 item 19).
            let seconds = value("--seconds").flatMap(Double.init) ?? 0.5
            Task { @MainActor in
                let (world, cam) = SpikeView.makeWorld()
                do {
                    try await Snapshot.render(world: world, camera: cam, size: CGSize(width: 1200, height: 800),
                                              seconds: seconds, to: URL(fileURLWithPath: out))
                    print("snapshot written")
                } catch { print("snapshot failed: \(error)") }
                exit(0)
            }
            return
        }

        // --about-snapshot PATH: a picture of the About window, for checking its layout.
        if let out = value("--about-snapshot") {
            Task { @MainActor in
                let r = ImageRenderer(content: AboutView().background(Color(nsColor: .windowBackgroundColor)))
                r.scale = 2
                if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: out))
                    print("snapshot written")
                }
                exit(0)
            }
            return
        }

        if args.contains("--sizes") {
            Task { @MainActor in
                for n in ["desk", "chairDesk", "computerScreen", "loungeSofaLong", "kitchenBar", "speaker", "bookcaseClosedWide", "tableCoffee", "pottedPlant", "floorFull"] {
                    if let e = try? Assets.shared.furniture(n) { print(n, e.visualBounds(relativeTo: nil).extents, e.visualBounds(relativeTo: nil).center) }
                }
                if let c = try? Assets.shared.character("male-a", outfit: nil) { print("male-a", c.root.visualBounds(relativeTo: nil).extents) }
                exit(0)
            }
            return
        }

        // Update notices; a demo makes no automatic check, so a check stays quiet and offline.
        Task { @MainActor in
            Updater.shared.start(store: TownApp.shared.store, automatic: value("--demo") == nil && value("--snapshot") == nil)
        }

        if let fixture = value("--demo") {
            Task { @MainActor in
                let town = TownApp.shared
                do {
                    Demo.play(try Demo.events(from: fixture), into: town.store, speed: value("--speed").flatMap(Double.init) ?? 1)
                } catch { print("demo failed: \(error)"); exit(1) }
                if let out = value("--snapshot") {
                    let at = value("--at").flatMap(Double.init) ?? 3
                    // --size WIDTHxHEIGHT: the window size to render, 1400x900 when not given.
                    let wh = (value("--size") ?? "").split(separator: "x").compactMap { Double($0) }
                    let size = wh.count == 2 ? CGSize(width: wh[0], height: wh[1]) : CGSize(width: 1400, height: 900)
                    do {
                        try await Demo.snapshot(scene: town.scene, at: at, to: URL(fileURLWithPath: out), size: size)
                        print("snapshot written")
                    } catch { print("snapshot failed: \(error)") }
                    exit(0)
                }
            }
            if value("--snapshot") != nil { return }
        } else {
            Task { @MainActor in TownApp.shared.startServer() }
        }

        // A menu bar app: no Dock icon and not in ⌘-Tab. The window comes to the front when shown.
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { Prefs.quitting = true }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { TownApp.shared.stopServer() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

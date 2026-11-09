import AppKit
import SwiftUI

@main
struct AgentTownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("agent-town") {
            if CommandLine.arguments.contains("--spike") {
                SpikeView().frame(minWidth: 900, minHeight: 600)
            } else {
                SpikeView().frame(minWidth: 900, minHeight: 600)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            // `--snapshot out.png [--seconds N]`: render the test scene offscreen and quit.
            let seconds = args.firstIndex(of: "--seconds").flatMap { Double(args[$0 + 1]) } ?? 0.5
            Task { @MainActor in
                let (world, cam) = SpikeView.makeWorld()
                do {
                    try await Snapshot.render(world: world, camera: cam, size: CGSize(width: 1200, height: 800),
                                              seconds: seconds, to: URL(fileURLWithPath: args[i + 1]))
                    print("snapshot written")
                } catch {
                    print("snapshot failed: \(error)")
                }
                exit(0)
            }
            return
        }
        // A SwiftPM executable starts as a background process; make it a regular app with a window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

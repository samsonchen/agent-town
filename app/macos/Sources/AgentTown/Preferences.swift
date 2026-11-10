import AppKit
import SwiftUI

/// The user's choices from the menu bar and Settings, kept in UserDefaults so they survive a
/// restart of the app or the Mac.
enum Prefs {
    /// The office window is open. Default on.
    static let showWindow = "showWindow"
    /// Sounds play. Default on; each sound also has its own setting.
    static let sound = "sound"
    /// The closable tips in the office window show. Default on; closing a tip turns it off.
    static let showTips = "showTips"
    /// The UI language (`en`, `zh-Hant`); absent or empty follows macOS.
    static let language = "language"
    /// The office window's frame in screen coordinates, as NSStringFromRect writes it.
    static let windowFrame = "windowFrame"

    static func isOn(_ key: String) -> Bool {
        let d = UserDefaults.standard
        return d.object(forKey: key) == nil ? true : d.bool(forKey: key) // bool(forKey:) also reads "NO" from a launch argument
    }

    /// Set while the app quits, so the window closing then does not count as the user hiding it.
    @MainActor static var quitting = false

    /// Starts a new copy of the app and quits this one (for a new language).
    @MainActor static func relaunch() {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundle, configuration: config) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } else if let exe = Bundle.main.executableURL {
            // Run from the build folder (swift run): start the same executable again.
            let p = Process()
            p.executableURL = exe
            p.arguments = Array(CommandLine.arguments.dropFirst())
            try? p.run()
            NSApp.terminate(nil)
        }
    }
}

/// The menu bar menu: About, show the window, sound, tips, Settings and Quit.
struct TownMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Prefs.showWindow) private var showWindow = true
    @AppStorage(Prefs.sound) private var sound = true
    @AppStorage(Prefs.showTips) private var showTips = true

    var body: some View {
        Button(Labels.text("About agent-town")) {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Toggle(Labels.text("Show agent-town"), isOn: Binding(get: { showWindow }, set: { on in
            if on {
                openWindow(id: "town")
                NSApp.activate(ignoringOtherApps: true)
            } else {
                dismissWindow(id: "town")
            }
            showWindow = on
        }))
        Toggle(Labels.text("Sound"), isOn: $sound)
        Toggle(Labels.text("Show tips"), isOn: $showTips)
        Divider()
        Button(Labels.text("Settings…")) {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Divider()
        Button(Labels.text("Quit agent-town")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Settings. Language is the only one for now; more come later.
struct SettingsView: View {
    @AppStorage(Prefs.language) private var language = ""

    var body: some View {
        Form {
            Picker(Labels.text("Language"), selection: $language) {
                Text(Labels.text("System (macOS setting)")).tag("")
                Text("English").tag("en")
                Text("繁體中文").tag("zh-Hant")
            }
            // Labels are made when the app starts, so a new language needs a restart.
            if Labels.resolve(language) != Labels.language {
                HStack {
                    Text(Labels.text("Restart agent-town to use the new language."))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(Labels.text("Restart now")) { Prefs.relaunch() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

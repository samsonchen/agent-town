import AppKit
import ServiceManagement
import SwiftUI

/// The user's choices from the menu bar and Settings, kept in UserDefaults so they survive a
/// restart of the app or the Mac.
enum Prefs {
    /// The office window is open. Default on.
    static let showWindow = "showWindow"
    /// Sounds play. Default on; each sound also has its own setting.
    static let sound = "sound"
    /// The office window floats above other apps' windows. Default off.
    static let stayOnTop = "stayOnTop"
    /// The closable tips in the office window show. Default on; closing a tip turns it off.
    static let showTips = "showTips"
    /// The UI language (`en`, `zh-Hant`); absent or empty follows macOS.
    static let language = "language"
    /// The office window's frame in screen coordinates, as NSStringFromRect writes it.
    static let windowFrame = "windowFrame"
    /// The office window's opacity, 0.1 to 1. Default 1 (opaque).
    static let opacity = "opacity"
    /// agent-town's sound volume, 0 to 1. Default 1. Each sound's switch and choice are in SoundKind.
    static let soundVolume = "soundVolume"
    /// Seconds a task must take before the completion sound plays, 0 to 3600. Default 0: every task.
    static let completionThreshold = "completionThreshold"

    static let thresholdRange: ClosedRange<Double> = 0...3600

    static func clampThreshold(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(thresholdRange.upperBound, max(thresholdRange.lowerBound, v))
    }

    /// The office window never goes below 10%, so it can't vanish; hiding it is in the menu.
    static let opacityRange: ClosedRange<Double> = 0.1...1

    /// A stored opacity made safe to use: anything outside 0.1...1, or not a number, is brought in.
    static func clampOpacity(_ v: Double) -> Double {
        guard v.isFinite else { return opacityRange.upperBound }
        return min(opacityRange.upperBound, max(opacityRange.lowerBound, v))
    }

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

/// The menu bar menu: About, show the window, stay on top, sound, tips, Settings and Quit.
struct TownMenu: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Prefs.showWindow) private var showWindow = true
    @AppStorage(Prefs.stayOnTop) private var stayOnTop = false
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
        Toggle(Labels.text("Stay on top"), isOn: $stayOnTop)
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

/// Settings: Open at login, the language, the office window's opacity, and the sounds.
struct SettingsView: View {
    @AppStorage(Prefs.language) private var language = ""
    @AppStorage(Prefs.opacity) private var opacity = 1.0
    @State private var openAtLogin = LoginItem.isOn
    @State private var loginNote: String?

    var body: some View {
        Form {
            Toggle(Labels.text("Open at login"), isOn: Binding(get: { openAtLogin }, set: { on in
                loginNote = LoginItem.set(on)
                openAtLogin = LoginItem.isOn
            }))
            .disabled(!LoginItem.isAvailable)
            if let note = loginNote ?? LoginItem.note {
                Text(note).font(.callout).foregroundStyle(.secondary)
            }
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
            LabeledContent(Labels.text("Opacity")) {
                HStack {
                    Slider(value: Binding(get: { Prefs.clampOpacity(opacity) }, set: { opacity = Prefs.clampOpacity($0) }),
                           in: Prefs.opacityRange)
                        .labelsHidden()
                    Text(Prefs.clampOpacity(opacity), format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            SoundSettingsView()
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Opening agent-town when the user logs in to the Mac, as a login item macOS manages
/// (System Settings → General → Login Items). Only the packaged app can be one.
@MainActor enum LoginItem {
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var isOn: Bool {
        guard isAvailable else { return false }
        let s = SMAppService.mainApp.status
        return s == .enabled || s == .requiresApproval
    }

    /// Why the setting can't take effect, or nil.
    static var note: String? {
        if !isAvailable { return Labels.text("Available in the installed app only.") }
        if SMAppService.mainApp.status == .requiresApproval {
            return Labels.text("Allow agent-town in System Settings → General → Login Items.")
        }
        return nil
    }

    /// Turns the login item on or off; returns a message when macOS refused.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return note
        } catch {
            return String(format: Labels.text("macOS did not allow it: %@"), error.localizedDescription)
        }
    }
}

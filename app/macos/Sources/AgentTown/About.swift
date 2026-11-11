import AppKit
import SwiftUI

/// The app's version, from Info.plist in the packaged app.
enum AppInfo {
    /// Used when running from the build folder (swift run), which has no Info.plist.
    /// Keep it the same as the town-link plugin's version.
    static let fallbackVersion = "0.2.8"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? fallbackVersion
    }

    /// The build number (the commit count when release.sh built it); nil when run from the build folder.
    static var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }

    static let repository = URL(string: "https://github.com/samsonchen/agent-town")!
}

/// A third-party component the app ships with.
private struct Component: Identifiable {
    let name: String
    let author: String
    let license: String
    let url: URL
    let licenseURL: URL
    var id: String { name }
}

private let cc0 = URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!

private let components = [
    Component(name: "Mini Characters", author: "Kenney", license: "CC0 1.0",
              url: URL(string: "https://kenney.nl/assets/mini-characters-1")!, licenseURL: cc0),
    Component(name: "Furniture Kit", author: "Kenney", license: "CC0 1.0",
              url: URL(string: "https://kenney.nl/assets/furniture-kit")!, licenseURL: cc0),
]

/// A translated text whose `[words](url)` parts are links.
private func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s)) ?? AttributedString(s)
}

/// The About window: version, author, license and the third-party components.
struct AboutView: View {
    private var versionText: String {
        if let build = AppInfo.build {
            return String(format: Labels.text("Version %@ (build %@)"), AppInfo.version, build)
        }
        return String(format: Labels.text("Version %@ (development build)"), AppInfo.version)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("agent-town").font(.title2.bold())
                    Text(versionText).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }

            Text(Labels.text("Shows Claude Code's work as a small office."))

            VStack(alignment: .leading, spacing: 4) {
                Text(Labels.text("By Samson Chen"))
                Text(markdown("[github.com/samsonchen/agent-town](\(AppInfo.repository.absoluteString))"))
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(Labels.text("License")).font(.headline)
                Text(markdown(Labels.text("agent-town is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).")))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(Labels.text("Third-party components")).font(.headline)
                ForEach(components) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(markdown("[\(c.author) \(c.name)](\(c.url.absoluteString))"))
                        Text(markdown(String(format: Labels.text("3D models, license: [%@](%@)"), c.license, c.licenseURL.absoluteString)))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(Labels.text("CC0 does not require credit; we credit Kenney (kenney.nl) anyway."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

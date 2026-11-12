import Foundation

/// A version such as `1.0.10`, compared number by number (spec: Updates).
public struct VersionNumber: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    /// Nil for anything that is not dot-separated numbers.
    public init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        let nums = pieces.compactMap { Int($0) }
        guard nums.count == pieces.count else { return nil }
        parts = nums
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (a: VersionNumber, b: VersionNumber) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: VersionNumber, b: VersionNumber) -> Bool { !(a < b) && !(b < a) }
}

/// A published release of the app.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: String
    public let tag: String
    public let notes: String
    /// The release's page on GitHub.
    public let page: URL
    /// The installer to download (the macOS `.dmg`), if the release has one.
    public let download: URL?

    public init(version: String, tag: String, notes: String, page: URL, download: URL?) {
        self.version = version; self.tag = tag; self.notes = notes; self.page = page; self.download = download
    }
}

/// Reads what GitHub answers (spec: Updates).
public enum UpdateFeed {
    /// The releases of the repository, newest first by GitHub's order.
    public static let releasesURL = URL(string: "https://api.github.com/repos/samsonchen/agent-town/releases?per_page=50")!
    /// town-link's manifest on `main`: what `claude plugin update` installs.
    public static let pluginManifestURL = URL(string: "https://raw.githubusercontent.com/samsonchen/agent-town/main/plugin/.claude-plugin/plugin.json")!

    /// The highest-versioned release whose tag is `<tagPrefix><version>`, skipping drafts and
    /// pre-releases. The macOS app passes `v`, so `windows-v…` tags never match. GitHub's
    /// "Latest" flag is not used. `downloadSuffix` picks the installer among the assets.
    public static func newest(fromReleases data: Data, tagPrefix: String, downloadSuffix: String) -> ReleaseInfo? {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable {
            let tag_name: String
            let draft: Bool?
            let prerelease: Bool?
            let body: String?
            let html_url: URL
            let assets: [Asset]?
        }
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else { return nil }
        var best: (VersionNumber, ReleaseInfo)?
        for r in releases where r.draft != true && r.prerelease != true && r.tag_name.hasPrefix(tagPrefix) {
            let rest = String(r.tag_name.dropFirst(tagPrefix.count))
            guard rest.contains("."), let v = VersionNumber(rest) else { continue }
            if let b = best, !(b.0 < v) { continue }
            let dl = r.assets?.first { $0.name.lowercased().hasSuffix(downloadSuffix.lowercased()) }?.browser_download_url
            best = (v, ReleaseInfo(version: rest, tag: r.tag_name, notes: r.body ?? "", page: r.html_url, download: dl))
        }
        return best?.1
    }

    /// The `version` in a plugin.json, if it is a version number.
    public static func pluginVersion(fromManifest data: Data) -> String? {
        struct M: Decodable { let version: String? }
        guard let v = (try? JSONDecoder().decode(M.self, from: data))?.version, VersionNumber(v) != nil else { return nil }
        return v
    }

    /// Whether `running` is older than `newest`. A running version that isn't a version number
    /// (absent: town-link 1.0.2 or older) counts as older.
    public static func isOlder(_ running: String?, than newest: String) -> Bool {
        guard let n = VersionNumber(newest) else { return false }
        guard let r = running.flatMap(VersionNumber.init) else { return true }
        return r < n
    }
}

import Foundation

/// Puts each session's events in `seq` order. An event that arrives early waits
/// up to `windowMs` for the missing ones; after that it is applied anyway
/// (docs/protocol.md: receiver rules).
public struct Sequencer: Sendable {
    public let windowMs: Int64
    private var next: [String: Int] = [:]
    private var waiting: [String: [(event: TownEvent, arrived: Int64)]] = [:]

    public init(windowMs: Int64 = 500) { self.windowMs = windowMs }

    /// Accepts an event; returns the events now ready, in order.
    public mutating func push(_ e: TownEvent, nowMs: Int64) -> [TownEvent] {
        let s = e.sessionId
        guard let expected = next[s] else {
            // First event seen for a session: start from it (the app may have started late).
            next[s] = e.seq + 1
            return [e] + drain(s)
        }
        if e.seq < expected { return [e] } // late duplicate or restart: apply as it comes
        if e.seq == expected {
            next[s] = e.seq + 1
            return [e] + drain(s)
        }
        waiting[s, default: []].append((e, nowMs))
        waiting[s]!.sort { $0.event.seq < $1.event.seq }
        return []
    }

    /// Releases events that have waited longer than the window.
    public mutating func flush(nowMs: Int64) -> [TownEvent] {
        var out: [TownEvent] = []
        for s in waiting.keys.sorted() {
            guard let first = waiting[s]?.first, nowMs - first.arrived >= windowMs else { continue }
            next[s] = first.event.seq
            out += drain(s)
        }
        return out
    }

    private mutating func drain(_ s: String) -> [TownEvent] {
        var out: [TownEvent] = []
        while let first = waiting[s]?.first, first.event.seq <= next[s]! {
            waiting[s]!.removeFirst()
            out.append(first.event)
            next[s] = max(next[s]!, first.event.seq + 1)
        }
        if waiting[s]?.isEmpty == true { waiting[s] = nil }
        return out
    }
}

/// Model ID → badge label (docs/architecture.md: model families).
public struct ModelFamilies: Sendable {
    public struct Entry: Decodable, Sendable { public let match: String; public let family: String }
    private struct File: Decodable { let families: [Entry] }
    public let entries: [Entry]

    public init(entries: [Entry]) { self.entries = entries }
    public init(json: Data) throws { entries = try JSONDecoder().decode(File.self, from: json).families }

    public func label(for id: String) -> String {
        let lower = id.lowercased()
        if let e = entries.first(where: { lower.contains($0.match.lowercased()) }) { return e.family }
        var s = id
        if let r = s.range(of: "anthropic.") { s = String(s[r.upperBound...]) }
        if s.hasPrefix("claude-") { s.removeFirst("claude-".count) }
        if let r = s.range(of: #"\[[^\]]*\]$"#, options: .regularExpression) { s.removeSubrange(r) }
        if let r = s.range(of: #"-\d{8}$"#, options: .regularExpression) { s.removeSubrange(r) }
        return String(s.prefix(12))
    }
}

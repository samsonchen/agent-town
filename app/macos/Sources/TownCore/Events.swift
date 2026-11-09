import Foundation

/// A JSON value, for the event fields beyond the envelope.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
}

/// One protocol event: the envelope plus its other fields (docs/protocol.md).
public struct TownEvent: Decodable, Equatable, Sendable {
    public let type: String
    public let sessionId: String
    public let seq: Int
    public let ts: Int64
    public let projectId: String
    public let fields: [String: JSONValue]

    private static let envelopeKeys: Set<String> = ["type", "sessionId", "seq", "ts", "projectId"]

    public init(type: String, sessionId: String, seq: Int, ts: Int64, projectId: String, fields: [String: JSONValue] = [:]) {
        self.type = type; self.sessionId = sessionId; self.seq = seq; self.ts = ts; self.projectId = projectId; self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        let all = try [String: JSONValue](from: decoder)
        func str(_ k: String) throws -> String {
            guard case .string(let s)? = all[k] else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing \(k)")) }
            return s
        }
        func num(_ k: String) throws -> Double {
            guard case .number(let n)? = all[k] else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "missing \(k)")) }
            return n
        }
        type = try str("type")
        sessionId = try str("sessionId")
        seq = Int(try num("seq"))
        ts = Int64(try num("ts"))
        projectId = try str("projectId")
        fields = all.filter { !Self.envelopeKeys.contains($0.key) }
    }

    public func string(_ k: String) -> String? { if case .string(let s)? = fields[k] { return s }; return nil }
    public func int(_ k: String) -> Int64? { if case .number(let n)? = fields[k] { return Int64(n) }; return nil }
    public func bool(_ k: String) -> Bool? { if case .bool(let b)? = fields[k] { return b }; return nil }
    public func strings(_ k: String) -> [String] {
        guard case .array(let a)? = fields[k] else { return [] }
        return a.compactMap { if case .string(let s) = $0 { return s }; return nil }
    }
}

/// The body of a POST to /v1/events.
public struct Batch: Decodable, Sendable {
    public let `protocol`: Int
    public let events: [TownEvent]

    public init(protocol p: Int, events: [TownEvent]) { self.protocol = p; self.events = events }

    /// Decodes a batch. Events that do not parse are skipped, not fatal.
    public static func decode(_ data: Data) throws -> Batch {
        struct Loose: Decodable { let `protocol`: Int; let events: [Lenient] }
        struct Lenient: Decodable {
            let event: TownEvent?
            init(from decoder: Decoder) throws { event = try? TownEvent(from: decoder) }
        }
        let loose = try JSONDecoder().decode(Loose.self, from: data)
        return Batch(protocol: loose.protocol, events: loose.events.compactMap(\.event))
    }
}

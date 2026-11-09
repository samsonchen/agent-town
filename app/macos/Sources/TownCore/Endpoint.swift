import Foundation

/// The endpoint file the app writes so the plugin can find it (docs/protocol.md).
public struct EndpointFile: Codable, Equatable, Sendable {
    public let `protocol`: Int
    public let port: Int
    public let token: String
    public let pid: Int32
    public let app: String
    public let appVersion: String

    public static let protocolVersion = 1

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/agent-town/endpoint.json")
    }

    /// A fresh 32-byte random token, base64url without padding.
    public static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public init(port: Int, token: String, pid: Int32 = ProcessInfo.processInfo.processIdentifier, appVersion: String) {
        self.protocol = Self.protocolVersion
        self.port = port; self.token = token; self.pid = pid
        self.app = "agent-town"; self.appVersion = appVersion
    }

    /// Writes the file atomically with mode 0600.
    public func write(to url: URL = defaultURL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        let data = try JSONEncoder().encode(self)
        fm.createFile(atPath: tmp.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let h = try FileHandle(forWritingTo: tmp)
        try h.write(contentsOf: data)
        try h.close()
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        _ = try? fm.removeItem(at: url)
        try fm.moveItem(at: tmp, to: url)
    }

    /// Deletes the file only if it is ours (same pid), so a second app instance's file survives.
    public static func remove(at url: URL = defaultURL, pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        guard let data = try? Data(contentsOf: url),
              let f = try? JSONDecoder().decode(EndpointFile.self, from: data), f.pid == pid else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// A parsed HTTP/1.1 request, enough for POST /v1/events.
public struct HTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String] // lowercased names
    public let body: Data
}

public enum HTTPParser {
    public enum Result: Equatable { case incomplete, invalid, complete(HTTPRequest, consumed: Int) }

    /// Parses one request from the start of `data`. Bodies are limited to `maxBody` bytes.
    public static func parse(_ data: Data, maxBody: Int = 4 << 20) -> Result {
        guard let headEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 16_384 ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headEnd.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count == 3 else { return .invalid }
        var headers: [String: String] = [:]
        for l in lines {
            guard let c = l.firstIndex(of: ":") else { continue }
            headers[l[..<c].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= maxBody else { return .invalid }
        let bodyStart = headEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return .incomplete }
        let bodyEnd = data.index(bodyStart, offsetBy: length)
        let req = HTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(data[bodyStart..<bodyEnd]))
        return .complete(req, consumed: data.distance(from: data.startIndex, to: bodyEnd))
    }

    public static func response(status: Int) -> Data {
        let reason = [204: "No Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
                      405: "Method Not Allowed", 413: "Payload Too Large", 426: "Upgrade Required"][status] ?? "Error"
        return Data("HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }
}

/// The checks the server makes on each request (docs/protocol.md: responses).
public enum EventEndpoint {
    public static func handle(_ req: HTTPRequest, token: String) -> (status: Int, batch: Batch?) {
        guard req.path == "/v1/events" else { return (404, nil) }
        guard req.method == "POST" else { return (405, nil) }
        guard req.headers["authorization"] == "Bearer \(token)" else { return (401, nil) }
        guard let batch = try? Batch.decode(req.body) else { return (400, nil) }
        guard batch.protocol == EndpointFile.protocolVersion else { return (426, nil) }
        return (204, batch)
    }
}

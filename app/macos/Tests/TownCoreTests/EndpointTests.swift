import Foundation
import Testing
@testable import TownCore

private func request(_ body: String, token: String = "tok", path: String = "/v1/events", method: String = "POST") -> Data {
    Data("\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer \(token)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
}

private let goodBody = #"{"protocol":1,"events":[{"type":"heartbeat","sessionId":"s","seq":1,"ts":1,"projectId":"p"},{"type":"x"}]}"#

@Test func parsesAWholeRequestAndWaitsForAPartialOne() {
    let full = request(goodBody)
    guard case .complete(let req, let n) = HTTPParser.parse(full) else { Issue.record("not complete"); return }
    #expect(n == full.count)
    #expect(req.headers["content-type"] == "application/json")
    #expect(HTTPParser.parse(full.prefix(full.count - 3)) == .incomplete)
    #expect(HTTPParser.parse(Data("GET /\r\n\r\n".utf8)) == .invalid)
}

@Test func endpointStatuses() {
    func status(_ d: Data, token: String = "tok") -> Int {
        guard case .complete(let r, _) = HTTPParser.parse(d) else { return -1 }
        return EventEndpoint.handle(r, token: token).status
    }
    #expect(status(request(goodBody)) == 204)
    #expect(status(request(goodBody, token: "wrong")) == 401)
    #expect(status(request(goodBody, path: "/other")) == 404)
    #expect(status(request(#"{"protocol":2,"events":[]}"#)) == 426)
    #expect(status(request("not json")) == 400)
    // A malformed event is skipped, the rest is kept.
    guard case .complete(let r, _) = HTTPParser.parse(request(goodBody)) else { return }
    #expect(EventEndpoint.handle(r, token: "tok").batch?.events.count == 1)
}

@Test func endpointFileIsPrivateAndRemovedOnlyByItsOwner() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "town-\(UUID().uuidString)")
    let url = dir.appending(path: "endpoint.json")
    let f = EndpointFile(port: 4242, token: EndpointFile.newToken(), appVersion: "test")
    try f.write(to: url)
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try JSONDecoder().decode(EndpointFile.self, from: Data(contentsOf: url)) == f)
    #expect(f.token.count == 43)
    EndpointFile.remove(at: url, pid: f.pid + 1)
    #expect(FileManager.default.fileExists(atPath: url.path))
    EndpointFile.remove(at: url, pid: f.pid)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    try? FileManager.default.removeItem(at: dir)
}

import Foundation
import Testing
@testable import TownCore

/// The repository root, found from this file's path.
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

func fixture(_ name: String) throws -> [TownEvent] {
    try Batch.decode(Data(contentsOf: repoRoot.appending(path: "protocol/fixtures/\(name).json"))).events
}

/// Replays a fixture. The state is taken just before any `session.close`, so tests can read it.
func replay(_ name: String, sound: SoundSettings = SoundSettings()) throws -> (Building, [Change]) {
    var b = Building()
    b.sound = sound
    var all: [Change] = []
    for e in try fixture(name) where e.type != "session.close" { all += b.apply(e) }
    return (b, all)
}

@Test func everyFixtureDecodes() throws {
    let names = try FileManager.default.contentsOfDirectory(atPath: repoRoot.appending(path: "protocol/fixtures").path)
        .filter { $0.hasSuffix(".json") }
    #expect(names.count >= 5)
    for n in names {
        let events = try fixture(String(n.dropLast(5)))
        #expect(!events.isEmpty, "\(n)")
    }
}

@Test func basicTicket() throws {
    let (b, changes) = try replay("01-basic-ticket", sound: SoundSettings(thresholdSeconds: 5))
    #expect(b.blockOrder.count == 1)
    #expect(changes.contains { if case .blockAdded = $0 { return true }; return false })
    #expect(changes.contains { if case .hat(_, _, let t) = $0 { return !t.isEmpty }; return false })
    let done = changes.compactMap { c -> (Issuer, Bool)? in
        if case .ticketDone(_, _, _, let issuer, _, let play) = c { return (issuer, play) }; return nil
    }
    #expect(done.count == 1)
    #expect(done.first?.0 == .ceo)
    let chief = b.blocks.values.first!.chiefs.values.first!
    #expect(chief.ticket == nil)
}

@Test func staffAndApproval() throws {
    let (b, changes) = try replay("02-staff-and-approval")
    let chief = b.blocks.values.first!.chiefs.values.first!
    #expect(!chief.staff.isEmpty)
    #expect(chief.staff.values.allSatisfy { $0.role != nil })
    #expect(chief.approvals.isEmpty)
    #expect(changes.contains { if case .approvalWait = $0 { return true }; return false })
    #expect(changes.contains { if case .approvalEnd = $0 { return true }; return false })
}

@Test func taskFollowUpReportsToTheParentIssuer() throws {
    let (b, changes) = try replay("03-background-task-followup")
    let chief = b.blocks.values.first!.chiefs.values.first!
    #expect(chief.operators.isEmpty)
    #expect(changes.contains { if case .taskStarted = $0 { return true }; return false })
    let tickets = changes.compactMap { c -> Ticket? in if case .ticketSubmitted(_, _, let t) = c { return t }; return nil }
    #expect(tickets.contains { $0.origin == "task" && $0.issuer == .ceo })
}

@Test func scheduledTicketReportsToTheDispatcherAndCanBeReturned() throws {
    let (b, changes) = try replay("04-schedule-and-inspector")
    #expect(changes.contains { if case .ticketReturned = $0 { return true }; return false })
    let issuers = changes.compactMap { c -> Issuer? in if case .ticketDone(_, _, _, let i, _, _) = c { return i }; return nil }
    #expect(issuers.contains(.dispatcher))
    _ = b
}

@Test func twoProjectsAndMessages() throws {
    let (b, changes) = try replay("05-two-projects-messages")
    #expect(b.blockOrder.count == 2)
    #expect(changes.contains { if case .message = $0 { return true }; return false })
}

@Test func completionSoundRule() {
    var s = SoundSettings()
    #expect(s.thresholdSeconds == 0) // every finished task, however short
    #expect(s.playsCompletion(durationMs: 0, aborted: false))
    #expect(s.playsCompletion(durationMs: 1200, aborted: false))
    #expect(!s.playsCompletion(durationMs: 60000, aborted: true))
    s.thresholdSeconds = 5
    #expect(!s.playsCompletion(durationMs: 4999, aborted: false))
    #expect(s.playsCompletion(durationMs: 5000, aborted: false))
    s.thresholdSeconds = -3
    #expect(s.thresholdSeconds == 0)
    s.completionOn = false
    #expect(!s.playsCompletion(durationMs: 60000, aborted: false))
}

@Test func returnAfterDoneReopensTheTicket() {
    var b = Building()
    func ev(_ type: String, _ seq: Int, _ f: [String: JSONValue]) -> TownEvent {
        TownEvent(type: type, sessionId: "s", seq: seq, ts: Int64(seq), projectId: "p", fields: f)
    }
    b.apply(ev("ticket.submit", 1, ["ticketId": .string("t1"), "text": .string("x"), "origin": .string("user")]))
    b.apply(ev("ticket.done", 2, ["ticketId": .string("t1"), "durationMs": .number(10), "aborted": .bool(false)]))
    let c = b.apply(ev("ticket.return", 3, ["ticketId": .string("t1")]))
    #expect(c == [.ticketReturned(projectId: "p", sessionId: "s", ticketId: "t1")])
    #expect(b.blocks["p"]!.chiefs["s"]!.ticket?.returnedCount == 1)
}

@Test func staleSessionsLeave() {
    var b = Building()
    b.apply(TownEvent(type: "ticket.submit", sessionId: "s", seq: 1, ts: 1000, projectId: "p",
                      fields: ["ticketId": .string("t1"), "text": .string("x"), "origin": .string("user")]))
    #expect(b.expireStale(nowMs: 60_000).isEmpty)
    #expect(b.expireStale(nowMs: 200_000) == [.chiefLeft(projectId: "p", sessionId: "s"), .blockRemoved(projectId: "p")])
}

@Test func sequencerReorders() {
    var q = Sequencer(windowMs: 500)
    func e(_ n: Int) -> TownEvent { TownEvent(type: "heartbeat", sessionId: "s", seq: n, ts: 0, projectId: "p") }
    #expect(q.push(e(1), nowMs: 0).map(\.seq) == [1])
    #expect(q.push(e(3), nowMs: 10).isEmpty)
    #expect(q.push(e(2), nowMs: 20).map(\.seq) == [2, 3])
    #expect(q.push(e(5), nowMs: 30).isEmpty)
    #expect(q.flush(nowMs: 100).isEmpty)
    #expect(q.flush(nowMs: 600).map(\.seq) == [5]) // 4 never came
}

@Test func modelFamilies() throws {
    let m = try ModelFamilies(json: Data(contentsOf: repoRoot.appending(path: "catalog/models.json")))
    #expect(m.label(for: "claude-opus-5-5") == "Opus")
    #expect(m.label(for: "us.anthropic.claude-haiku-5-5-20261001-v1:0") == "Haiku")
    #expect(m.label(for: "claude-nova-2-20261001") == "nova-2")
    #expect(m.label(for: "claude-zeta-1[1m]") == "zeta-1")
}

@Test func staleUsesArrivalTimeNotSenderClock() {
    var b = Building()
    // An event stamped long ago by the sender, received now, is not stale.
    b.apply(TownEvent(type: "heartbeat", sessionId: "s", seq: 1, ts: 1000, projectId: "p"), receivedMs: 10_000_000)
    #expect(b.expireStale(nowMs: 10_060_000).isEmpty)
}

@Test func blockGoesWhenItsLastSessionCloses() throws {
    var b = Building()
    func ev(_ type: String, _ s: String, _ ts: Int64) -> TownEvent {
        try! Batch.decode(Data("""
        {"protocol":1,"events":[{"type":"\(type)","seq":\(ts),"ts":\(ts),"projectId":"p","sessionId":"\(s)","projectName":"demo","surface":"terminal","ccVersion":"2.1.318"}]}
        """.utf8)).events[0]
    }
    b.apply(ev("session.open", "a", 1))
    b.apply(ev("session.open", "b", 2))
    #expect(b.blockOrder == ["p"])
    let first = b.apply(ev("session.close", "a", 3))
    #expect(!first.contains { if case .blockRemoved = $0 { return true }; return false })
    let last = b.apply(ev("session.close", "b", 4))
    #expect(last.contains(.blockRemoved(projectId: "p")))
    #expect(b.blockOrder.isEmpty)
}

@Test func autoModeApprovalIsMarked() {
    var b = Building()
    func ev(_ type: String, _ seq: Int, _ f: [String: JSONValue]) -> TownEvent {
        TownEvent(type: type, sessionId: "s", seq: seq, ts: Int64(seq), projectId: "p", fields: f)
    }
    b.apply(ev("ticket.submit", 1, ["ticketId": .string("t1"), "text": .string("x"), "origin": .string("user")]))
    let quiet = b.apply(ev("approval.wait", 2, ["approvalId": .string("u1"), "tool": .string("Bash"), "autoMode": .bool(true)]))
    #expect(quiet == [.approvalWait(projectId: "p", sessionId: "s", approvalId: "u1", agentId: nil, autoMode: true)])
    let loud = b.apply(ev("approval.wait", 3, ["approvalId": .string("u2"), "tool": .string("Bash")]))
    #expect(loud == [.approvalWait(projectId: "p", sessionId: "s", approvalId: "u2", agentId: nil, autoMode: false)])
}

@Test func sessionOpenBringsItsBlock() {
    var b = Building()
    let c = b.apply(TownEvent(type: "session.open", sessionId: "s", seq: 1, ts: 1, projectId: "p", fields: ["projectName": .string("demo")]))
    #expect(c == [.blockAdded(projectId: "p"), .chiefArrived(projectId: "p", sessionId: "s")])
    #expect(b.blocks["p"]?.name == "demo")
}

@Test func compactionStartsAndEnds() {
    var b = Building()
    func ev(_ type: String, _ seq: Int, _ f: [String: JSONValue]) -> TownEvent {
        TownEvent(type: type, sessionId: "s", seq: seq, ts: Int64(seq), projectId: "p", fields: f)
    }
    b.apply(ev("session.open", 1, [:]))
    #expect(b.apply(ev("compact.start", 2, ["trigger": .string("manual")])) == [.compactStarted(projectId: "p", sessionId: "s", trigger: "manual")])
    #expect(b.blocks["p"]?.chiefs["s"]?.compacting == true)
    let end = b.apply(ev("compact.end", 3, ["outcome": .string("done"), "tokensBefore": .number(150_000), "tokensAfter": .number(20_000)]))
    #expect(end == [.compactDone(projectId: "p", sessionId: "s", outcome: "done", tokensBefore: 150_000, tokensAfter: 20_000)])
    #expect(b.blocks["p"]?.chiefs["s"]?.compacting == false)
    // An end with no start (the app started mid-compaction) changes nothing.
    #expect(b.apply(ev("compact.end", 4, ["outcome": .string("done")])).isEmpty)
}

@Test func contextUpdatesKeepEachField() {
    var b = Building()
    func ev(_ seq: Int, _ f: [String: JSONValue]) -> TownEvent {
        TownEvent(type: "context.update", sessionId: "s", seq: seq, ts: Int64(seq), projectId: "p", fields: f)
    }
    b.apply(ev(1, ["window": .number(200_000)]))
    b.apply(ev(2, ["effort": .string("high")]))
    #expect(b.apply(ev(3, ["tokens": .number(84_000), "percent": .number(42)])).last == .context(projectId: "p", sessionId: "s"))
    let c = b.blocks["p"]?.chiefs["s"]?.context
    #expect(c == ContextUsage(tokens: 84_000, window: 200_000, percent: 42, effort: "high"))
    #expect(c?.fraction == 0.42)
}

@Test func ticketTitleSticksToItsOwnTicket() {
    var b = Building()
    func ev(_ seq: Int, _ type: String, _ f: [String: JSONValue]) -> TownEvent {
        TownEvent(type: type, sessionId: "s", seq: seq, ts: Int64(seq), projectId: "p", fields: f)
    }
    b.apply(ev(1, "ticket.submit", ["ticketId": .string("t1"), "text": .string("Fix the sound")]))
    b.apply(ev(2, "ticket.title", ["ticketId": .string("old"), "title": .string("Stale")]))
    #expect(b.blocks["p"]?.chiefs["s"]?.ticket?.title == nil)
    b.apply(ev(3, "ticket.title", ["ticketId": .string("t1"), "title": .string("  Sound fix \n")]))
    #expect(b.blocks["p"]?.chiefs["s"]?.ticket?.title == "Sound fix")
}

@Test func contextKeepsTheLastTurnsTokens() {
    var b = Building()
    b.apply(TownEvent(type: "context.update", sessionId: "s", seq: 1, ts: 1, projectId: "p",
                      fields: ["window": .number(1_000_000), "lastTurnTokens": .number(137_500)]))
    #expect(b.blocks["p"]?.chiefs["s"]?.context.lastTurnTokens == 137_500)
}

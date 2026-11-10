import Foundation

/// Who a ticket's report goes back to (spec: "the issuer rule").
public enum Issuer: String, Sendable, Equatable { case ceo, dispatcher }

public struct Ticket: Sendable, Equatable {
    public let id: String
    public let origin: String // user, schedule, task, unknown
    public let text: String
    public let issuer: Issuer
    public var taskType: String?
    public var returnedCount = 0
}

public struct Staff: Sendable, Equatable {
    public let agentId: String
    public let parentAgentId: String?
    public let subagentType: String
    public let name: String?
    public let description: String
    public let background: Bool
    public var role: String?
    public var model: String?
    public var activity: String?
    public var done = false
}

public struct Operator: Sendable, Equatable {
    public let taskId: String
    public let kind: String
    public let agentId: String?
    public let description: String
    public let startedTicketId: String?
    public var role: String?
}

public struct Approval: Sendable, Equatable {
    public let approvalId: String
    public let agentId: String?
    public let tool: String
}

public struct Chief: Sendable, Equatable {
    public let sessionId: String
    public var model: String?
    public var ticket: Ticket?
    public var staff: [String: Staff] = [:]
    public var operators: [String: Operator] = [:]
    public var approvals: [String: Approval] = [:]
    public var activity: String?
    /// The conversation is being compacted (`/compact`, or the automatic one).
    public var compacting = false
    /// When the app last heard from this session (its own clock).
    public var lastEventTs: Int64
    /// Issuers of past tickets, so a task follow-up reports to the right place.
    public var issuers: [String: Issuer] = [:]

    /// A Chief of Staff wears the hat only while no staff are working.
    public var hat: String? {
        guard let t = ticket, staff.values.allSatisfy(\.done) else { return nil }
        return t.taskType
    }
}

public struct Block: Sendable, Equatable {
    public let projectId: String
    public var name: String
    public var chiefs: [String: Chief] = [:]
    /// Session IDs in arrival order, for stable desk placement.
    public var order: [String] = []
}

public struct Schedule: Sendable, Equatable {
    public let scheduleId: String
    public let sessionId: String
    public let projectId: String
    public let text: String
    public let recurring: Bool
    public let nextRunTs: Int64?
}

/// What changed, for the choreographer. Story changes are queued per character;
/// `activity` is not (spec: timing rules).
public enum Change: Equatable, Sendable {
    case blockAdded(projectId: String)
    /// The project's last session closed; the block goes, so the layout stays as small as possible.
    case blockRemoved(projectId: String)
    case chiefArrived(projectId: String, sessionId: String)
    case chiefLeft(projectId: String, sessionId: String)
    case ticketSubmitted(projectId: String, sessionId: String, ticket: Ticket)
    case hat(projectId: String, sessionId: String, taskType: String)
    case ticketReturned(projectId: String, sessionId: String, ticketId: String)
    case ticketDone(projectId: String, sessionId: String, ticketId: String, issuer: Issuer, aborted: Bool, playSound: Bool)
    case staffHired(projectId: String, sessionId: String, agentId: String)
    case staffRole(projectId: String, sessionId: String, agentId: String, role: String)
    case staffDone(projectId: String, sessionId: String, agentId: String, status: String)
    case taskStarted(projectId: String, sessionId: String, taskId: String)
    case taskRole(projectId: String, sessionId: String, taskId: String, role: String)
    case taskDone(projectId: String, sessionId: String, taskId: String, status: String)
    case scheduleAdded(scheduleId: String)
    case scheduleRemoved(scheduleId: String)
    /// `autoMode`: the session is in auto mode, where a classifier answers most asks; no sound.
    case approvalWait(projectId: String, sessionId: String, approvalId: String, agentId: String?, autoMode: Bool)
    case approvalEnd(projectId: String, sessionId: String, approvalId: String, agentId: String?)
    case activity(projectId: String, sessionId: String, agentId: String?, kind: String)
    case message(projectId: String, sessionId: String, from: String?, to: String?, broadcast: Bool)
    case model(projectId: String, sessionId: String, agentId: String?, model: String)
    /// The main conversation's compaction began; `trigger` is manual, auto or other.
    case compactStarted(projectId: String, sessionId: String, trigger: String)
    /// It ended: `outcome` is done, skipped or failed; the sizes in tokens when known.
    case compactDone(projectId: String, sessionId: String, outcome: String, tokensBefore: Int64?, tokensAfter: Int64?)
}

public struct SoundSettings: Sendable, Equatable {
    public var completionOn = true
    /// Seconds; never below 5 (spec: sounds).
    /// Seconds a task must take before its completion sound plays. 0 (the default): every task.
    public var thresholdSeconds: Double = 0 { didSet { thresholdSeconds = max(0, thresholdSeconds) } }
    public init(completionOn: Bool = true, thresholdSeconds: Double = 0) {
        self.completionOn = completionOn
        self.thresholdSeconds = max(0, thresholdSeconds)
    }

    public func playsCompletion(durationMs: Int64, aborted: Bool) -> Bool {
        completionOn && !aborted && Double(durationMs) >= thresholdSeconds * 1000
    }
}

/// The building, updated from protocol events only (docs/architecture.md: Building state).
public struct Building: Sendable {
    public private(set) var blocks: [String: Block] = [:]
    public private(set) var blockOrder: [String] = []
    public private(set) var schedules: [String: Schedule] = [:]
    public var sound = SoundSettings()
    public init() {}

    /// Applies one event and returns what changed. Unknown types are ignored.
    /// `receivedMs` is the app's clock when the event arrived; stale-session checks use it,
    /// since the sender's clock (`ts`) may differ. Defaults to `ts`.
    @discardableResult
    public mutating func apply(_ e: TownEvent, receivedMs: Int64? = nil) -> [Change] {
        let seen = receivedMs ?? e.ts
        var out: [Change] = []
        let p = e.projectId, s = e.sessionId

        if e.type == "session.close" {
            return closeSession(projectId: p, sessionId: s)
        }

        // Any event creates the block and the session (the app may start after the session).
        // Whether a block is on screen is the scene's choice (TownScene+Blocks).
        if blocks[p] == nil {
            blocks[p] = Block(projectId: p, name: e.string("projectName") ?? p)
            blockOrder.append(p)
            out.append(.blockAdded(projectId: p))
        }
        if blocks[p]!.chiefs[s] == nil {
            blocks[p]!.chiefs[s] = Chief(sessionId: s, model: e.string("model"), lastEventTs: seen)
            blocks[p]!.order.append(s)
            out.append(.chiefArrived(projectId: p, sessionId: s))
        }
        if let name = e.string("projectName"), e.type == "session.open" { blocks[p]!.name = name }

        var c = blocks[p]!.chiefs[s]!
        c.lastEventTs = max(c.lastEventTs, seen)

        switch e.type {
        case "ticket.submit":
            let origin = e.string("origin") ?? "user"
            let issuer: Issuer
            switch origin {
            case "schedule": issuer = .dispatcher
            case "task": issuer = e.string("parentTicketId").flatMap { c.issuers[$0] } ?? .ceo
            default: issuer = .ceo
            }
            let t = Ticket(id: e.string("ticketId") ?? "?", origin: origin, text: e.string("text") ?? "", issuer: issuer)
            c.ticket = t
            c.issuers[t.id] = issuer
            out.append(.ticketSubmitted(projectId: p, sessionId: s, ticket: t))
            if origin == "schedule", let sid = e.string("scheduleId"), schedules[sid]?.recurring == false {
                schedules[sid] = nil
                out.append(.scheduleRemoved(scheduleId: sid))
            }

        case "chief.hat":
            if let tt = e.string("taskType"), c.ticket?.id == e.string("ticketId") {
                c.ticket?.taskType = tt
                out.append(.hat(projectId: p, sessionId: s, taskType: tt))
            }

        case "ticket.return":
            let id = e.string("ticketId") ?? ""
            if c.ticket?.id == id {
                c.ticket?.returnedCount += 1
                out.append(.ticketReturned(projectId: p, sessionId: s, ticketId: id))
            } else if let issuer = c.issuers[id] {
                // ticket.done already arrived: reopen it.
                var t = Ticket(id: id, origin: "unknown", text: "", issuer: issuer)
                t.returnedCount = 1
                c.ticket = t
                out.append(.ticketReturned(projectId: p, sessionId: s, ticketId: id))
            }

        case "ticket.done":
            let id = e.string("ticketId") ?? ""
            let aborted = e.bool("aborted") ?? false
            let issuer = c.issuers[id] ?? c.ticket?.issuer ?? .ceo
            let play = sound.playsCompletion(durationMs: e.int("durationMs") ?? 0, aborted: aborted)
            if c.ticket?.id == id { c.ticket = nil }
            c.activity = nil
            out.append(.ticketDone(projectId: p, sessionId: s, ticketId: id, issuer: issuer, aborted: aborted, playSound: play))

        case "staff.hire":
            guard let id = e.string("agentId") else { break }
            c.staff[id] = Staff(agentId: id, parentAgentId: e.string("parentAgentId"),
                                subagentType: e.string("subagentType") ?? "general-purpose", name: e.string("name"),
                                description: e.string("description") ?? "", background: e.bool("background") ?? false,
                                model: e.string("model") ?? e.string("parentAgentId").flatMap { c.staff[$0]?.model } ?? c.model)
            out.append(.staffHired(projectId: p, sessionId: s, agentId: id))

        case "staff.role":
            if let id = e.string("agentId"), let role = e.string("role"), c.staff[id] != nil {
                c.staff[id]!.role = role
                out.append(.staffRole(projectId: p, sessionId: s, agentId: id, role: role))
            }

        case "staff.done":
            if let id = e.string("agentId"), c.staff[id] != nil {
                c.staff[id]!.done = true
                c.staff[id]!.activity = nil
                out.append(.staffDone(projectId: p, sessionId: s, agentId: id, status: e.string("status") ?? "completed"))
            }

        case "task.start":
            guard let id = e.string("taskId") else { break }
            c.operators[id] = Operator(taskId: id, kind: e.string("kind") ?? "other", agentId: e.string("agentId"),
                                       description: e.string("description") ?? "", startedTicketId: e.string("ticketId"),
                                       role: e.string("role"))
            out.append(.taskStarted(projectId: p, sessionId: s, taskId: id))
            if let r = e.string("role") { out.append(.taskRole(projectId: p, sessionId: s, taskId: id, role: r)) }

        case "task.role":
            if let id = e.string("taskId"), let role = e.string("role"), c.operators[id] != nil {
                c.operators[id]!.role = role
                out.append(.taskRole(projectId: p, sessionId: s, taskId: id, role: role))
            }

        case "task.done":
            if let id = e.string("taskId"), c.operators[id] != nil {
                c.operators[id] = nil
                out.append(.taskDone(projectId: p, sessionId: s, taskId: id, status: e.string("status") ?? "completed"))
            }

        case "schedule.create":
            if let id = e.string("scheduleId") {
                schedules[id] = Schedule(scheduleId: id, sessionId: s, projectId: p, text: e.string("text") ?? "",
                                         recurring: e.bool("recurring") ?? true, nextRunTs: e.int("nextRunTs"))
                out.append(.scheduleAdded(scheduleId: id))
            }

        case "schedule.delete":
            if let id = e.string("scheduleId"), schedules.removeValue(forKey: id) != nil {
                out.append(.scheduleRemoved(scheduleId: id))
            }

        case "approval.wait":
            if let id = e.string("approvalId") {
                let a = Approval(approvalId: id, agentId: e.string("agentId"), tool: e.string("tool") ?? "")
                c.approvals[id] = a
                out.append(.approvalWait(projectId: p, sessionId: s, approvalId: id, agentId: a.agentId,
                                         autoMode: e.bool("autoMode") ?? false))
            }

        case "approval.end":
            if let id = e.string("approvalId"), let a = c.approvals.removeValue(forKey: id) {
                out.append(.approvalEnd(projectId: p, sessionId: s, approvalId: id, agentId: a.agentId))
            }

        case "activity":
            let kind = e.string("kind") ?? "other"
            if let id = e.string("agentId") {
                if c.staff[id] != nil { c.staff[id]!.activity = kind }
            } else {
                c.activity = kind
            }
            out.append(.activity(projectId: p, sessionId: s, agentId: e.string("agentId"), kind: kind))

        case "message.send":
            var to = e.string("toAgentId")
            if to == nil, let name = e.string("toName") {
                to = c.staff.values.first { $0.name == name }?.agentId
            }
            out.append(.message(projectId: p, sessionId: s, from: e.string("fromAgentId"), to: to,
                                broadcast: e.bool("broadcast") ?? false))

        case "model.update":
            guard let m = e.string("model") else { break }
            if let id = e.string("agentId") {
                if c.staff[id] != nil { c.staff[id]!.model = m }
            } else {
                c.model = m
            }
            out.append(.model(projectId: p, sessionId: s, agentId: e.string("agentId"), model: m))

        case "compact.start":
            c.compacting = true
            out.append(.compactStarted(projectId: p, sessionId: s, trigger: e.string("trigger") ?? "other"))

        case "compact.end":
            guard c.compacting else { break }
            c.compacting = false
            out.append(.compactDone(projectId: p, sessionId: s, outcome: e.string("outcome") ?? "done",
                                    tokensBefore: e.int("tokensBefore"), tokensAfter: e.int("tokensAfter")))

        default:
            break // session.open, heartbeat, unknown types
        }

        blocks[p]!.chiefs[s] = c
        return out
    }

    private mutating func closeSession(projectId p: String, sessionId s: String) -> [Change] {
        guard blocks[p]?.chiefs[s] != nil else { return [] }
        blocks[p]!.chiefs[s] = nil
        blocks[p]!.order.removeAll { $0 == s }
        var out: [Change] = [.chiefLeft(projectId: p, sessionId: s)]
        for (id, sch) in schedules where sch.sessionId == s {
            schedules[id] = nil
            out.append(.scheduleRemoved(scheduleId: id))
        }
        if blocks[p]!.chiefs.isEmpty {
            blocks[p] = nil
            blockOrder.removeAll { $0 == p }
            out.append(.blockRemoved(projectId: p))
        }
        return out
    }

    /// Closes sessions with no event for `staleAfterMs` (spec scene 10; architecture: stale sessions).
    public mutating func expireStale(nowMs: Int64, staleAfterMs: Int64 = 120_000) -> [Change] {
        var out: [Change] = []
        for (p, f) in blocks {
            for (s, c) in f.chiefs where nowMs - c.lastEventTs > staleAfterMs {
                out += closeSession(projectId: p, sessionId: s)
            }
        }
        return out
    }
}

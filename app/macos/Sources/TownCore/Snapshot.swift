import Foundation

/// A language-neutral picture of the building state (protocol/fixtures/expected/README.md).
/// Any app that reads the protocol must reach the same state from the same events, so this holds
/// only what such an app must agree on: no Swift internals, no animation, no clock-based fields.
extension Building {
    public func snapshot() -> [String: Any] {
        func put(_ d: inout [String: Any], _ k: String, _ v: Any?) { if let v { d[k] = v } }

        let blocks: [[String: Any]] = blockOrder.compactMap { id in
            guard let b = self.blocks[id] else { return nil }
            let sessions: [[String: Any]] = b.order.compactMap { s in
                guard let c = b.chiefs[s] else { return nil }
                var d: [String: Any] = ["sessionId": s, "compacting": c.compacting]
                put(&d, "model", c.model)
                put(&d, "activity", c.activity)
                put(&d, "hat", c.hat)
                if let t = c.ticket {
                    var td: [String: Any] = ["ticketId": t.id, "origin": t.origin, "issuer": t.issuer.rawValue,
                                             "text": t.text, "returnedCount": t.returnedCount]
                    put(&td, "taskType", t.taskType)
                    put(&td, "title", t.title)
                    put(&td, "returnReason", t.returnReason)
                    put(&td, "messageKind", t.messageKind)
                    put(&td, "fromAgentId", t.fromAgentId)
                    d["ticket"] = td
                }
                d["staff"] = c.staff.values.sorted { $0.agentId < $1.agentId }.map { st -> [String: Any] in
                    var x: [String: Any] = ["agentId": st.agentId, "subagentType": st.subagentType,
                                            "background": st.background, "done": st.done]
                    put(&x, "parentAgentId", st.parentAgentId)
                    put(&x, "role", st.role)
                    put(&x, "model", st.model)
                    put(&x, "activity", st.activity)
                    return x
                }
                d["operators"] = c.operators.values.sorted { $0.taskId < $1.taskId }.map { o -> [String: Any] in
                    var x: [String: Any] = ["taskId": o.taskId, "kind": o.kind]
                    put(&x, "agentId", o.agentId)
                    put(&x, "role", o.role)
                    put(&x, "startedTicketId", o.startedTicketId)
                    return x
                }
                d["approvals"] = c.approvals.values.sorted { $0.approvalId < $1.approvalId }.map { a -> [String: Any] in
                    var x: [String: Any] = ["approvalId": a.approvalId, "tool": a.tool]
                    put(&x, "agentId", a.agentId)
                    return x
                }
                var ctx: [String: Any] = [:]
                put(&ctx, "tokens", c.context.tokens)
                put(&ctx, "window", c.context.window)
                put(&ctx, "percent", c.context.percent)
                put(&ctx, "effort", c.context.effort)
                put(&ctx, "lastTurnTokens", c.context.lastTurnTokens)
                if !ctx.isEmpty { d["context"] = ctx }
                return d
            }
            return ["projectId": b.projectId, "name": b.name, "sessions": sessions]
        }
        let schedules: [[String: Any]] = self.schedules.values.sorted { $0.scheduleId < $1.scheduleId }.map { s in
            var x: [String: Any] = ["scheduleId": s.scheduleId, "sessionId": s.sessionId, "projectId": s.projectId,
                                    "text": s.text, "recurring": s.recurring]
            put(&x, "nextRunTs", s.nextRunTs)
            return x
        }
        return ["blocks": blocks, "schedules": schedules]
    }

    /// The expected-state file for a fixture: the state after each event that changes it.
    public static func expectedStates(for events: [TownEvent]) -> [[String: Any]] {
        var b = Building()
        var out: [[String: Any]] = []
        var last: Data?
        for (i, e) in events.enumerated() {
            b.apply(e)
            let state = b.snapshot()
            let data = canonicalJSON(state)
            guard data != last else { continue }
            last = data
            out.append(["after": i, "type": e.type, "state": state])
        }
        return out
    }

    /// Sorted keys and two-space indentation, so the files diff cleanly.
    public static func canonicalJSON(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])) ?? Data()
    }
}

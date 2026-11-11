class_name Building
extends RefCounted
## The building, updated from protocol events only (docs/architecture.md: Building state).
## Port of app/macos/Sources/TownCore/Building.swift and Snapshot.swift. Both apps must reach the
## same state from the same events; protocol/fixtures/expected/ holds the answers.
## Optional values are null when unknown.

const CEO := "ceo"
const DISPATCHER := "dispatcher"


class Ticket:
	var id: String
	var origin: String ## user, schedule, task, unknown
	var text: String
	var issuer: String ## CEO or DISPATCHER: who the report goes back to
	var task_type: Variant = null
	var title: Variant = null ## a few words naming the task, from a small model
	var returned_count: int = 0
	var return_reason: Variant = null ## the hook's reason for the last return
	var message_kind: Variant = null ## report or message, for a turn that starts with another agent's message
	var from_agent_id: Variant = null

	func _init(p_id: String, p_origin: String, p_text: String, p_issuer: String) -> void:
		id = p_id
		origin = p_origin
		text = p_text
		issuer = p_issuer


class Staff:
	var agent_id: String
	var parent_agent_id: Variant = null
	var subagent_type: String
	var name: Variant = null
	var description: String
	var background: bool
	var role: Variant = null
	var model: Variant = null
	var activity: Variant = null
	var done: bool = false


class Operator:
	var task_id: String
	var kind: String
	var agent_id: Variant = null
	var description: String
	var started_ticket_id: Variant = null
	var role: Variant = null


class Approval:
	var approval_id: String
	var agent_id: Variant = null
	var tool: String


## The main conversation's context window (protocol: context.update). Each field keeps its last value.
class ContextUsage:
	var tokens: Variant = null
	var window: Variant = null
	var percent: Variant = null
	var effort: Variant = null
	var last_turn_tokens: Variant = null

	## How full the window is, 0 to 1, when known.
	func fraction() -> Variant:
		if percent != null:
			return clampf(float(percent) / 100.0, 0.0, 1.0)
		if tokens != null and window != null and int(window) > 0:
			return minf(1.0, float(tokens) / float(window))
		return null


class Chief:
	var session_id: String
	var model: Variant = null
	var ticket: Ticket = null
	var staff: Dictionary = {} ## agent_id -> Staff
	var operators: Dictionary = {} ## task_id -> Operator
	var approvals: Dictionary = {} ## approval_id -> Approval
	var activity: Variant = null
	var context := ContextUsage.new()
	var compacting: bool = false ## the conversation is being compacted
	var last_event_ts: int ## when the app last heard from this session (its own clock)
	var issuers: Dictionary = {} ## ticket_id -> issuer of past tickets, so a task follow-up reports to the right place

	## A Chief of Staff wears the hat only while no staff are working.
	func hat() -> Variant:
		if ticket == null:
			return null
		for st: Staff in staff.values():
			if not st.done:
				return null
		return ticket.task_type


class Block:
	var project_id: String
	var name: String
	var chiefs: Dictionary = {} ## session_id -> Chief
	var order: Array[String] = [] ## session IDs in arrival order, for stable desk placement


class Schedule:
	var schedule_id: String
	var session_id: String
	var project_id: String
	var text: String
	var recurring: bool
	var next_run_ts: Variant = null


## Whether the completion sound plays for a finished ticket (spec: sounds).
class SoundSettings:
	var completion_on: bool = true
	var threshold_seconds: float = 0.0: ## seconds a task must take; 0 means every task
		set(v):
			threshold_seconds = maxf(0.0, v)

	func plays_completion(duration_ms: int, aborted: bool) -> bool:
		return completion_on and not aborted and float(duration_ms) >= threshold_seconds * 1000.0


var blocks: Dictionary = {} ## project_id -> Block
var block_order: Array[String] = []
var schedules: Dictionary = {} ## schedule_id -> Schedule
var sound := SoundSettings.new()


## Applies one event and returns what changed, for the choreographer: an Array of Dictionaries,
## each with a "kind" (the Swift `Change` case name) and its values. Unknown types are ignored.
## `received_ms` is the app's clock when the event arrived (stale-session checks use it); -1 means `ts`.
func apply(e: TownEvent, received_ms: int = -1) -> Array[Dictionary]:
	var seen := e.ts if received_ms < 0 else received_ms
	var out: Array[Dictionary] = []
	var p := e.project_id
	var s := e.session_id

	if e.type == "session.close":
		return _close_session(p, s)

	# Any event creates the block and the session (the app may start after the session).
	if not blocks.has(p):
		var b := Block.new()
		b.project_id = p
		b.name = e.string("projectName") if e.string("projectName") != null else p
		blocks[p] = b
		block_order.append(p)
		out.append({"kind": "blockAdded", "projectId": p})
	var block: Block = blocks[p]
	if not block.chiefs.has(s):
		var nc := Chief.new()
		nc.session_id = s
		nc.model = e.string("model")
		nc.last_event_ts = seen
		block.chiefs[s] = nc
		block.order.append(s)
		out.append({"kind": "chiefArrived", "projectId": p, "sessionId": s})
	if e.type == "session.open" and e.string("projectName") != null:
		block.name = e.string("projectName")

	var c: Chief = block.chiefs[s]
	c.last_event_ts = maxi(c.last_event_ts, seen)

	match e.type:
		"ticket.submit":
			var origin: String = e.string("origin") if e.string("origin") != null else "user"
			var issuer := CEO
			if origin == "schedule":
				issuer = DISPATCHER
			elif origin == "task":
				var parent: Variant = e.string("parentTicketId")
				if parent != null and c.issuers.has(parent):
					issuer = c.issuers[parent]
			var t := Ticket.new(_or(e.string("ticketId"), "?"), origin, _or(e.string("text"), ""), issuer)
			t.message_kind = e.string("messageKind")
			t.from_agent_id = e.string("fromAgentId")
			c.ticket = t
			c.issuers[t.id] = issuer
			out.append({"kind": "ticketSubmitted", "projectId": p, "sessionId": s, "ticket": t})
			var sid: Variant = e.string("scheduleId")
			if origin == "schedule" and sid != null and schedules.has(sid) and not (schedules[sid] as Schedule).recurring:
				schedules.erase(sid)
				out.append({"kind": "scheduleRemoved", "scheduleId": sid})

		"chief.hat":
			var tt: Variant = e.string("taskType")
			if tt != null and c.ticket != null and c.ticket.id == e.string("ticketId"):
				c.ticket.task_type = tt
				out.append({"kind": "hat", "projectId": p, "sessionId": s, "taskType": tt})

		"ticket.title":
			var raw: Variant = e.string("title")
			if raw != null:
				var title: String = (raw as String).strip_edges()
				if not title.is_empty() and c.ticket != null and c.ticket.id == e.string("ticketId"):
					c.ticket.title = title.substr(0, 60)

		"ticket.return":
			var id: String = _or(e.string("ticketId"), "")
			var reason: Variant = e.string("reason")
			if c.ticket != null and c.ticket.id == id:
				c.ticket.returned_count += 1
				c.ticket.return_reason = reason
				out.append({"kind": "ticketReturned", "projectId": p, "sessionId": s, "ticketId": id})
			elif c.issuers.has(id):
				# ticket.done already arrived: reopen it.
				var t := Ticket.new(id, "unknown", "", c.issuers[id])
				t.returned_count = 1
				t.return_reason = reason
				c.ticket = t
				out.append({"kind": "ticketReturned", "projectId": p, "sessionId": s, "ticketId": id})

		"ticket.done":
			var id: String = _or(e.string("ticketId"), "")
			var aborted: bool = _or(e.boolean("aborted"), false)
			var issuer: String = CEO
			if c.issuers.has(id):
				issuer = c.issuers[id]
			elif c.ticket != null:
				issuer = c.ticket.issuer
			var play := sound.plays_completion(_or(e.number("durationMs"), 0), aborted)
			if c.ticket != null and c.ticket.id == id:
				c.ticket = null
			c.activity = null
			out.append({"kind": "ticketDone", "projectId": p, "sessionId": s, "ticketId": id, "issuer": issuer,
				"aborted": aborted, "playSound": play})

		"staff.hire":
			var id: Variant = e.string("agentId")
			if id != null:
				var st := Staff.new()
				st.agent_id = id
				st.parent_agent_id = e.string("parentAgentId")
				st.subagent_type = _or(e.string("subagentType"), "general-purpose")
				st.name = e.string("name")
				st.description = _or(e.string("description"), "")
				st.background = _or(e.boolean("background"), false)
				# The model it runs on, else its parent's (a staff member's, or the Chief of Staff's).
				st.model = e.string("model")
				if st.model == null and st.parent_agent_id != null and c.staff.has(st.parent_agent_id):
					st.model = (c.staff[st.parent_agent_id] as Staff).model
				if st.model == null:
					st.model = c.model
				c.staff[id] = st
				out.append({"kind": "staffHired", "projectId": p, "sessionId": s, "agentId": id})

		"staff.role":
			var id: Variant = e.string("agentId")
			var role: Variant = e.string("role")
			if id != null and role != null and c.staff.has(id):
				(c.staff[id] as Staff).role = role
				out.append({"kind": "staffRole", "projectId": p, "sessionId": s, "agentId": id, "role": role})

		"staff.done":
			var id: Variant = e.string("agentId")
			if id != null and c.staff.has(id):
				var st: Staff = c.staff[id]
				st.done = true
				st.activity = null
				out.append({"kind": "staffDone", "projectId": p, "sessionId": s, "agentId": id,
					"status": _or(e.string("status"), "completed")})

		"task.start":
			var id: Variant = e.string("taskId")
			if id != null:
				var o := Operator.new()
				o.task_id = id
				o.kind = _or(e.string("kind"), "other")
				o.agent_id = e.string("agentId")
				o.description = _or(e.string("description"), "")
				o.started_ticket_id = e.string("ticketId")
				o.role = e.string("role")
				c.operators[id] = o
				out.append({"kind": "taskStarted", "projectId": p, "sessionId": s, "taskId": id})
				if o.role != null:
					out.append({"kind": "taskRole", "projectId": p, "sessionId": s, "taskId": id, "role": o.role})

		"task.role":
			var id: Variant = e.string("taskId")
			var role: Variant = e.string("role")
			if id != null and role != null and c.operators.has(id):
				(c.operators[id] as Operator).role = role
				out.append({"kind": "taskRole", "projectId": p, "sessionId": s, "taskId": id, "role": role})

		"task.done":
			var id: Variant = e.string("taskId")
			if id != null and c.operators.has(id):
				c.operators.erase(id)
				out.append({"kind": "taskDone", "projectId": p, "sessionId": s, "taskId": id,
					"status": _or(e.string("status"), "completed")})

		"schedule.create":
			var id: Variant = e.string("scheduleId")
			if id != null:
				var sch := Schedule.new()
				sch.schedule_id = id
				sch.session_id = s
				sch.project_id = p
				sch.text = _or(e.string("text"), "")
				sch.recurring = _or(e.boolean("recurring"), true)
				sch.next_run_ts = e.number("nextRunTs")
				schedules[id] = sch
				out.append({"kind": "scheduleAdded", "scheduleId": id})

		"schedule.delete":
			var id: Variant = e.string("scheduleId")
			if id != null and schedules.has(id):
				schedules.erase(id)
				out.append({"kind": "scheduleRemoved", "scheduleId": id})

		"approval.wait":
			var id: Variant = e.string("approvalId")
			if id != null:
				var a := Approval.new()
				a.approval_id = id
				a.agent_id = e.string("agentId")
				a.tool = _or(e.string("tool"), "")
				c.approvals[id] = a
				out.append({"kind": "approvalWait", "projectId": p, "sessionId": s, "approvalId": id,
					"agentId": a.agent_id, "autoMode": _or(e.boolean("autoMode"), false)})

		"approval.end":
			var id: Variant = e.string("approvalId")
			if id != null and c.approvals.has(id):
				var a: Approval = c.approvals[id]
				c.approvals.erase(id)
				out.append({"kind": "approvalEnd", "projectId": p, "sessionId": s, "approvalId": id, "agentId": a.agent_id})

		"activity":
			var kind: String = _or(e.string("kind"), "other")
			var id: Variant = e.string("agentId")
			if id != null:
				if c.staff.has(id):
					(c.staff[id] as Staff).activity = kind
			else:
				c.activity = kind
			out.append({"kind": "activity", "projectId": p, "sessionId": s, "agentId": id, "activityKind": kind})

		"message.send":
			var to: Variant = e.string("toAgentId")
			var to_name: Variant = e.string("toName")
			if to == null and to_name != null:
				for st: Staff in c.staff.values():
					if st.name == to_name:
						to = st.agent_id
						break
			out.append({"kind": "message", "projectId": p, "sessionId": s, "from": e.string("fromAgentId"), "to": to,
				"broadcast": _or(e.boolean("broadcast"), false)})

		"model.update":
			var m: Variant = e.string("model")
			if m != null:
				var id: Variant = e.string("agentId")
				if id != null:
					if c.staff.has(id):
						(c.staff[id] as Staff).model = m
				else:
					c.model = m
				out.append({"kind": "model", "projectId": p, "sessionId": s, "agentId": id, "model": m})

		"context.update":
			if e.number("tokens") != null: c.context.tokens = e.number("tokens")
			if e.number("window") != null: c.context.window = e.number("window")
			if e.number("percent") != null: c.context.percent = e.number("percent")
			if e.string("effort") != null: c.context.effort = e.string("effort")
			if e.number("lastTurnTokens") != null: c.context.last_turn_tokens = e.number("lastTurnTokens")
			out.append({"kind": "context", "projectId": p, "sessionId": s})

		"compact.start":
			c.compacting = true
			out.append({"kind": "compactStarted", "projectId": p, "sessionId": s, "trigger": _or(e.string("trigger"), "other")})

		"compact.end":
			if c.compacting:
				c.compacting = false
				out.append({"kind": "compactDone", "projectId": p, "sessionId": s, "outcome": _or(e.string("outcome"), "done"),
					"tokensBefore": e.number("tokensBefore"), "tokensAfter": e.number("tokensAfter")})

		_:
			pass # session.open, heartbeat, unknown types

	return out


func _close_session(p: String, s: String) -> Array[Dictionary]:
	if not blocks.has(p) or not (blocks[p] as Block).chiefs.has(s):
		return []
	var block: Block = blocks[p]
	block.chiefs.erase(s)
	block.order.erase(s)
	var out: Array[Dictionary] = [{"kind": "chiefLeft", "projectId": p, "sessionId": s}]
	for id: String in schedules.keys():
		if (schedules[id] as Schedule).session_id == s:
			schedules.erase(id)
			out.append({"kind": "scheduleRemoved", "scheduleId": id})
	if block.chiefs.is_empty():
		blocks.erase(p)
		block_order.erase(p)
		out.append({"kind": "blockRemoved", "projectId": p})
	return out


## Closes sessions with no event for `stale_after_ms` (spec scene 10; architecture: stale sessions).
func expire_stale(now_ms: int, stale_after_ms: int = 120_000) -> Array[Dictionary]:
	var stale: Array[Array] = []
	for p: String in blocks:
		for s: String in (blocks[p] as Block).chiefs:
			if now_ms - ((blocks[p] as Block).chiefs[s] as Chief).last_event_ts > stale_after_ms:
				stale.append([p, s])
	var out: Array[Dictionary] = []
	for ps: Array in stale:
		out.append_array(_close_session(ps[0], ps[1]))
	return out


## A language-neutral picture of the state (protocol/fixtures/expected/README.md). Unknown values
## are left out, lists are sorted as the README says, so both apps can compare.
func snapshot() -> Dictionary:
	var out_blocks: Array = []
	for id: String in block_order:
		if not blocks.has(id):
			continue
		var b: Block = blocks[id]
		var sessions: Array = []
		for s: String in b.order:
			if not b.chiefs.has(s):
				continue
			var c: Chief = b.chiefs[s]
			var d: Dictionary = {"sessionId": s, "compacting": c.compacting}
			_put(d, "model", c.model)
			_put(d, "activity", c.activity)
			_put(d, "hat", c.hat())
			if c.ticket != null:
				var t := c.ticket
				var td: Dictionary = {"ticketId": t.id, "origin": t.origin, "issuer": t.issuer, "text": t.text,
					"returnedCount": t.returned_count}
				_put(td, "taskType", t.task_type)
				_put(td, "title", t.title)
				_put(td, "returnReason", t.return_reason)
				_put(td, "messageKind", t.message_kind)
				_put(td, "fromAgentId", t.from_agent_id)
				d["ticket"] = td
			var staff: Array = []
			for k: String in _sorted_keys(c.staff):
				var st: Staff = c.staff[k]
				var x: Dictionary = {"agentId": st.agent_id, "subagentType": st.subagent_type, "background": st.background,
					"done": st.done}
				_put(x, "parentAgentId", st.parent_agent_id)
				_put(x, "role", st.role)
				_put(x, "model", st.model)
				_put(x, "activity", st.activity)
				staff.append(x)
			d["staff"] = staff
			var ops: Array = []
			for k: String in _sorted_keys(c.operators):
				var o: Operator = c.operators[k]
				var x: Dictionary = {"taskId": o.task_id, "kind": o.kind}
				_put(x, "agentId", o.agent_id)
				_put(x, "role", o.role)
				_put(x, "startedTicketId", o.started_ticket_id)
				ops.append(x)
			d["operators"] = ops
			var approvals: Array = []
			for k: String in _sorted_keys(c.approvals):
				var a: Approval = c.approvals[k]
				var x: Dictionary = {"approvalId": a.approval_id, "tool": a.tool}
				_put(x, "agentId", a.agent_id)
				approvals.append(x)
			d["approvals"] = approvals
			var ctx: Dictionary = {}
			_put(ctx, "tokens", c.context.tokens)
			_put(ctx, "window", c.context.window)
			_put(ctx, "percent", c.context.percent)
			_put(ctx, "effort", c.context.effort)
			_put(ctx, "lastTurnTokens", c.context.last_turn_tokens)
			if not ctx.is_empty():
				d["context"] = ctx
			sessions.append(d)
		out_blocks.append({"projectId": b.project_id, "name": b.name, "sessions": sessions})
	var out_schedules: Array = []
	for k: String in _sorted_keys(schedules):
		var sch: Schedule = schedules[k]
		var x: Dictionary = {"scheduleId": sch.schedule_id, "sessionId": sch.session_id, "projectId": sch.project_id,
			"text": sch.text, "recurring": sch.recurring}
		_put(x, "nextRunTs", sch.next_run_ts)
		out_schedules.append(x)
	return {"blocks": out_blocks, "schedules": out_schedules}


static func _put(d: Dictionary, k: String, v: Variant) -> void:
	if v != null:
		d[k] = v


## Keys in code-point order, as Swift's String `<` sorts them.
static func _sorted_keys(d: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for k: Variant in d.keys():
		keys.append(k)
	keys.sort_custom(_less)
	return keys


static func _less(a: String, b: String) -> bool:
	var n := mini(a.length(), b.length())
	for i in n:
		if a.unicode_at(i) != b.unicode_at(i):
			return a.unicode_at(i) < b.unicode_at(i)
	return a.length() < b.length()


static func _or(v: Variant, fallback: Variant) -> Variant:
	return fallback if v == null else v

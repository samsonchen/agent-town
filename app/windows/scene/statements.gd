class_name Statements
extends RefCounted
## What a character tells the CEO about its work when the CEO stands next to it (spec: walking the
## CEO, talking to a character). Port of `statement(for:)` in
## app/macos/Sources/AgentTown/TownScene+CEO.swift; the strings are the macOS app's.

static func for_actor(scene: TownScene, a: TownActor) -> String:
	var L := scene.labels
	match a.kind:
		"ceo":
			return ""
		"dispatcher":
			var n := scene.building.schedules.size()
			if n == 0:
				return L.t("Nothing scheduled on the board.")
			var s := L.t("%lld scheduled job on the board." if n == 1 else "%lld scheduled jobs on the board.", [n])
			var next: Building.Schedule = null
			for sch: Building.Schedule in scene.building.schedules.values():
				if sch.next_run_ts != null and (next == null or int(sch.next_run_ts) < int(next.next_run_ts)):
					next = sch
			if next != null:
				s += " " + L.t("Next up: %@.", [quote(L, clip(next.text))])
			return s
		"inspector":
			var returned := 0
			for b: Building.Block in scene.building.blocks.values():
				for c: Building.Chief in b.chiefs.values():
					if c.ticket != null:
						returned += c.ticket.returned_count
			if returned == 0:
				return L.t("I check returned tickets. All quiet for now.")
			return L.t("%lld ticket was sent back. I'm keeping an eye on it." if returned == 1
				else "%lld tickets were sent back. I'm keeping an eye on them.", [returned])
		"chief":
			return _chief(scene, a)
		_:
			return _worker(scene, a)


static func _chief(scene: TownScene, a: TownActor) -> String:
	var L := scene.labels
	var block: Building.Block = scene.building.blocks.get(a.block_id)
	var c: Building.Chief = block.chiefs.get(a.id) if block != null else null
	if c == null:
		return L.t("Just got here.")
	for ap: Building.Approval in c.approvals.values():
		if ap.agent_id == null:
			return L.t("I need your approval to use %@.", [ap.tool])
	if c.compacting:
		return L.t("I'm tidying our conversation notes to make room. Back to work in a moment.")
	var t := c.ticket
	if t == null:
		return L.t("No ticket right now. Ready for the next one.")
	var parts: Array[String] = []
	if a.since >= 0:
		parts.append(L.t("Working on %@ for %@.", [quote(L, clip(t.text)), duration(L, a.since)]))
	else:
		parts.append(L.t("Working on %@.", [quote(L, clip(t.text))]))
	if t.task_type != null:
		parts.append(L.t("It's a %@ job.", [L.task_type(t.task_type).to_lower()]))
	if t.returned_count > 0:
		parts.append(L.t("It came back %lld×, so I'm redoing it.", [t.returned_count]))
	var staff := 0
	for st: Building.Staff in c.staff.values():
		if not st.done:
			staff += 1
	var ops := c.operators.size()
	if staff + ops > 0:
		parts.append(L.t("%lld staff and %lld operator are helping." if ops == 1 else "%lld staff and %lld operators are helping.", [staff, ops]))
	var waiting := 0
	for ap: Building.Approval in c.approvals.values():
		if ap.agent_id != null:
			waiting += 1
	if waiting > 0:
		parts.append(L.t("%lld of them needs your approval." if waiting == 1 else "%lld of them need your approval.", [waiting]))
	var kind: Variant = a.activity if a.activity != null else c.activity
	if a.working and kind != null:
		parts.append(L.t("Right now I'm %@.", [activity(L, kind)]))
	return " ".join(parts)


static func _worker(scene: TownScene, a: TownActor) -> String:
	var L := scene.labels
	if a.job == null:
		if a.role != null:
			return L.t("Waiting on the bench. My last job was %@.", [L.role(a.role)])
		return L.t("Waiting on the bench for a job.")
	var inf := scene.staff.info(a.block_id, a.job)
	var parts := StaffDirector.parse(a.job)
	var desc: String = inf["description"]
	var what := L.t("a job") if desc == "" else quote(L, clip(desc))
	if not a.at_work:
		return L.t("On my way to start %@.", [what])
	if a.awaiting_approval:
		var block: Building.Block = scene.building.blocks.get(a.block_id)
		var c: Building.Chief = block.chiefs.get(parts[0]) if block != null else null
		if c != null:
			for ap: Building.Approval in c.approvals.values():
				if ap.agent_id == parts[1]:
					return L.t("I need your approval to use %@.", [ap.tool])
		return L.t("I'm waiting for your approval.")
	var time := duration(L, a.since) if a.since >= 0 else ""
	if parts[2]:
		return L.t("Running %@ in the background for %@.", [what, time])
	var role := L.role(inf["role"]) if inf["role"] != null else L.t("Staff")
	var out := L.t("%@ here. On %@ for %@.", [role, what, time])
	if a.activity != null:
		out += " " + L.t("Right now I'm %@.", [activity(L, a.activity)])
	return out


static func activity(L: TownLabels, kind: String) -> String:
	match kind:
		"read": return L.t("reading files")
		"edit": return L.t("editing files")
		"shell": return L.t("running commands")
		"web": return L.t("looking things up on the web")
		"mcp": return L.t("using a connected tool")
	return L.t("thinking it through")


## How long since `since_ms` (Time.get_ticks_msec), as "42s" or "3m 5s".
static func duration(L: TownLabels, since_ms: int) -> String:
	var s := maxi(0, (Time.get_ticks_msec() - since_ms) / 1000)
	if s < 60:
		return L.t("%llds", [s])
	return L.t("%lldm %llds", [s / 60, s % 60])


## Quoted text from the user or a model: “…” in English, 「…」 in Chinese.
static func quote(L: TownLabels, s: String) -> String:
	return L.t("“%@”", [s])


## The first line of `text`, cut to `n` characters with "…".
static func clip(text: String, n: int = 48) -> String:
	var one := text.split("\n")[0] if text != "" else ""
	return one.left(n) + "…" if one.length() > n else one

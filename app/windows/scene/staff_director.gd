class_name StaffDirector
extends RefCounted
## Staff, operators and the resource bench (spec scenes 3, 4, 5, 7, 11, 12, 16).
## Port of app/macos/Sources/AgentTown/TownScene+Staff.swift.

var scene: TownScene
var bench_size := 4 ## characters waiting per block (a setting later)
var staff_runs: Dictionary = {} ## base job key -> how many times that staff member was hired again
var pending_calls: Dictionary = {} ## caller id -> {"caller", "node", "jobs"}: hires waiting for one bench trip
var _next_worker_id := 0


func _init(p_scene: TownScene) -> void:
	scene = p_scene


func worker(p: String, job: String) -> TownActor:
	var b: BlockNode = scene.blocks.get(p)
	return b.jobs.get(job) if b != null else null


## The job key for a staff member's current run: `a:<session>/<agent>`, then `#<n>` from the
## second run on. A message to a finished agent resumes it and it is hired again; each run is its
## own job, so a report never goes to a character called for another run.
func staff_job(s: String, agent_id: String) -> String:
	var base := "a:%s/%s" % [s, agent_id]
	var n: int = staff_runs.get(base, 0)
	return base if n == 0 else "%s#%d" % [base, n]


## A hire: the first run of a staff member, or the next one when it was hired before.
func new_staff_run(s: String, agent_id: String) -> String:
	var base := "a:%s/%s" % [s, agent_id]
	staff_runs[base] = int(staff_runs[base]) + 1 if staff_runs.has(base) else 0
	return staff_job(s, agent_id)


## The session and the agent or task ID in a job key (a run's `#<n>` left out): [session, id, is_operator].
static func parse(job: String) -> Array:
	var rest := job.substr(2)
	var slash := rest.find("/")
	var id := rest.substr(slash + 1).get_slice("#", 0)
	return [rest.substr(0, slash), id, job.begins_with("t:")]


## What the building knows about a job: {"role", "description", "model", "parent"}.
func info(p: String, job: String) -> Dictionary:
	var parts := parse(job)
	var block: Building.Block = scene.building.blocks.get(p)
	var chief: Building.Chief = block.chiefs.get(parts[0]) if block != null else null
	if chief != null and parts[2] and chief.operators.has(parts[1]):
		var o: Building.Operator = chief.operators[parts[1]]
		return {"role": o.role, "description": o.description, "model": null, "parent": o.agent_id}
	if chief != null and not parts[2] and chief.staff.has(parts[1]):
		var st: Building.Staff = chief.staff[parts[1]]
		return {"role": st.role, "description": st.description, "model": st.model, "parent": st.parent_agent_id}
	return {"role": null, "description": "", "model": null, "parent": null}


## Who calls from the bench for `job` and gets its report: the staff member who started it, else
## the Chief of Staff.
func _boss(p: String, job: String) -> TownActor:
	var s: String = parse(job)[0]
	var parent: Variant = info(p, job)["parent"]
	if parent != null:
		var w := worker(p, staff_job(s, parent))
		if w != null and w.job != null:
			return w
	return scene.actors.get(s)


func has_working_staff(chief: TownActor) -> bool:
	if chief.kind != "chief" or not scene.blocks.has(chief.block_id):
		return false
	for k: String in (scene.blocks[chief.block_id] as BlockNode).jobs:
		if k.begins_with("a:%s/" % chief.id):
			return true
	return false


# --- Hiring (scenes 4 and 11) ------------------------------------------------------------

func hire(p: String, _s: String, job: String) -> void:
	var b: BlockNode = scene.blocks.get(p)
	var caller := _boss(p, job)
	if b == null or caller == null:
		return
	if pending_calls.has(caller.id):
		(pending_calls[caller.id]["jobs"] as Array).append(job)
		return
	pending_calls[caller.id] = {"caller": caller, "node": b, "jobs": [job]}
	# Subagents or tasks that start within about a second are called in one page.
	await scene.wait(1.0)
	if not pending_calls.has(caller.id):
		return
	var call: Dictionary = pending_calls[caller.id]
	pending_calls.erase(caller.id)
	caller.enqueue(func() -> void: await _bench_trip(call))


## The caller stays where they are and pages the bench over its speaker (on the desk phone when
## they have one): one character per job stands up and walks to a desk or a console.
func _bench_trip(call: Dictionary) -> void:
	var caller: TownActor = call["caller"]
	var b: BlockNode = call["node"]
	var jobs: Array = call["jobs"]
	var p := b.id
	while caller.on_call:
		await scene.wait(0.15)
	caller.on_call = true
	caller.play("interact-right", false)
	await scene.wait(0.35)
	var phone := caller.phone
	if phone != null:
		phone.lift(caller)
	caller.play("holding-right")
	var page := [caller, b, ""]
	scene.pages.append(page)

	# Wait up to 3 seconds for the roles, so the right character can be picked.
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000 and jobs.any(func(j: String) -> bool: return info(p, j)["role"] == null):
		await scene.wait(0.2)

	var called: Array = [] # [job, TownActor]
	var front_free := Layout.MAX_DESKS - b.staff_slots.values().filter(func(v: int) -> bool: return v < Layout.MAX_DESKS).size()
	for job: String in jobs:
		var i := info(p, job)
		var is_op: bool = parse(job)[2]
		var w: TownActor
		var back := b.free_back_slot()
		if not is_op and front_free <= 0 and back >= 0:
			# The front desks are taken: someone new walks in carrying a desk for the back row.
			w = spawn_worker(b, Layout.WORKER_ENTRANCE, null)
			b.temp_slots[w.id] = back
		else:
			if not is_op:
				front_free -= 1
			# The bench is empty: someone new walks in from the path.
			w = _pick(b, i["role"], is_op)
			if w == null:
				w = spawn_worker(b, Layout.WORKER_ENTRANCE, null)
		_link(w, job, b)
		called.append([job, w])
	var names: Array[String] = []
	for c: Array in called:
		var role: Variant = info(p, c[0])["role"]
		names.append(scene.labels.role(role) if role != null else scene.labels.t("Operator" if parse(c[0])[2] else "Staff"))
	page[2] = scene.labels.t("Paging: %@", [", ".join(names)])
	await scene.wait(0.6)
	for c: Array in called:
		(c[1] as TownActor).ticket_text = info(p, c[0])["description"]
		_assign(c[1], c[0], b)
	await scene.wait(1.2)

	scene.pages.erase(page)
	if phone != null:
		phone.hang_up()
	await scene.wait(0.3)
	caller.on_call = false
	caller.settle()


## Picks a waiting character: one who last had the same role, then one from the same department,
## then a neutral one, then anyone.
func _pick(b: BlockNode, role: Variant, is_operator: bool) -> TownActor:
	var dept: Variant = scene.labels.department_of(role) if role != null else ("background" if is_operator else null)
	var tests: Array[Callable] = [
		func(w: TownActor) -> bool: return role != null and w.role == role,
		func(w: TownActor) -> bool: return dept != null and w.department == dept,
		func(w: TownActor) -> bool: return w.department == null,
		func(_w: TownActor) -> bool: return true,
	]
	for test in tests:
		var best: TownActor = null
		for w in b.bench:
			if test.call(w) and (best == null or w.waiting_since < best.waiting_since):
				best = w
		if best != null:
			b.bench.erase(best)
			b.bench_spots.erase(best.id)
			best.sitting = false
			return best
	return null


## Ties a called character to its job right away, so approvals and activities find them.
func _link(w: TownActor, job: String, b: BlockNode) -> void:
	w.job = job
	w.at_work = false
	w.since = Time.get_ticks_msec()
	b.jobs[job] = w
	update_delegating(parse(job)[0])


## The main agent's work moved to the desk worker on `job`: they work, and the session's other desk
## workers wait at their desks until the ticket ends.
func focus_desk(p: String, s: String, job: String) -> void:
	var b: BlockNode = scene.blocks.get(p)
	if b == null:
		return
	b.active_desk[s] = job
	for k: String in b.jobs:
		if not k.begins_with("a:%s/desk-" % s):
			continue
		var w: TownActor = b.jobs[k]
		var on := k == job
		if w.working == on:
			continue
		w.working = on
		if not on:
			w.activity = null
		if w.at_work and not w.is_busy():
			w.settle()


## The Chief of Staff stops typing while staff do the work, and picks it back up after.
func update_delegating(s: String) -> void:
	var chief: TownActor = scene.actors.get(s)
	if chief == null:
		return
	var d := has_working_staff(chief)
	if d == chief.delegating:
		return
	chief.delegating = d
	if not chief.is_busy():
		chief.settle()


func _assign(w: TownActor, job: String, b: BlockNode) -> void:
	if b.jobs.get(job) != w: # the session ended during the bench trip
		w.ticket_text = null
		return
	var i := info(b.id, job)
	var parts := parse(job)
	var is_op: bool = parts[2]
	w.job = job
	w.is_operator = is_op
	w.role = i["role"]
	w.department = scene.labels.department_of(w.role) if w.role != null else null
	_dress(w)
	w.model_id = i["model"]
	# A desk worker whose turn has passed while they walked over waits at the desk.
	var session: String = parts[0]
	w.working = not (parts[1] as String).begins_with("desk-") or not b.active_desk.has(session) or b.active_desk[session] == job
	w.activity = null
	var back: int = -1 if is_op else int(b.temp_slots.get(w.id, -1))
	if back >= 0:
		w.has_computer = true
		w.home = Layout.chief_spot(back)
		w.home_facing = Vector2(0, 1)
		if w.carrying == null:
			scene.carry(scene.make_desk_kit(b, false)[0], w)
	elif is_op:
		var slot := BlockNode.free_slot(b.console_slots)
		b.console_slots[w.id] = slot
		w.has_computer = false
		w.home = Layout.operator_spot(slot)
		w.home_facing = Vector2(0, -1)
	else:
		var slot := BlockNode.free_slot(b.staff_slots)
		b.staff_slots[w.id] = slot
		w.has_computer = slot < Layout.MAX_DESKS # past the desks, staff stand at hot desks and write
		w.home = Layout.staff_spot(slot)
		w.home_facing = Vector2(0, 1)
	b.jobs[job] = w
	w.enqueue(func() -> void:
		await scene.go_home(w)
		if back >= 0 and w.carrying != null:
			await scene.put_down(w.carrying, w, b, back)
			scene.face(w, w.home_facing)
			w.settle()
		w.ticket_text = null
		if b.jobs.get(job) != w:
			return # the session ended on the way
		w.at_work = true
		for replay: Callable in b.deferred.get(job, []):
			replay.call()
		b.deferred.erase(job)
		if b.pending_done.has(job):
			var status: String = b.pending_done[job]
			b.pending_done.erase(job)
			await _finish(w, job, b, status))


## Dresses a character in its department's color, or the neutral outfit.
func _dress(w: TownActor) -> void:
	var hex := scene.labels.operator_color() if w.is_operator and w.role != null else scene.labels.color_for_department(w.department)
	if w.outfit == hex or not is_instance_valid(w.model):
		return
	scene.assets.dress(w.model, w.base, hex)
	w.outfit = hex


func role_decided(p: String, job: String, role: String) -> void:
	var w := worker(p, job)
	if w == null:
		return
	w.role = role
	w.department = scene.labels.department_of(role)
	_dress(w)


# --- Reports (scenes 7 and 12) -------------------------------------------------------------

func job_done(p: String, job: String, status: String) -> void:
	var b: BlockNode = scene.blocks.get(p)
	if b == null:
		return
	var w: TownActor = b.jobs.get(job)
	if w != null and w.at_work:
		w.enqueue(func() -> void: await _finish(w, job, b, status))
	else:
		b.pending_done[job] = status # still being called from the bench


## Brings the report (or a task's result) to whoever started the job, then goes back to the bench.
## A killed task leaves with no result.
func _finish(w: TownActor, job: String, b: BlockNode, status: String) -> void:
	if b.jobs.get(job) != w:
		return
	var receiver := _boss(b.id, job)
	if status != "killed" and receiver != null and receiver != w:
		await scene.walk(w, visitor_spot(receiver, b))
		scene.face(w, receiver.spot() - w.spot())
		w.ticket_text = scene.labels.t("Result" if w.is_operator else "Report")
		if status == "failed":
			w.bubble = scene.labels.t("Failed")
		w.play("interact-right", false)
		if not receiver.is_busy() and not receiver.on_call:
			receiver.play("pick-up", false)
		await scene.wait(1.1)
		w.ticket_text = null
		w.bubble = null
		if not receiver.is_busy():
			receiver.settle()
	_release(w, b)
	update_delegating(parse(job)[0])
	await _off_duty(w, b)


## Back to the bench; or, for someone who carried a desk in, out along the path with it.
func _off_duty(w: TownActor, b: BlockNode) -> void:
	if not b.temp_slots.has(w.id):
		await _return_to_bench(w, b)
		return
	var back: int = b.temp_slots[w.id]
	if b.carried.has(back):
		await scene.walk(w, Layout.chief_spot(back))
		scene.face(w, Vector2(0, 1))
		await scene.pick_up(w, b, back)
	b.temp_slots.erase(w.id)
	await scene.leave(w)


func _release(w: TownActor, b: BlockNode) -> void:
	if w.job != null and b.jobs.get(w.job) == w:
		b.jobs.erase(w.job)
	b.staff_slots.erase(w.id)
	b.console_slots.erase(w.id)
	w.job = null
	w.since = -1
	w.at_work = false
	w.working = false
	w.activity = null
	w.awaiting_approval = false


func _return_to_bench(w: TownActor, b: BlockNode) -> void:
	var spots := Layout.bench_spots()
	var index := BlockNode.free_slot(b.bench_spots, spots.size())
	if index >= spots.size():
		await scene.leave(w)
		return
	b.bench_spots[w.id] = index
	var spot: Vector2 = spots[index][0]
	var sitting: bool = spots[index][1]
	w.home = spot
	w.home_facing = Vector2(0, 1) if sitting else Layout.BENCH_CENTER - spot
	await scene.walk(w, spot)
	scene.face(w, w.home_facing)
	w.sitting = sitting
	w.waiting_since = Time.get_ticks_msec()
	b.bench.append(w)
	w.settle()
	_trim_bench(b)


## When the bench has more characters than its size, those who waited longest leave.
func _trim_bench(b: BlockNode) -> void:
	while b.bench.size() > bench_size:
		var oldest: TownActor = b.bench[0]
		for w in b.bench:
			if w.waiting_since < oldest.waiting_since:
				oldest = w
		b.bench.erase(oldest)
		b.bench_spots.erase(oldest.id)
		oldest.enqueue(func() -> void: await scene.leave(oldest))


## Scene 10: the session's staff and operators go back to the bench.
func session_ended(s: String, b: BlockNode) -> void:
	pending_calls.erase(s)
	for key: String in staff_runs.keys():
		if key.begins_with("a:%s/" % s):
			staff_runs.erase(key)
	b.active_desk.erase(s)
	for job: String in b.jobs.keys():
		if parse(job)[0] != s:
			continue
		var w: TownActor = b.jobs[job]
		w.enqueue(func() -> void:
			_release(w, b)
			await _off_duty(w, b))
	for id: String in scene.approvals.keys():
		var a: TownActor = scene.approvals[id]
		if a.id == s or (a.job != null and parse(a.job)[0] == s):
			scene.approvals.erase(id)
			a.awaiting_approval = false


## The block went: forget its pending pages.
func block_removed(b: BlockNode) -> void:
	for id: String in pending_calls.keys():
		if pending_calls[id]["node"] == b:
			pending_calls.erase(id)


# --- The bench -------------------------------------------------------------------------------

func spawn_worker(b: BlockNode, spot: Vector2, department: Variant) -> TownActor:
	_next_worker_id += 1
	var fixed: Array = (scene.assets.catalog["fixed"] as Dictionary).values()
	var bases := scene.assets.character_names().filter(func(c: String) -> bool: return not fixed.has(c))
	var hex := scene.labels.color_for_department(department)
	var w := scene.make_actor("w%d" % _next_worker_id, "worker", bases.pick_random(), hex, b, "", spot)
	w.department = department
	return w


## A new block starts with a mixed bench: a few in common department colors, a few neutral.
func fill_bench(b: BlockNode) -> void:
	var mix: Array = ["software-engineering", "background", null, null, "software-engineering", null, "background", null]
	var spots := Layout.bench_spots()
	for i in mini(bench_size, spots.size()):
		var spot: Vector2 = spots[i][0]
		var sitting: bool = spots[i][1]
		var w := spawn_worker(b, spot, mix[i % mix.size()])
		if w.department == "background":
			w.is_operator = true
		w.home = spot
		w.home_facing = Vector2(0, 1) if sitting else Layout.BENCH_CENTER - spot
		scene.face(w, w.home_facing)
		w.sitting = sitting
		w.waiting_since = Time.get_ticks_msec() - i * 1000
		b.bench_spots[w.id] = i
		b.bench.append(w)
		w.settle()


## Idle life on the bench: now and then someone standing chats or stretches.
func bench_life_loop() -> void:
	while scene.is_inside_tree():
		await scene.wait(2.5)
		var idle: Array[TownActor] = []
		for id: String in scene.blocks:
			for w: TownActor in (scene.blocks[id] as BlockNode).bench:
				if not w.is_busy() and not w.sitting:
					idle.append(w)
		if idle.is_empty():
			continue
		var w: TownActor = idle.pick_random()
		w.enqueue(func() -> void:
			w.play("emote-yes" if randf() < 0.5 else "interact-left", false)
			await scene.wait(1.2)
			w.settle())


# --- Messages (scene 16) ---------------------------------------------------------------------

func message(p: String, s: String, from: Variant, to: Variant, broadcast: bool) -> void:
	var b: BlockNode = scene.blocks.get(p)
	if b == null:
		return
	var sender: TownActor = worker(p, staff_job(s, from)) if from != null else scene.actors.get(s)
	if sender == null:
		return
	if sender.kind == "worker" and not sender.at_work and sender.job != null:
		if not b.deferred.has(sender.job):
			b.deferred[sender.job] = []
		(b.deferred[sender.job] as Array).append(func() -> void: message(p, s, from, to, broadcast))
		return
	var receiver: TownActor = null
	if to != null:
		receiver = worker(p, staff_job(s, to))
	elif from != null:
		receiver = scene.actors.get(s)
	if broadcast or receiver == null or receiver == sender:
		sender.speaking = true
		await scene.wait(1.5)
		sender.speaking = false
		return
	sender.enqueue(func() -> void:
		await scene.walk(sender, visitor_spot(receiver, b))
		scene.face(sender, receiver.spot() - sender.spot())
		sender.settle()
		sender.speaking = true
		receiver.speaking = true
		await scene.wait(1.4)
		sender.speaking = false
		receiver.speaking = false
		await scene.go_home(sender))


## Where someone stands to talk to `r`: across the desk, or behind an operator.
func visitor_spot(r: TownActor, b: BlockNode) -> Vector2:
	if r.kind == "chief" and b.chief_slots.has(r.id):
		return Layout.chief_visitor(b.chief_slots[r.id])
	if b.temp_slots.has(r.id):
		return Layout.chief_visitor(b.temp_slots[r.id])
	if b.staff_slots.has(r.id):
		return Layout.staff_visitor(b.staff_slots[r.id])
	if b.console_slots.has(r.id):
		return Layout.operator_spot(b.console_slots[r.id]) + Vector2(0, 0.45)
	return r.spot() + Vector2(0.45, 0)

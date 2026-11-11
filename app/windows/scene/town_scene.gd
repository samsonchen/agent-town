class_name TownScene
extends Node3D
## The office: blocks on one flat floor, furniture and characters, and the choreography that turns
## building changes into scenes. Staff, operators and the bench are in staff_director.gd.
## Port of app/macos/Sources/AgentTown/TownScene.swift and TownScene+Desks.swift.
## Still to come: the Inspector and the Dispatcher's board, compaction, walking the CEO.

signal office_resized(size: Vector2)
signal sound(name: String) ## "dispatch", "approval", "completion"

const EXECUTIVE := "executive"
const PITCH := deg_to_rad(62.0) ## the camera's angle above the floor
## Characters lean back toward the camera so they show their fronts on the top-down map.
const LEAN := -(PITCH - 0.2)
const BLOCK_COLORS := [["#CDD0DA", "#C3C6D1"], ["#B9CDE6", "#AFC4DF"], ["#C5DCC0", "#BAD3B4"], ["#E3CDA8", "#DBC39C"]]
const CARRIED_DESK_SCALE := 0.7 ## how big a carried desk looks, against its size when set down

var labels: TownLabels
var assets := TownAssets.new()
var building: Building ## the store's building, read for names, roles and context
var staff: StaffDirector
var office_size := Layout.office_size(1)
var blocks: Dictionary = {} ## id -> BlockNode
var block_order: Array[String] = []
var actors: Dictionary = {} ## id -> TownActor
var calls: Array = [] ## [caller, callee] pairs on a call now
var pages: Array = [] ## [caller, BlockNode, text]: pages in progress over a bench speaker
var approvals: Dictionary = {} ## approval_id -> TownActor waiting
var exec_phones: Dictionary = {} ## "ceo", "inspector", "dispatcher" -> TownPhone

var _ground := Node3D.new()
var _ground_size := Vector2.ZERO
var _color_index := 0
var _ceo_ringing := false


func _init(p_labels: TownLabels, p_building: Building) -> void:
	labels = p_labels
	building = p_building
	staff = StaffDirector.new(self)


func _ready() -> void:
	_add_light()
	add_child(_ground)
	var exec := BlockNode.new()
	exec.id = EXECUTIVE
	exec.name = labels.executive()
	blocks[EXECUTIVE] = exec
	block_order = [EXECUTIVE]
	_build_executive_block(exec)
	relayout()
	var fixed: Dictionary = assets.catalog["fixed"]
	for spec: Array in [["ceo", labels.ceo(), Layout.CEO_HOME], ["dispatcher", labels.dispatcher(), Layout.DISPATCHER_HOME],
			["inspector", labels.inspector(), Layout.INSPECTOR_HOME]]:
		var a := make_actor(spec[0], spec[0], fixed[spec[0]], "", exec, spec[1], spec[2])
		a.phone = exec_phones.get(spec[0])
		a.play("idle")
	_typing_loop()
	staff.bench_life_loop()


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- Changes --------------------------------------------------------------------------------

func handle(change: Dictionary) -> void:
	var p: String = change.get("projectId", "")
	var s: String = change.get("sessionId", "")
	match change["kind"]:
		"blockAdded":
			_add_block(p)
		"blockRemoved":
			_remove_block(p)
		"chiefArrived":
			_chief_arrived(p, s)
		"chiefLeft":
			_chief_left(p, s)
		"ticketSubmitted":
			_ticket_submitted(p, s, change["ticket"])
		"hat":
			if actors.has(s):
				(actors[s] as TownActor).hat = labels.task_type(change["taskType"])
		"ticketDone":
			_ticket_done(p, s, change["issuer"], change["aborted"], change["playSound"])
		"activity":
			var a := _who(p, s, change["agentId"])
			if a != null:
				a.activity = change["activityKind"]
				var agent: Variant = change["agentId"]
				if agent != null and (agent as String).begins_with("desk-"):
					staff.focus_desk(p, s, staff.staff_job(s, agent))
				if not a.is_busy():
					a.settle()
		"model":
			var a := _who(p, s, change["agentId"])
			if a != null:
				a.model_id = change["model"]
		"staffHired":
			staff.hire(p, s, staff.new_staff_run(s, change["agentId"]))
		"staffRole":
			staff.role_decided(p, staff.staff_job(s, change["agentId"]), change["role"])
		"staffDone":
			staff.job_done(p, staff.staff_job(s, change["agentId"]), change["status"])
		"taskStarted":
			staff.hire(p, s, "t:%s/%s" % [s, change["taskId"]])
		"taskRole":
			staff.role_decided(p, "t:%s/%s" % [s, change["taskId"]], change["role"])
		"taskDone":
			staff.job_done(p, "t:%s/%s" % [s, change["taskId"]], change["status"])
		"approvalWait":
			var a := _who(p, s, change["agentId"])
			if a != null:
				approvals[change["approvalId"]] = a
				a.awaiting_approval = true
				if not a.is_busy():
					a.settle()
				if not change["autoMode"]:
					sound.emit("approval") # in auto mode a classifier, not the user, answers
				_ring_ceo_for_approvals()
		"approvalEnd":
			var a: TownActor = approvals.get(change["approvalId"])
			if a != null:
				approvals.erase(change["approvalId"])
				if not approvals.values().has(a):
					a.awaiting_approval = false
					if not a.is_busy():
						a.settle()
		"message":
			staff.message(p, s, change["from"], change["to"], change["broadcast"])


## The character an agent ID names: a staff member's current run, or the Chief of Staff for null.
func _who(p: String, s: String, agent: Variant) -> TownActor:
	if agent != null:
		return staff.worker(p, staff.staff_job(s, agent))
	return actors.get(s)


func _add_block(p: String) -> void:
	if blocks.has(p):
		return
	var b := BlockNode.new()
	b.id = p
	var block: Building.Block = building.blocks.get(p)
	b.name = block.name if block != null else p
	blocks[p] = b
	block_order.append(p)
	var colors: Array = BLOCK_COLORS[_color_index % BLOCK_COLORS.size()]
	_color_index += 1
	_build_project_block(b, colors)
	relayout()
	staff.fill_bench(b)


func _remove_block(p: String) -> void:
	# The last session closed: the block goes at once, no one walks out.
	if not blocks.has(p):
		return
	var b: BlockNode = blocks[p]
	for id: String in actors.keys():
		if (actors[id] as TownActor).block_id == p:
			actors.erase(id)
	staff.block_removed(b)
	blocks.erase(p)
	block_order.erase(p)
	b.node.queue_free()
	relayout()


func _chief_arrived(p: String, s: String) -> void:
	if not blocks.has(p) or actors.has(s):
		return
	var b: BlockNode = blocks[p]
	var block: Building.Block = building.blocks.get(p)
	if block != null:
		b.name = block.name
	# The front desk if it is free, else a back-row slot nobody uses or is still clearing.
	var slot := 0
	if b.chief_slots.values().has(0):
		slot = b.free_back_slot()
		if slot < 0:
			slot = Layout.MAX_DESKS
	b.chief_slots[s] = slot
	var carries := slot > 0
	var chief := make_actor(s, "chief", _chief_base(b), assets.catalog["chiefOfStaff"]["color"], b, labels.chief_of_staff(),
		Layout.ENTRANCE if carries else Layout.chief_spot(slot))
	chief.home = Layout.chief_spot(slot)
	chief.has_computer = true
	if block != null and block.chiefs.has(s):
		chief.model_id = (block.chiefs[s] as Building.Chief).model
	if carries:
		# Another session in the project: its Chief walks in with a desk and a phone.
		var kit: Array = make_desk_kit(b, true)
		carry(kit[0], chief)
		chief.enqueue(func() -> void:
			await walk(chief, chief.home)
			await put_down(kit[0], chief, b, slot)
			chief.phone = kit[1]
			face(chief, chief.home_facing)
			chief.settle())
	else:
		# The first Chief is already at the desk when the block shows; no walk-in.
		chief.phone = b.desk_phones.get(0)
		chief.settle()


func _chief_left(p: String, s: String) -> void:
	var chief: TownActor = actors.get(s)
	if chief == null or chief.block_id != p or not blocks.has(p):
		return
	var b: BlockNode = blocks[p]
	var slot: int = b.chief_slots.get(s, -1)
	b.chief_slots.erase(s)
	chief.working = false
	staff.session_ended(s, b)
	actors.erase(s)
	if slot > 0:
		# A Chief who carried a desk in carries it out again, after the walk-in if still under way.
		b.leaving_slots.append(slot)
		chief.enqueue(func() -> void:
			if b.carried.has(slot):
				await walk(chief, Layout.chief_spot(slot))
				await pick_up(chief, b, slot)
			b.leaving_slots.erase(slot)
			await leave(chief))
	else:
		# The session ended: the Chief of Staff is gone at once, no walk-out.
		_remove_body(chief)


func _remove_body(a: TownActor) -> void:
	if is_instance_valid(a.root):
		a.root.queue_free()
	if a.shadow != null and is_instance_valid(a.shadow):
		a.shadow.queue_free()


func _ticket_submitted(p: String, s: String, ticket: Building.Ticket) -> void:
	var chief: TownActor = actors.get(s)
	if chief == null:
		return
	chief.hat = null
	if ticket.origin == "user" or ticket.origin == "schedule":
		# The CEO (or the Dispatcher, for a schedule) phones the Chief of Staff with the ticket.
		var issuer: TownActor = actors["dispatcher" if ticket.issuer == Building.DISPATCHER else "ceo"]
		chief.enqueue(func() -> void:
			await call_between(issuer, chief, ticket.text, func() -> void: sound.emit("dispatch"))
			chief.working = true
			chief.settle())
	else:
		# A follow-up or an untraced turn: the Chief of Staff picks it up from the inbox.
		chief.enqueue(func() -> void:
			chief.play("pick-up", false)
			await wait(0.8)
			chief.ticket_text = _untraced_note(ticket, p, s)
			chief.working = true
			chief.settle())


func _ticket_done(p: String, s: String, issuer: String, aborted: bool, play_sound: bool) -> void:
	if blocks.has(p):
		(blocks[p] as BlockNode).active_desk.erase(s)
	var chief: TownActor = actors.get(s)
	if chief == null:
		return
	chief.working = false
	chief.hat = null
	if aborted:
		# Scene 9: stop working; no report call, no sound.
		chief.ticket_text = null
		chief.settle()
		return
	var receiver: TownActor = actors["dispatcher" if issuer == Building.DISPATCHER else "ceo"]
	_report_when_desk_workers_are_back(p, s, chief, receiver, play_sound)


## The Chief of Staff phones the report back to whoever issued the ticket, once the desk workers
## who did the main loop's work have brought theirs (up to 15 seconds).
func _report_when_desk_workers_are_back(p: String, s: String, chief: TownActor, receiver: TownActor, play_sound: bool) -> void:
	var until := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < until and blocks.has(p):
		var waiting := false
		for k: String in (blocks[p] as BlockNode).jobs:
			if k.begins_with("a:%s/desk-" % s):
				waiting = true
		if not waiting:
			break
		await wait(0.2)
	chief.enqueue(func() -> void:
		# The sound plays as the report call rings, so the call is on screen when it is heard.
		await call_between(chief, receiver, null, func() -> void:
			if play_sound:
				sound.emit("completion"))
		chief.settle())


## The note for a ticket picked up from the inbox: its text; for another agent's message, who it
## is from ("Report from planner"); else "Continuing".
func _untraced_note(ticket: Building.Ticket, p: String, s: String) -> String:
	if ticket.text != "":
		return ticket.text
	if ticket.message_kind == null:
		return labels.t("Continuing")
	var st: Building.Staff = null
	var block: Building.Block = building.blocks.get(p)
	if ticket.from_agent_id != null and block != null and block.chiefs.has(s):
		st = (block.chiefs[s] as Building.Chief).staff.get(ticket.from_agent_id)
	var who: Variant = null
	if st != null:
		var d := st.description.strip_edges()
		if d != "" and TownLabels.display_width(d) <= 24:
			who = d
		elif st.role != null:
			who = labels.role(st.role)
	if who == null:
		return labels.t("Message from a colleague")
	return labels.t("Report from %@" if ticket.message_kind == "report" else "Message from %@", [who])


# --- Calls ----------------------------------------------------------------------------------

## A phone call. The caller lifts the handset, the other phone rings and is answered, they talk,
## and the ticket (the caller's, or `text`) passes to the callee. `ringing` runs as the callee's
## phone starts to ring, for a sound heard while the call shows.
func call_between(caller: TownActor, callee: TownActor, text: Variant, ringing: Callable = Callable()) -> void:
	while caller.on_call or callee.on_call:
		await wait(0.15)
	var out := caller.phone
	var inn := callee.phone
	if out == null or inn == null:
		return
	caller.on_call = true
	callee.on_call = true
	if text != null:
		caller.ticket_text = text
	caller.play("interact-right", false)
	await wait(0.35)
	out.lift(caller)
	caller.play("holding-right")
	calls.append([caller, callee])
	while inn.ringing: # an approval ring in progress
		await wait(0.1)
	if ringing.is_valid():
		ringing.call()
	await inn.ring(1.2)
	callee.play("interact-right", false)
	await wait(0.35)
	inn.lift(callee)
	callee.play("holding-right")
	await wait(1.6)
	callee.ticket_text = caller.ticket_text if callee.kind == "chief" else null # the CEO and the Dispatcher just take the report
	caller.ticket_text = null
	out.hang_up()
	inn.hang_up()
	calls = calls.filter(func(c: Array) -> bool: return not (c[0] == caller and c[1] == callee))
	await wait(0.3)
	caller.on_call = false
	callee.on_call = false
	caller.settle()
	callee.settle()


## The CEO's phone rings while any tool call waits for approval (spec scene 6).
func _ring_ceo_for_approvals() -> void:
	var ceo: TownActor = actors.get("ceo")
	if _ceo_ringing or ceo == null:
		return
	_ceo_ringing = true
	while not approvals.is_empty():
		if not ceo.on_call and ceo.phone != null:
			await ceo.phone.ring(1.0)
		await wait(0.6)
	_ceo_ringing = false
	if not ceo.on_call and not ceo.is_busy():
		ceo.play("emote-yes", false)
		await wait(0.8)
		if not ceo.on_call:
			ceo.settle()


# --- Motion ---------------------------------------------------------------------------------

func move(a: TownActor, p: Vector2, speed: float = Layout.WALK_SPEED) -> void:
	if not is_instance_valid(a.root):
		return
	var from := a.spot()
	var d := from.distance_to(p)
	if d <= 0.01:
		return
	face(a, p - from)
	a.play("walk")
	var seconds := d / speed
	var tw := a.root.create_tween()
	tw.tween_property(a.root, "position", Vector3(p.x, Layout.FLOOR_THICKNESS, p.y), seconds)
	if a.shadow != null and is_instance_valid(a.shadow):
		a.shadow.create_tween().tween_property(a.shadow, "position", Vector3(p.x, Layout.FLOOR_THICKNESS + 0.003, p.y), seconds)
	await wait(seconds) # a timer, not the tween, so a body freed on the way cannot leave the queue waiting


## Walks inside the block along the walkways.
func walk(a: TownActor, dest: Vector2) -> void:
	a.sitting = false
	for p in Layout.route(a.spot(), dest):
		await move(a, p)
	a.play("idle")


## Walks to the character's own spot and settles there.
func go_home(a: TownActor) -> void:
	await walk(a, a.home)
	face(a, a.home_facing)
	a.settle()


## Out along the path below the block's left entrance, then gone.
func leave(a: TownActor) -> void:
	await walk(a, Layout.WORKER_ENTRANCE)
	await move(a, Vector2(Layout.WORKER_ENTRANCE.x, Layout.BLOCK_DEPTH + Layout.GAP / 2.0))
	_remove_body(a)
	if actors.get(a.id) == a:
		actors.erase(a.id)


func face(a: TownActor, dir: Vector2) -> void:
	if dir.length() < 0.001 or not is_instance_valid(a.root):
		return
	a.root.basis = Basis(Vector3.RIGHT, LEAN) * Basis(Vector3.UP, atan2(dir.x, dir.y))


## Desk workers switch hands as they type.
func _typing_loop() -> void:
	while is_inside_tree():
		await wait(0.45)
		for a: TownActor in actors.values():
			if a.is_busy() or a.on_call:
				continue
			if a.current_clip == "type-right":
				a.play("type-left", true, 0.12)
			elif a.current_clip == "type-left":
				a.play("type-right", true, 0.12)


# --- Building -------------------------------------------------------------------------------

func make_actor(id: String, kind: String, base: String, outfit: String, b: BlockNode, display_name: String, spot: Vector2) -> TownActor:
	var a := TownActor.new(self, id, kind)
	a.base = base
	a.name = display_name
	a.block_id = b.id
	a.home = spot
	a.outfit = outfit
	a.model = assets.character(base, outfit)
	a.model.scale = Vector3.ONE * Layout.CHARACTER_SCALE
	a.root.add_child(a.model)
	var players := a.model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		a.player = players[0]
		assets.attach_motion(a.player, assets.catalog["characters"][base]["model"])
	# A soft round shadow under the feet, kept flat on the floor.
	var blob := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.16
	disc.bottom_radius = 0.16
	disc.height = 0.002
	blob.mesh = disc
	var shade := StandardMaterial3D.new()
	shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shade.albedo_color = Color(0, 0, 0, 0.18)
	blob.material_override = shade
	blob.position = Vector3(spot.x, Layout.FLOOR_THICKNESS + 0.003, spot.y)
	b.node.add_child(blob)
	a.shadow = blob
	a.root.position = Vector3(spot.x, Layout.FLOOR_THICKNESS, spot.y)
	b.node.add_child(a.root)
	face(a, Vector2(0, 1))
	actors[id] = a
	return a


## Chiefs of Staff in one block get different base characters.
func _chief_base(b: BlockNode) -> String:
	var excluded: Array = assets.catalog["chiefOfStaff"]["exclude"]
	var all := assets.character_names().filter(func(c: String) -> bool: return not excluded.has(c))
	var in_block: Array = []
	for s: String in b.chief_slots:
		if actors.has(s):
			in_block.append((actors[s] as TownActor).base)
	var start := absi(hash(b.id)) % all.size()
	for i in all.size():
		var c: String = all[(start + i) % all.size()]
		if not in_block.has(c):
			return c
	return all[start]


## Places the blocks in one column and sizes the path around them.
func relayout() -> void:
	for i in block_order.size():
		var b: BlockNode = blocks[block_order[i]]
		var o := Layout.block_origin(i)
		var to := Vector3(o.x, 0, o.y)
		if b.placed:
			create_tween().tween_property(b.node, "position", to, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		else:
			b.node.position = to
			add_child(b.node)
			b.placed = true
	office_size = Layout.office_size(block_order.size())
	_build_ground()
	office_resized.emit(office_size)


func _add_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.5
	sun.shadow_enabled = true
	sun.transform = Transform3D.IDENTITY.looking_at(Vector3(3, -10, -5), Vector3.UP)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.2
	fill.transform = Transform3D.IDENTITY.looking_at(Vector3(-4, -5, -9), Vector3.UP)
	add_child(fill)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#F4EADB")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.32
	add_child(env)


static func box(size: Vector3, color: String, at: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.roughness = 0.8
	m.material_override = mat
	m.position = at
	return m


## A flat tiled rectangle, drawn without lighting so it reads as a 2D map.
static func tiles(width: float, depth: float, tile: float, colors: Array, grout: String = "", brick: bool = false) -> MeshInstance3D:
	var px := 24
	var cols := maxi(1, roundi(width / tile))
	var rows := maxi(1, roundi(depth / tile) * (2 if brick else 1))
	var rh := px / 2 if brick else px
	var full := Rect2i(0, 0, cols * px, rows * rh)
	var img := Image.create(cols * px, rows * rh, false, Image.FORMAT_RGBA8)
	var c0 := Color(colors[0])
	var c1 := Color(colors[1])
	for r in rows:
		for c in range(-1, cols + 1):
			var x := c * px + (px / 2 if brick and r % 2 == 1 else 0)
			img.fill_rect(Rect2i(x, r * rh, px, rh).intersection(full), c0 if brick or (r + c + 2) % 2 == 0 else c1)
			if grout != "":
				img.fill_rect(Rect2i(x, r * rh, px, 1).intersection(full), Color(grout))
				img.fill_rect(Rect2i(x, r * rh, 1, rh).intersection(full), Color(grout))
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, depth)
	m.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## The cream brick path the blocks sit on, larger than any window shows.
func _build_ground() -> void:
	var size := office_size + Vector2(40, 40)
	if size.x <= _ground_size.x and size.y <= _ground_size.y:
		return
	_ground_size = size
	for c in _ground.get_children():
		c.queue_free()
	var plane := tiles(size.x, size.y, 0.5, ["#F4EADB", "#F4EADB"], "#EADDC9", true)
	plane.position = Vector3(office_size.x / 2.0, -0.001, office_size.y / 2.0)
	_ground.add_child(plane)


## The block's floor: a tiled carpet with a darker edge along the front.
func _floor(b: BlockNode, colors: Array, d: float = Layout.BLOCK_DEPTH) -> void:
	var w := Layout.BLOCK_WIDTH
	var carpet := tiles(w, d, 0.5, colors)
	carpet.position = Vector3(w / 2.0, Layout.FLOOR_THICKNESS, d / 2.0)
	b.node.add_child(carpet)
	var edge := Color(colors[1]).lerp(Color.BLACK, 0.35).to_html(false)
	b.node.add_child(box(Vector3(w, Layout.FLOOR_THICKNESS, 0.08), "#" + edge, Vector3(w / 2.0, Layout.FLOOR_THICKNESS / 2.0, d + 0.04)))


## The bounds of everything drawn under `n`, in `relative_to`'s space.
static func bounds(n: Node3D, relative_to: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for vi: Node in n.find_children("*", "VisualInstance3D", true, false):
		var v := vi as VisualInstance3D
		var b := _transform_to(v, relative_to) * v.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## `n`'s transform in `ancestor`'s space, walking up the parents (works before they are in the tree).
static func _transform_to(n: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Places a furniture model with its footprint centered on `p` (Kenney models are anchored at a corner).
func place(name: String, parent: Node3D, p: Vector2, yaw: float = 0.0, scale_: float = 1.0, on_top_of: Node3D = null) -> Node3D:
	var model := assets.furniture(name)
	var e := Node3D.new()
	e.add_child(model)
	var k := scale_ * Layout.FURNITURE_SCALE
	e.basis = Basis(Vector3.UP, yaw).scaled(Vector3(k, k, k))
	parent.add_child(e)
	var b := bounds(e, parent)
	var floor_y := bounds(on_top_of, parent).end.y if on_top_of != null else Layout.FLOOR_THICKNESS
	var c := b.get_center()
	e.position += Vector3(p.x - c.x, floor_y - b.position.y, p.y - c.z)
	return e


## A desk telephone at `p` on top of `desk`.
func telephone(parent: Node3D, p: Vector2, desk: Node3D) -> TownPhone:
	var top := bounds(desk, parent).end.y
	var k := Layout.FURNITURE_SCALE / 0.85
	var device := Node3D.new()
	device.position = Vector3(p.x, top, p.y)
	device.add_child(box(Vector3(0.16, 0.05, 0.12) * k, "#B8322F", Vector3(0, 0.025, 0) * k))
	device.add_child(box(Vector3(0.09, 0.006, 0.05) * k, "#F2EEE6", Vector3(0, 0.052, 0.025) * k))
	var handset := box(Vector3(0.17, 0.035, 0.045) * k, "#8E2321", Vector3(0, 0.07, -0.03) * k)
	device.add_child(handset)
	parent.add_child(device)
	return TownPhone.new(device, handset)


func _build_executive_block(b: BlockNode) -> void:
	var f := b.node
	_floor(b, ["#9D9FDC", "#9294D4"], Layout.EXEC_DEPTH)
	place("rugRectangle", f, Vector2(Layout.CEO_DESK.x, Layout.CEO_DESK.y - 0.25), 0.0, 0.9)
	var desk := place("desk", f, Layout.CEO_DESK)
	place("computerScreen", f, Vector2(Layout.CEO_DESK.x - 0.1, Layout.CEO_DESK.y - 0.05), 0.0, 0.8, desk)
	exec_phones["ceo"] = telephone(f, Vector2(Layout.CEO_DESK.x + 0.28, Layout.CEO_DESK.y + 0.02), desk)
	# Reception, where the Inspector stands.
	place("kitchenBar", f, Vector2(Layout.RECEPTION_DESK.x - 0.19, Layout.RECEPTION_DESK.y))
	var bar := place("kitchenBar", f, Vector2(Layout.RECEPTION_DESK.x + 0.19, Layout.RECEPTION_DESK.y))
	exec_phones["inspector"] = telephone(f, Vector2(Layout.RECEPTION_DESK.x + 0.24, Layout.RECEPTION_DESK.y + 0.02), bar)
	# The schedule board on the back wall, and the Dispatcher's desk with the radio.
	var w := Layout.BOARD_WIDTH
	f.add_child(box(Vector3(w, 0.55, 0.04), "#2E5244", Vector3(Layout.BOARD_CENTER.x, 0.42, Layout.BOARD_CENTER.y)))
	f.add_child(box(Vector3(w + 0.1, 0.05, 0.05), "#7A5A3A", Vector3(Layout.BOARD_CENTER.x, 0.16, Layout.BOARD_CENTER.y)))
	var ddesk := place("desk", f, Layout.DISPATCHER_DESK)
	var radio := place("radio", f, Vector2(Layout.DISPATCHER_DESK.x + 0.25, Layout.DISPATCHER_DESK.y), 0.0, 1.0, ddesk)
	# The radio is lifted whole; a holder stays on the desk where it stood.
	var holder := Node3D.new()
	holder.transform = radio.transform
	f.add_child(holder)
	f.remove_child(radio)
	radio.transform = Transform3D.IDENTITY
	holder.add_child(radio)
	exec_phones["dispatcher"] = TownPhone.new(holder, radio)
	place("pottedPlant", f, Vector2(0.3, 0.3))
	place("pottedPlant", f, Vector2(6.7, 0.3))


func _build_project_block(b: BlockNode, colors: Array) -> void:
	var f := b.node
	_floor(b, colors)
	# One Chief of Staff desk with a telephone; the rest of the back row is open floor, where a
	# second session's Chief, or staff past the front desks, set down a desk they carry in.
	var x0 := Layout.desk_x(0)
	var desk := place("desk", f, Vector2(x0, Layout.CHIEF_DESK_Z))
	place("computerScreen", f, Vector2(x0 - 0.1, Layout.CHIEF_DESK_Z - 0.05), 0.0, 0.8, desk)
	b.desk_phones[0] = telephone(f, Vector2(x0 + 0.28, Layout.CHIEF_DESK_Z + 0.02), desk)
	for slot in Layout.MAX_DESKS:
		var x := Layout.desk_x(slot)
		var sd := place("desk", f, Vector2(x, Layout.STAFF_DESK_Z))
		place("laptop", f, Vector2(x, Layout.STAFF_DESK_Z - 0.03), 0.0, 1.0, sd)
	# Server room (front left): racks along the back, for operators.
	f.add_child(box(Vector3(3.3, 0.006, 1.95), "#7D8590", Vector3(1.8, Layout.FLOOR_THICKNESS + 0.003, 4.275)))
	for i in Layout.CONSOLES:
		place("speaker", f, Vector2(Layout.rack_x(i) - 0.15, Layout.RACK_Z), 0.0, 1.4)
		place("speaker", f, Vector2(Layout.rack_x(i) + 0.15, Layout.RACK_Z), 0.0, 1.4)
	# Resource bench (front right): a lounge.
	place("rugRound", f, Layout.BENCH_CENTER, 0.0, 1.3)
	place("loungeSofaLong", f, Vector2(Layout.BENCH_CENTER.x, 3.5))
	place("tableCoffee", f, Vector2(Layout.BENCH_CENTER.x, 4.3))
	var table := place("sideTable", f, Layout.SPEAKER_SPOT)
	b.speaker = place("speaker", f, Layout.SPEAKER_SPOT, 0.0, 0.8, table)
	place("kitchenCoffeeMachine", f, Vector2(6.75, 3.45))
	place("pottedPlant", f, Vector2(6.75, 5.1))
	place("pottedPlant", f, Vector2(6.75, 0.3))


# --- Carried desks (spec: six desks per project block) ------------------------------------

## A desk ready to carry: with a screen and a telephone for a Chief of Staff, else a laptop.
## Its origin is the middle of its footprint, on the floor. Returns [kit, TownPhone or null].
func make_desk_kit(b: BlockNode, chief: bool) -> Array:
	var kit := Node3D.new()
	b.node.add_child(kit)
	var desk := place("desk", kit, Vector2.ZERO)
	var phone: TownPhone = null
	if chief:
		place("computerScreen", kit, Vector2(-0.1, -0.05), 0.0, 0.8, desk)
		phone = telephone(kit, Vector2(0.28, 0.02), desk)
	else:
		place("laptop", kit, Vector2(0, -0.03), 0.0, 1.0, desk)
	return [kit, phone]


## Holds `kit` above the character's head; it moves and turns with them.
func carry(kit: Node3D, a: TownActor) -> void:
	kit.get_parent().remove_child(kit)
	a.root.add_child(kit)
	kit.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * CARRIED_DESK_SCALE), Vector3(0, 0.67 * Layout.CHARACTER_SCALE + 0.03, 0))
	a.carrying = kit


## Sets the carried desk down at back-row `slot`.
func put_down(kit: Node3D, a: TownActor, b: BlockNode, slot: int) -> void:
	a.play("pick-up", false)
	await wait(0.4)
	if not is_instance_valid(kit) or not is_instance_valid(b.node):
		return
	kit.get_parent().remove_child(kit)
	b.node.add_child(kit)
	kit.transform = Transform3D(Basis.IDENTITY, Vector3(Layout.desk_x(slot), 0, Layout.CHIEF_DESK_Z))
	a.carrying = null
	b.carried[slot] = kit
	await wait(0.3)


## Lifts the desk at back-row `slot` to carry it away.
func pick_up(a: TownActor, b: BlockNode, slot: int) -> void:
	var kit: Node3D = b.carried.get(slot)
	if kit == null:
		return
	b.carried.erase(slot)
	a.play("pick-up", false)
	await wait(0.4)
	if is_instance_valid(kit) and is_instance_valid(a.root):
		carry(kit, a)
	await wait(0.2)


# --- Labels ---------------------------------------------------------------------------------

## What the label overlay draws: each item {"anchor": Vector3, "lines": [[text, style]]}, block
## signs, and the context bars ({"meter": true, "anchor", "row", "fraction", "text"}).
func label_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for a: TownActor in actors.values():
		if not is_instance_valid(a.root) or not a.root.is_inside_tree():
			continue
		var lines: Array = []
		if a.speaking:
			lines.append(["• • •", "speech"])
		if a.awaiting_approval:
			lines.append([labels.t("Needs approval"), "ring"])
		if a.bubble != null:
			lines.append([a.bubble, "bubble"])
		if a.note != null:
			lines.append([a.note, "ticket"])
		# The hat shows only while no staff are working (spec: hats).
		if a.hat != null and not staff.has_working_staff(a):
			lines.append([a.hat, "hat"])
		if a.ticket_text != null and a.ticket_text != "":
			var t: String = a.ticket_text
			lines.append([t.left(28) + ("…" if t.length() > 28 else ""), "ticket"])
		if a.kind == "worker":
			if a.job != null:
				lines.append([labels.role(a.role) if a.role != null else labels.t("Operator" if a.is_operator else "Staff"), "name"])
			elif a.role != null:
				lines.append([labels.role(a.role), "faint"])
		else:
			lines.append([a.name, "name"])
		if not lines.is_empty():
			items.append({"anchor": a.head(0.04), "lines": lines})
		if a.phone != null and a.phone.ringing and is_instance_valid(a.phone.device):
			items.append({"anchor": a.phone.anchor(), "lines": [[labels.t("Ring ring"), "ring"]]})
	for page: Array in pages:
		var top: Variant = _speaker_top(page[1])
		if page[2] != "" and top != null:
			items.append({"anchor": (top as Vector3) + Vector3(0, 0.05, 0), "lines": [[page[2], "ring"]]})
	for id in block_order:
		var b: BlockNode = blocks[id]
		var o := b.node.position
		var edge := Layout.EXEC_DEPTH if id == EXECUTIVE else 0.0
		items.append({"anchor": o + Vector3(Layout.BLOCK_WIDTH / 2.0, 0, edge), "lines": [[_sign(b), "sign"]]})
		if id == EXECUTIVE:
			continue
		var at := Layout.SERVER_ROOM_LABEL
		items.append({"anchor": o + Vector3(at.x, 0, at.y), "lines": [[labels.server_room(), "faint"]]})
		var block: Building.Block = building.blocks.get(id)
		if block == null:
			continue
		var row := 0
		for s in block.order:
			var c: Building.Chief = block.chiefs.get(s)
			if c == null:
				continue
			var text := labels.context_line(c.context)
			if block.order.size() > 1 and b.chief_slots.has(s):
				text = labels.desk(int(b.chief_slots[s]) + 1) + " · " + text
			items.append({"meter": true, "anchor": o + Vector3(Layout.BLOCK_WIDTH / 2.0, 0, Layout.BLOCK_DEPTH), "row": row,
				"fraction": c.context.fraction(), "text": text})
			row += 1
	return items


## The top of a block's bench speaker, in this scene's space, or null.
func _speaker_top(b: BlockNode) -> Variant:
	if b.speaker == null or not is_instance_valid(b.speaker):
		return null
	var box_ := bounds(b.speaker, self)
	return Vector3(box_.get_center().x, box_.end.y, box_.get_center().z)


## Lines between the two ends of each call, from each caller to the bench speaker they page, and
## from each character waiting for approval to the CEO.
func call_lines() -> Array:
	var out: Array = []
	for c: Array in calls:
		var a: TownActor = c[0]
		var b: TownActor = c[1]
		if is_instance_valid(a.root) and is_instance_valid(b.root):
			out.append([a.head(-0.15), b.head(-0.15)])
	for page: Array in pages:
		var caller: TownActor = page[0]
		var top: Variant = _speaker_top(page[1])
		if top != null and is_instance_valid(caller.root):
			out.append([caller.head(-0.15), top])
	var ceo: TownActor = actors.get("ceo")
	if ceo != null:
		var seen: Array = []
		for a: TownActor in approvals.values():
			if not seen.has(a) and is_instance_valid(a.root):
				seen.append(a)
				out.append([a.head(-0.15), ceo.head(-0.15)])
	return out


## The block's sign: the project's name, then the title of each running task, by desk.
func _sign(b: BlockNode) -> String:
	if b.id == EXECUTIVE:
		return b.name
	var block: Building.Block = building.blocks.get(b.id)
	if block == null:
		return b.name
	var titles: Array[String] = []
	var sessions := block.chiefs.keys()
	sessions.sort_custom(func(x: String, y: String) -> bool: return int(b.chief_slots.get(x, 99)) < int(b.chief_slots.get(y, 99)))
	for s: String in sessions:
		var c: Building.Chief = block.chiefs[s]
		if c.ticket != null and c.ticket.title != null and titles.size() < 2:
			titles.append(c.ticket.title)
	if titles.is_empty():
		return block.name
	var parts: Array[String] = []
	if block.name != block.project_id:
		parts.append(block.name)
	parts.append(" · ".join(titles))
	return " · ".join(parts)

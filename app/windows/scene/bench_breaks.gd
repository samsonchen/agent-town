class_name BenchBreaks
extends RefCounted
## Break time on the bench (docs/spec.md → Resource bench → Break time). When a project block has
## had no work for a while, the characters waiting on its bench start passing the time, one now and
## then, each for a short while. As soon as the block has work again, everyone stops and is ready to
## be called. The CEO coming to talk to someone on a break ends that break: they turn to the CEO (a
## dozer wakes with a "!"), and turn back when the CEO leaves.
## Port of app/macos/Sources/AgentTown/TownScene+Breaks.swift.

const PASTIMES: Array[String] = ["juggle", "cube", "toss", "phone", "chat", "doze"]
const JUGGLE_COLORS: Array[String] = ["#FF3B30", "#FFCC00", "#007AFF"] # red, yellow, blue
const CUBE_COLORS: Array[String] = ["#FFFFFF", "#FFCC00", "#FF3B30", "#FF9500", "#007AFF", "#34C759"]

var scene: TownScene
## Seconds a block must have been idle before breaks start; `--break-idle N` shortens it.
var idle_seconds := 180.0
## `--break-pastime NAME`: standing characters take only this one (seated ones still doze).
var only_pastime := ""
var idle_since: Dictionary = {} ## project id -> msec when the block last became idle


func _init(p_scene: TownScene) -> void:
	scene = p_scene


## Four times a second: the CEO's visit first, then in each block idle long enough, now and then
## one more bench character takes a break. A block with work, or hidden, stops every break.
func loop() -> void:
	while scene.is_inside_tree():
		await scene.wait(0.25)
		_greet_ceo()
		var now := Time.get_ticks_msec()
		for p: String in scene.blocks:
			if p == TownScene.EXECUTIVE:
				continue
			var b: BlockNode = scene.blocks[p]
			if not b.placed or not scene.settled(p):
				idle_since.erase(p)
				stop(b)
				continue
			var since: int = idle_since.get(p, now)
			idle_since[p] = since
			if now - since >= idle_seconds * 1000.0 and randf() < 0.05:
				_start_break(b)


## Ends every break in the block at once: the next frame each character drops its props and settles.
func stop(b: BlockNode) -> void:
	for a: TownActor in b.bench:
		if a.on_break:
			a.break_ends = 0


func _on_bench(a: TownActor) -> bool:
	var b: BlockNode = scene.blocks.get(a.block_id)
	return b != null and b.bench.has(a)


func _touched() -> TownActor:
	return scene.ceo_driver.touched() if scene.ceo_driver != null else null


func _ceo_direction(a: TownActor) -> Variant:
	var ceo: TownActor = scene.ceo_driver.ceo() if scene.ceo_driver != null else null
	if ceo == null or not is_instance_valid(ceo.root) or not is_instance_valid(a.root):
		return null
	return CeoDriver.world_spot(ceo) - CeoDriver.world_spot(a)


## The character the CEO is next to stops its break (a chat stops for both) and faces the CEO;
## whoever was turned to the CEO turns back once the CEO has left. A seated one keeps facing forward.
func _greet_ceo() -> void:
	var touched := _touched()
	if touched != null and touched.kind == "worker" and _on_bench(touched):
		if touched.on_break:
			touched.greeting_ceo = true
			touched.break_ends = 0
			var partner := touched.chat_partner
			if partner != null and partner.on_break:
				partner.greeting_ceo = true
				partner.greets_along = touched
				partner.break_ends = 0
		elif touched.greeting_ceo:
			# Both of a chat follow the CEO while they talk.
			for g: TownActor in scene.actors.values():
				if (g == touched or g.greets_along == touched) and g.greeting_ceo and not g.is_busy() and not g.sitting:
					var dir: Variant = _ceo_direction(g)
					if dir != null:
						scene.face(g, dir)
	for a: TownActor in scene.actors.values():
		if a.greeting_ceo and a != touched and not a.is_busy() and (touched == null or a.greets_along != touched) and _on_bench(a):
			a.greeting_ceo = false
			a.greets_along = null
			scene.face(a, a.home_facing)
			a.settle()


## At the end of a break: turned to the CEO when the CEO came to talk, else back to the bench.
func _end_break(a: TownActor) -> void:
	var dir: Variant = _ceo_direction(a) if a.greeting_ceo and not a.sitting else null
	scene.face(a, dir if dir != null else a.home_facing)
	a.settle()


func _start_break(b: BlockNode) -> void:
	var touched := _touched()
	var free: Array = b.bench.filter(func(a: TownActor) -> bool:
		return not a.is_busy() and not a.on_break and not a.greeting_ceo and a != touched)
	var busy := b.bench.size() - free.size()
	# Up to all but one on break; standing characters first, so dozing seats don't use every turn.
	var standing: Array = free.filter(func(a: TownActor) -> bool: return not a.sitting)
	if free.is_empty() or busy >= maxi(1, b.bench.size() - 1):
		return
	var a: TownActor = (free if standing.is_empty() or randf() < 0.25 else standing).pick_random()
	# Seated characters doze; standing ones do anything, a chat only with someone else standing free.
	var choices: Array[String] = []
	choices.assign(["doze"] if a.sitting else PASTIMES)
	var partner: TownActor = null
	for o: TownActor in standing:
		if o != a and (partner == null or o.spot().distance_to(a.spot()) < partner.spot().distance_to(a.spot())):
			partner = o
	if partner == null:
		choices.erase("chat")
	if not a.sitting and only_pastime != "":
		choices.assign(choices.filter(func(c: String) -> bool: return c == only_pastime))
	if choices.is_empty():
		return
	var pastime: String = choices.pick_random()
	var length := randf_range(10.0, 25.0)
	if pastime == "chat":
		_chat(a, partner, length)
	else:
		_take_break(a, pastime, length)


# --- Pastimes -------------------------------------------------------------------------------

## A point in front of the character's chest, in its own space (the root is not scaled).
static func _hands(y: float = 0.2, forward: float = 0.14) -> Vector3:
	return Vector3(0, y, forward) * (Layout.CHARACTER_SCALE / 0.75)


static func _ball(radius: float, color: String) -> MeshInstance3D:
	var k := Layout.CHARACTER_SCALE / 0.75
	var m := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius * k
	mesh.height = 2.0 * radius * k
	mesh.radial_segments = 16
	mesh.rings = 8
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.roughness = 0.6
	m.material_override = mat
	return m


## A puzzle cube: six faces, each its own color.
static func _cube() -> Node3D:
	var s := 0.11 * Layout.CHARACTER_SCALE / 0.75
	var cube := Node3D.new()
	var faces := [[Vector3(0, 0, 1), Vector3.ZERO], [Vector3(0, 0, -1), Vector3(0, PI, 0)],
		[Vector3(1, 0, 0), Vector3(0, PI / 2.0, 0)], [Vector3(-1, 0, 0), Vector3(0, -PI / 2.0, 0)],
		[Vector3(0, 1, 0), Vector3(-PI / 2.0, 0, 0)], [Vector3(0, -1, 0), Vector3(PI / 2.0, 0, 0)]]
	for i in faces.size():
		var face := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(s, s)
		face.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(CUBE_COLORS[i])
		mat.roughness = 0.6
		face.material_override = mat
		face.position = (faces[i][0] as Vector3) * s / 2.0
		face.rotation = faces[i][1]
		cube.add_child(face)
	return cube


## Upright in front of the face, its light blue screen toward the eyes.
static func _phone() -> Node3D:
	var k := Layout.CHARACTER_SCALE / 0.75
	var phone := TownScene.box(Vector3(0.07, 0.12, 0.016) * k, "#3A3F4B", Vector3.ZERO)
	phone.add_child(TownScene.box(Vector3(0.058, 0.1, 0.002) * k, "#8FD3FF", Vector3(0, 0, -0.009) * k))
	return phone


func _take_break(a: TownActor, pastime: String, length: float) -> void:
	a.on_break = true
	a.break_ends = Time.get_ticks_msec() + int(length * 1000.0)
	a.enqueue(func() -> void: await _break(a, pastime))


func _break(a: TownActor, pastime: String) -> void:
	var k := Layout.CHARACTER_SCALE / 0.75
	var props: Array[Node3D] = []
	# Arms down (the standing pose) for all but the cube: the arms-out holding poses with something
	# dark in the hands read as aiming.
	match pastime:
		"juggle":
			a.play("idle")
			for c: String in JUGGLE_COLORS:
				props.append(_ball(0.045, c))
		"cube":
			a.play("holding-both")
			props.append(_cube())
		"toss":
			a.play("idle")
			props.append(_ball(0.05, "#F7F7F7"))
		"phone":
			a.play("idle")
			props.append(_phone())
	if is_instance_valid(a.root):
		for e in props:
			a.root.add_child(e)
	var start := Time.get_ticks_msec()
	var turn := 0
	while Time.get_ticks_msec() < a.break_ends and is_instance_valid(a.root) and scene.is_inside_tree():
		var t := float(Time.get_ticks_msec() - start) / 1000.0
		match pastime:
			"juggle":
				# Three balls on a loop over the hands, a third of a turn apart.
				for i in props.size():
					var phase := t * 4.2 + float(i) * TAU / 3.0
					props[i].position = _hands(0.22, 0.16) + Vector3(0.14 * k * cos(phase), 0.2 * k * (1.0 + sin(phase)), 0)
			"cube":
				props[0].position = _hands(0.24, 0.17)
				var step := int(t / 0.7)
				if step != turn: # a quarter turn about a random axis, now and then
					turn = step
					var axis: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK].pick_random()
					var to: Quaternion = props[0].quaternion * Quaternion(axis, PI / 2.0)
					props[0].create_tween().tween_property(props[0], "quaternion", to, 0.25)
			"toss":
				props[0].position = _hands(0.22, 0.14) + Vector3(0.1 * k, 0.5 * k * absf(sin(t * 2.4)), 0)
			"phone":
				props[0].position = _hands(0.4, 0.13)
				props[0].rotation = Vector3(-0.25, 0, 0) # tipped back a little, as when reading
			"doze":
				a.idle_bubble = ["z", "zZ", "zZZ"][int(t / 0.8) % 3]
		await scene.get_tree().process_frame
	for e in props:
		if is_instance_valid(e):
			e.queue_free()
	a.idle_bubble = null
	a.on_break = false
	if not is_instance_valid(a.root) or not scene.is_inside_tree():
		return
	_end_break(a)
	if pastime == "doze" and a.greeting_ceo:
		# Woken by the CEO: a start, shown for a moment.
		a.idle_bubble = "!"
		await scene.wait(1.2)
		a.idle_bubble = null


## Two characters turn to each other and take turns saying "• • •".
func _chat(a: TownActor, b: TownActor, length: float) -> void:
	var ends := Time.get_ticks_msec() + int(length * 1000.0)
	a.chat_partner = b
	b.chat_partner = a
	# Both are on the break before either starts: an action starts at once when queued, and a chat
	# ends as soon as the partner is not on the break.
	for me: TownActor in [a, b]:
		me.on_break = true
		me.break_ends = ends
	a.enqueue(func() -> void: await _chat_turns(a, b, true))
	b.enqueue(func() -> void: await _chat_turns(b, a, false))


func _chat_turns(me: TownActor, other: TownActor, first: bool) -> void:
	scene.face(me, other.spot() - me.spot())
	me.play("idle")
	var start := Time.get_ticks_msec()
	# The partner's break ending (called to work, or the CEO) ends the chat for both.
	while Time.get_ticks_msec() < me.break_ends and other.on_break and is_instance_valid(me.root) and scene.is_inside_tree():
		var mine := (int(float(Time.get_ticks_msec() - start) / 1600.0) % 2 == 0) == first
		me.speaking = mine
		await scene.get_tree().process_frame
	me.speaking = false
	me.on_break = false
	me.chat_partner = null
	if other.greeting_ceo:
		me.greeting_ceo = true # both turn to the CEO
	if is_instance_valid(me.root) and scene.is_inside_tree():
		_end_break(me)

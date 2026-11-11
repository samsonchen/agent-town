class_name TownScene
extends Node3D
## The office: blocks on one flat floor, furniture and characters. Port of the building parts of
## app/macos/Sources/AgentTown/TownScene.swift. This stage builds the blocks and places the fixed
## characters and the Chiefs of Staff; walking, calls, staff and the bench come in later stages.

signal office_resized(size: Vector2)

const EXECUTIVE := "executive"
const PITCH := deg_to_rad(62.0) ## the camera's angle above the floor
## Characters lean back toward the camera so they show their fronts on the top-down map.
const LEAN := -(PITCH - 0.2)
const BLOCK_COLORS := [["#CDD0DA", "#C3C6D1"], ["#B9CDE6", "#AFC4DF"], ["#C5DCC0", "#BAD3B4"], ["#E3CDA8", "#DBC39C"]]


class BlockNode:
	var id: String
	var name: String
	var node := Node3D.new()
	var placed := false
	var chief_slots: Dictionary = {} ## session_id -> desk slot
	var extra_desks: Dictionary = {} ## slot -> Node3D, the desks set down past the first


class Actor:
	var id: String
	var kind: String ## ceo, dispatcher, inspector, chief
	var base: String
	var name: String
	var block_id: String
	var home: Vector2
	var root := Node3D.new()
	var model: Node3D
	var player: AnimationPlayer

	func play(clip: String) -> void:
		if player != null and player.has_animation(clip) and player.current_animation != clip:
			player.play(clip, 0.15)

	## A point `above` meters over the top of the head, following the lean.
	func head(above: float = 0.0) -> Vector3:
		return root.global_position + Basis(Vector3.RIGHT, TownScene.LEAN) * Vector3(0, 0.67 * Layout.CHARACTER_SCALE + above, 0)


var labels: TownLabels
var assets := TownAssets.new()
var building: Building ## the store's building, read for names, titles and context
var office_size := Layout.office_size(1)
var blocks: Dictionary = {} ## id -> BlockNode
var block_order: Array[String] = []
var actors: Dictionary = {} ## id -> Actor

var _ground := Node3D.new()
var _ground_size := Vector2.ZERO
var _color_index := 0


func _init(p_labels: TownLabels, p_building: Building) -> void:
	labels = p_labels
	building = p_building


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
	for spec: Array in [["ceo", fixed["ceo"], labels.ceo(), Layout.CEO_HOME],
			["dispatcher", fixed["dispatcher"], labels.dispatcher(), Layout.DISPATCHER_HOME],
			["inspector", fixed["inspector"], labels.inspector(), Layout.INSPECTOR_HOME]]:
		var a := make_actor(spec[0], spec[0], spec[1], "", exec, spec[2], spec[3])
		a.play("idle")


# --- Changes --------------------------------------------------------------------------------

func handle(change: Dictionary) -> void:
	match change["kind"]:
		"blockAdded":
			_add_block(change["projectId"])
		"blockRemoved":
			_remove_block(change["projectId"])
		"chiefArrived":
			_chief_arrived(change["projectId"], change["sessionId"])
		"chiefLeft":
			_chief_left(change["projectId"], change["sessionId"])


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


func _remove_block(p: String) -> void:
	if not blocks.has(p):
		return
	var b: BlockNode = blocks[p]
	for id: String in actors.keys():
		if (actors[id] as Actor).block_id == p:
			actors.erase(id)
	blocks.erase(p)
	block_order.erase(p)
	b.node.queue_free()
	relayout()


func _chief_arrived(p: String, s: String) -> void:
	if not blocks.has(p):
		_add_block(p)
	var b: BlockNode = blocks[p]
	var slot := 0
	while b.chief_slots.values().has(slot):
		slot += 1
	b.chief_slots[s] = slot
	if slot > 0 and slot < Layout.MAX_DESKS:
		# A second session's Chief of Staff sets a desk down in the back row (carried in: a later stage).
		var desk := _place("desk", b.node, Vector2(Layout.desk_x(slot), Layout.CHIEF_DESK_Z))
		_telephone(b.node, Vector2(Layout.desk_x(slot) + 0.28, Layout.CHIEF_DESK_Z + 0.02), desk)
		b.extra_desks[slot] = desk
	var a := make_actor(s, "chief", _chief_base(b), assets.catalog["chiefOfStaff"]["color"], b, labels.chief_of_staff(),
		Layout.chief_spot(slot))
	a.play("idle")


func _chief_left(p: String, s: String) -> void:
	if actors.has(s):
		(actors[s] as Actor).root.queue_free()
		actors.erase(s)
	if blocks.has(p):
		var b: BlockNode = blocks[p]
		var slot: Variant = b.chief_slots.get(s)
		b.chief_slots.erase(s)
		if slot != null and b.extra_desks.has(slot):
			(b.extra_desks[slot] as Node3D).queue_free()
			b.extra_desks.erase(slot)


## Chiefs of Staff in one block get different base characters.
func _chief_base(b: BlockNode) -> String:
	var excluded: Array = assets.catalog["chiefOfStaff"]["exclude"]
	var all := assets.character_names().filter(func(c: String) -> bool: return not excluded.has(c))
	var in_block: Array = []
	for s: String in b.chief_slots:
		if actors.has(s):
			in_block.append((actors[s] as Actor).base)
	var start := absi(hash(b.id)) % all.size()
	for i in all.size():
		var c: String = all[(start + i) % all.size()]
		if not in_block.has(c):
			return c
	return all[start]


# --- Building -------------------------------------------------------------------------------

func make_actor(id: String, kind: String, base: String, outfit: String, b: BlockNode, display_name: String, spot: Vector2) -> Actor:
	var a := Actor.new()
	a.id = id
	a.kind = kind
	a.base = base
	a.name = display_name
	a.block_id = b.id
	a.home = spot
	a.model = assets.character(base, outfit)
	a.model.scale = Vector3.ONE * Layout.CHARACTER_SCALE
	a.root.add_child(a.model)
	var players := a.model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		a.player = players[0]
		for clip: String in ["idle", "walk", "sit"]:
			if a.player.has_animation(clip):
				a.player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
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
	a.root.position = Vector3(spot.x, Layout.FLOOR_THICKNESS, spot.y)
	b.node.add_child(a.root)
	face(a, Vector2(0, 1))
	actors[id] = a
	return a


func face(a: Actor, dir: Vector2) -> void:
	if dir.length() < 0.001:
		return
	a.root.basis = Basis(Vector3.RIGHT, LEAN) * Basis(Vector3.UP, atan2(dir.x, dir.y))


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
	var img := Image.create(cols * px, rows * rh, false, Image.FORMAT_RGBA8)
	var c0 := Color(colors[0])
	var c1 := Color(colors[1])
	var g := Color(grout) if grout != "" else Color.TRANSPARENT
	for r in rows:
		for c in range(-1, cols + 1):
			var x := c * px + (px / 2 if brick and r % 2 == 1 else 0)
			var color := c0 if brick or (r + c + 2) % 2 == 0 else c1
			img.fill_rect(Rect2i(x, r * rh, px, rh).intersection(Rect2i(0, 0, cols * px, rows * rh)), color)
			if grout != "":
				img.fill_rect(Rect2i(x, r * rh, px, 1).intersection(Rect2i(0, 0, cols * px, rows * rh)), g)
				img.fill_rect(Rect2i(x, r * rh, 1, rh).intersection(Rect2i(0, 0, cols * px, rows * rh)), g)
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
		var box_ := _transform_to(v, relative_to) * v.get_aabb()
		out = box_ if first else out.merge(box_)
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
func _place(name: String, parent: Node3D, p: Vector2, yaw: float = 0.0, scale_: float = 1.0, on_top_of: Node3D = null) -> Node3D:
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
func _telephone(parent: Node3D, p: Vector2, desk: Node3D) -> Node3D:
	var top := bounds(desk, parent).end.y
	var k := Layout.FURNITURE_SCALE / 0.85
	var device := Node3D.new()
	device.position = Vector3(p.x, top, p.y)
	device.add_child(box(Vector3(0.16, 0.05, 0.12) * k, "#B8322F", Vector3(0, 0.025, 0) * k))
	device.add_child(box(Vector3(0.09, 0.006, 0.05) * k, "#F2EEE6", Vector3(0, 0.052, 0.025) * k))
	device.add_child(box(Vector3(0.17, 0.035, 0.045) * k, "#8E2321", Vector3(0, 0.07, -0.03) * k))
	parent.add_child(device)
	return device


func _build_executive_block(b: BlockNode) -> void:
	var f := b.node
	_floor(b, ["#9D9FDC", "#9294D4"], Layout.EXEC_DEPTH)
	_place("rugRectangle", f, Vector2(Layout.CEO_DESK.x, Layout.CEO_DESK.y - 0.25), 0.0, 0.9)
	var desk := _place("desk", f, Layout.CEO_DESK)
	_place("computerScreen", f, Vector2(Layout.CEO_DESK.x - 0.1, Layout.CEO_DESK.y - 0.05), 0.0, 0.8, desk)
	_telephone(f, Vector2(Layout.CEO_DESK.x + 0.28, Layout.CEO_DESK.y + 0.02), desk)
	# Reception, where the Inspector stands.
	_place("kitchenBar", f, Vector2(Layout.RECEPTION_DESK.x - 0.19, Layout.RECEPTION_DESK.y))
	var bar := _place("kitchenBar", f, Vector2(Layout.RECEPTION_DESK.x + 0.19, Layout.RECEPTION_DESK.y))
	_telephone(f, Vector2(Layout.RECEPTION_DESK.x + 0.24, Layout.RECEPTION_DESK.y + 0.02), bar)
	# The schedule board on the back wall, and the Dispatcher's desk with the radio.
	var w := Layout.BOARD_WIDTH
	f.add_child(box(Vector3(w, 0.55, 0.04), "#2E5244", Vector3(Layout.BOARD_CENTER.x, 0.42, Layout.BOARD_CENTER.y)))
	f.add_child(box(Vector3(w + 0.1, 0.05, 0.05), "#7A5A3A", Vector3(Layout.BOARD_CENTER.x, 0.16, Layout.BOARD_CENTER.y)))
	var ddesk := _place("desk", f, Layout.DISPATCHER_DESK)
	_place("radio", f, Vector2(Layout.DISPATCHER_DESK.x + 0.25, Layout.DISPATCHER_DESK.y), 0.0, 1.0, ddesk)
	_place("pottedPlant", f, Vector2(0.3, 0.3))
	_place("pottedPlant", f, Vector2(6.7, 0.3))


func _build_project_block(b: BlockNode, colors: Array) -> void:
	var f := b.node
	_floor(b, colors)
	# One Chief of Staff desk with a telephone; the rest of the back row is open floor.
	var x0 := Layout.desk_x(0)
	var desk := _place("desk", f, Vector2(x0, Layout.CHIEF_DESK_Z))
	_place("computerScreen", f, Vector2(x0 - 0.1, Layout.CHIEF_DESK_Z - 0.05), 0.0, 0.8, desk)
	_telephone(f, Vector2(x0 + 0.28, Layout.CHIEF_DESK_Z + 0.02), desk)
	for slot in Layout.MAX_DESKS:
		var x := Layout.desk_x(slot)
		var sd := _place("desk", f, Vector2(x, Layout.STAFF_DESK_Z))
		_place("laptop", f, Vector2(x, Layout.STAFF_DESK_Z - 0.03), 0.0, 1.0, sd)
	# Server room (front left): racks along the back, for operators.
	f.add_child(box(Vector3(3.3, 0.006, 1.95), "#7D8590", Vector3(1.8, Layout.FLOOR_THICKNESS + 0.003, 4.275)))
	for i in Layout.CONSOLES:
		_place("speaker", f, Vector2(Layout.rack_x(i) - 0.15, Layout.RACK_Z), 0.0, 1.4)
		_place("speaker", f, Vector2(Layout.rack_x(i) + 0.15, Layout.RACK_Z), 0.0, 1.4)
	# Resource bench (front right): a lounge.
	_place("rugRound", f, Layout.BENCH_CENTER, 0.0, 1.3)
	_place("loungeSofaLong", f, Vector2(Layout.BENCH_CENTER.x, 3.5))
	_place("tableCoffee", f, Vector2(Layout.BENCH_CENTER.x, 4.3))
	var table := _place("sideTable", f, Layout.SPEAKER_SPOT)
	_place("speaker", f, Layout.SPEAKER_SPOT, 0.0, 0.8, table)
	_place("kitchenCoffeeMachine", f, Vector2(6.75, 3.45))
	_place("pottedPlant", f, Vector2(6.75, 5.1))
	_place("pottedPlant", f, Vector2(6.75, 0.3))


# --- Labels ---------------------------------------------------------------------------------

## What the label overlay draws: each item {"anchor": Vector3, "lines": [[text, style]]}, plus
## block signs and the context bars ({"meter": true, "anchor", "row", "fraction", "text"}).
func label_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for a: Actor in actors.values():
		items.append({"anchor": a.head(0.04), "lines": [[a.name, "name"]]})
	for id in block_order:
		var b: BlockNode = blocks[id]
		var o := b.node.position
		var edge := Layout.EXEC_DEPTH if id == EXECUTIVE else 0.0
		items.append({"anchor": o + Vector3(Layout.BLOCK_WIDTH / 2.0, 0, edge), "lines": [[_sign(b), "sign"]]})
		if id != EXECUTIVE:
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
	var head := block.name if block.name != block.project_id else ""
	var parts: Array[String] = []
	if head != "":
		parts.append(head)
	parts.append(" · ".join(titles))
	return " · ".join(parts)

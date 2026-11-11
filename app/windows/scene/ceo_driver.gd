class_name CeoDriver
extends Node
## The CEO under the user's control (spec: walking the CEO): the arrow keys walk the CEO around the
## office, sliding along furniture, and H walks the CEO back to the desk around it. The view follows
## (`moved`), and away from the desk the CEO's calls go to a mobile phone.
## Port of the driving part of app/macos/Sources/AgentTown/TownScene+CEO.swift; clicks, talking
## and the tips come next.

signal moved(spot: Vector2) ## the CEO's spot on the office floor (x, z), for the camera
signal away_changed(away: bool)

const ARROWS := {KEY_LEFT: Vector2(-1, 0), KEY_RIGHT: Vector2(1, 0), KEY_DOWN: Vector2(0, 1), KEY_UP: Vector2(0, -1)}
const RADIUS := 0.15
const TOUCH_DISTANCE := 1.1 ## close enough to talk, across a desk included
const AWAY_DISTANCE := 0.3 ## the CEO counts as away once this far from the desk

var scene: TownScene
var mobile: TownPhone
var away := false

var _held: Dictionary = {} ## arrow keycode -> true while held
var _trip: Array[Vector2] = [] ## points still to walk to, on the office floor
var _arrived := Callable()
var _stalls := 0
var _moving := false


func _init(p_scene: TownScene) -> void:
	scene = p_scene


func ceo() -> TownActor:
	return scene.actors.get("ceo")


## A key from the window. Returns true when the key was used.
func key(code: int, pressed: bool) -> bool:
	if code == KEY_H:
		if pressed:
			send_home()
		return true
	if not ARROWS.has(code):
		return false
	if pressed:
		_held[code] = true
		_trip.clear() # the user takes over from a walk home
	else:
		_held.erase(code)
	return true


## The window lost focus; key releases will not come.
func release_keys() -> void:
	_held.clear()


## The CEO's spot on the office floor (x, z), across blocks.
static func world_spot(a: TownActor) -> Vector2:
	return Vector2(a.root.global_position.x, a.root.global_position.z)


func _exec_origin() -> Vector2:
	var exec: BlockNode = scene.blocks[TownScene.EXECUTIVE]
	return Vector2(exec.node.position.x, exec.node.position.z)


func _process(delta: float) -> void:
	var c := ceo()
	if c == null:
		return
	var dt := minf(0.05, delta)
	var dir := Vector2.ZERO
	for k: int in _held:
		dir += ARROWS[k]
	if dir.length() > 0.01:
		_step(c, dir.normalized(), Layout.WALK_SPEED * dt)
		_moving = true
		return
	if not _trip.is_empty():
		_follow_trip(c, dt)
		_moving = true
		return
	if _moving:
		_moving = false
		_stopped(c)


func _follow_trip(c: TownActor, dt: float) -> void:
	# On the desk phone the CEO finishes the call before walking.
	if c.on_call and c.phone != mobile:
		return
	var target := _trip[0]
	var d := target - world_spot(c)
	var length := d.length()
	if length < 0.01:
		_trip.pop_front()
		if _trip.is_empty():
			_finish_trip(c)
		return
	_step(c, d / length, minf(length, Layout.WALK_SPEED * maxf(1.0 / 120.0, dt)))
	# Pressed against furniture for a while: skip to the next point.
	_stalls = _stalls + 1 if (target - world_spot(c)).length() >= length - 0.001 else 0
	if _stalls > 10:
		_stalls = 0
		_trip.pop_front()
		if _trip.is_empty():
			_finish_trip(c)


func _finish_trip(c: TownActor) -> void:
	_moving = false
	_stopped(c)
	if not c.on_call and _arrived.is_valid():
		_arrived.call()
	_arrived = Callable()


## Moves the CEO up to `distance` along `dir`, sliding along furniture it bumps into.
func _step(c: TownActor, dir: Vector2, distance: float) -> void:
	if c.on_call and c.phone != mobile:
		return # on the desk phone the CEO stays at the desk until hanging up
	if not c.steering:
		c.steering = true
		c.sitting = false
	scene.face(c, dir)
	c.play("walk")
	var from := world_spot(c)
	var to := from + dir * distance
	var rects := scene.world_obstacles()
	var size := scene.office_size
	var next := from
	if not FloorPlan.blocked(to, from, size, rects, RADIUS):
		next = to
	elif dir.x != 0 and not FloorPlan.blocked(Vector2(to.x, from.y), from, size, rects, RADIUS):
		next = Vector2(to.x, from.y)
	elif dir.y != 0 and not FloorPlan.blocked(Vector2(from.x, to.y), from, size, rects, RADIUS):
		next = Vector2(from.x, to.y)
	_place(c, next)
	_moved()


## Puts the CEO (and its shadow) at a spot on the office floor.
func _place(c: TownActor, spot: Vector2) -> void:
	var local := spot - _exec_origin()
	c.root.position = Vector3(local.x, Layout.FLOOR_THICKNESS, local.y)
	if c.shadow != null and is_instance_valid(c.shadow):
		c.shadow.position = Vector3(local.x, Layout.FLOOR_THICKNESS + 0.003, local.y)


## The CEO stopped walking.
func _stopped(c: TownActor) -> void:
	c.steering = false
	if c.on_call:
		c.play("holding-right")
		return
	if not away:
		# Close enough to the desk: settle in the chair spot.
		_place(c, Layout.CEO_HOME + _exec_origin())
		scene.face(c, c.home_facing)
		_moved()
	else:
		var other := touched()
		if other != null:
			scene.face(c, world_spot(other) - world_spot(c)) # turn to the one being talked to
	c.settle()


## Updates what follows the CEO: the camera, whether it is away, and which phone it answers.
func _moved() -> void:
	var c := ceo()
	var local := world_spot(c) - _exec_origin()
	var now_away := local.distance_to(Layout.CEO_HOME) > AWAY_DISTANCE
	if now_away != away:
		away = now_away
		away_changed.emit(away)
	sync_phone()
	moved.emit(world_spot(c))


## At the desk the CEO answers the desk phone; away from it, the mobile. Never mid-call.
func sync_phone() -> void:
	var c := ceo()
	if c == null or c.on_call:
		return
	var want: TownPhone = mobile if away else scene.exec_phones["ceo"]
	if c.phone != want:
		c.phone = want
		if not away and not c.steering:
			# Came home during a mobile call: back in the chair spot now that it is over.
			_place(c, Layout.CEO_HOME + _exec_origin())
			scene.face(c, c.home_facing)
	if mobile != null and is_instance_valid(mobile.device):
		mobile.device.visible = c.phone == mobile


## H: the CEO walks back to the desk around the furniture.
func send_home() -> void:
	if not away or not _held.is_empty():
		return
	walk_to(Layout.CEO_HOME + _exec_origin())


## Walks the CEO to a spot on the office floor (x, z), finding a way around furniture.
## `arrived` runs once the CEO has stopped there.
func walk_to(goal: Vector2, arrived: Callable = Callable()) -> void:
	var c := ceo()
	if c == null:
		return
	_trip = FloorPlan.find_path(world_spot(c), goal, scene.office_size, scene.world_obstacles(), RADIUS)
	_arrived = arrived
	_stalls = 0


## The CEO's mobile, held in the hand while away from the desk.
func make_mobile() -> void:
	var c := ceo()
	var k := Layout.CHARACTER_SCALE / 0.75
	var holder := Node3D.new()
	holder.position = Vector3(0.19, 0.17, 0.12) * k
	var phone := TownScene.box(Vector3(0.1, 0.014, 0.058) * k, "#3A3F4B", Vector3.ZERO)
	phone.add_child(TownScene.box(Vector3(0.086, 0.002, 0.048) * k, "#8FD3FF", Vector3(0, 0.008, 0) * k))
	holder.add_child(phone)
	c.root.add_child(holder)
	holder.visible = false
	mobile = TownPhone.new(holder, phone)
	mobile.tag_lift = -0.22 # below the face, by the hand


## The character the CEO is touching: the nearest one within reach, while the CEO is away.
func touched() -> TownActor:
	var c := ceo()
	if c == null or not (away or c.steering):
		return null
	var at := world_spot(c)
	var best: TownActor = null
	var best_d := INF
	for a: TownActor in scene.actors.values():
		if a == c or not is_instance_valid(a.root) or not a.root.is_inside_tree():
			continue
		var d := world_spot(a).distance_to(at)
		if d < TOUCH_DISTANCE and d < best_d:
			best = a
			best_d = d
	return best

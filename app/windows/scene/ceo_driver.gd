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
var _visitee: TownActor = null ## the character the user clicked; the CEO talks to them once there
var _user_moves := 0 ## counts arrow keys and clicks; a change calls off the walk home when all work is done


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
		_visitee = null
		_user_moves += 1
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
	_visitee = null
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


## The character the CEO is touching: the one clicked, once within reach, else the nearest one
## within reach, while the CEO is away.
func touched() -> TownActor:
	var c := ceo()
	if c == null or not (away or c.steering):
		return null
	var at := world_spot(c)
	if _visitee != null and is_instance_valid(_visitee.root) and _visitee.root.is_inside_tree() \
			and world_spot(_visitee).distance_to(at) < TOUCH_DISTANCE:
		return _visitee
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


# --- Clicks ---------------------------------------------------------------------------------

## A click in the office at `point` (window pixels). On a character, the CEO walks over to them;
## on the CEO's desk, the CEO goes back to it, as with H; anywhere else on the floor, the CEO walks
## there. Nothing happens while the arrow keys drive.
func click(point: Vector2, camera: Camera3D) -> void:
	var c := ceo()
	if c == null or not _held.is_empty():
		return
	_user_moves += 1
	var a := actor_at(point, camera)
	if a != null:
		visit(a) # a click on the CEO does nothing
		return
	var hit: Variant = floor_at(point, camera)
	if hit == null:
		return
	var spot: Vector2 = hit
	# The CEO's desk and the spot behind it (a click on the desk top lands on the floor behind it).
	var o := _exec_origin()
	var desk := Rect2(Vector2(Layout.CEO_DESK.x - 0.6, 0) + o, Vector2(1.2, Layout.CEO_DESK.y + 0.35))
	if FloorPlan.inside(spot, desk, 0.0):
		send_home()
		return
	# Off the floor: the nearest point on it; inside furniture: the nearest free spot beside it.
	var goal: Variant = FloorPlan.free_spot(spot, scene.office_size, scene.world_obstacles(), RADIUS)
	if goal == null or (goal as Vector2).distance_to(world_spot(c)) <= 0.05:
		return
	_visitee = null
	walk_to(goal)


## The spot on the office floor (x, z) drawn at window point `point`, through the tilted camera.
static func floor_at(point: Vector2, camera: Camera3D) -> Variant:
	var from := camera.project_ray_origin(point)
	var dir := camera.project_ray_normal(point)
	var hit: Variant = Plane(Vector3.UP, Layout.FLOOR_THICKNESS).intersects_ray(from, dir)
	return Vector2((hit as Vector3).x, (hit as Vector3).z) if hit != null else null


## The character drawn under `point`, if any: the body, or the tags just above the head.
## The one nearest the camera (farthest down the screen) wins.
func actor_at(point: Vector2, camera: Camera3D) -> TownActor:
	var best: TownActor = null
	var best_depth := -INF
	for a: TownActor in scene.actors.values():
		if not is_instance_valid(a.root) or not a.root.is_inside_tree():
			continue
		var feet := camera.unproject_position(a.root.global_position)
		var top := camera.unproject_position(a.head(0.0))
		var half := maxf(14.0, absf(feet.y - top.y) * 0.45)
		if absf(point.x - feet.x) > half or point.y > feet.y + 6.0 or point.y < top.y - 24.0:
			continue
		var depth := world_spot(a).y
		if depth > best_depth:
			best = a
			best_depth = depth
	return best


## A click on a character: the CEO walks to a free spot beside them (across their desk if need
## be) and turns to them, and they say how their work is going.
func visit(a: TownActor) -> void:
	var c := ceo()
	if c == null or a == c or not _held.is_empty():
		return
	var target := world_spot(a)
	var from := world_spot(c)
	var rects := scene.world_obstacles()
	var goal: Variant = null
	var best := INF
	for r: float in [0.45, 0.7, 0.95]:
		for i in 16:
			var t := float(i) / 16.0 * TAU
			var p := target + r * Vector2(cos(t), sin(t))
			if FloorPlan.off_floor(p, scene.office_size, RADIUS) > 0.0:
				continue
			var clear := true
			for rect in rects:
				if FloorPlan.inside(p, rect, RADIUS):
					clear = false
					break
			var cost := p.distance_to(from) + 2.0 * p.distance_to(target)
			if clear and cost < best:
				goal = p
				best = cost
	if goal == null:
		return
	_visitee = a
	if from.distance_to(target) < TOUCH_DISTANCE and from.distance_to(goal) < 0.2:
		scene.face(c, target - from) # already there
		return
	walk_to(goal, func() -> void:
		if is_instance_valid(a.root):
			scene.face(c, world_spot(a) - world_spot(c)))


# --- Going home on its own -------------------------------------------------------------------

## The last task ended: once the report calls are over, the CEO stops talking to whoever it was
## with and walks back to the desk. New work, a click or an arrow key calls it off; a CEO the user
## moves afterwards stays where it is put (spec: walking the CEO).
func home_when_all_done() -> void:
	if not away:
		return
	var moves := _user_moves
	await scene.wait(1.5) # let the report call start
	for i in 120:
		if moves != _user_moves or not scene.all_work_done() or not away or not _held.is_empty():
			return
		var c := ceo()
		if c != null and (c.on_call or not scene.staff.pending_calls.is_empty()):
			await scene.wait(0.5)
			continue
		_visitee = null
		send_home()
		return


## The last project block went: nothing is left to visit, so the CEO walks back to the seat. A CEO
## who was in another block shows up on the path at the nearest edge of the executive office and
## walks in from there.
func back_if_office_empty() -> void:
	var c := ceo()
	if c == null or not away or scene.block_order.size() != 1:
		return
	_held.clear()
	_trip.clear()
	_moving = false
	c.steering = false
	var origin := _exec_origin()
	var local := world_spot(c) - origin
	var edge := 0.35 # on the path, just off the carpet
	var entry := Vector2(clampf(local.x, -edge, Layout.BLOCK_WIDTH + edge), clampf(local.y, -edge, Layout.EXEC_DEPTH + edge))
	if not entry.is_equal_approx(local):
		_place(c, origin + entry)
		_moved()
	send_home()

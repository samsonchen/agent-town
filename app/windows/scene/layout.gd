class_name Layout
extends RefCounted
## World layout, in meters, on one flat plane (y up). x runs right and z runs down the screen.
## The office is the executive block, a strip along the top, then one block per open project in a
## column below it, with a path between them. Positions inside a block are local to its top-left
## corner and written as Vector2(x, z). Port of app/macos/Sources/AgentTown/Layout.swift.

const BLOCK_WIDTH := 7.0
const BLOCK_DEPTH := 5.4
const GAP := 1.4 ## the path between blocks
const MARGIN := 0.9 ## the path around the whole office
const FURNITURE_SCALE := 0.85
const CHARACTER_SCALE := 0.75
const FLOOR_THICKNESS := 0.02
const WALK_SPEED := 2.34 ## m/s

# Executive block: as wide as a project block and a third as deep, with the CEO, the Inspector and
# the Dispatcher in one row along the back, each behind a desk.
const EXEC_DEPTH := BLOCK_DEPTH / 3.0
const EXEC_ROW_Z := 0.55
const EXEC_DESK_Z := 1.0
const CEO_DESK := Vector2(1.3, EXEC_DESK_Z)
const CEO_HOME := Vector2(1.3, EXEC_ROW_Z)
const RECEPTION_DESK := Vector2(3.5, EXEC_DESK_Z)
const INSPECTOR_HOME := Vector2(3.5, EXEC_ROW_Z)
const DISPATCHER_DESK := Vector2(5.7, EXEC_DESK_Z)
const DISPATCHER_HOME := Vector2(5.7, EXEC_ROW_Z)
const BOARD_CENTER := Vector2(4.6, 0.12) ## the schedule board, on the back wall
const BOARD_WIDTH := 1.1

# Project block, back to front: the Chiefs of Staff's row, the staff row, then the server room
# (left) and the resource bench (right).
const MAX_DESKS := 5
const FIRST_DESK_X := 1.1
const DESK_GAP := 1.2
const CHIEF_DESK_Z := 1.0
const STAFF_DESK_Z := 2.35
const LANES: Array[float] = [0.55, 1.6, 2.95] ## walkways across the block
const SIDE_LANES: Array[float] = [0.3, BLOCK_WIDTH - 0.3]
const HOT_DESK_X := 3.85

# Server room: racks along the back, operators facing them.
const CONSOLES := 4
const RACK_Z := 3.55
const SERVER_ROOM_LABEL := Vector2(1.8, 5.1)

# Resource bench: a sofa, a coffee table and standing spots around it.
const BENCH_CENTER := Vector2(5.4, 4.2)
const SPEAKER_SPOT := Vector2(4.05, 3.45) ## the bench speaker, on a side table left of the sofa
## How far a seated character is lifted onto the sofa cushion: the sit pose puts the hips at floor
## height, behind the feet, which left the body inside the seat.
const BENCH_SEAT_LIFT := 0.1
const SOFA_FRONT_Z := 3.95 ## in front of the sofa, between it and the coffee table

## Chiefs of Staff come in from the path on the block's left, along the back walkway; bench
## characters along the front walkway.
const ENTRANCE := Vector2(-GAP / 2.0, 0.55)
const WORKER_ENTRANCE := Vector2(-GAP / 2.0, 2.95)


static func desk_x(slot: int) -> float:
	return FIRST_DESK_X + float(slot % MAX_DESKS) * DESK_GAP


## Where a Chief of Staff stands at desk `slot` (behind the desk, facing the viewer).
static func chief_spot(slot: int) -> Vector2:
	return Vector2(desk_x(slot), LANES[0])


## Where someone stands to talk to the Chief of Staff at desk `slot`, across the desk.
static func chief_visitor(slot: int) -> Vector2:
	return Vector2(desk_x(slot), LANES[1])


## Staff desks; past the last desk, staff work standing at the hot desks between the server room and the bench.
static func staff_spot(slot: int) -> Vector2:
	if slot < MAX_DESKS:
		return Vector2(desk_x(slot), 1.95)
	return Vector2(HOT_DESK_X - 0.3, 3.45 + float((slot - MAX_DESKS) % 4) * 0.5)


static func staff_visitor(slot: int) -> Vector2:
	return Vector2(desk_x(slot), 2.8) if slot < MAX_DESKS else staff_spot(slot) + Vector2(0.55, 0)


static func rack_x(i: int) -> float:
	return 0.65 + float(i) * 0.75


static func operator_spot(slot: int) -> Vector2:
	return Vector2(rack_x(slot), 4.1) if slot < CONSOLES else Vector2(rack_x(slot % CONSOLES), 4.75)


## The bench: [spot, sitting].
static func bench_spots() -> Array:
	# On the sofa's two cushions, between its arms.
	return [[Vector2(5.2, 3.72), true], [Vector2(5.6, 3.72), true],
		[Vector2(4.4, 4.45), false], [Vector2(6.4, 4.45), false], [Vector2(4.9, 4.95), false], [Vector2(5.9, 4.95), false],
		[Vector2(4.2, 5.1), false], [Vector2(6.6, 5.1), false]]


## The gaps between desks, and the side lanes, where characters cross from one walkway to another.
static func crossings() -> Array[float]:
	var out: Array[float] = SIDE_LANES.duplicate()
	for i in MAX_DESKS - 1:
		out.append(FIRST_DESK_X + DESK_GAP * (float(i) + 0.5))
	return out


## A walking path from `a` to `b` inside a block, along the walkways. The sofa seats are reached
## from the front: down beside the sofa, across in front of it, and back onto the seat; leaving a
## seat is the same the other way. Otherwise the walk from the walkway went straight through the sofa.
static func route(a: Vector2, b: Vector2) -> Array[Vector2]:
	if is_seat(b) and not is_seat(a):
		var side := Vector2(sofa_side_x(b), SOFA_FRONT_Z)
		var pts: Array[Vector2] = walkways(a, side)
		pts.append_array([Vector2(b.x, SOFA_FRONT_Z), b] as Array[Vector2])
		return _clean(pts, a)
	if is_seat(a) and not is_seat(b):
		var side := Vector2(sofa_side_x(a), SOFA_FRONT_Z)
		var pts: Array[Vector2] = [Vector2(a.x, SOFA_FRONT_Z), side]
		pts.append_array(walkways(side, b))
		return _clean(pts, a)
	return walkways(a, b)


## A sofa seat on the bench (block-local).
static func is_seat(p: Vector2) -> bool:
	for s: Array in bench_spots():
		if s[1] and (s[0] as Vector2).distance_to(p) < 0.05:
			return true
	return false


## Beside the sofa, on the seat's side.
static func sofa_side_x(seat: Vector2) -> float:
	return 4.82 if seat.x < BENCH_CENTER.x else 5.98


## Drops points closer than 2 cm to the one before (starting from `a`).
static func _clean(pts: Array[Vector2], a: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var last := a
	for p in pts:
		if p.distance_to(last) > 0.02:
			out.append(p)
			last = p
	return out


## Along the walkways: across the block on the nearest walkway, crossing between walkways at a
## side lane or a gap between desks.
static func walkways(a: Vector2, b: Vector2) -> Array[Vector2]:
	var la := _lane(a.y)
	var lb := _lane(b.y)
	var pts: Array[Vector2] = [Vector2(a.x, la)]
	if la != lb:
		# Cross between walkways at a side lane or a gap between desks, whichever is shortest.
		# From or to the path outside the block: the left side lane only. (A typed array, built
		# without the conditional expression, which would give an untyped one.)
		var cols: Array[float] = crossings()
		if a.x < 0 or b.x < 0:
			cols = [SIDE_LANES[0]]
		var best := cols[0]
		for x in cols:
			if absf(a.x - x) + absf(b.x - x) < absf(a.x - best) + absf(b.x - best):
				best = x
		pts.append(Vector2(best, la))
		pts.append(Vector2(best, lb))
	pts.append(Vector2(b.x, lb))
	pts.append(b)
	return _clean(pts, a)


static func _lane(z: float) -> float:
	var best: float = LANES[0]
	for l in LANES:
		if absf(l - z) < absf(best - z):
			best = l
	return best


## Floor depth one context bar row takes on screen at the smallest scale (22 px at 70 px/m, tilted).
## In compact view the bars are 75% as tall on an office drawn at half scale, so a row takes 1.5
## times the floor.
static func meter_row_depth() -> float:
	return 0.36 * ViewScale.text / ViewScale.world


## Room under the executive block for `rows` context bars of hidden blocks.
static func exec_extra(rows: int) -> float:
	return 0.0 if rows == 0 else float(rows) * meter_row_depth() + 0.15


## The top-left corner of block `index` (0 is the executive block; project blocks stack under it).
## `extra` is room under the executive block for the context bars of hidden blocks.
static func block_origin(index: int, extra: float = 0.0) -> Vector2:
	if index <= 0:
		return Vector2(MARGIN, MARGIN)
	return Vector2(MARGIN, MARGIN + EXEC_DEPTH + extra + GAP + float(index - 1) * (BLOCK_DEPTH + GAP))


## The whole office for `count` blocks (the executive block included), path margin included.
static func office_size(count: int, extra: float = 0.0) -> Vector2:
	var projects := maxi(0, count - 1)
	var column := 0.0 if projects == 0 else float(projects) * (GAP + BLOCK_DEPTH)
	return Vector2(2.0 * MARGIN + BLOCK_WIDTH, 2.0 * MARGIN + EXEC_DEPTH + extra + column)

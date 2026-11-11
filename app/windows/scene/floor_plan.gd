class_name FloorPlan
extends RefCounted
## Floor math for walking the CEO: the office floor, furniture footprints, free spots and paths.
## Positions are on the office floor, Vector2(x, z) in meters; a footprint is a Rect2 in the same
## space. Port of `FloorPlan` (TownCore/FloorView.swift) and the path search in
## app/macos/Sources/AgentTown/TownScene+CEO.swift.

const CELL := 0.1 ## the path grid, in meters


## `p` moved inside a floor of `size` (from the origin), keeping `radius` from the edge.
static func clamp_to(p: Vector2, size: Vector2, radius: float) -> Vector2:
	var hi := Vector2(maxf(radius, size.x - radius), maxf(radius, size.y - radius))
	return p.clamp(Vector2(radius, radius), hi)


static func inside(p: Vector2, r: Rect2, pad: float) -> bool:
	return p.x > r.position.x - pad and p.x < r.end.x + pad and p.y > r.position.y - pad and p.y < r.end.y + pad


## How far `p` is outside the floor, keeping `radius` from the edge.
static func off_floor(p: Vector2, size: Vector2, radius: float) -> float:
	return maxf(0, radius - p.x) + maxf(0, radius - p.y) + maxf(0, p.x - (size.x - radius)) + maxf(0, p.y - (size.y - radius))


## True when the CEO cannot stand at `p`. Furniture it already overlaps at `from` does not count,
## so a CEO squeezed against a desk can always step away; off the floor, any step back is allowed.
static func blocked(p: Vector2, from: Vector2, size: Vector2, rects: Array[Rect2], radius: float) -> bool:
	if off_floor(p, size, radius) > off_floor(from, size, radius) + 0.0001:
		return true
	for r in rects:
		if inside(p, r, radius) and not inside(from, r, radius):
			return true
	return false


## The nearest spot to `p` on the floor and clear of `rects`: `p` itself when free, else the
## closest free point on rings around it, up to `reach` meters away; null if none.
static func free_spot(p: Vector2, size: Vector2, rects: Array[Rect2], radius: float, reach: float = 2.0) -> Variant:
	var start := clamp_to(p, size, radius)
	var free := func(q: Vector2) -> bool:
		if not clamp_to(q, size, radius).is_equal_approx(q):
			return false
		for r in rects:
			if inside(q, r, radius):
				return false
		return true
	if free.call(start):
		return start
	var ring_r := 0.05
	while ring_r <= reach:
		var n := maxi(8, int(TAU * ring_r / 0.05))
		var best: Variant = null
		for i in n:
			var t := float(i) / n * TAU
			var q := start + ring_r * Vector2(cos(t), sin(t))
			if free.call(q) and (best == null or q.distance_to(p) < (best as Vector2).distance_to(p)):
				best = q
		if best != null:
			return best
		ring_r += 0.05
	return null


## A walking path from `a` to `b` on a 10 cm grid around the furniture, straightened where the way
## is clear. Diagonal steps never cut a corner past furniture. Returns the points after `a`.
static func find_path(a: Vector2, b: Vector2, size: Vector2, rects: Array[Rect2], radius: float) -> Array[Vector2]:
	var cols := int(size.x / CELL) + 1
	var rows := int(size.y / CELL) + 1
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, cols, rows)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(CELL / 2.0, CELL / 2.0)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var wall: PackedByteArray = []
	wall.resize(cols * rows)
	for z in rows:
		for x in cols:
			var c := Vector2((x + 0.5) * CELL, (z + 0.5) * CELL)
			# Near the start and the goal, let the CEO squeeze past (the desk spot is tight).
			if c.distance_to(a) < 0.3 or c.distance_to(b) < 0.3:
				continue
			var solid := c.x < radius or c.y < radius or c.x > size.x - radius or c.y > size.y - radius
			if not solid:
				for r in rects:
					if inside(c, r, radius):
						solid = true
						break
			if solid:
				wall[x + z * cols] = 1
				grid.set_point_solid(Vector2i(x, z), true)
	var cell := func(p: Vector2) -> Vector2i:
		return Vector2i(clampi(int(p.x / CELL), 0, cols - 1), clampi(int(p.y / CELL), 0, rows - 1))
	var cells := grid.get_point_path(cell.call(a), cell.call(b))
	if cells.is_empty():
		return [b]
	var points: Array[Vector2] = [a]
	for i in range(1, cells.size()):
		points.append(cells[i])
	points.append(b)
	# Straighten: skip every point the CEO can walk past in a straight line.
	var clear := func(p: Vector2, q: Vector2) -> bool:
		var n := maxi(1, int(p.distance_to(q) / 0.05))
		for k in n + 1:
			var c: Vector2i = cell.call(p + (q - p) * float(k) / n)
			if wall[c.x + c.y * cols] == 1:
				return false
		return true
	var out: Array[Vector2] = []
	var k := 0
	while k < points.size() - 1:
		var j := points.size() - 1
		while j > k + 1 and not clear.call(points[k], points[j]):
			j -= 1
		out.append(points[j])
		k = j
	return out

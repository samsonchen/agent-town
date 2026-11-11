extends TestSupport
## Floor math for walking the CEO: staying on the floor, furniture, free spots and paths.

const SIZE := Vector2(8.8, 10.0)
const R := 0.15


func test_clamp_keeps_the_radius_from_the_edge() -> void:
	check_eq(FloorPlan.clamp_to(Vector2(-1, 20), SIZE, R), Vector2(R, SIZE.y - R), "pulled onto the floor")
	check_eq(FloorPlan.clamp_to(Vector2(3, 4), SIZE, R), Vector2(3, 4), "already on the floor")


func test_furniture_blocks_but_lets_a_squeezed_ceo_step_away() -> void:
	var desk: Array[Rect2] = [Rect2(2, 2, 1, 0.6)]
	check(FloorPlan.blocked(Vector2(2.5, 2.3), Vector2(2.5, 1.5), SIZE, desk, R), "walking into the desk")
	check(not FloorPlan.blocked(Vector2(2.5, 1.5), Vector2(2.5, 1.4), SIZE, desk, R), "clear of the desk")
	check(not FloorPlan.blocked(Vector2(2.5, 1.84), Vector2(2.5, 1.9), SIZE, desk, R), "already touching it, stepping away")
	check(FloorPlan.blocked(Vector2(-0.5, 3), Vector2(0.3, 3), SIZE, desk, R), "off the floor")


func test_a_free_spot_is_found_beside_furniture() -> void:
	var desk: Array[Rect2] = [Rect2(2, 2, 1, 0.6)]
	check_eq(FloorPlan.free_spot(Vector2(5, 5), SIZE, desk, R), Vector2(5, 5), "a free spot is itself")
	var near: Variant = FloorPlan.free_spot(Vector2(2.5, 2.3), SIZE, desk, R)
	check(near != null, "a spot is found")
	if near != null:
		var q: Vector2 = near
		check(not FloorPlan.inside(q, desk[0], R), "clear of the desk")
		check(q.distance_to(Vector2(2.5, 2.3)) < 0.6, "close to where the click was")


func test_a_path_goes_around_a_desk() -> void:
	var desk: Array[Rect2] = [Rect2(1, 2, 3, 0.6)]
	var a := Vector2(2.5, 1.2)
	var b := Vector2(2.5, 3.6)
	var path := FloorPlan.find_path(a, b, SIZE, desk, R)
	check(path.size() >= 2, "goes around, not straight (%d points)" % path.size())
	check_eq(path.back(), b, "ends at the goal")
	var prev := a
	for p in path:
		var n := maxi(1, int(prev.distance_to(p) / 0.02))
		for k in n + 1:
			var q := prev + (p - prev) * float(k) / n
			if FloorPlan.inside(q, desk[0], 0.0):
				failures.append("the path crosses the desk at %s" % q)
				return
		prev = p

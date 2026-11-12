extends TestSupport
## Auto-scroll's choice of where to look (ViewFocusTests.swift on the Mac).

const HALF := Vector2(2, 2)


func test_nobody_moving_keeps_the_view() -> void:
	check_eq(ViewFocus.best_center([] as Array[Vector2], Vector2(5, 5), HALF), null, "no movers")


func test_the_current_view_stays_when_it_holds_the_most() -> void:
	check_eq(ViewFocus.best_center([Vector2(5, 5), Vector2(20, 20)] as Array[Vector2], Vector2(5, 5), HALF), Vector2(5, 5), "stays")


func test_moves_to_the_group_with_the_most_walkers() -> void:
	# One walker in view, three together further down.
	var c: Variant = ViewFocus.best_center([Vector2(5, 5), Vector2(10, 20), Vector2(11, 20), Vector2(10, 21)] as Array[Vector2],
		Vector2(5, 5), HALF)
	check_eq(c != null and (c as Vector2).distance_to(Vector2(31.0 / 3.0, 61.0 / 3.0)) < 0.01, true, "the group's center")


func test_moves_to_a_lone_walker_when_the_view_is_empty() -> void:
	check_eq(ViewFocus.best_center([Vector2(12, 3)] as Array[Vector2], Vector2(0, 0), HALF), Vector2(12, 3), "lone walker")

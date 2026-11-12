class_name ViewFocus
extends RefCounted
## Where auto-scroll looks (docs/spec.md: the office): the window-sized area with the most moving
## characters. Port of app/macos/Sources/TownCore/ViewFocus.swift.


## The center of a view (`half` meters each way) holding the most movers: the current view when it
## already holds as many as any, else the nearest best spot. Null when nobody moves.
static func best_center(movers: Array[Vector2], current: Vector2, half: Vector2) -> Variant:
	var here := _held(movers, current, half).size()
	var best: Variant = null
	var best_count := here
	for m in movers:
		# A view around this mover, centered on the movers it holds.
		var group := _held(movers, m, half)
		var c := Vector2.ZERO
		for g in group:
			c += g
		c /= float(group.size())
		var n := _held(movers, c, half).size()
		if n > best_count or (n == best_count and best != null and c.distance_to(current) < (best as Vector2).distance_to(current)):
			best = c
			best_count = n
	if best != null:
		return best
	return current if here > 0 else null


static func _held(movers: Array[Vector2], c: Vector2, half: Vector2) -> Array[Vector2]:
	return movers.filter(func(m: Vector2) -> bool: return absf(m.x - c.x) <= half.x and absf(m.y - c.y) <= half.y)

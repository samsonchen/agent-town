class_name BoardAndNotes
extends RefCounted
## Two small scenes on top of the office:
## - The Dispatcher's board (scene 13): one card for each active schedule, in the color of its
##   project's block, pinned when the schedule is created and taken down when it is deleted, and a
##   line on the floor under the board naming the projects. Port of TownScene+Board.swift.
## - Compaction (scene 17): the Chief of Staff goes through a stack of notes on the desk, and when
##   it ends the stack shrinks to what was kept. Port of TownScene+Compact.swift.

## Cards in a row and rows on the board. More schedules than this are counted but get no card.
const BOARD_COLUMNS := 3
const BOARD_ROWS := 2
const CARD_SIZE := Vector3(0.3, 0.22, 0.01)
const PAPER_SHEETS := 10

var scene: TownScene
var cards: Dictionary = {} ## schedule id -> Node3D card
var order: Array[String] = [] ## schedule ids, in the order their cards were pinned


func _init(p_scene: TownScene) -> void:
	scene = p_scene


# --- The Dispatcher's board -------------------------------------------------------------------

## The board's front face, block-local (the board is 0.04 deep, centered on BOARD_CENTER).
static func _board_face() -> float:
	return Layout.BOARD_CENTER.y + 0.02 + CARD_SIZE.z / 2.0


## Where card `i` sits on the board, block-local.
static func card_spot(i: int) -> Vector3:
	var col := i % BOARD_COLUMNS
	var row := i / BOARD_COLUMNS
	var step := Layout.BOARD_WIDTH / float(BOARD_COLUMNS)
	var x := Layout.BOARD_CENTER.x - Layout.BOARD_WIDTH / 2.0 + step * (float(col) + 0.5)
	return Vector3(x, 0.56 if row == 0 else 0.29, _board_face())


func _exec() -> BlockNode:
	return scene.blocks.get(TownScene.EXECUTIVE)


func schedule_added(id: String) -> void:
	var schedule: Building.Schedule = scene.building.schedules.get(id)
	if cards.has(id) or schedule == null or _exec() == null:
		return
	var b: BlockNode = scene.blocks.get(schedule.project_id)
	var card := Node3D.new()
	card.add_child(TownScene.box(CARD_SIZE, b.color if b != null and b.color != "" else "#F4EEDC", Vector3.ZERO))
	# A red pin at the top.
	card.add_child(TownScene.box(Vector3(0.03, 0.03, 0.02), "#C8463C", Vector3(0, CARD_SIZE.y / 2.0 - 0.03, 0.01)))
	cards[id] = card
	order.append(id)
	var i := order.size() - 1
	if i >= BOARD_COLUMNS * BOARD_ROWS:
		return
	card.position = card_spot(i)
	card.scale = Vector3.ONE * 0.01
	_exec().node.add_child(card)
	card.create_tween().tween_property(card, "scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT)


func schedule_removed(id: String) -> void:
	var card: Node3D = cards.get(id)
	if card == null:
		return
	cards.erase(id)
	order.erase(id)
	if card.is_inside_tree():
		var tw := card.create_tween()
		tw.tween_property(card, "scale", Vector3.ONE * 0.01, 0.25).set_ease(Tween.EASE_IN)
		tw.tween_callback(card.queue_free)
	else:
		card.queue_free()
	_layout_board()


## Moves the cards left to close a gap, and pins any that had no room before.
func _layout_board() -> void:
	var exec := _exec()
	if exec == null:
		return
	for i in order.size():
		var card: Node3D = cards.get(order[i])
		if card == null:
			continue
		if i >= BOARD_COLUMNS * BOARD_ROWS:
			if card.is_inside_tree():
				card.get_parent().remove_child(card)
			continue
		if not card.is_inside_tree():
			card.position = card_spot(i)
			card.scale = Vector3.ONE
			exec.node.add_child(card)
		else:
			card.create_tween().tween_property(card, "position", card_spot(i), 0.3).set_trans(Tween.TRANS_SINE)


## One line on the floor under the board: each project with active schedules, with a count when
## it has more than one, in the order their first card was pinned.
func board_label() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var exec := _exec()
	if exec == null or order.is_empty():
		return out
	var names: Array[String] = []
	var counts: Dictionary = {}
	for id in order:
		var s: Building.Schedule = scene.building.schedules.get(id)
		if s == null:
			continue
		var name := s.project_id
		if scene.blocks.has(s.project_id):
			name = (scene.blocks[s.project_id] as BlockNode).name
		elif scene.building.blocks.has(s.project_id):
			name = (scene.building.blocks[s.project_id] as Building.Block).name
		if not counts.has(name):
			names.append(name)
		counts[name] = int(counts.get(name, 0)) + 1
	if names.is_empty():
		return out
	var parts: Array[String] = []
	for n in names:
		parts.append("%s ×%d" % [n, counts[n]] if int(counts[n]) > 1 else n)
	var below := Vector3(Layout.BOARD_CENTER.x, 0, Layout.BOARD_CENTER.y + 0.5)
	out.append({"anchor": exec.node.position + below, "lines": [[TownLabels.clip_width(" · ".join(parts), 34), "faint"]]})
	return out


# --- Compaction -----------------------------------------------------------------------------

func compact_started(p: String, s: String) -> void:
	var chief: TownActor = scene.actors.get(s)
	var b: BlockNode = scene.blocks.get(p)
	if chief == null or b == null or not b.chief_slots.has(s):
		return
	chief.compacting = true
	chief.note = scene.labels.t("Tidying notes…")
	if chief.papers != null and is_instance_valid(chief.papers):
		chief.papers.queue_free()
	chief.papers = _paper_stack(b, int(b.chief_slots[s]))
	if not chief.is_busy():
		chief.settle()
	_shuffle_papers(chief)


func compact_done(p: String, s: String, outcome: String, before: Variant, after: Variant) -> void:
	var chief: TownActor = scene.actors.get(s)
	if chief == null:
		return
	chief.compacting = false
	if outcome != "done":
		# Skipped or failed: the notes go back as they were.
		if chief.note == scene.labels.t("Tidying notes…"):
			chief.note = null
		if chief.papers != null and is_instance_valid(chief.papers):
			chief.papers.queue_free()
		chief.papers = null
		if not chief.is_busy():
			chief.settle()
		return
	var text := compacted(scene.labels, before, after)
	chief.note = text
	if not chief.is_busy():
		chief.settle()
	_tidy(chief, chief.papers, text, before, after)


## After a compaction: the conversation's size before and after, in tokens, when known.
static func compacted(L: TownLabels, before: Variant, after: Variant) -> String:
	if before == null or after == null:
		return L.t("Notes tidied")
	return L.t("Notes tidied: %@ → %@ tokens", [_k(int(before)), _k(int(after))])


static func _k(n: int) -> String:
	return "%dk" % ((n + 500) / 1000) if n >= 1000 else str(n)


## Most sheets fly off; what is left matches how much was kept. The note and the stack go after 4 s.
func _tidy(chief: TownActor, stack: Node3D, text: String, before: Variant, after: Variant) -> void:
	if stack != null and is_instance_valid(stack):
		var sheets := _bottom_up(stack)
		var keep := 2
		if before != null and after != null and int(before) > 0:
			keep = clampi(ceili(float(after) / float(before) * sheets.size()), 1, sheets.size())
		var gone := sheets.slice(keep)
		gone.reverse()
		for sheet: Node3D in gone:
			if not is_instance_valid(sheet):
				continue
			var tw := sheet.create_tween().set_parallel()
			tw.tween_property(sheet, "position", sheet.position + Vector3(0.25, 0.35, -0.1), 0.35)
			tw.tween_property(sheet, "rotation:y", sheet.rotation.y + 0.9, 0.35)
			tw.tween_property(sheet, "scale", Vector3.ONE * 0.2, 0.35)
			tw.chain().tween_callback(sheet.queue_free)
			await scene.wait(0.18)
	await scene.wait(4.0)
	if chief.note == text:
		chief.note = null
	if not chief.compacting and chief.papers == stack:
		if stack != null and is_instance_valid(stack):
			stack.queue_free()
		chief.papers = null


## The stack's sheets from the bottom up (going through them reorders them).
static func _bottom_up(stack: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in stack.get_children():
		if c is Node3D and not c.is_queued_for_deletion():
			out.append(c)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.position.y < b.position.y)
	return out


## A stack of sheets on the left of the Chief of Staff's desk, big enough to read at the zoom where
## the whole office fits.
func _paper_stack(b: BlockNode, slot: int) -> Node3D:
	var k := Layout.FURNITURE_SCALE / 0.85
	var stack := Node3D.new()
	stack.position = Vector3(Layout.desk_x(slot) - 0.36, b.desk_top, Layout.CHIEF_DESK_Z + 0.04)
	var thick := 0.02 * k
	for i in PAPER_SHEETS:
		var sheet := TownScene.box(Vector3(0.34 * k, thick, 0.42 * k), "#FBF8F0" if i % 2 == 0 else "#ECE6D6",
			Vector3(0, thick * (float(i) + 0.5), 0))
		sheet.rotation.y = float(i % 3 - 1) * 0.08
		stack.add_child(sheet)
	b.node.add_child(stack)
	return stack


## While compacting, the Chief of Staff goes through the notes: the top sheet lifts well clear of
## the stack, turns over to the side as if read, and is tucked back under the others.
func _shuffle_papers(chief: TownActor) -> void:
	var stack := chief.papers
	var flip := false
	while chief.compacting and chief.papers == stack and is_instance_valid(stack):
		var sheets := _bottom_up(stack)
		if sheets.size() > 1:
			var sheet: Node3D = sheets[-1]
			var heights: Array[float] = []
			for sh in sheets:
				heights.append(sh.position.y)
			var rest := sheet.transform
			var up := Transform3D(Basis(Vector3(0, 0, 1), 0.5 if flip else -0.5) * Basis(Vector3.RIGHT, 0.6),
				rest.origin + Vector3(0.12 if flip else -0.12, 0.28, 0))
			sheet.create_tween().tween_property(sheet, "transform", up, 0.3)
			await scene.wait(0.7)
			if not is_instance_valid(sheet):
				break
			if not chief.compacting or chief.papers != stack:
				sheet.transform = rest
				break
			# Back under the stack: the others rise one place and this one goes to the bottom.
			for i in sheets.size() - 1:
				if is_instance_valid(sheets[i]):
					sheets[i].position.y = heights[i + 1]
			var low := rest
			low.origin.y = heights[0]
			sheet.create_tween().tween_property(sheet, "transform", low, 0.3)
			await scene.wait(0.3)
		flip = not flip
		await scene.wait(0.5)

class_name LabelOverlay
extends Control
## Name tags, block signs and context bars, drawn in 2D over the 3D view at each anchor's
## projected position so text stays sharp. Port of the label views in
## app/macos/Sources/AgentTown/TownView.swift (Tag, MeterOverlay).

const FONT_SIZE := 12 ## Cubic 11 is drawn at its own pixel size, or a multiple of it
const BAR_WIDTH := 96.0
const ROW_HEIGHT := 22.0
const METER_GAP := 8.0

const BACKGROUND := {
	"name": Color(0, 0, 0, 0.55), "hat": Color(0.98, 0.80, 0.25), "ticket": Color.WHITE, "bubble": Color(0.86, 0.15, 0.15),
	"badge": Color(0.36, 0.30, 0.75), "sign": Color(0.20, 0.24, 0.30), "ring": Color(0.98, 0.55, 0.20),
	"faint": Color(0, 0, 0, 0.22), "speech": Color.WHITE, "statement": Color(1, 0.98, 0.92)}
const DARK_TEXT := ["hat", "ticket", "speech", "statement"]
const METER_BACKGROUND := Color(0.20, 0.24, 0.30, 0.92)
const CALL_COLOR := Color(0.95, 0.45, 0.15)

const SCROLL_SPEED := 28.0 ## pixels per second for a sign that scrolls

var scene: TownScene
var camera: Camera3D
var font: FontFile
var _boxes: Dictionary = {} ## style -> StyleBoxFlat
var _scrollers: Dictionary = {} ## sign id -> ScrollingSign


## A block sign whose task titles are too wide: the whole sign scrolls sideways in a window
## TownLabels.TITLE_WIDTH columns wide, fading at both ends. Port of `ScrollingSign` in
## app/macos/Sources/AgentTown/TownView.swift.
class ScrollingSign:
	extends Control
	var overlay: LabelOverlay
	var text := ""
	var _offset := 0.0

	func _process(delta: float) -> void:
		_offset += delta * LabelOverlay.SCROLL_SPEED
		queue_redraw()

	func _draw() -> void:
		var f := overlay.font
		var fs := LabelOverlay.FONT_SIZE
		var pad := Vector2(5, 2)
		var loop := text + "      "
		var loop_w := f.get_string_size(loop, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var bg: Color = LabelOverlay.BACKGROUND["sign"]
		draw_style_box(overlay._box("sign"), Rect2(Vector2.ZERO, size))
		var x := pad.x - fmod(_offset, maxf(1.0, loop_w))
		var y := pad.y + f.get_ascent(fs)
		draw_string(f, Vector2(x, y), loop, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		draw_string(f, Vector2(x + loop_w, y), loop, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		# Soft ends: the sign's color fading to clear over 6% of its width at each side.
		var fade := size.x * 0.06
		var clear := Color(bg, 0.0)
		draw_polygon([Vector2(0, 0), Vector2(fade, 0), Vector2(fade, size.y), Vector2(0, size.y)], [bg, clear, clear, bg])
		draw_polygon([Vector2(size.x - fade, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - fade, size.y)],
			[clear, bg, bg, clear])


func _init(p_scene: TownScene, p_camera: Camera3D) -> void:
	scene = p_scene
	camera = p_camera
	font = load("res://fonts/Cubic_11.ttf")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Dashed lines for calls in progress, pages and approval waits, under the tags.
	for line: Array in scene.call_lines():
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		if camera.is_position_behind(a) or camera.is_position_behind(b):
			continue
		draw_dashed_line(camera.unproject_position(a), camera.unproject_position(b), CALL_COLOR, 2.0, 6.0)
	var seen: Array = []
	for item: Dictionary in scene.label_items():
		var anchor: Vector3 = item["anchor"]
		if camera.is_position_behind(anchor):
			continue
		var p := camera.unproject_position(anchor).round()
		if item.get("scroll", false):
			seen.append(item["id"])
			_place_scroller(item["id"], item["lines"][0][0], p)
			continue
		if item.get("meter", false):
			_draw_meter(p, item)
			continue
		var lines: Array = item["lines"]
		if lines.size() == 1 and lines[0][1] == "sign":
			_draw_tag(p, lines[0][0], "sign", true)
			continue
		# Tags stack upward from the anchor, the last line nearest the head.
		var y := p.y
		for i in range(lines.size() - 1, -1, -1):
			var h := _draw_tag(Vector2(p.x, y), lines[i][0], lines[i][1], false)
			y -= h + 2.0
	# A sign that no longer scrolls (or whose block went) loses its scroller.
	for id: String in _scrollers.keys():
		if not seen.has(id):
			(_scrollers[id] as Node).queue_free()
			_scrollers.erase(id)


## Keeps a scrolling sign's control centered on `at`, the width of TITLE_WIDTH columns.
func _place_scroller(id: String, text: String, at: Vector2) -> void:
	var sc: ScrollingSign = _scrollers.get(id)
	if sc == null:
		sc = ScrollingSign.new()
		sc.overlay = self
		sc.clip_contents = true
		sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sc)
		_scrollers[id] = sc
	sc.text = text
	var w := font.get_string_size("n".repeat(TownLabels.TITLE_WIDTH), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 10.0
	var h := font.get_height(FONT_SIZE) + 4.0
	sc.size = Vector2(w, h)
	sc.position = (at - sc.size / 2.0).round()


## Draws one tag centered on x; its bottom at `at.y`, or its center there when `centered`. Returns its height.
func _draw_tag(at: Vector2, text: String, style: String, centered: bool) -> float:
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var pad := Vector2(5, 2)
	var rect := Rect2(Vector2(at.x - size.x / 2.0 - pad.x, at.y - size.y - 2.0 * pad.y), size + 2.0 * pad)
	if centered:
		rect.position.y = at.y - rect.size.y / 2.0
	rect.position = rect.position.round()
	draw_style_box(_box(style), rect)
	var color := Color.BLACK if style in DARK_TEXT else Color.WHITE
	draw_string(font, rect.position + Vector2(pad.x, pad.y + font.get_ascent(FONT_SIZE)), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		FONT_SIZE, color)
	return rect.size.y


## The context bar: how full the window is, then the figures (spec: context bar).
func _draw_meter(at: Vector2, item: Dictionary) -> void:
	var text: String = item["text"]
	var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var w := 8.0 + BAR_WIDTH + 7.0 + tsize.x + 8.0
	var h := ROW_HEIGHT - 4.0
	var top := at.y + METER_GAP + float(item["row"]) * ROW_HEIGHT
	var rect := Rect2(Vector2(at.x - w / 2.0, top), Vector2(w, h)).abs()
	rect.position = rect.position.round()
	draw_style_box(_rounded(METER_BACKGROUND, 5), rect)
	var bar := Rect2(rect.position + Vector2(8, (h - 7) / 2.0), Vector2(BAR_WIDTH, 7))
	draw_style_box(_rounded(Color(1, 1, 1, 0.22), 3), bar)
	var f: Variant = item["fraction"]
	if f != null and float(f) > 0.0:
		draw_style_box(_rounded(meter_color(float(f)), 3), Rect2(bar.position, Vector2(BAR_WIDTH * float(f), 7)))
	draw_string(font, Vector2(bar.end.x + 7, rect.position.y + (h - tsize.y) / 2.0 + font.get_ascent(FONT_SIZE)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color.WHITE)


## Green while there is room, amber past 60%, red past 80%.
static func meter_color(f: float) -> Color:
	if f >= 0.8:
		return Color(0.88, 0.27, 0.22)
	if f >= 0.6:
		return Color(0.95, 0.65, 0.18)
	return Color(0.30, 0.72, 0.42)


func _box(style: String) -> StyleBoxFlat:
	if not _boxes.has(style):
		_boxes[style] = _rounded(BACKGROUND.get(style, Color(0, 0, 0, 0.55)), 4)
	return _boxes[style]


static func _rounded(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	return s

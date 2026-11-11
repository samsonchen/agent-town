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

var scene: TownScene
var camera: Camera3D
var font: FontFile
var _boxes: Dictionary = {} ## style -> StyleBoxFlat


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
	for item: Dictionary in scene.label_items():
		var anchor: Vector3 = item["anchor"]
		if camera.is_position_behind(anchor):
			continue
		var p := camera.unproject_position(anchor).round()
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

extends Node
## The agent-town window: the office, its camera and labels, fed by the store.
##
## Demo mode replays a fixture instead of listening, to check scenes without Claude Code
## (port of app/macos/Sources/AgentTown/Demo.swift):
##   godot --path app/windows -- --demo ../../protocol/fixtures/01-basic-ticket.json [--speed N]
##         [--snapshot out.png --at SECONDS]
## Gaps between events keep their timing, each capped at 4 s and divided by `--speed`.

const PIXELS_PER_METER := 110.0 ## the office is shown at this size when it fits
const MIN_PIXELS_PER_METER := 70.0
const MIN_HEIGHT := 480

var labels := TownLabels.new()
var store := TownStore.new()
var scene: TownScene
var camera := Camera3D.new()
var overlay: LabelOverlay
var pan := Vector2.ZERO

var _args: Dictionary = {}


func _ready() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	get_window().title = "agent-town"
	add_child(store)
	scene = TownScene.new(labels, store.building)
	add_child(scene)
	store.changed.connect(scene.handle)
	var audio := TownAudio.new()
	add_child(audio)
	scene.sound.connect(audio.play)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	scene.add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	overlay = LabelOverlay.new(scene, camera)
	layer.add_child(overlay)
	scene.office_resized.connect(func(_s: Vector2) -> void: _fit_window())
	get_window().size_changed.connect(_update_camera)
	_fit_window()

	if _args.has("demo"):
		_play_demo(_args["demo"], float(_args.get("speed", "1")))
	else:
		var version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
		store.start(version)
	if _args.has("snapshot"):
		_snapshot_later(_args["snapshot"], _args.get("at", "3"))


static func _parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i := 0
	while i < args.size():
		if args[i].begins_with("--") and i + 1 < args.size():
			out[args[i].trim_prefix("--")] = args[i + 1]
			i += 2
		else:
			i += 1
	return out


# --- Camera and window ------------------------------------------------------------------------

## Screen size of the office at `ppm`, the floor's depth foreshortened by the camera tilt.
func _office_pixels(ppm: float) -> Vector2:
	return Vector2(scene.office_size.x * ppm, scene.office_size.y * sin(TownScene.PITCH) * ppm)


func pixels_per_meter(size: Vector2) -> float:
	var fit := _office_pixels(1.0)
	var k := minf(size.x / maxf(1.0, fit.x), size.y / maxf(1.0, fit.y))
	return minf(PIXELS_PER_METER, maxf(MIN_PIXELS_PER_METER, k))


## How far the camera may pan from the office center before showing only path.
func _pan_limit(size: Vector2) -> Vector2:
	var ppm := pixels_per_meter(size)
	var extra := _office_pixels(ppm)
	return Vector2(maxf(0.0, (extra.x - size.x) / ppm / 2.0), maxf(0.0, (extra.y - size.y) / ppm / 2.0 / sin(TownScene.PITCH)))


func _update_camera() -> void:
	var size := Vector2(get_viewport().get_visible_rect().size)
	var ppm := pixels_per_meter(size)
	var lim := _pan_limit(size)
	pan = pan.clamp(-lim, lim)
	var target := Vector3(scene.office_size.x / 2.0 + pan.x, 0, scene.office_size.y / 2.0 + pan.y)
	var dir := Vector3(0, sin(TownScene.PITCH), cos(TownScene.PITCH))
	camera.size = size.y / ppm # visible height in meters
	camera.near = 1.0
	camera.far = 100.0
	camera.look_at_from_position(target + dir * 40.0, target, Vector3.UP)


## Makes the window as tall as the office at the current width's scale, keeping its top edge and
## staying on the screen (spec: the window grows with the office). A taller office scrolls.
func _fit_window() -> void:
	var w := get_window()
	if w.mode != Window.MODE_WINDOWED:
		_update_camera()
		return
	var ppm := minf(PIXELS_PER_METER, maxf(MIN_PIXELS_PER_METER, float(w.size.x) / maxf(1.0, scene.office_size.x)))
	var wanted := maxi(MIN_HEIGHT, ceili(_office_pixels(ppm).y))
	var usable := DisplayServer.screen_get_usable_rect(w.current_screen)
	var height := mini(wanted, usable.size.y - 40)
	if absi(w.size.y - height) > 1:
		var top := w.position.y
		w.size = Vector2i(w.size.x, height)
		w.position = Vector2i(w.position.x, maxi(usable.position.y + 30, mini(top, usable.end.y - height)))
	_update_camera()


# --- Demo -----------------------------------------------------------------------------------

func _play_demo(path: String, speed: float) -> void:
	var text := FileAccess.get_file_as_string(path)
	var batch: Variant = TownEvent.decode_batch(text)
	if batch == null:
		push_error("agent-town: --demo %s is not a protocol fixture" % path)
		return
	var last := -1
	for e: TownEvent in batch["events"]:
		if last >= 0:
			await get_tree().create_timer(minf(4.0, float(e.ts - last) / 1000.0) / maxf(0.01, speed)).timeout
		last = e.ts
		store.receive({"protocol": 1, "events": [e] as Array[TownEvent]}, Time.get_ticks_msec())


## `--at` may list several times ("6,12,21"): each writes out-1.png, out-2.png …; the last quits.
func _snapshot_later(path: String, at: String) -> void:
	var times := Array(at.split(",")).map(func(t: String) -> float: return t.to_float())
	var elapsed := 0.0
	for i in times.size():
		await get_tree().create_timer(maxf(0.0, times[i] - elapsed)).timeout
		elapsed = times[i]
		await RenderingServer.frame_post_draw
		var out := path if times.size() == 1 else "%s-%d.%s" % [path.get_basename(), i + 1, path.get_extension()]
		get_viewport().get_texture().get_image().save_png(out)
		print("snapshot: ", out)
	get_tree().quit()

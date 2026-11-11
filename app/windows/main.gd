extends Node
## The agent-town app: the office window with its camera and labels, fed by the store, and the
## tray icon with its menu (docs/windows/spec.md). The window has no taskbar button and closing it
## only hides it; the TownWindow add-on (app/windows/native/) does what Godot cannot.
##
## Demo mode replays a fixture instead of listening, to check scenes without Claude Code
## (port of app/macos/Sources/AgentTown/Demo.swift):
##   godot --path app/windows -- --demo ../../protocol/fixtures/01-basic-ticket.json [--speed N]
##         [--snapshot out.png --at SECONDS[,SECONDS…]] [--language en|zh-Hant] [--open settings|about]
##         [--keys "down:1.5,right:1,h"]
## Gaps between events keep their timing, each capped at 4 s and divided by `--speed`.

const PIXELS_PER_METER := 110.0 ## the office is shown at this size when it fits
const MIN_PIXELS_PER_METER := 70.0
const MIN_HEIGHT := 480

enum Menu { ABOUT, SHOW, ON_TOP, SOUND, SETTINGS, QUIT }

var settings := TownSettings.new()
var labels: TownLabels
var store := TownStore.new()
var scene: TownScene
var camera := Camera3D.new()
var overlay: LabelOverlay
var audio := TownAudio.new()
var pan := Vector2.ZERO

var _office := Control.new() ## the 3D view and its labels; its alpha is the window's opacity
var _view := SubViewportContainer.new()
var _tray := StatusIndicator.new()
var _menu := PopupMenu.new()
var _settings_window: SettingsWindow
var _about_window: AboutWindow
var _args: Dictionary = {}


func _ready() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	# --language en|zh-Hant overrides the setting for this run (for checking screens).
	labels = TownLabels.new(_args.get("language", settings.language))
	var w := get_window()
	w.title = "agent-town"
	get_tree().auto_accept_quit = false # closing the window hides it; Quit is in the tray menu

	add_child(store)
	_office.set_anchors_preset(Control.PRESET_FULL_RECT)
	_office.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_office)
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.stretch = true
	_office.add_child(_view)
	var sub := SubViewport.new()
	_view.add_child(sub)
	scene = TownScene.new(labels, store.building)
	sub.add_child(scene)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	scene.add_child(camera)
	overlay = LabelOverlay.new(scene, camera)
	_office.add_child(overlay)
	store.changed.connect(scene.handle)
	add_child(audio)
	_apply_sounds()
	scene.sound.connect(audio.play)
	scene.office_resized.connect(func(_s: Vector2) -> void: _fit_window())
	w.size_changed.connect(_update_camera)
	w.focus_exited.connect(func() -> void: scene.ceo_driver.release_keys())
	scene.ceo_driver.moved.connect(_follow)

	_restore_window()
	w.always_on_top = settings.stay_on_top
	_apply_opacity(settings.opacity)
	_build_tray()
	_settings_window = SettingsWindow.new(settings, labels, audio)
	_settings_window.sounds_changed.connect(_apply_sounds)
	_settings_window.visible = false
	_settings_window.opacity_changed.connect(_apply_opacity)
	add_child(_settings_window)
	_about_window = AboutWindow.new(labels)
	_about_window.visible = false
	add_child(_about_window)
	_call_window("hide_from_taskbar", [_hwnd()])
	_fit_window()
	if not settings.show_window and not _args.has("snapshot"):
		_set_shown(false)

	# --open settings|about pops that window up at start (for checking screens).
	match _args.get("open", ""):
		"settings": _settings_window.popup_centered.call_deferred()
		"about": _about_window.popup_centered.call_deferred()
	if _args.has("demo"):
		_play_demo(_args["demo"], float(_args.get("speed", "1")))
	else:
		var version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
		store.start(version)
	if _args.has("keys"):
		_press_keys(_args["keys"])
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


## The arrow keys and H walk the CEO (spec: walking the CEO); the scroll wheel pans the view
## when the office does not fit (Shift or a sideways wheel pans across).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not (event as InputEventKey).echo:
		var k := event as InputEventKey
		if scene.ceo_driver.key(k.keycode, k.pressed):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		var step := 0.6
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_pan_by(Vector2(-step, 0) if mb.shift_pressed else Vector2(0, -step))
			MOUSE_BUTTON_WHEEL_DOWN:
				_pan_by(Vector2(step, 0) if mb.shift_pressed else Vector2(0, step))
			MOUSE_BUTTON_WHEEL_LEFT:
				_pan_by(Vector2(-step, 0))
			MOUSE_BUTTON_WHEEL_RIGHT:
				_pan_by(Vector2(step, 0))


func _pan_by(d: Vector2) -> void:
	pan += d
	_update_camera()


## Pans so the CEO stays inside the middle of the window while walking.
func _follow(spot: Vector2) -> void:
	var size := Vector2(get_window().size)
	var p := camera.unproject_position(Vector3(spot.x, 0.3, spot.y))
	var m := size * 0.2
	var dx := p.x - m.x if p.x < m.x else (p.x - (size.x - m.x) if p.x > size.x - m.x else 0.0)
	var dy := p.y - m.y if p.y < m.y else (p.y - (size.y - m.y) if p.y > size.y - m.y else 0.0)
	if dx == 0.0 and dy == 0.0:
		return
	var ppm := pixels_per_meter(size)
	_pan_by(Vector2(dx / ppm, dy / ppm / sin(TownScene.PITCH)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_set_shown(false) # the app keeps running in the tray


# --- The tray and the window ------------------------------------------------------------------

func _build_tray() -> void:
	_menu.prefer_native_menu = true
	_menu.add_item(labels.t("About agent-town"), Menu.ABOUT)
	_menu.add_separator()
	_menu.add_check_item(labels.t("Show agent-town"), Menu.SHOW)
	_menu.add_check_item(labels.t("Stay on top"), Menu.ON_TOP)
	_menu.add_check_item(labels.t("Sound"), Menu.SOUND)
	_menu.add_separator()
	_menu.add_item(labels.t("Settings…"), Menu.SETTINGS)
	_menu.add_separator()
	_menu.add_item(labels.t("Quit agent-town"), Menu.QUIT)
	_menu.id_pressed.connect(_on_menu)
	_menu.about_to_popup.connect(_sync_menu)
	add_child(_menu)
	var icon := (load("res://shared/icons/app-icon-1024.png") as Texture2D).get_image()
	icon.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	_tray.icon = ImageTexture.create_from_image(icon)
	_tray.tooltip = "agent-town"
	add_child(_tray)
	_tray.menu = _tray.get_path_to(_menu)
	_tray.pressed.connect(func(button: int, _at: Vector2i) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_set_shown(true))
	_sync_menu()


func _sync_menu() -> void:
	_menu.set_item_checked(_menu.get_item_index(Menu.SHOW), settings.show_window)
	_menu.set_item_checked(_menu.get_item_index(Menu.ON_TOP), settings.stay_on_top)
	_menu.set_item_checked(_menu.get_item_index(Menu.SOUND), settings.sound)


func _on_menu(id: int) -> void:
	match id:
		Menu.ABOUT:
			_about_window.popup_centered()
		Menu.SHOW:
			_set_shown(not settings.show_window)
		Menu.ON_TOP:
			settings.stay_on_top = not settings.stay_on_top
			get_window().always_on_top = settings.stay_on_top
			settings.save()
		Menu.SOUND:
			settings.sound = not settings.sound
			settings.save()
			_apply_sounds()
		Menu.SETTINGS:
			_settings_window.popup_centered()
		Menu.QUIT:
			_remember_window()
			settings.save()
			get_tree().quit()
	_sync_menu()


func _hwnd() -> int:
	return DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, get_window().get_window_id())


## Calls the TownWindow add-on when it is loaded (it is Windows only).
func _call_window(method: String, args: Array) -> Variant:
	if not ClassDB.class_exists("TownWindow"):
		return null
	return ClassDB.class_call_static("TownWindow", method, args[0]) if args.size() == 1 \
		else ClassDB.class_call_static("TownWindow", method, args[0], args[1])


func _set_shown(on: bool) -> void:
	if not on:
		_remember_window()
	settings.show_window = on
	settings.save()
	_call_window("set_shown", [_hwnd(), on])
	_sync_menu()


## The sound settings: the menu's Sound item, the volume, each sound's switch and choice, and the
## completion threshold (applied where the building decides whether a finished ticket plays it).
func _apply_sounds() -> void:
	audio.muted = not settings.sound
	audio.volume = settings.volume
	for key: String in TownSettings.SOUNDS:
		audio.enabled[key] = settings.sound_on[key]
		audio.choose(key, settings.sound_choice[key])
	store.building.sound.threshold_seconds = settings.completion_threshold


## The office's opacity (Settings): the window turns see-through below 100%.
func _apply_opacity(value: float) -> void:
	var see_through := value < 0.999
	get_window().transparent = see_through
	get_viewport().transparent_bg = see_through
	_office.modulate.a = value


## The window opens where it was, on the same display if it is still connected (spec).
func _restore_window() -> void:
	var w := get_window()
	if settings.window_position == null or settings.window_screen < 0 or settings.window_screen >= DisplayServer.get_screen_count():
		return
	var rect := DisplayServer.screen_get_usable_rect(settings.window_screen)
	var pos: Vector2i = settings.window_position
	if not rect.has_point(pos + Vector2i(40, 10)):
		return
	if settings.window_width >= 320:
		w.size = Vector2i(mini(settings.window_width, rect.size.x), w.size.y)
	w.position = pos


func _remember_window() -> void:
	var w := get_window()
	settings.window_position = w.position
	settings.window_width = w.size.x
	settings.window_screen = w.current_screen


# --- Camera and window size ---------------------------------------------------------------

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
	var size := Vector2(get_window().size)
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
	var batch: Variant = TownEvent.decode_batch(FileAccess.get_file_as_string(path))
	if batch == null:
		push_error("agent-town: --demo %s is not a protocol fixture" % path)
		return
	var last := -1
	for e: TownEvent in batch["events"]:
		if last >= 0:
			await get_tree().create_timer(minf(4.0, float(e.ts - last) / 1000.0) / maxf(0.01, speed)).timeout
		last = e.ts
		store.receive({"protocol": 1, "events": [e] as Array[TownEvent]}, Time.get_ticks_msec())


## `--keys "down:1.5,right:1,h"` presses keys through the normal input path, for checking the CEO:
## each item is a key and how long it is held (H and others are tapped). Starts after 1 s.
func _press_keys(spec: String) -> void:
	var names := {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN, "h": KEY_H}
	await get_tree().create_timer(1.0).timeout
	for item: String in spec.split(","):
		var parts := item.strip_edges().split(":")
		var code: int = names.get(parts[0].to_lower(), KEY_NONE)
		var hold := float(parts[1]) if parts.size() > 1 else 0.05
		for pressed: bool in [true, false]:
			var e := InputEventKey.new()
			e.keycode = code
			e.pressed = pressed
			Input.parse_input_event(e)
			if pressed:
				await get_tree().create_timer(hold).timeout
		await get_tree().create_timer(0.2).timeout


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

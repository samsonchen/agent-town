extends Node
## The agent-town app: the office window with its camera and labels, fed by the store, and the
## tray icon with its menu (docs/windows/spec.md). The window has no taskbar button and closing it
## only hides it; the TownWindow add-on (app/windows/native/) does what Godot cannot.
##
## Demo mode replays a fixture instead of listening, to check scenes without Claude Code
## (port of app/macos/Sources/AgentTown/Demo.swift):
##   godot --path app/windows -- --demo ../../protocol/fixtures/01-basic-ticket.json [--speed N]
##         [--snapshot out.png --at SECONDS[,SECONDS…]] [--language en|zh-Hant] [--open settings|about]
##         [--keys "down:1.5,right:1,h"] [--clicks "95:270@2,300:500@6"] [--hide-idle SECONDS]
##         [--compact yes] [--resize WxH] [--fake-update yes] [--check-now yes] [--open updates]
## [--sound no] keeps this run quiet; [--settings-file PATH] uses its own settings; --open takes
## several windows, comma-separated (settings,updates).
## --fake-update makes up a newer app and town-link (99.0.0) without the network; --check-now makes a
## real update check, even in a demo (a demo or a snapshot makes no automatic check).
## --compact yes shows compact view for this run; --resize shrinks the window 8 s in, as a drag would.
## A run with --snapshot never starts the server, so it cannot take the endpoint from the running app.
## Gaps between events keep their timing, each capped at 4 s and divided by `--speed`.

## The office is shown at 110 pixels per meter when it fits, never under 70; half that in compact view.
static var PIXELS_PER_METER := 110.0
static var MIN_PIXELS_PER_METER := 70.0
static var MIN_HEIGHT := 480
## The smallest window: a corner of a laptop screen. A window smaller than the office scrolls.
const MIN_SIZE := Vector2i(320, 240)
const AUTO_SCROLL_PAUSE := 10000 ## msec the user's own scrolling, or walking the CEO, holds auto-scroll off

enum Menu { ABOUT, SHOW, ON_TOP, SOUND, SETTINGS, QUIT, APP_UPDATE, PLUGIN_UPDATE }

var settings: TownSettings ## made in _ready, from --settings-file when given
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
var _updates_window: UpdatesWindow
var updater: Updater
var _icon: Image ## the tray icon without the update dot
var _args: Dictionary = {}
var _tip: PanelContainer
var _tip_label: Label
var _last_office := Vector2.ZERO ## the office size the window was last fitted to
# Auto-scroll (spec: the office): where each character was, which ones walk, and when the user
# last took the view.
var _seen_spots: Dictionary = {} ## id -> Vector3, position in its block at the last look
var _moving_until: Dictionary = {} ## id -> msec it still counts as walking
var _auto_paused_until := 0
var _auto_target: Variant = null ## Vector2 pan, or null
var _auto_clock := 0.0


func _ready() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	# --settings-file PATH: a run from the checkout (scripts/run-local.ps1) keeps its own settings.
	settings = TownSettings.new(_args.get("settings-file", ""))
	# --language en|zh-Hant overrides the setting for this run (for checking screens).
	labels = TownLabels.new(_args.get("language", settings.language))
	# Compact view is read once here, so a change in Settings applies after a restart.
	ViewScale.set_compact(settings.compact_view or _args.get("compact", "") == "yes")
	PIXELS_PER_METER = 110.0 * ViewScale.world
	MIN_PIXELS_PER_METER = 70.0 * ViewScale.world
	MIN_HEIGHT = roundi(480 * ViewScale.world)
	settings.use_view(ViewScale.compact, ceili((2.0 * Layout.MARGIN + Layout.BLOCK_WIDTH) * PIXELS_PER_METER))
	var w := get_window()
	w.title = "agent-town"
	w.min_size = MIN_SIZE
	get_tree().auto_accept_quit = false # closing the window hides it; Quit is in the tray menu

	add_child(store)
	_office.set_anchors_preset(Control.PRESET_FULL_RECT)
	_office.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_office)
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.stretch = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE # clicks reach _unhandled_input, for the CEO
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
	_build_tip()
	store.changed.connect(scene.handle)
	add_child(audio)
	_apply_sounds()
	_apply_office()
	scene.sound.connect(audio.play)
	scene.office_resized.connect(func(_s: Vector2) -> void:
		_fit_window(_last_office)
		_last_office = scene.office_size)
	w.size_changed.connect(_update_camera)
	w.focus_exited.connect(func() -> void: scene.ceo_driver.release_keys())
	scene.ceo_driver.moved.connect(_follow)
	scene.ceo_driver.away_changed.connect(func(_away: bool) -> void: _update_tip())

	_restore_window()
	w.always_on_top = settings.stay_on_top
	_apply_opacity(settings.opacity)
	var version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	updater = Updater.new(settings, store, version)
	add_child(updater)
	_build_tray()
	_settings_window = SettingsWindow.new(settings, labels, audio)
	_settings_window.updater = updater
	_settings_window.sounds_changed.connect(_apply_sounds)
	_settings_window.office_changed.connect(_apply_office)
	_settings_window.restart_requested.connect(func() -> void:
		_remember_window()
		settings.save()
		OS.set_restart_on_exit(true, OS.get_cmdline_args())
		get_tree().quit())
	_settings_window.visible = false
	_settings_window.opacity_changed.connect(_apply_opacity)
	add_child(_settings_window)
	_about_window = AboutWindow.new(labels)
	_about_window.visible = false
	add_child(_about_window)
	_updates_window = UpdatesWindow.new(updater, labels)
	_updates_window.visible = false
	add_child(_updates_window)
	updater.changed.connect(_fill_menu)
	updater.window_requested.connect(_show_updates)
	updater.start(not _args.has("demo") and not _args.has("snapshot"), _args.has("fake-update"), _args.has("check-now"))
	_call_window("hide_from_taskbar", [_hwnd()])
	LoginItem.repair() # an Open at login entry from 1.0.4 or older, which Windows skipped at sign-in
	# Sessions already open; a restored height the user made shorter than the office stays.
	_fit_window(scene.office_size if settings.window_height > 0 else null)
	_last_office = scene.office_size
	if _args.has("resize"):
		_resize_later(_args["resize"])
	if not settings.show_window and not _args.has("snapshot"):
		_set_shown(false)

	# --open settings|about pops that window up at start (for checking screens).
	for name: String in str(_args.get("open", "")).split(",", false):
		match name:
			"settings": _settings_window.popup_centered.call_deferred()
			"about": _about_window.popup_centered.call_deferred()
			"updates": _updates_window.popup_centered.call_deferred()
	if _args.has("demo"):
		_play_demo(_args["demo"], float(_args.get("speed", "1")))
	elif not _args.has("snapshot"): # a check run never takes the endpoint from the running app
		store.start(version)
	if _args.has("keys"):
		_press_keys(_args["keys"])
	if _args.has("clicks"):
		_click_at(_args["clicks"])
	if _args.has("snapshot"):
		_snapshot_later(_args["snapshot"], _args.get("at", "3"))


## `--name value` pairs; a flag with no value (`--fake-update`) counts as "yes".
static func _parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i := 0
	while i < args.size():
		if not args[i].begins_with("--"):
			i += 1
		elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
			out[args[i].trim_prefix("--")] = args[i + 1]
			i += 2
		else:
			out[args[i].trim_prefix("--")] = "yes"
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
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			_pause_auto_scroll() # the user's own scrolling holds for a while
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				scene.ceo_driver.click(mb.position, camera)
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
	_pause_auto_scroll() # the user is walking the CEO
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


# --- The tip --------------------------------------------------------------------------------

## The tip at the bottom of the window (spec: walking the CEO): how to move the CEO, or while the
## CEO is away, how to send it back. Closing it turns off Show tips. Port of `TipBar` in
## app/macos/Sources/AgentTown/TownView.swift.
func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.theme = SettingsWindow.ui_theme()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.7)
	box.set_corner_radius_all(14)
	box.content_margin_left = 12
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	_tip.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_tip.add_child(row)
	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", 13)
	_tip_label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(_tip_label)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.tooltip_text = labels.t("Close")
	close.add_theme_color_override("font_color", Color.WHITE)
	close.add_theme_font_size_override("font_size", 11)
	close.pressed.connect(func() -> void:
		settings.show_tips = false
		settings.save()
		_update_tip())
	row.add_child(close)
	_office.add_child(_tip)
	_tip.resized.connect(_place_tip)
	get_window().size_changed.connect(_place_tip)
	_update_tip()


func _update_tip() -> void:
	if _tip == null:
		return
	_tip.visible = settings.show_tips
	var away := scene.ceo_driver != null and scene.ceo_driver.away
	_tip_label.text = labels.t("Press H or click the CEO's desk to send the CEO back" if away
		else "Move the CEO with the arrow keys ← ↑ ↓ → or click where to go")
	_tip.reset_size()
	_place_tip()


## Centered along the bottom of the window.
func _place_tip() -> void:
	if _tip == null:
		return
	var size := Vector2(get_window().size)
	_tip.position = Vector2(roundf((size.x - _tip.size.x) / 2.0), size.y - _tip.size.y - 10.0)


# --- The tray and the window ------------------------------------------------------------------

func _build_tray() -> void:
	_menu.prefer_native_menu = true
	_menu.id_pressed.connect(_on_menu)
	_menu.about_to_popup.connect(_sync_menu)
	add_child(_menu)
	_icon = (load("res://shared/icons/app-icon-1024.png") as Texture2D).get_image()
	_icon.resize(64, 64, Image.INTERPOLATE_LANCZOS)
	_fill_menu()
	add_child(_tray)
	_tray.menu = _tray.get_path_to(_menu)
	_tray.pressed.connect(func(button: int, _at: Vector2i) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_set_shown(true))
	_sync_menu()


## The tray menu, with a line at the top for each update available (spec: Updates), and the tray
## icon, with a red dot while there is one.
func _fill_menu() -> void:
	_menu.clear()
	var app: Variant = updater.app_update()
	var plugin := updater.plugin_update()
	if app != null:
		_menu.add_item(labels.t("agent-town %@ is available…", [app["version"]]), Menu.APP_UPDATE)
	if plugin != "":
		_menu.add_item(labels.t("town-link %@ is available…", [plugin]), Menu.PLUGIN_UPDATE)
	if app != null or plugin != "":
		_menu.add_separator()
	_menu.add_item(labels.t("About agent-town"), Menu.ABOUT)
	_menu.add_separator()
	_menu.add_check_item(labels.t("Show agent-town"), Menu.SHOW)
	_menu.add_check_item(labels.t("Stay on top"), Menu.ON_TOP)
	_menu.add_check_item(labels.t("Sound"), Menu.SOUND)
	_menu.add_separator()
	_menu.add_item(labels.t("Settings…"), Menu.SETTINGS)
	_menu.add_separator()
	_menu.add_item(labels.t("Quit agent-town"), Menu.QUIT)
	_sync_menu()
	var dot := updater.has_update()
	_tray.icon = ImageTexture.create_from_image(with_dot(_icon) if dot else _icon)
	_tray.tooltip = labels.t("agent-town: an update is available") if dot else "agent-town"


## The icon with a red dot about half its height in the top-right corner, and a thin transparent
## ring cut around the dot so it stands apart from the building.
static func with_dot(icon: Image) -> Image:
	var img := icon.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var n := img.get_width()
	var r := n / 4.0
	var c := Vector2(n - r, r)
	var ring := maxf(2.0, n / 24.0)
	for y in ceili(2.0 * r + ring):
		for x in range(floori(n - 2.0 * r - ring), n):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r:
				img.set_pixel(x, y, Color(0.92, 0.2, 0.18))
			elif d <= r + ring:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return img


func _sync_menu() -> void:
	_menu.set_item_checked(_menu.get_item_index(Menu.SHOW), settings.show_window)
	_menu.set_item_checked(_menu.get_item_index(Menu.ON_TOP), settings.stay_on_top)
	_menu.set_item_checked(_menu.get_item_index(Menu.SOUND), settings.sound)


## The Updates window, in front: opened if it is closed, raised if it is behind Settings.
func _show_updates() -> void:
	if not _updates_window.visible:
		_updates_window.popup_centered()
	_updates_window.move_to_foreground()
	_updates_window.grab_focus()


func _on_menu(id: int) -> void:
	match id:
		Menu.APP_UPDATE, Menu.PLUGIN_UPDATE:
			_show_updates()
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


## Settings → Office: the tips, and whether idle project blocks hide. `--hide-idle N` turns hiding
## on for this run with N seconds, without saving (for checking it with a demo).
func _apply_office() -> void:
	_update_tip()
	scene.hide_idle = settings.hide_idle_blocks
	scene.idle_seconds = settings.idle_hide_seconds
	if _args.has("hide-idle"):
		scene.hide_idle = true
		scene.idle_seconds = TownSettings.clamp_idle_hide(float(_args["hide-idle"]))


## The sound settings: the menu's Sound item, the volume, each sound's switch and choice, and the
## completion threshold (applied where the building decides whether a finished ticket plays it).
func _apply_sounds() -> void:
	audio.muted = not settings.sound or _args.get("sound", "") == "no" # --sound no: quiet for this run
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
	var width := mini(maxi(settings.window_width, MIN_SIZE.x), rect.size.x) if settings.window_width > 0 else w.size.x
	var height := mini(maxi(settings.window_height, MIN_SIZE.y), rect.size.y) if settings.window_height > 0 else w.size.y
	w.size = Vector2i(width, height)
	w.position = pos


func _remember_window() -> void:
	var w := get_window()
	settings.window_position = w.position
	settings.window_width = w.size.x
	settings.window_height = w.size.y
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
## A window the user made shorter than the office (`before`, the office it was showing) keeps its
## height and auto-scrolls instead, so a small window on a laptop stays small.
func _fit_window(before: Variant = null) -> void:
	var w := get_window()
	if w.mode != Window.MODE_WINDOWED:
		_update_camera()
		return
	var ppm := minf(PIXELS_PER_METER, maxf(MIN_PIXELS_PER_METER, float(w.size.x) / maxf(1.0, scene.office_size.x)))
	var usable := DisplayServer.screen_get_usable_rect(w.current_screen)
	if before != null and (before as Vector2) != Vector2.ZERO:
		var shown := (before as Vector2).y * sin(TownScene.PITCH) * ppm
		if w.size.y < shown - 2.0 and w.size.y < usable.size.y - 42:
			_update_camera()
			return
	var wanted := maxi(MIN_HEIGHT, ceili(_office_pixels(ppm).y))
	var height := mini(wanted, usable.size.y - 40)
	if absi(w.size.y - height) > 1:
		var top := w.position.y
		w.size = Vector2i(w.size.x, height)
		w.position = Vector2i(w.position.x, maxi(usable.position.y + 30, mini(top, usable.end.y - height)))
	_update_camera()


# --- Auto-scroll ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_auto_clock += delta
	if _auto_clock >= 0.033: # about 30 times a second
		_auto_clock = 0.0
		_auto_scroll_step()


func _pause_auto_scroll() -> void:
	_auto_paused_until = Time.get_ticks_msec() + AUTO_SCROLL_PAUSE
	_auto_target = null


## The floor spots of characters walking now: those whose position in their block changed since
## the last look (a block moving down when another is added does not count). A walker stays counted
## 0.6 s after stopping, so a pause between legs of a walk does not drop it.
func _movers(now: int) -> Array[Vector2]:
	var seen: Dictionary = {}
	var out: Array[Vector2] = []
	for c: Dictionary in scene.character_spots():
		var id: String = c["id"]
		seen[id] = c["local"]
		if _seen_spots.has(id) and (_seen_spots[id] as Vector3).distance_to(c["local"]) > 0.002:
			_moving_until[id] = now + 600
		if int(_moving_until.get(id, 0)) > now:
			out.append(c["floor"])
	_seen_spots = seen
	for id: String in _moving_until.keys():
		if not seen.has(id) or int(_moving_until[id]) <= now:
			_moving_until.erase(id)
	return out


## One step of auto-scroll: when the office does not fit, ease the view toward the window-sized
## area with the most walking characters. Walking the CEO and the user's own scrolling come first.
## Port of `autoScrollStep` in app/macos/Sources/AgentTown/TownView.swift.
func _auto_scroll_step() -> void:
	var size := Vector2(get_window().size)
	var lim := _pan_limit(size)
	if lim.x <= 0.01 and lim.y <= 0.01:
		return # the whole office is in view
	var now := Time.get_ticks_msec()
	var movers := _movers(now)
	if now < _auto_paused_until:
		return
	var ppm := pixels_per_meter(size)
	var half := Vector2(size.x / ppm / 2.0, size.y / ppm / 2.0 / sin(TownScene.PITCH))
	var middle := scene.office_size / 2.0
	var current := middle + pan.clamp(-lim, lim)
	var center: Variant = ViewFocus.best_center(movers, current, half * 0.8)
	if center != null:
		_auto_target = ((center as Vector2) - middle).clamp(-lim, lim)
	if _auto_target == null:
		return
	var from := pan.clamp(-lim, lim)
	var d: Vector2 = (_auto_target as Vector2) - from
	if d.length() <= 0.01:
		return
	pan = from + d * 0.12 # eases in over about half a second
	_update_camera()


## --resize WxH: 8 seconds in, once the demo's blocks are open, shrink the window as a user's drag
## would, to see auto-scroll.
func _resize_later(spec: String) -> void:
	var wh := spec.split("x")
	if wh.size() != 2:
		return
	await get_tree().create_timer(8.0).timeout
	get_window().size = Vector2i(maxi(int(wh[0]), MIN_SIZE.x), maxi(int(wh[1]), MIN_SIZE.y))


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


## `--clicks "95:270@2,300:500@6"` clicks the left mouse button at window pixels x:y at each time
## in seconds, through the normal input path, for checking the CEO.
func _click_at(spec: String) -> void:
	var elapsed := 0.0
	for item: String in spec.split(","):
		var at := item.split("@")
		var xy := at[0].split(":")
		var t := float(at[1]) if at.size() > 1 else elapsed + 1.0
		await get_tree().create_timer(maxf(0.0, t - elapsed)).timeout
		elapsed = t
		for pressed: bool in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.position = Vector2(float(xy[0]), float(xy[1]))
			e.global_position = e.position
			e.pressed = pressed
			Input.parse_input_event(e)


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
		if updater.has_update(): # the tray icon with its dot, to look at
			(_tray.icon as ImageTexture).get_image().save_png("%s-tray.png" % out.get_basename())
		for w: Window in [_settings_window, _about_window, _updates_window]:
			if w.visible: # an open window from --open is saved beside it
				var extra := "%s-%s.png" % [out.get_basename(), w.title.to_lower().replace(" ", "-")]
				w.get_texture().get_image().save_png(extra)
				print("snapshot: ", extra)
	get_tree().quit()

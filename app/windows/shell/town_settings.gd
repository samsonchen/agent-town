class_name TownSettings
extends RefCounted
## The user's choices from the tray menu and Settings, kept in %APPDATA%\agent-town\settings.cfg so
## they survive a restart. Port of `Prefs` in app/macos/Sources/AgentTown/Preferences.swift.

const OPACITY_MIN := 0.1
const OPACITY_MAX := 1.0
const SOUNDS: Array[String] = ["dispatch", "completion", "approval"]
const THRESHOLD_MAX := 3600
const IDLE_HIDE_MIN := 1
const IDLE_HIDE_MAX := 3600

var path: String
var language := "" ## "", "en" or "zh-Hant"; "" follows Windows
var stay_on_top := false
var sound := true
var show_tips := true ## the closable tips in the window
var hide_idle_blocks := false ## project blocks show only while they have work
var idle_hide_seconds := 5 ## how long a block's work must have settled before it hides
var compact_view := false ## the office at half size; applies after a restart
var check_updates := true ## check GitHub for a newer app and town-link once a day (spec: Updates)
var last_update_check := 0 ## unix time of the last answered check; 0 before any
var show_window := true
var opacity := 1.0
var window_position: Variant = null ## Vector2i, or null before the first save
var window_width := 0
var window_screen := -1
var window_height := 0 ## 0 before the first save; the height follows the office unless the user made it shorter
var _window_section := "window" ## "window_compact" in compact view: each view keeps its own size
# Sounds (spec: sound settings). A choice is "" for the default, "media:<name>" for a sound in
# C:\Windows\Media, or "file:<path>" for a file of the user's own.
var volume := 1.0 ## 0 to 1, agent-town's own sounds only
var sound_on: Dictionary = {"dispatch": true, "completion": true, "approval": true}
var sound_choice: Dictionary = {"dispatch": "", "completion": "", "approval": ""}
var completion_threshold := 0 ## seconds a task must take before the completion sound plays

var _cfg := ConfigFile.new()


func _init(p_path: String = "") -> void:
	path = p_path if p_path != "" else OS.get_environment("APPDATA").path_join("agent-town").path_join("settings.cfg")
	if _cfg.load(path) != OK:
		return
	language = _cfg.get_value("app", "language", language)
	if not language in ["", "en", "zh-Hant"]:
		language = ""
	stay_on_top = bool(_cfg.get_value("app", "stay_on_top", stay_on_top))
	sound = bool(_cfg.get_value("app", "sound", sound))
	show_tips = bool(_cfg.get_value("app", "show_tips", show_tips))
	hide_idle_blocks = bool(_cfg.get_value("app", "hide_idle_blocks", hide_idle_blocks))
	idle_hide_seconds = clamp_idle_hide(_cfg.get_value("app", "idle_hide_seconds", 5))
	compact_view = bool(_cfg.get_value("app", "compact_view", false))
	check_updates = bool(_cfg.get_value("updates", "check_automatically", true))
	last_update_check = int(_cfg.get_value("updates", "last_check", 0))
	show_window = bool(_cfg.get_value("app", "show_window", show_window))
	opacity = clamp_opacity(_cfg.get_value("app", "opacity", opacity))
	_read_window("window")
	volume = clamp_volume(_cfg.get_value("sounds", "volume", volume))
	completion_threshold = clamp_threshold(_cfg.get_value("sounds", "completion_threshold", 0))
	for key in SOUNDS:
		sound_on[key] = bool(_cfg.get_value("sounds", key + "_on", true))
		var c: Variant = _cfg.get_value("sounds", key + "_choice", "")
		sound_choice[key] = c if typeof(c) == TYPE_STRING and (c == "" or c.begins_with("media:") or c.begins_with("file:")) else ""


## The saved place of the window in the view the app runs in. The first time in compact view: the
## normal window's top-left corner, at half its height, and wide enough for the office at compact
## view's full scale (`full_width` pixels).
func use_view(compact: bool, full_width: int) -> void:
	_window_section = "window_compact" if compact else "window"
	if _cfg.has_section_key(_window_section, "position"):
		_read_window(_window_section)
	elif compact and window_position != null:
		window_width = mini(window_width, maxi(window_width / 2, full_width)) if window_width > 0 else full_width
		window_height = window_height / 2
	else:
		window_position = null


func _read_window(section: String) -> void:
	# A null default means "none given" to ConfigFile, which logs an error, so check first.
	window_position = _cfg.get_value(section, "position") if _cfg.has_section_key(section, "position") else null
	window_width = int(_cfg.get_value(section, "width", 0))
	window_height = int(_cfg.get_value(section, "height", 0))
	window_screen = int(_cfg.get_value(section, "screen", -1))


## Stored values made safe to use: anything out of range, or not a number, is brought in.
static func clamp_volume(v: Variant) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 1.0
	var f := float(v)
	return 1.0 if is_nan(f) or is_inf(f) else clampf(f, 0.0, 1.0)


## Hide after: 1 to 3600 seconds, 5 when not a number.
static func clamp_idle_hide(v: Variant) -> int:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 5
	var f := float(v)
	return 5 if is_nan(f) or is_inf(f) else clampi(roundi(f), IDLE_HIDE_MIN, IDLE_HIDE_MAX)


static func clamp_threshold(v: Variant) -> int:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 0
	var f := float(v)
	return 0 if is_nan(f) or is_inf(f) else clampi(int(f), 0, THRESHOLD_MAX)


## Opacity: 10%–100%.
static func clamp_opacity(v: Variant) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return OPACITY_MAX
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return OPACITY_MAX
	return clampf(f, OPACITY_MIN, OPACITY_MAX)


func save() -> void:
	_cfg.set_value("app", "language", language)
	_cfg.set_value("app", "stay_on_top", stay_on_top)
	_cfg.set_value("app", "sound", sound)
	_cfg.set_value("app", "show_tips", show_tips)
	_cfg.set_value("app", "hide_idle_blocks", hide_idle_blocks)
	_cfg.set_value("app", "idle_hide_seconds", idle_hide_seconds)
	_cfg.set_value("app", "compact_view", compact_view)
	_cfg.set_value("updates", "check_automatically", check_updates)
	_cfg.set_value("updates", "last_check", last_update_check)
	_cfg.set_value("app", "show_window", show_window)
	_cfg.set_value("app", "opacity", opacity)
	_cfg.set_value("sounds", "volume", volume)
	_cfg.set_value("sounds", "completion_threshold", completion_threshold)
	for key in SOUNDS:
		_cfg.set_value("sounds", key + "_on", sound_on[key])
		_cfg.set_value("sounds", key + "_choice", sound_choice[key])
	if window_position != null:
		_cfg.set_value(_window_section, "position", window_position)
		_cfg.set_value(_window_section, "width", window_width)
		_cfg.set_value(_window_section, "height", window_height)
		_cfg.set_value(_window_section, "screen", window_screen)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_cfg.save(path)

class_name TownSettings
extends RefCounted
## The user's choices from the tray menu and Settings, kept in %APPDATA%\agent-town\settings.cfg so
## they survive a restart. Port of `Prefs` in app/macos/Sources/AgentTown/Preferences.swift.

const OPACITY_MIN := 0.1
const OPACITY_MAX := 1.0
const SOUNDS: Array[String] = ["dispatch", "completion", "approval"]
const THRESHOLD_MAX := 3600

var path: String
var language := "" ## "", "en" or "zh-Hant"; "" follows Windows
var stay_on_top := false
var sound := true
var show_window := true
var opacity := 1.0
var window_position: Variant = null ## Vector2i, or null before the first save
var window_width := 0
var window_screen := -1
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
	show_window = bool(_cfg.get_value("app", "show_window", show_window))
	opacity = clamp_opacity(_cfg.get_value("app", "opacity", opacity))
	# A null default means "none given" to ConfigFile, which logs an error, so check first.
	window_position = _cfg.get_value("window", "position") if _cfg.has_section_key("window", "position") else null
	window_width = int(_cfg.get_value("window", "width", 0))
	window_screen = int(_cfg.get_value("window", "screen", -1))
	volume = clamp_volume(_cfg.get_value("sounds", "volume", volume))
	completion_threshold = clamp_threshold(_cfg.get_value("sounds", "completion_threshold", 0))
	for key in SOUNDS:
		sound_on[key] = bool(_cfg.get_value("sounds", key + "_on", true))
		var c: Variant = _cfg.get_value("sounds", key + "_choice", "")
		sound_choice[key] = c if typeof(c) == TYPE_STRING and (c == "" or c.begins_with("media:") or c.begins_with("file:")) else ""


## Stored values made safe to use: anything out of range, or not a number, is brought in.
static func clamp_volume(v: Variant) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 1.0
	var f := float(v)
	return 1.0 if is_nan(f) or is_inf(f) else clampf(f, 0.0, 1.0)


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
	_cfg.set_value("app", "show_window", show_window)
	_cfg.set_value("app", "opacity", opacity)
	_cfg.set_value("sounds", "volume", volume)
	_cfg.set_value("sounds", "completion_threshold", completion_threshold)
	for key in SOUNDS:
		_cfg.set_value("sounds", key + "_on", sound_on[key])
		_cfg.set_value("sounds", key + "_choice", sound_choice[key])
	if window_position != null:
		_cfg.set_value("window", "position", window_position)
		_cfg.set_value("window", "width", window_width)
		_cfg.set_value("window", "screen", window_screen)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_cfg.save(path)

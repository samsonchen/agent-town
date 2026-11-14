class_name WindowPresence
extends Node
## "Hide the window when no Claude Code session is open" (docs/spec.md → Settings (app)). The office
## window hides a few seconds after the last session closes, so a Chief walking out is seen and a
## `/clear` does not make it blink, and comes back, without taking the focus, when a session opens.
## "Show agent-town" keeps meaning that the user wants the window: the app's show_window setting
## stays on while the window is hidden this way. Port of `WindowPresence` in
## app/macos/Sources/AgentTown/WindowPresence.swift.

signal hide_window ## hide the office window, leaving show_window on
signal show_window ## show it again without taking the focus

const DELAY := 5.0 ## seconds without a session before the window hides

var enabled := false ## the setting
var auto_hidden := false ## the window is hidden because no session is open
## Whether the user wants the window (the tray's Show agent-town); set by the app.
var user_wants_window: Callable = func() -> bool: return true

var _has_sessions := false
var _known := false ## sessions_changed has been called once
var _hide_in := -1.0 ## seconds until the hide; below 0 when none is pending


## Any block with a Chief of Staff in it: a session is open.
static func sessions_open(building: Building) -> bool:
	for b: Building.Block in building.blocks.values():
		if not b.chiefs.is_empty():
			return true
	return false


## Called with the current answer after every change in the building; only a change counts, as a
## session's other events must not restart the countdown. The first call starts it at launch.
func sessions_changed(open: bool) -> void:
	if _known and open == _has_sessions:
		return
	_known = true
	_has_sessions = open
	_evaluate()


func set_enabled(on: bool) -> void:
	enabled = on
	_evaluate()


## The user chose Show agent-town: the window shows now, even with no session, and hides again
## only after the next session closes.
func show_now() -> void:
	_hide_in = -1.0
	auto_hidden = false


func is_pending() -> bool:
	return _hide_in >= 0.0


func _evaluate() -> void:
	if not enabled or _has_sessions:
		_hide_in = -1.0
		if auto_hidden:
			auto_hidden = false
			if user_wants_window.call():
				show_window.emit()
		return
	if not auto_hidden and _hide_in < 0.0:
		_hide_in = DELAY


func _process(delta: float) -> void:
	tick(delta)


## Moves the hide's countdown on by `delta` seconds (the tests call it directly).
func tick(delta: float) -> void:
	if _hide_in < 0.0:
		return
	_hide_in -= delta
	if _hide_in > 0.0:
		return
	_hide_in = -1.0
	if enabled and not _has_sessions and user_wants_window.call():
		auto_hidden = true
		hide_window.emit()

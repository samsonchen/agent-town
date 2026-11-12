class_name TownStore
extends Node
## Holds the building state. Events arrive from the loopback server, are put in order, applied,
## and each resulting change is emitted for the choreographer. Port of
## app/macos/Sources/AgentTown/TownStore.swift.
##
## TOWN_LOG=<file>: appends what arrives and what changes, for debugging the live app.

signal changed(change: Dictionary)
signal plugin_versions_changed ## a session opened with its town-link version, or closed

const STALE_CHECK_MS := 5000

var building := Building.new()
var server := LoopbackServer.new()
var last_event_ms := -1 ## the app's clock when the last batch arrived; -1 before any
## session id -> its town-link version from session.open ("" when it sent none: town-link 1.0.2 or
## older), for open sessions only (spec: Updates).
var plugin_versions: Dictionary = {}

var _sequencer := Sequencer.new()
var _last_expiry_ms := 0
var _log_path := OS.get_environment("TOWN_LOG")


## Starts the server. `endpoint_path` is for tests; the app leaves it empty.
func start(app_version: String, endpoint_path: String = "") -> Error:
	var err := server.start(app_version, endpoint_path)
	if err == OK:
		_log("listening on 127.0.0.1:%d, endpoint %s" % [server.port, server.endpoint_path])
	else:
		push_error("agent-town: could not start the loopback server or write the endpoint file (%s)" % error_string(err))
	return err


func _exit_tree() -> void:
	server.stop()


func _process(_delta: float) -> void:
	tick(Time.get_ticks_msec())


## One step: take new batches, release events that waited long enough, expire stale sessions.
## Public so tests can drive it with their own clock.
func tick(now_ms: int) -> void:
	for batch: Dictionary in server.poll(now_ms):
		receive(batch, now_ms)
	_apply(_sequencer.flush(now_ms), now_ms)
	if now_ms - _last_expiry_ms > STALE_CHECK_MS:
		_last_expiry_ms = now_ms
		_emit(building.expire_stale(now_ms))
		_prune_plugin_versions()


func receive(batch: Dictionary, now_ms: int) -> void:
	last_event_ms = now_ms
	var events: Array = batch["events"]
	_log("batch protocol=%d events=%d" % [int(batch.get("protocol", 0)), events.size()])
	for e: TownEvent in events:
		_apply(_sequencer.push(e, now_ms), now_ms)


func _apply(events: Array[TownEvent], now_ms: int) -> void:
	for e in events:
		# The whole event: full session and project IDs, the sender's clock and every field, so a
		# log shows exactly what town-link sent (for example the projectName of a session.open).
		_log("event %s seq=%d ts=%d session=%s project=%s fields=%s" % [e.type, e.seq, e.ts, e.session_id,
			JSON.stringify(e.project_id), JSON.stringify(e.fields)])
		_emit(building.apply(e, now_ms))
		if e.type == "session.open": # after the building has the session, for its project name
			var v: Variant = e.string("pluginVersion")
			var version: String = v if v != null else ""
			if plugin_versions.get(e.session_id) != version:
				plugin_versions[e.session_id] = version
				plugin_versions_changed.emit()
	if not events.is_empty():
		_prune_plugin_versions()


## Forgets the versions of sessions that have closed or expired.
func _prune_plugin_versions() -> void:
	var open: Dictionary = {}
	for b: Building.Block in building.blocks.values():
		for s: String in b.chiefs:
			open[s] = true
	var gone := plugin_versions.keys().filter(func(s: String) -> bool: return not open.has(s))
	if gone.is_empty():
		return
	for s: String in gone:
		plugin_versions.erase(s)
	plugin_versions_changed.emit()


## The project name of an open session, or "".
func project_name_of(session_id: String) -> String:
	for b: Building.Block in building.blocks.values():
		if b.chiefs.has(session_id):
			return b.name
	return ""


func _emit(changes: Array[Dictionary]) -> void:
	for c in changes:
		_log("change %s" % _describe(c))
		changed.emit(c)


func _log(line: String) -> void:
	if _log_path == "":
		return
	var f := FileAccess.open(_log_path, FileAccess.READ_WRITE if FileAccess.file_exists(_log_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line("%s %s" % [Time.get_datetime_string_from_system(false, true), line])
	f.close()


static func _describe(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: String in c:
		if k != "kind" and k != "ticket":
			parts.append("%s=%s" % [k, c[k]])
	return "%s(%s)" % [c["kind"], ", ".join(parts)]

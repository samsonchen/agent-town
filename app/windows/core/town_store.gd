class_name TownStore
extends Node
## Holds the building state. Events arrive from the loopback server, are put in order, applied,
## and each resulting change is emitted for the choreographer. Port of
## app/macos/Sources/AgentTown/TownStore.swift.
##
## TOWN_LOG=<file>: appends what arrives and what changes, for debugging the live app.

signal changed(change: Dictionary)

const STALE_CHECK_MS := 5000

var building := Building.new()
var server := LoopbackServer.new()
var last_event_ms := -1 ## the app's clock when the last batch arrived; -1 before any

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


func receive(batch: Dictionary, now_ms: int) -> void:
	last_event_ms = now_ms
	for e: TownEvent in batch["events"]:
		_apply(_sequencer.push(e, now_ms), now_ms)


func _apply(events: Array[TownEvent], now_ms: int) -> void:
	for e in events:
		_log("event %s seq=%d session=%s project=%s" % [e.type, e.seq, e.session_id.left(8), e.project_id])
		_emit(building.apply(e, now_ms))


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
	f.store_line("%s %s" % [Time.get_datetime_string_from_system(true), line])
	f.close()


static func _describe(c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: String in c:
		if k != "kind" and k != "ticket":
			parts.append("%s=%s" % [k, c[k]])
	return "%s(%s)" % [c["kind"], ", ".join(parts)]

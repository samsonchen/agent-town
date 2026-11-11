class_name Sequencer
extends RefCounted
## Puts each session's events in `seq` order. An event that arrives early waits up to `window_ms`
## for the missing ones; after that it is applied anyway (docs/protocol.md: receiver rules).
## Port of the Sequencer in app/macos/Sources/TownCore/Ordering.swift.

var window_ms: int
var _next: Dictionary = {} ## session_id -> next expected seq
var _waiting: Dictionary = {} ## session_id -> Array of [TownEvent, arrived_ms], sorted by seq


func _init(p_window_ms: int = 500) -> void:
	window_ms = p_window_ms


## Accepts an event; returns the events now ready, in order.
func push(e: TownEvent, now_ms: int) -> Array[TownEvent]:
	var s := e.session_id
	if not _next.has(s):
		# First event seen for a session: start from it (the app may have started late).
		_next[s] = e.seq + 1
		return _with(e, _drain(s))
	var expected: int = _next[s]
	if e.seq < expected:
		return [e] # late duplicate or restart: apply as it comes
	if e.seq == expected:
		_next[s] = e.seq + 1
		return _with(e, _drain(s))
	if not _waiting.has(s):
		_waiting[s] = []
	var list: Array = _waiting[s]
	list.append([e, now_ms])
	list.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as TownEvent).seq < (b[0] as TownEvent).seq)
	return []


## Releases events that have waited longer than the window.
func flush(now_ms: int) -> Array[TownEvent]:
	var out: Array[TownEvent] = []
	var sessions: Array = _waiting.keys()
	sessions.sort()
	for s: String in sessions:
		var list: Array = _waiting[s]
		if list.is_empty() or now_ms - int(list[0][1]) < window_ms:
			continue
		_next[s] = (list[0][0] as TownEvent).seq
		out.append_array(_drain(s))
	return out


func _drain(s: String) -> Array[TownEvent]:
	var out: Array[TownEvent] = []
	if not _waiting.has(s):
		return out
	var list: Array = _waiting[s]
	while not list.is_empty() and (list[0][0] as TownEvent).seq <= int(_next[s]):
		var e: TownEvent = list.pop_front()[0]
		out.append(e)
		_next[s] = maxi(int(_next[s]), e.seq + 1)
	if list.is_empty():
		_waiting.erase(s)
	return out


static func _with(first: TownEvent, rest: Array[TownEvent]) -> Array[TownEvent]:
	var out: Array[TownEvent] = [first]
	out.append_array(rest)
	return out

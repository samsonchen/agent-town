class_name TownEvent
extends RefCounted
## One protocol event: the envelope plus its other fields (docs/protocol.md).
## Port of app/macos/Sources/TownCore/Events.swift.

const ENVELOPE_KEYS: Array[String] = ["type", "sessionId", "seq", "ts", "projectId"]

var type: String
var session_id: String
var seq: int
var ts: int
var project_id: String
var fields: Dictionary = {}


static func make(p_type: String, p_session_id: String, p_seq: int, p_ts: int, p_project_id: String, p_fields: Dictionary = {}) -> TownEvent:
	var e := TownEvent.new()
	e.type = p_type
	e.session_id = p_session_id
	e.seq = p_seq
	e.ts = p_ts
	e.project_id = p_project_id
	e.fields = p_fields
	return e


## Parses one event from a decoded JSON object. Returns null when the envelope is missing or mistyped.
static func from_json(d: Variant) -> TownEvent:
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var all: Dictionary = d
	for k: String in ["type", "sessionId", "projectId"]:
		if typeof(all.get(k)) != TYPE_STRING:
			return null
	for k: String in ["seq", "ts"]:
		if not _is_number(all.get(k)):
			return null
	var f: Dictionary = {}
	for k: Variant in all:
		if not ENVELOPE_KEYS.has(k):
			f[k] = all[k]
	return make(all["type"], all["sessionId"], int(all["seq"]), int(all["ts"]), all["projectId"], f)


## A string field, or null when it is absent or not a string.
func string(k: String) -> Variant:
	var v: Variant = fields.get(k)
	return v if typeof(v) == TYPE_STRING else null


## A number field as an int, or null when it is absent or not a number.
func number(k: String) -> Variant:
	var v: Variant = fields.get(k)
	return int(v) if _is_number(v) else null


## A bool field, or null when it is absent or not a bool.
func boolean(k: String) -> Variant:
	var v: Variant = fields.get(k)
	return v if typeof(v) == TYPE_BOOL else null


## The string items of an array field; others are skipped.
func strings(k: String) -> Array[String]:
	var out: Array[String] = []
	var v: Variant = fields.get(k)
	if typeof(v) == TYPE_ARRAY:
		for x: Variant in v:
			if typeof(x) == TYPE_STRING:
				out.append(x)
	return out


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## The body of a POST to /v1/events: `{ "protocol": 1, "events": [...] }`.
## Returns { "protocol": int, "events": Array[TownEvent] }, or null when the body is not a batch.
## Events that do not parse are skipped, not fatal.
static func decode_batch(text: String) -> Variant:
	var json := JSON.new() # not JSON.parse_string, which logs an error for every bad body
	if json.parse(text) != OK:
		return null
	var d: Variant = json.data
	if typeof(d) != TYPE_DICTIONARY or not _is_number(d.get("protocol")) or typeof(d.get("events")) != TYPE_ARRAY:
		return null
	var events: Array[TownEvent] = []
	for raw: Variant in d["events"]:
		var e := from_json(raw)
		if e != null:
			events.append(e)
	return {"protocol": int(d["protocol"]), "events": events}

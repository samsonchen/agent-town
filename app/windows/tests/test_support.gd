class_name TestSupport
extends RefCounted
## Base for test suites: `check` records a failure instead of stopping, like Swift's #expect.

var failures := PackedStringArray()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func check_eq(got: Variant, want: Variant, what: String) -> void:
	var diff := TestSupport.first_difference(got, want, "")
	if diff != "":
		failures.append("%s: %s" % [what, diff])


## The repo root, two folders above the Godot project.
static func repo_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../..").simplify_path()


## The events of protocol/fixtures/<name>.json.
static func fixture(name: String) -> Array[TownEvent]:
	var text := FileAccess.get_file_as_string(repo_root().path_join("protocol/fixtures/%s.json" % name))
	var batch: Variant = TownEvent.decode_batch(text)
	var out: Array[TownEvent] = []
	if batch != null:
		out = batch["events"]
	return out


## Shorthand for an event in session "s" of project "p", with ts = seq unless given.
static func ev(type: String, seq: int, fields: Dictionary = {}, ts: int = -1) -> TownEvent:
	return TownEvent.make(type, "s", seq, seq if ts < 0 else ts, "p", fields)


## Compares two JSON-like values. Numbers compare by value (JSON parsing gives floats, the port
## keeps ints). Returns "" when equal, else where they first differ.
static func first_difference(got: Variant, want: Variant, path: String) -> String:
	var gn := typeof(got) == TYPE_INT or typeof(got) == TYPE_FLOAT
	var wn := typeof(want) == TYPE_INT or typeof(want) == TYPE_FLOAT
	if gn and wn:
		return "" if float(got) == float(want) else "%s: got %s, want %s" % [path, got, want]
	if typeof(got) != typeof(want):
		return "%s: got %s, want %s" % [path, JSON.stringify(got), JSON.stringify(want)]
	match typeof(want):
		TYPE_DICTIONARY:
			var g: Dictionary = got
			var w: Dictionary = want
			for k: Variant in w:
				if not g.has(k):
					return "%s.%s: missing (want %s)" % [path, k, JSON.stringify(w[k])]
			for k: Variant in g:
				if not w.has(k):
					return "%s.%s: unexpected %s" % [path, k, JSON.stringify(g[k])]
			for k: Variant in w:
				var d := first_difference(g[k], w[k], "%s.%s" % [path, k])
				if d != "":
					return d
			return ""
		TYPE_ARRAY:
			var g: Array = got
			var w: Array = want
			if g.size() != w.size():
				return "%s: %d items, want %d" % [path, g.size(), w.size()]
			for i in w.size():
				var d := first_difference(g[i], w[i], "%s[%d]" % [path, i])
				if d != "":
					return d
			return ""
		_:
			return "" if got == want else "%s: got %s, want %s" % [path, JSON.stringify(got), JSON.stringify(want)]

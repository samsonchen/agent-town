class_name TownLabels
extends RefCounted
## UI text in the user's language, plus task type and role labels and outfit colors from catalog/*.json.
## Port of `Labels` in app/macos/Sources/AgentTown/Layout.swift.
##
## UI strings are keyed by their English text, read from the macOS app's Localizable.strings
## (copied to res://shared/strings/). A missing translation shows the English.

const SHARED := "res://shared/"
const TITLE_WIDTH := 20 ## a task title on a sign shows whole up to this many columns; wider ones scroll

var language: String ## "en" or "zh-Hant"
var locale: String ## the key for this language in catalog labels ("en", "zh-TW")
var neutral_color := "#D1D5DB"

var _strings: Dictionary = {}
var _task_types: Dictionary = {} ## id -> {locale: label}
var _roles: Dictionary = {} ## id -> {locale: label}
var _role_department: Dictionary = {}
var _department_color: Dictionary = {}


## `choice` is the Settings language ("en", "zh-Hant"); empty follows Windows.
func _init(choice: String = "") -> void:
	language = choice if choice in ["en", "zh-Hant"] else language_for_locale(OS.get_locale())
	locale = "zh-TW" if language == "zh-Hant" else "en"
	if language != "en":
		_strings = parse_strings(FileAccess.get_file_as_string(SHARED + "strings/%s.lproj/Localizable.strings" % language))
	var tt: Variant = _json(SHARED + "catalog/task-types.json")
	if tt is Dictionary:
		for t: Dictionary in tt.get("taskTypes", []):
			_task_types[t["id"]] = t["labels"]
	var r: Variant = _json(SHARED + "catalog/roles.json")
	if r is Dictionary:
		for role: Dictionary in r.get("roles", []):
			_roles[role["id"]] = role["labels"]
			_role_department[role["id"]] = role["department"]
		for d: Dictionary in r.get("departments", []):
			_department_color[d["id"]] = d["color"]
		neutral_color = r.get("neutralColor", neutral_color)


## The language for a Windows locale (docs/windows/spec.md): Traditional Chinese for Taiwan,
## Hong Kong, Macau and any Hant script; English for everything else, Simplified Chinese included.
static func language_for_locale(loc: String) -> String:
	var l := loc.replace("-", "_").to_lower()
	if not (l == "zh" or l.begins_with("zh_")):
		return "en"
	var parts := l.split("_")
	if parts.has("hant") or parts.has("tw") or parts.has("hk") or parts.has("mo"):
		return "zh-Hant"
	return "en"


## Parses a .strings file: `"key" = "value";` lines, with /* */ comments and \" \n \\ escapes.
static func parse_strings(text: String) -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.create_from_string('"((?:[^"\\\\]|\\\\.)*)"\\s*=\\s*"((?:[^"\\\\]|\\\\.)*)"\\s*;')
	for m in re.search_all(text):
		out[_unescape(m.get_string(1))] = _unescape(m.get_string(2))
	return out


static func _unescape(s: String) -> String:
	return s.replace("\\n", "\n").replace("\\\"", "\"").replace("\\\\", "\\")


## The UI text for an English key in the chosen language, with `args` put in for %@ and %lld
## (and %1$@, %2$@ … in a translation that reorders them).
func t(english: String, args: Array = []) -> String:
	return format(_strings.get(english, english), args)


static func format(s: String, args: Array) -> String:
	var re := RegEx.create_from_string("%(?:(\\d+)\\$)?(@|lld|d)")
	var out := ""
	var at := 0
	var next := 0
	for m in re.search_all(s):
		out += s.substr(at, m.get_start() - at)
		var i := next
		if m.get_string(1) != "":
			i = m.get_string(1).to_int() - 1
		else:
			next += 1
		out += str(args[i]) if i < args.size() else m.get_string()
		at = m.get_end()
	return out + s.substr(at)


func task_type(id: String) -> String:
	return _label(_task_types, id)


func role(id: String) -> String:
	return _label(_roles, id)


func _label(table: Dictionary, id: String) -> String:
	var labels: Dictionary = table.get(id, {})
	return labels.get(locale, labels.get("en", id))


## The outfit color for a role: its department's color, else the neutral gray.
func color_for_role(id: Variant) -> String:
	if id == null or not _role_department.has(id):
		return neutral_color
	return _department_color.get(_role_department[id], neutral_color)


func operator_color() -> String:
	return _department_color.get("background", "#FF6B00")


# The fixed words the office shows.
func chief_of_staff() -> String: return t("Chief of Staff")
func ceo() -> String: return t("CEO")
func dispatcher() -> String: return t("Dispatcher")
func inspector() -> String: return t("Inspector")
func executive() -> String: return t("Executive office")
func server_room() -> String: return t("Server room")
func desk(n: int) -> String: return t("Desk %lld", [n])


## Width in columns: a CJK or full-width character counts 2, others 1.
static func display_width(s: String) -> int:
	var w := 0
	for i in s.length():
		w += 2 if is_wide(s.unicode_at(i)) else 1
	return w


static func is_wide(u: int) -> bool:
	return (u >= 0x1100 and u <= 0x115F) or (u >= 0x2E80 and u <= 0xA4CF) or (u >= 0xAC00 and u <= 0xD7A3) \
		or (u >= 0xF900 and u <= 0xFAFF) or (u >= 0xFE30 and u <= 0xFE4F) or (u >= 0xFF00 and u <= 0xFF60) \
		or (u >= 0xFFE0 and u <= 0xFFE6) or (u >= 0x20000 and u <= 0x3FFFD)


## "131k / 200K (66%) · last turn 137.5k", or what is known of it (spec: context bar).
func context_line(c: Building.ContextUsage) -> String:
	var line: String
	var pct := " (%d%%)" % int(c.percent) if c.percent != null else ""
	if c.tokens != null and c.window != null:
		line = "%s / %s%s" % [_used(int(c.tokens)), _size(int(c.window)), pct]
	elif c.window != null:
		line = t("%@ context", [_size(int(c.window))])
	else:
		line = t("Context —")
	if c.last_turn_tokens != null:
		line += " · " + t("last turn %@", [_one_decimal(int(c.last_turn_tokens))])
	return line


static func _used(n: int) -> String:
	if n >= 1_000_000:
		return "%.1fM" % (n / 1e6)
	return "%dk" % ((n + 500) / 1000) if n >= 1000 else str(n)


static func _size(n: int) -> String:
	if n >= 1_000_000:
		return "%dM" % ((n + 500_000) / 1_000_000)
	return "%dK" % ((n + 500) / 1000) if n >= 1000 else str(n)


static func _one_decimal(n: int) -> String:
	var f := func(v: float, unit: String) -> String:
		var r := roundf(v * 10.0) / 10.0
		return (str(int(r)) if r == roundf(r) else "%.1f" % r) + unit
	if n >= 1_000_000:
		return f.call(n / 1e6, "M")
	return f.call(n / 1e3, "k") if n >= 1000 else str(n)


static func _json(path: String) -> Variant:
	var j := JSON.new()
	return j.data if j.parse(FileAccess.get_file_as_string(path)) == OK else null

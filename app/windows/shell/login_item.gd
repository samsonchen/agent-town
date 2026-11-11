class_name LoginItem
extends RefCounted
## Opening agent-town when the user signs in to Windows: a value under the user's Run key, which
## also lists the app in Settings → Apps → Startup. Only the exported app can be one, not a run
## from the Godot editor. Port of `LoginItem` in app/macos/Sources/AgentTown/Preferences.swift.

const KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const VALUE := "agent-town"


static func is_available() -> bool:
	return OS.has_feature("template")


static func is_on() -> bool:
	if not is_available():
		return false
	var out: Array = []
	return OS.execute("reg", ["query", KEY, "/v", VALUE], out, true) == 0


## Turns it on or off. Returns "" when it worked, else Windows' reason.
static func set_on(on: bool) -> String:
	if not is_available():
		return ""
	var out: Array = []
	var code: int
	if on:
		code = OS.execute("reg", ["add", KEY, "/v", VALUE, "/t", "REG_SZ", "/d", "\"%s\"" % OS.get_executable_path(), "/f"], out, true)
	else:
		code = OS.execute("reg", ["delete", KEY, "/v", VALUE, "/f"], out, true)
	return "" if code == 0 else "\n".join(out).strip_edges()

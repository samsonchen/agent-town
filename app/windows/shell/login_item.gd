class_name LoginItem
extends RefCounted
## Opening agent-town when the user signs in to Windows: a value under the user's Run key, which
## also lists the app in Settings → Apps → Startup. Only the exported app can be one, not a run
## from the Godot editor, and not a Microsoft Store copy, whose startup task Windows Settings turns
## on (Distribution). Port of `LoginItem` in app/macos/Sources/AgentTown/Preferences.swift.

const KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const VALUE := "agent-town-claude-code"


static func is_available() -> bool:
	return OS.has_feature("template") and not Distribution.is_store()


static func is_on() -> bool:
	if not is_available():
		return false
	var out: Array = []
	return OS.execute("reg", ["query", KEY, "/v", VALUE], out, true) == 0


## The value's command: the exe's Windows path, with backslashes and in quotes. Explorer skips a
## command written with Godot's forward slashes (C:/Users/...) at sign-in without a word.
static func command(exe_path: String) -> String:
	return "\"%s\"" % exe_path.replace("/", "\\")


## Turns it on or off. Returns "" when it worked, else Windows' reason.
static func set_on(on: bool) -> String:
	if not is_available():
		return ""
	var out: Array = []
	var code: int
	if on:
		# reg.exe reads its arguments the C runtime's way, where \" is a quote kept in the value.
		var arg := command(OS.get_executable_path()).replace("\"", "\\\"")
		code = OS.execute("reg", ["add", KEY, "/v", VALUE, "/t", "REG_SZ", "/d", arg, "/f"], out, true)
	else:
		code = OS.execute("reg", ["delete", KEY, "/v", VALUE, "/f"], out, true)
	return "" if code == 0 else "\n".join(out).strip_edges()


## The command the value holds now, or "" when it is off.
static func current_command() -> String:
	if not is_available():
		return ""
	var out: Array = []
	if OS.execute("reg", ["query", KEY, "/v", VALUE], out, true) != 0:
		return ""
	for line: String in "\n".join(out).split("\n"):
		var at := line.find("REG_SZ")
		if at >= 0:
			return line.substr(at + "REG_SZ".length()).strip_edges()
	return ""


## When it is on but written for another path or the old way (forward slashes, no quotes, which
## Windows skipped), writes it again for this exe. Run at launch.
static func repair() -> void:
	var now := current_command()
	if now != "" and now != command(OS.get_executable_path()):
		set_on(true)

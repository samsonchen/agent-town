class_name Updater
extends Node
## Tells the user about a newer agent-town for Windows or a newer town-link (docs/spec.md: Updates),
## with the tray icon and menu only: no Windows notifications. It installs nothing: the installer
## and Claude Code's plugin commands do that. A Microsoft Store copy updates through the Store, so it
## checks only town-link (Distribution). Port of `Updater` in
## app/macos/Sources/AgentTown/Updates.swift.

signal changed
## Show the Updates window and bring it to the front (main.gd does it).
signal window_requested

const PLUGIN_COMMANDS: Array[String] = ["claude plugin marketplace update agent-town-claude-code", "claude plugin update town-link@agent-town-claude-code"]
const DAY := 24 * 3600
## After a failed check at launch, it tries again after these many seconds (at login the network
## may not be up yet).
const LAUNCH_RETRIES: Array[int] = [60, 120, 300, 600]

var settings: TownSettings
var store: TownStore
var app_version: String
var newest_app: Variant = null ## the newest Windows release (UpdateFeed.newest_release), once a check found one
var newest_plugin := "" ## town-link's version on main, once a check read it
var app_checked := false ## a check has read the releases (there may be no Windows release yet)
var outdated: Array[Dictionary] = [] ## {"id", "project", "version"}: open sessions with an older town-link
var checking := false
var last_check_failed := false
## A Microsoft Store copy: no check for a newer app, and app_update() is always null.
var store_build := Distribution.is_store()


func _init(p_settings: TownSettings, p_store: TownStore, p_version: String) -> void:
	settings = p_settings
	store = p_store
	app_version = p_version


## Starts watching the sessions' versions and, when `automatic`, checks 10 s after launch (again
## after 1, 2, 5 and 10 minutes while it fails) and then once a day while Check for updates automatically is on. `fake` makes up a newer app and town-link
## (99.0.0) without the network, to look at the notices; `check_now` checks at once, even in a demo.
func start(automatic: bool, fake: bool, check_now: bool) -> void:
	store.plugin_versions_changed.connect(_refresh_sessions)
	if fake:
		newest_app = {"version": "99.0.0", "tag": "windows-v99.0.0", "notes": "Made-up release notes, for --fake-update.",
			"page": AboutWindow.REPOSITORY + "/releases", "download": ""}
		newest_plugin = "99.0.0"
		app_checked = true
		_refresh_sessions()
		return
	if check_now:
		check()
	if not automatic:
		return
	_later_first_check()
	var timer := Timer.new()
	timer.wait_time = 3600
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if settings.check_updates and not checking and int(Time.get_unix_time_from_system()) - settings.last_update_check >= DAY:
			check())
	add_child(timer)


func _later_first_check() -> void:
	await _wait(10.0)
	await launch_checks()


## The check at launch: tried again after each of LAUNCH_RETRIES while it fails; stops once one
## works or Check for updates automatically is turned off.
func launch_checks() -> void:
	for retry: int in LAUNCH_RETRIES + [0]:
		if not settings.check_updates:
			return
		await check()
		if not last_check_failed or retry == 0:
			return
		await _wait(retry)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func app_update() -> Variant:
	if store_build or newest_app == null or not UpdateFeed.is_older(app_version, newest_app["version"]):
		return null
	return newest_app


## town-link's newest version while an open session runs an older one, else "".
func plugin_update() -> String:
	return "" if outdated.is_empty() else newest_plugin


func has_update() -> bool:
	return app_update() != null or plugin_update() != ""


func show_window() -> void:
	window_requested.emit()


## Reads the newest release (not in a Store copy) and town-link's version from GitHub. Sends
## nothing about the user.
func check() -> void:
	if checking:
		return
	checking = true
	changed.emit()
	var releases := {"done": true, "body": null} if store_build else _request(UpdateFeed.RELEASES_URL)
	var manifest := _request(UpdateFeed.PLUGIN_MANIFEST_URL)
	var r: Variant = await _answer(releases)
	var m: Variant = await _answer(manifest)
	var releases_read: bool = r != null and UpdateFeed.is_release_list(r)
	var app: Variant = UpdateFeed.newest_release(r) if releases_read else null
	var plugin: String = UpdateFeed.plugin_version(m) if m != null else ""
	if releases_read:
		app_checked = true
		if app != null:
			newest_app = app
	if plugin != "":
		newest_plugin = plugin
	last_check_failed = (not releases_read and not store_build) or plugin == ""
	if releases_read or plugin != "":
		settings.last_update_check = int(Time.get_unix_time_from_system())
		settings.save()
	checking = false
	_refresh_sessions()
	changed.emit()


## Starts a request; its answer is recorded as soon as it arrives (both requests run at once, so
## the second can finish while the first is awaited). {"done": bool, "body": String or null}
func _request(url: String) -> Dictionary:
	var answer := {"done": false, "body": null}
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if result == HTTPRequest.RESULT_SUCCESS and status == 200:
			answer["body"] = body.get_string_from_utf8()
		else:
			push_warning("agent-town: update check: %s answered result %d, status %d" % [url, result, status])
		answer["done"] = true
		http.queue_free())
	var err := http.request(url, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: agent-town-windows/" + app_version]))
	if err != OK:
		push_warning("agent-town: update check: %s could not start (%s)" % [url, error_string(err)])
		http.queue_free()
		answer["done"] = true
	return answer


## The body of a 200 answer, or null.
func _answer(answer: Dictionary) -> Variant:
	while not answer["done"]:
		await get_tree().process_frame
	return answer["body"]


func _refresh_sessions() -> void:
	var list: Array[Dictionary] = []
	if newest_plugin != "":
		for id: String in store.plugin_versions:
			var v: String = store.plugin_versions[id]
			if UpdateFeed.is_older(v, newest_plugin):
				var project := store.project_name_of(id)
				list.append({"id": id, "project": project if project != "" else id, "version": v})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["project"] < b["project"] if a["project"] != b["project"] else a["id"] < b["id"])
	if list != outdated:
		outdated = list
		changed.emit()


## "When the last check ran" for the check row, in local time.
static func format_time(unix: int) -> String:
	var bias: int = Time.get_time_zone_from_system().get("bias", 0)
	var d := Time.get_datetime_dict_from_unix_time(unix + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]

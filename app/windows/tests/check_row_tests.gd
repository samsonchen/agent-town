extends TestSupport
## Check now: in Settings it opens the Updates window when the check finds an update; nowhere else,
## and not when there is none or the check failed (docs/spec.md: Updates).


## An Updater whose check answers at once with a made-up result, without the network.
class StubUpdater:
	extends Updater
	var next_app: Variant = null
	var fail := false
	var asked := 0

	func check() -> void:
		newest_app = next_app
		app_checked = not fail
		last_check_failed = fail
		changed.emit()

	func show_window() -> void:
		asked += 1


static func _updater(app_version: String) -> StubUpdater:
	var path := OS.get_temp_dir().path_join("agent-town-claude-code-test-%d" % randi()).path_join("settings.cfg")
	var u := StubUpdater.new(TownSettings.new(path), TownStore.new(), app_version)
	return u


static func _free(u: StubUpdater) -> void:
	u.store.free()
	u.free()


static func _release(version: String) -> Dictionary:
	return {"version": version, "tag": "windows-v" + version, "notes": "", "page": "", "download": ""}


static func _press(u: StubUpdater, in_settings: bool) -> int:
	var row := UpdateCheckRow.new(u, TownLabels.new("en"), in_settings)
	row.check_now()
	row.free()
	return u.asked


func test_settings_check_opens_the_window_only_for_an_update() -> void:
	var u := _updater("1.0.3")
	u.next_app = _release("1.0.4")
	check_eq(_press(u, true), 1, "a newer app opens the Updates window")
	_free(u)

	u = _updater("1.0.3")
	u.next_app = _release("1.0.3")
	check_eq(_press(u, true), 0, "the same version opens nothing")
	_free(u)

	u = _updater("1.0.3")
	u.fail = true
	check_eq(_press(u, true), 0, "a failed check opens nothing")
	_free(u)


func test_the_updates_windows_own_check_opens_nothing() -> void:
	var u := _updater("1.0.3")
	u.next_app = _release("1.0.4")
	check_eq(_press(u, false), 0, "the row in the Updates window leaves it as it is")
	_free(u)


func test_a_store_copy_never_offers_a_newer_app() -> void:
	var u := _updater("1.0.3")
	u.store_build = true
	u.next_app = _release("1.0.4")
	check_eq(_press(u, true), 0, "a newer release opens nothing in a Store copy")
	check_eq(u.app_update(), null, "no app update: the Store updates it")
	check(not u.has_update(), "no red dot for the app")
	_free(u)


func test_the_installer_copy_is_not_a_store_copy() -> void:
	check(not Distribution.is_store(), "no store feature outside the Store export")
	check_eq(LoginItem.is_available(), OS.has_feature("template"), "Open at login as before")

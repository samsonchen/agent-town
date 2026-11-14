extends TestSupport
## The update check at launch tries again after 1, 2, 5 and 10 minutes while it fails, and stops
## once one works or Check for updates automatically is off (docs/spec.md: Updates).


## An Updater whose checks fail or work as listed, and whose waits are only recorded.
class RetryUpdater:
	extends Updater
	var results: Array[bool] = [] ## true: that check fails
	var checks := 0
	var waits: Array[float] = []
	var turn_off_after := -1 ## the user turns automatic checks off after this many checks

	func check() -> void:
		last_check_failed = results[checks] if checks < results.size() else false
		checks += 1
		if checks == turn_off_after:
			settings.check_updates = false

	func _wait(seconds: float) -> void:
		waits.append(seconds)


static func _updater(results: Array[bool]) -> RetryUpdater:
	var path := OS.get_temp_dir().path_join("agent-town-claude-code-test-%d" % randi()).path_join("settings.cfg")
	var u := RetryUpdater.new(TownSettings.new(path), TownStore.new(), "1.0.0")
	u.results = results
	return u


static func _free(u: RetryUpdater) -> void:
	u.store.free()
	u.free()


func test_a_check_that_works_is_not_retried() -> void:
	var u := _updater([false])
	u.launch_checks()
	check_eq([u.checks, u.waits], [1, []], "one check")
	_free(u)


func test_failed_checks_retry_after_1_2_5_and_10_minutes() -> void:
	var u := _updater([true, true, false])
	u.launch_checks()
	check_eq([u.checks, u.waits], [3, [60.0, 120.0]], "stops once one works")
	_free(u)
	u = _updater([true, true, true, true, true, true])
	u.launch_checks()
	check_eq([u.checks, u.waits], [5, [60.0, 120.0, 300.0, 600.0]], "five tries at most")
	_free(u)


func test_stops_when_automatic_checks_are_turned_off() -> void:
	var u := _updater([true, true, true, true, true])
	u.turn_off_after = 2
	u.launch_checks()
	check_eq(u.checks, 2, "no check after it is turned off")
	_free(u)
	u = _updater([true])
	u.settings.check_updates = false
	u.launch_checks()
	check_eq(u.checks, 0, "off from the start: no check")
	_free(u)

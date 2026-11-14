extends TestSupport
## Hide the window when no Claude Code session is open (docs/spec.md → Settings (app)): the window
## hides 5 s after the last session closes and comes back when one opens; Show agent-town wins.


class Seen:
	var hides := 0
	var shows := 0


static func _presence(seen: Seen, wants: Array = [true]) -> WindowPresence:
	var p := WindowPresence.new()
	p.user_wants_window = func() -> bool: return wants[0]
	p.hide_window.connect(func() -> void: seen.hides += 1)
	p.show_window.connect(func() -> void: seen.shows += 1)
	return p


func test_hides_five_seconds_after_the_last_session_closes() -> void:
	var seen := Seen.new()
	var p := _presence(seen)
	p.set_enabled(true)
	p.sessions_changed(true)
	p.sessions_changed(false)
	p.tick(4.9)
	check_eq(seen.hides, 0, "not yet at 4.9 s")
	p.tick(0.2)
	check_eq(seen.hides, 1, "hidden at 5 s")
	check(p.auto_hidden, "hidden for want of a session")
	p.sessions_changed(true)
	check_eq(seen.shows, 1, "a session brings it back")
	check(not p.auto_hidden, "no longer hidden")
	p.free()


func test_a_session_within_the_delay_cancels_the_hide() -> void:
	var seen := Seen.new()
	var p := _presence(seen)
	p.set_enabled(true)
	p.sessions_changed(true)
	p.sessions_changed(false)
	p.tick(3.0)
	p.sessions_changed(true) # a /clear: the old session closes, a new one opens
	p.tick(10.0)
	check_eq([seen.hides, seen.shows], [0, 0], "no blink")
	p.free()


func test_at_launch_with_no_session_it_hides_after_the_delay() -> void:
	var seen := Seen.new()
	var p := _presence(seen)
	p.set_enabled(true)
	p.sessions_changed(false)
	p.sessions_changed(false) # other changes in the building do not restart the countdown
	p.tick(2.5)
	p.sessions_changed(false)
	p.tick(2.6)
	check_eq(seen.hides, 1, "hidden 5 s after launch")
	p.free()


func test_off_does_nothing_and_turning_it_off_brings_the_window_back() -> void:
	var seen := Seen.new()
	var p := _presence(seen)
	p.sessions_changed(false)
	p.tick(10.0)
	check_eq(seen.hides, 0, "off: stays")
	p.set_enabled(true)
	p.tick(5.1)
	check_eq(seen.hides, 1, "on: hides")
	p.set_enabled(false)
	check_eq(seen.shows, 1, "off again: back")
	p.free()


func test_show_agent_town_shows_it_until_the_next_session_closes() -> void:
	var seen := Seen.new()
	var p := _presence(seen)
	p.set_enabled(true)
	p.sessions_changed(false)
	p.tick(5.1)
	p.show_now() # the user chose Show agent-town
	check(not p.auto_hidden, "shown")
	p.tick(60.0)
	check_eq(seen.hides, 1, "stays shown with no session")
	p.sessions_changed(true)
	check_eq(seen.shows, 0, "already shown: nothing to bring back")
	p.sessions_changed(false)
	p.tick(5.1)
	check_eq(seen.hides, 2, "hides again after the next session closes")
	p.free()


func test_a_window_the_user_closed_does_not_come_back_with_a_session() -> void:
	var seen := Seen.new()
	var wants := [true]
	var p := _presence(seen, wants)
	p.set_enabled(true)
	p.sessions_changed(false)
	p.tick(5.1)
	wants[0] = false # Show agent-town turned off
	p.sessions_changed(true)
	check_eq(seen.shows, 0, "stays closed")
	p.sessions_changed(false)
	p.tick(5.1)
	check_eq(seen.hides, 1, "a closed window is not hidden again")
	p.free()


func test_sessions_open_means_a_chief_in_some_block() -> void:
	var b := Building.new()
	check(not WindowPresence.sessions_open(b), "empty")
	b.apply(ev("session.open", 1, {"projectName": "demo"}))
	check(WindowPresence.sessions_open(b), "a session")
	b.apply(ev("session.close", 2))
	check(not WindowPresence.sessions_open(b), "closed")

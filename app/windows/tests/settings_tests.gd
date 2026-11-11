extends TestSupport
## The stored settings: safe opacity values and a save-and-load round trip.

func test_opacity_is_brought_into_range() -> void:
	check_eq(TownSettings.clamp_opacity(0.5), 0.5, "in range")
	check_eq(TownSettings.clamp_opacity(0.0), 0.1, "too low")
	check_eq(TownSettings.clamp_opacity(3), 1.0, "too high")
	check_eq(TownSettings.clamp_opacity("half"), 1.0, "not a number")
	check_eq(TownSettings.clamp_opacity(NAN), 1.0, "NaN")


func test_settings_survive_a_restart() -> void:
	var path := OS.get_temp_dir().path_join("agent-town-test-%d" % randi()).path_join("settings.cfg")
	var a := TownSettings.new(path)
	check_eq([a.language, a.stay_on_top, a.sound, a.show_window, a.opacity], ["", false, true, true, 1.0], "defaults")
	a.language = "zh-Hant"
	a.stay_on_top = true
	a.sound = false
	a.opacity = 0.4
	a.window_position = Vector2i(120, 80)
	a.window_width = 900
	a.window_screen = 0
	a.save()
	var b := TownSettings.new(path)
	check_eq([b.language, b.stay_on_top, b.sound, b.opacity, b.window_position, b.window_width, b.window_screen],
		["zh-Hant", true, false, 0.4, Vector2i(120, 80), 900, 0], "read back")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path.get_base_dir())

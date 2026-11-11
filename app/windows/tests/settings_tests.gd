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


func test_sound_settings_survive_a_restart_and_stay_in_range() -> void:
	var path := OS.get_temp_dir().path_join("agent-town-test-%d" % randi()).path_join("settings.cfg")
	var a := TownSettings.new(path)
	check_eq([a.volume, a.completion_threshold, a.sound_on, a.sound_choice],
		[1.0, 0, {"dispatch": true, "completion": true, "approval": true}, {"dispatch": "", "completion": "", "approval": ""}], "defaults")
	a.volume = 0.35
	a.completion_threshold = 30
	a.sound_on["approval"] = false
	a.sound_choice["dispatch"] = "media:Windows Ding"
	a.sound_choice["completion"] = "file:D:/sounds/done.mp3"
	a.save()
	var b := TownSettings.new(path)
	check_eq([b.volume, b.completion_threshold, b.sound_on["approval"], b.sound_choice["dispatch"], b.sound_choice["completion"]],
		[0.35, 30, false, "media:Windows Ding", "file:D:/sounds/done.mp3"], "read back")
	check_eq([TownSettings.clamp_volume(2), TownSettings.clamp_volume(-1), TownSettings.clamp_volume("x")], [1.0, 0.0, 1.0], "volume range")
	check_eq([TownSettings.clamp_threshold(99999), TownSettings.clamp_threshold(-5), TownSettings.clamp_threshold(12.7)], [3600, 0, 12], "threshold range")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path.get_base_dir())

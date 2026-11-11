extends TestSupport
## Sound choices: which file a choice names, loading by file type, the fallback to the default, and
## the list of Windows sounds.

func test_choices_name_their_files() -> void:
	check_eq(TownAudio.path_for(""), "", "the default")
	check_eq(TownAudio.path_for("media:Windows Ding"), "C:/Windows/Media/Windows Ding.wav", "a Windows sound")
	check_eq(TownAudio.path_for("file:D:/sounds/done.mp3"), "D:/sounds/done.mp3", "a file of the user's own")


func test_files_load_by_type_and_missing_ones_are_null() -> void:
	check(TownAudio.load_stream("C:/Windows/Media/Windows Ringout.wav") is AudioStreamWAV, "a WAV loads")
	check(TownAudio.load_stream("C:/no/such/file.wav") == null, "a missing file is null")
	check(TownAudio.load_stream("C:/Windows/win.ini") == null, "another file type is null")


func test_a_choice_that_cannot_load_falls_back_to_the_default() -> void:
	var audio := TownAudio.new()
	audio.choose("dispatch", "file:C:/no/such/sound.mp3")
	check(audio._streams.has("dispatch"), "the default plays instead")
	audio.choose("completion", "media:Windows Ding")
	check(audio._streams.has("completion"), "a Windows sound loads")
	audio.free()


func test_the_list_has_the_windows_sounds_and_the_defaults() -> void:
	var names := TownAudio.media_names()
	check(names.size() >= 30, "found %d Windows sounds" % names.size())
	for key: String in TownAudio.DEFAULTS:
		check(names.has(TownAudio.DEFAULTS[key]), "%s's default is in the list" % key)

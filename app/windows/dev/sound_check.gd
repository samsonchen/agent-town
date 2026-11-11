extends SceneTree
## Plays each of the three sounds and measures what reaches the output, to tell a sound that does
## not play from one that plays but is not heard. Not headless (that has no audio):
##   godot --path app/windows --script res://dev/sound_check.gd

var audio := TownAudio.new()
var capture := AudioEffectCapture.new()


func _initialize() -> void:
	print("audio driver: ", AudioServer.get_driver_name(), ", output device: ", AudioServer.output_device,
		", mix rate: ", AudioServer.get_mix_rate())
	print("devices: ", AudioServer.get_output_device_list())
	AudioServer.add_bus_effect(0, capture)
	root.add_child(audio)
	_run()


func _run() -> void:
	await process_frame
	for key: String in TownAudio.DEFAULTS:
		print("%s: %s, loaded %s" % [key, TownAudio.DEFAULTS[key], audio._streams.has(key)])
		capture.clear_buffer()
		audio.play(key)
		var peak := 0.0
		var t := 0.0
		while t < 1.5:
			await create_timer(0.1).timeout
			t += 0.1
			var frames := capture.get_frames_available()
			if frames > 0:
				for f: Vector2 in capture.get_buffer(frames):
					peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
		print("   peak level at the output: %.3f" % peak)
	quit()

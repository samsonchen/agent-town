extends SceneTree
## Runs the store headless and prints every change, for checking a live town-link session:
##   godot --headless --path app/windows --script res://dev/store_check.gd
## then run Claude Code with the plugin. STORE_SECONDS sets how long it listens (default 120).
## It writes the real endpoint file, so quit the app first if it is running.

var store := TownStore.new()


func _initialize() -> void:
	root.add_child(store)
	var version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	if store.start(version) != OK:
		quit(1)
		return
	print("listening on 127.0.0.1:%d (endpoint %s)" % [store.server.port, store.server.endpoint_path])
	store.changed.connect(func(c: Dictionary) -> void: print("change ", TownStore._describe(c)))
	var secs := OS.get_environment("STORE_SECONDS")
	create_timer(float(secs) if secs != "" else 120.0).timeout.connect(func() -> void:
		print("final state: ", JSON.stringify(store.building.snapshot()))
		quit())

extends Node
## Checks the TownWindow add-on in a real window: no taskbar button, hide and show, and that
## Godot's own window changes (stay on top, a title change) do not bring the button back.
## Prints CHECK lines and quits. Run: godot --path app/windows

func _ready() -> void:
	await get_tree().process_frame
	var win := get_window()
	win.title = "agent-town taskbar check"
	var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, win.get_window_id())
	print("CHECK add-on loaded: ", ClassDB.class_exists("TownWindow"))
	print("CHECK hide_from_taskbar: ", TownWindow.hide_from_taskbar(hwnd), " -> ", TownWindow.is_hidden_from_taskbar(hwnd))
	await get_tree().create_timer(1.0).timeout
	win.always_on_top = true
	win.title = "agent-town taskbar check (on top)"
	await get_tree().create_timer(0.5).timeout
	print("CHECK still hidden from taskbar after always_on_top and a title change: ", TownWindow.is_hidden_from_taskbar(hwnd))
	TownWindow.set_shown(hwnd, false)
	print("CHECK after set_shown(false): shown=", TownWindow.is_shown(hwnd))
	await get_tree().create_timer(2.0).timeout
	TownWindow.set_shown(hwnd, true)
	print("CHECK after set_shown(true): shown=", TownWindow.is_shown(hwnd), " hidden from taskbar=", TownWindow.is_hidden_from_taskbar(hwnd))
	await get_tree().create_timer(float(OS.get_environment("CHECK_HOLD") if OS.get_environment("CHECK_HOLD") != "" else "1")).timeout
	get_tree().quit()

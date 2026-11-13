// TownWindow: the few Windows calls GDScript cannot make. See docs/windows/architecture.md.
#pragma once

#include <godot_cpp/classes/object.hpp>

namespace godot {

class TownWindow : public Object {
	GDCLASS(TownWindow, Object)

protected:
	static void _bind_methods();

public:
	// `hwnd` is DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window_id).
	static bool hide_from_taskbar(int64_t hwnd);
	static bool is_hidden_from_taskbar(int64_t hwnd);
	static void set_shown(int64_t hwnd, bool shown);
	static bool is_shown(int64_t hwnd);
	static bool set_owner(int64_t hwnd, int64_t owner_hwnd);
	static int64_t get_owner(int64_t hwnd);
};

} // namespace godot

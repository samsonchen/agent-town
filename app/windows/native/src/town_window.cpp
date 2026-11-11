#include "town_window.h"

#include <godot_cpp/core/class_db.hpp>

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>

using namespace godot;

namespace {

constexpr UINT_PTR SUBCLASS_ID = 0x70776E; // "twn"

LONG_PTR tool_style(LONG_PTR ex) {
	return (ex | WS_EX_TOOLWINDOW) & ~static_cast<LONG_PTR>(WS_EX_APPWINDOW);
}

// Godot rebuilds the window's extended style when its own flags change (always on top, borderless …),
// which would bring the taskbar button back. This keeps the tool-window style in every such change.
LRESULT CALLBACK keep_tool_window(HWND h, UINT msg, WPARAM wp, LPARAM lp, UINT_PTR id, DWORD_PTR) {
	if (msg == WM_STYLECHANGING && wp == static_cast<WPARAM>(GWL_EXSTYLE)) {
		STYLESTRUCT *s = reinterpret_cast<STYLESTRUCT *>(lp);
		s->styleNew = static_cast<DWORD>(tool_style(s->styleNew));
	} else if (msg == WM_NCDESTROY) {
		RemoveWindowSubclass(h, keep_tool_window, id);
	}
	return DefSubclassProc(h, msg, wp, lp);
}

} // namespace

void TownWindow::_bind_methods() {
	ClassDB::bind_static_method("TownWindow", D_METHOD("hide_from_taskbar", "hwnd"), &TownWindow::hide_from_taskbar);
	ClassDB::bind_static_method("TownWindow", D_METHOD("is_hidden_from_taskbar", "hwnd"), &TownWindow::is_hidden_from_taskbar);
	ClassDB::bind_static_method("TownWindow", D_METHOD("set_shown", "hwnd", "shown"), &TownWindow::set_shown);
	ClassDB::bind_static_method("TownWindow", D_METHOD("is_shown", "hwnd"), &TownWindow::is_shown);
}

// Windows gives no taskbar button to a tool window. The style only takes effect on the taskbar
// when the window is shown again, so a visible window is hidden and shown around the change.
bool TownWindow::hide_from_taskbar(int64_t hwnd) {
	HWND h = reinterpret_cast<HWND>(hwnd);
	if (!IsWindow(h)) {
		return false;
	}
	SetWindowSubclass(h, keep_tool_window, SUBCLASS_ID, 0); // a second call only updates it
	LONG_PTR ex = GetWindowLongPtrW(h, GWL_EXSTYLE);
	LONG_PTR want = tool_style(ex);
	if (want == ex) {
		return true;
	}
	bool visible = IsWindowVisible(h) != FALSE;
	if (visible) {
		ShowWindow(h, SW_HIDE);
	}
	SetWindowLongPtrW(h, GWL_EXSTYLE, want);
	if (visible) {
		ShowWindow(h, SW_SHOWNA);
	}
	return true;
}

bool TownWindow::is_hidden_from_taskbar(int64_t hwnd) {
	HWND h = reinterpret_cast<HWND>(hwnd);
	return IsWindow(h) && (GetWindowLongPtrW(h, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0;
}

// Godot cannot hide its main window; this hides or shows it the Windows way.
void TownWindow::set_shown(int64_t hwnd, bool shown) {
	HWND h = reinterpret_cast<HWND>(hwnd);
	if (!IsWindow(h)) {
		return;
	}
	if (shown) {
		ShowWindow(h, SW_SHOW);
		SetForegroundWindow(h);
	} else {
		ShowWindow(h, SW_HIDE);
	}
}

bool TownWindow::is_shown(int64_t hwnd) {
	HWND h = reinterpret_cast<HWND>(hwnd);
	return IsWindow(h) && IsWindowVisible(h) != FALSE;
}

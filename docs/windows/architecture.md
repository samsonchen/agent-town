# Windows app architecture

The Windows app is a Godot 4 project in `app/windows/`, written in typed GDScript (every variable and function typed). It is built with Godot 4.7.2 (it needs 4.4 or later), the standard build, with the Compatibility (OpenGL) renderer.

It reimplements the macOS app's design, not its code: the same split between building state and choreographer (see [architecture.md](../architecture.md), "App side"), the same protocol, and the same shared files. town-link is the same plugin on both; on Windows it reads `%APPDATA%\agent-town\endpoint.json` ([protocol.md](../protocol.md)).

## Modules

| Module | Technology | Job |
|---|---|---|
| Shell | Godot `StatusIndicator` (tray icon) and a `PopupMenu`; the office in the main window | Tray menu, settings, About. No taskbar button, and closing the window hides it: Godot cannot do either from GDScript, so the native add-on TownWindow does it (below) |
| Loopback server | `TCPServer` on 127.0.0.1, with a small HTTP/1.1 reader in GDScript (Godot has no HTTP server class) | Accepts `POST /v1/events`; checks the token and reads `protocol` first (426 if unsupported); writes `%APPDATA%\agent-town\endpoint.json` and deletes it on quit if it still holds this app's `pid` |
| Building state | `app/windows/core/`: `TownEvent`, `Building`, `Sequencer`, with no scene code | The port of `app/macos/Sources/TownCore/` (`Events.swift`, `Building.swift`, `Snapshot.swift`, the sequencer in `Ordering.swift`). Changes come back as dictionaries with a `kind` named after the Swift `Change` case. Tested headless (`app/windows/tests/`) against `protocol/fixtures/` and `protocol/fixtures/expected/`, the same answers the macOS app is tested against, plus ports of its unit tests |
| Choreographer and scene | Godot 3D: an orthographic `Camera3D` tilted 62° from the floor, `AnimationPlayer` | Per-character queues and the timing rules, as on macOS |
| Labels | 2D `Control` nodes over the 3D view, at each character's projected position | Name tags, ticket text, block signs, call lines, in Cubic 11 |
| Audio | `AudioStreamWAV.load_from_file` on the files in `C:\Windows\Media` | Completion, approval and dispatch sounds, with the duration gate; volume and mute apply |
| Localization | Parses the macOS app's `Localizable.strings` files (the only source of UI strings) plus `catalog/*.json` | Picks the language by the explicit rule in [spec.md](spec.md), not by Godot's nearest-locale match |

## The native add-on: TownWindow

A GDExtension in `app/windows/native/` (C++, built with `godot-cpp` 10.0.0, a submodule) that makes the few Windows calls GDScript cannot. Its class `TownWindow` has static methods taking the main window's handle (`DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, id)`):

| Method | What it does |
|---|---|
| `hide_from_taskbar(hwnd)` | Gives the window the tool-window style (no taskbar button) and hooks its style changes (`WM_STYLECHANGING`), because Godot rebuilds the style when its own flags change and would otherwise bring the button back |
| `is_hidden_from_taskbar(hwnd)` | Whether the style is set |
| `set_shown(hwnd, shown)` | Hides or shows the window (`ShowWindow`); Godot itself refuses to hide its main window |
| `is_shown(hwnd)` | Whether the window is visible |

- The built DLLs are committed in `app/windows/addons/town_window/bin/` (x64 and ARM64, about 300 KB each), so working on the Godot project needs no C++ compiler.
- To rebuild after changing `native/src/`: `app/windows/native/build.ps1` (PowerShell; `build.sh` runs it from Git Bash). It needs Visual Studio Build Tools 2026 with the C++ x64 and ARM64 tools and a Windows SDK, and checks for them first. It fetches the `godot-cpp` submodule if missing, takes SCons from `SCONS` or `PATH` or else installs it into a private `native/.venv`, builds x64 and ARM64 (or one with `-Arch`), and checks each DLL's CPU type. `-Check` only checks the prerequisites.
- `app/windows/dev/taskbar_check.tscn` checks it in a real window (the project's main scene for now).

## Shared files

| File | Use on Windows |
|---|---|
| `assets/kenney/` (GLB) | Imported by Godot directly, with their animation clips. The USDZ files and `clips.json` are macOS only. |
| `catalog/characters.json` | Shirt swatches for recoloring the shared texture, as on macOS |
| `catalog/roles.json`, `catalog/task-types.json`, `catalog/models.json` | Role and task labels, outfit colors, model badge families |
| `app/macos/Sources/AgentTown/Resources/Localization/*.lproj/Localizable.strings` | UI strings, keyed by their English text |
| `protocol/fixtures/`, `protocol/fixtures/expected/` | Tests of the building state |

## Other parts

- **Settings** are kept in a file under `%APPDATA%\agent-town\`. Open at login is an entry under the user's `Run` registry key.
- **Builds:** Godot's export templates for Windows x64, and ARM64 where they work. The installer is made with Inno Setup.
- **Security:** as on macOS: 127.0.0.1 only, the token on every request, event text shown as text only. The endpoint file is protected by where it is: `%APPDATA%` is in the user's own profile. The app does not loosen that folder's permissions.

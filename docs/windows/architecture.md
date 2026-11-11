# Windows app architecture

The Windows app is a Godot 4 project in `app/windows/`, written in typed GDScript (every variable and function typed). It is built with Godot 4.7.2 (it needs 4.4 or later), the standard build, with the Compatibility (OpenGL) renderer.

It reimplements the macOS app's design, not its code: the same split between building state and choreographer (see [architecture.md](../architecture.md), "App side"), the same protocol, and the same shared files. town-link is the same plugin on both; on Windows it reads `%APPDATA%\agent-town\endpoint.json` ([protocol.md](../protocol.md)).

## Modules

| Module | Technology | Job |
|---|---|---|
| Shell | `main.gd`: Godot `StatusIndicator` (tray icon) and a native `PopupMenu`; `shell/settings_window.gd`, `shell/about_window.gd`, `shell/town_settings.gd`, `shell/login_item.gd` | Tray menu (About, Show agent-town, Stay on top, Sound, Settings…, Quit); a left click on the icon shows the window. No taskbar button, and closing the window hides it: Godot cannot do either from GDScript, so the native add-on TownWindow does it (below). Settings: Open at login (a value under the user's `Run` registry key, exported app only), language (with Restart now), opacity 10%–100% (the office renders in a `SubViewport` whose container fades, over a see-through window). Choices are kept in `%APPDATA%\agent-town\settings.cfg`, with the window's position and width. Settings and About use the Windows UI font (Segoe UI, Microsoft JhengHei UI); the office labels use Cubic 11. Windows-only UI strings are in `app/windows/strings/` |
| Loopback server | `core/loopback_server.gd`: a `TCPServer` on 127.0.0.1 polled each frame, with `core/town_http.gd` (a small HTTP/1.1 reader and the request checks; Godot has no HTTP server class) and `core/endpoint_file.gd`. Ports of `Endpoint.swift` and `Server.swift` | Accepts `POST /v1/events`; checks the token and reads `protocol` first (426 if unsupported); writes `%APPDATA%\agent-town\endpoint.json` and deletes it on quit if it still holds this app's `pid` |
| Store | `core/town_store.gd`, a Node | Each frame: takes the server's batches, puts events in `seq` order (`Sequencer`), applies them to the building, and emits each change (`changed` signal); every 5 s closes stale sessions. `TOWN_LOG=<file>` logs events and changes. Port of `TownStore.swift`. `dev/store_check.gd` runs it headless and prints changes, for checking a live session |
| Building state | `app/windows/core/`: `TownEvent`, `Building`, `Sequencer`, with no scene code | The port of `app/macos/Sources/TownCore/` (`Events.swift`, `Building.swift`, `Snapshot.swift`, the sequencer in `Ordering.swift`). Changes come back as dictionaries with a `kind` named after the Swift `Change` case. Tested headless (`app/windows/tests/`) against `protocol/fixtures/` and `protocol/fixtures/expected/`, the same answers the macOS app is tested against, plus ports of its unit tests |
| Choreographer and scene | `scene/town_scene.gd` (Godot 3D, `AnimationPlayer`), `scene/layout.gd`, `scene/town_assets.gd`; `main.gd` with an orthographic `Camera3D` tilted 62° from the floor | Builds the blocks (tiled floors, Kenney furniture, telephones) and places the characters, from the store's changes; sizes the window to the office (110 px per meter when it fits, at least 70). Each character (`scene/town_actor.gd`) has a queue of story actions, coroutines that play one after another at full length; activities are not queued. `town_scene.gd` turns changes into calls (`town_phone.gd`), walks along the walkways and carried desks; `scene/staff_director.gd` pages the bench, assigns desks and consoles, and plays reports and messages. Ports of `Layout.swift`, `Assets.swift`, `Actors.swift`, `TownScene.swift`, `TownScene+Desks.swift` and `TownScene+Staff.swift`. Characters share one set of looping copies of the clips and the typing and writing clips (`TownAssets.attach_motion`), so the imported clips stay one-shot. `main.gd -- --demo <fixture> [--speed N] [--snapshot out.png --at S]` replays a fixture, as on macOS |
| Labels | `scene/label_overlay.gd`, a `Control` drawn over the 3D view at each anchor's projected position; `scene/town_labels.gd` | Name tags, block signs and context bars now; ticket text and call lines next. In Cubic 11 (`fonts/`). `town_labels.gd` holds the UI strings, catalog labels and the language rule |
| Audio | `scene/town_audio.gd`: `AudioStreamWAV.load_from_file` on the files in `C:\Windows\Media` | Completion, approval and dispatch sounds, with the duration gate; volume and mute apply |
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

Godot loads only files inside its project, and the macOS app's resource symlinks become plain files in a Windows checkout, so `tools/sync-windows-assets.py` copies the shared files into `app/windows/shared/`. The copies are committed. Run it after changing a source; `--check` reports stale copies.


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

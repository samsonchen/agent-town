# Windows app architecture

The Windows app is a Godot 4 project in `app/windows/`, written in typed GDScript (every variable and function typed). It is built with Godot 4.7.2 (it needs 4.4 or later), the standard build, with the Compatibility (OpenGL) renderer.

It reimplements the macOS app's design, not its code: the same split between building state and choreographer (see [architecture.md](../architecture.md), "App side"), the same protocol, and the same shared files. town-link is the same plugin on both; on Windows it reads `%APPDATA%\agent-town-claude-code\endpoint.json` ([protocol.md](../protocol.md)).

## Modules

| Module | Technology | Job |
|---|---|---|
| Shell | `main.gd`: Godot `StatusIndicator` (tray icon) and a native `PopupMenu`; `shell/settings_window.gd`, `shell/about_window.gd`, `shell/town_settings.gd`, `shell/login_item.gd` | Tray menu (About, Show agent-town, Stay on top, Sound, Settings…, Quit); a left click on the icon shows the window. No taskbar button, and closing the window hides it: Godot cannot do either from GDScript, so the native add-on TownWindow does it (below). Settings: Open at login (a value under the user's `Run` registry key, exported app only), language (with Restart now), opacity 10%–100% (the office renders in a `SubViewport` whose container fades, over a see-through window). Choices are kept in `%APPDATA%\agent-town-claude-code\settings.cfg`, with the window's position and width. Settings and About use the Windows UI font (Segoe UI, Microsoft JhengHei UI); the office labels use Cubic 11. Windows-only UI strings are in `app/windows/strings/` |
| Loopback server | `core/loopback_server.gd`: a `TCPServer` on 127.0.0.1 polled each frame, with `core/town_http.gd` (a small HTTP/1.1 reader and the request checks; Godot has no HTTP server class) and `core/endpoint_file.gd`. Ports of `Endpoint.swift` and `Server.swift` | Accepts `POST /v1/events`; checks the token and reads `protocol` first (426 if unsupported); writes `%APPDATA%\agent-town-claude-code\endpoint.json` and deletes it on quit if it still holds this app's `pid` |
| Store | `core/town_store.gd`, a Node | Each frame: takes the server's batches, puts events in `seq` order (`Sequencer`), applies them to the building, and emits each change (`changed` signal); every 5 s closes stale sessions. `TOWN_LOG=<file>` logs each batch, each event in full (session and project IDs, the sender's clock, every field) and each change, in local time. Port of `TownStore.swift`. `dev/store_check.gd` runs it headless and prints changes, for checking a live session |
| Building state | `app/windows/core/`: `TownEvent`, `Building`, `Sequencer`, with no scene code | The port of `app/macos/Sources/TownCore/` (`Events.swift`, `Building.swift`, `Snapshot.swift`, the sequencer in `Ordering.swift`). Changes come back as dictionaries with a `kind` named after the Swift `Change` case. Tested headless (`app/windows/tests/`) against `protocol/fixtures/` and `protocol/fixtures/expected/`, the same answers the macOS app is tested against, plus ports of its unit tests |
| Choreographer and scene | `scene/town_scene.gd` (Godot 3D, `AnimationPlayer`), `scene/layout.gd`, `scene/town_assets.gd`; `main.gd` with an orthographic `Camera3D` tilted 62° from the floor | Builds the blocks (tiled floors, Kenney furniture, telephones) and places the characters, from the store's changes; sizes the window to the office (110 px per meter when it fits, at least 70). Each character (`scene/town_actor.gd`) has a queue of story actions, coroutines that play one after another at full length; activities are not queued. `town_scene.gd` turns changes into calls (`town_phone.gd`), walks along the walkways and carried desks; `scene/staff_director.gd` pages the bench, assigns desks and consoles, and plays reports and messages. Ports of `Layout.swift`, `Assets.swift`, `Actors.swift`, `TownScene.swift`, `TownScene+Desks.swift` and `TownScene+Staff.swift`. Characters share one set of looping copies of the clips and the typing and writing clips (`TownAssets.attach_motion`), so the imported clips stay one-shot. `main.gd -- --demo <fixture> [--speed N] [--snapshot out.png --at S]` replays a fixture, as on macOS |
| The CEO | `scene/ceo_driver.gd`, a Node; `scene/floor_plan.gd` | Drives the CEO each frame: held arrow keys step it (sliding along furniture footprints the blocks record as furniture is placed), H walks it home on a path (`AStarGrid2D` on a 10 cm grid, no corner cutting, straightened). Clicks: a character (body or tags, the nearest the camera wins) walks the CEO to a free spot beside them; the CEO's desk area sends it home; the floor (a camera ray onto the floor plane) walks it to the nearest free spot. Signals `moved` for the view to follow. Away from the desk the CEO answers a mobile phone. `scene/statements.gd` gives what the touched character says, from the macOS app's strings. Port of the driving part of `TownScene+CEO.swift` and `FloorPlan` |
| Labels | `scene/label_overlay.gd`, a `Control` drawn over the 3D view at each anchor's projected position; `scene/town_labels.gd` | Name tags, block signs and context bars now; ticket text and call lines next. In Cubic 11 (`fonts/`). `town_labels.gd` holds the UI strings, catalog labels and the language rule |
| Audio | `scene/town_audio.gd`: `AudioStreamWAV`, `AudioStreamMP3` and `AudioStreamOggVorbis` `load_from_file` | The three sounds, each the user's choice (a sound in `C:\Windows\Media`, or a file of their own), falling back to the default when a choice cannot be loaded; the volume, each sound's switch and the tray's Sound item apply, and Settings' Play previews regardless of them. The completion threshold goes to `Building.sound`, which decides whether a finished ticket plays it |
| Localization | Parses the macOS app's `Localizable.strings` files (the only source of UI strings) plus `catalog/*.json` | Picks the language by the explicit rule in [spec.md](spec.md), not by Godot's nearest-locale match |

## The native add-on: TownWindow

A GDExtension in `app/windows/native/` (C++, built with `godot-cpp` 10.0.0, a submodule) that makes the few Windows calls GDScript cannot. Its class `TownWindow` has static methods taking the main window's handle (`DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, id)`):

| Method | What it does |
|---|---|
| `hide_from_taskbar(hwnd)` | Gives the window the tool-window style (no taskbar button) and hooks its style changes (`WM_STYLECHANGING`), because Godot rebuilds the style when its own flags change and would otherwise bring the button back |
| `is_hidden_from_taskbar(hwnd)` | Whether the style is set |
| `set_shown(hwnd, shown)` | Hides or shows the window (`ShowWindow`); Godot itself refuses to hide its main window |
| `is_shown(hwnd)` | Whether the window is visible |
| `set_owner(hwnd, owner_hwnd)` | Makes the office window the owner of Settings, About and Updates (`GWLP_HWNDPARENT`), so Windows keeps them above it, also when Stay on top is on and the office is clicked; Godot gives its sub-windows no owner. `main.gd` calls it each time one of them is shown, because Godot makes a new native window on every show. 0 removes the owner |
| `get_owner(hwnd)` | The window's owner, or 0 |

- The built DLLs are committed in `app/windows/addons/town_window/bin/` (x64 and ARM64, about 300 KB each), so working on the Godot project needs no C++ compiler.
- The build's commands hold the checkout's full path, so after the folder is moved or renamed the first build compiles all of `godot-cpp` again (several minutes per architecture); later builds compile only `native/src/`.
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

- **On disk**, everything the app keeps is in `%APPDATA%\agent-town-claude-code\`: `endpoint.json`, `settings.cfg`, run-local's separate `run-local\settings.cfg`, and Godot's `user://` (its logs and shader cache), which `project.godot` points at the same folder (`application/config/custom_user_dir_name`). `EndpointFile.DATA_FOLDER` names it in the code. Open at login is the value `agent-town-claude-code` under the user's `Run` registry key, holding the exe's path with backslashes and in quotes (`"C:\...\agent-town.exe"`): Explorer skips a command written with Godot's forward slashes at sign-in, without a word. The app rewrites an entry written the old way when it starts (`LoginItem.repair`).
- **Builds:** Godot's export templates for Windows x64, and ARM64 where they work. The installer is made with Inno Setup.
- **Security:** as on macOS: 127.0.0.1 only, the token on every request, event text shown as text only. The endpoint file is protected by where it is: `%APPDATA%` is in the user's own profile. The app does not loosen that folder's permissions.

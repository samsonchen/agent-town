# Windows app architecture

The Windows app is a Godot 4 project in `app/windows/`, written in typed GDScript (every variable and function typed). It is built with Godot 4.7.2 (it needs 4.4 or later), the standard build, with the Compatibility (OpenGL) renderer.

It reimplements the macOS app's design, not its code: the same split between building state and choreographer (see [architecture.md](../architecture.md), "App side"), the same protocol, and the same shared files. town-link is the same plugin on both; on Windows it reads `%APPDATA%\agent-town\endpoint.json` ([protocol.md](../protocol.md)).

## Modules

| Module | Technology | Job |
|---|---|---|
| Shell | Godot `StatusIndicator` (tray icon) and a `PopupMenu`; the office in the main window | Tray menu, settings, About. No taskbar button, and closing the window hides it: Godot cannot do either from GDScript, so this needs a small native add-on that sets the Windows tool-window style on the main window and shows or hides it (not decided yet; see [roadmap.md](roadmap.md)) |
| Loopback server | `TCPServer` on 127.0.0.1, with a small HTTP/1.1 reader in GDScript (Godot has no HTTP server class) | Accepts `POST /v1/events`; checks the token and reads `protocol` first (426 if unsupported); writes `%APPDATA%\agent-town\endpoint.json` and deletes it on quit if it still holds this app's `pid` |
| Building state | GDScript classes with no scene code | The port of `app/macos/Sources/TownCore/Building.swift`. Tested headless against `protocol/fixtures/` and `protocol/fixtures/expected/`, the same answers the macOS app is tested against |
| Choreographer and scene | Godot 3D: an orthographic `Camera3D` tilted 62° from the floor, `AnimationPlayer` | Per-character queues and the timing rules, as on macOS |
| Labels | 2D `Control` nodes over the 3D view, at each character's projected position | Name tags, ticket text, block signs, call lines, in Cubic 11 |
| Audio | `AudioStreamWAV.load_from_file` on the files in `C:\Windows\Media` | Completion, approval and dispatch sounds, with the duration gate; volume and mute apply |
| Localization | Parses the macOS app's `Localizable.strings` files (the only source of UI strings) plus `catalog/*.json` | Picks the language by the explicit rule in [spec.md](spec.md), not by Godot's nearest-locale match |

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

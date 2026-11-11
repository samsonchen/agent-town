# Windows app roadmap

Godot 4.7.2 (4.4 or later works), typed GDScript, in `app/windows/`. Scope: [spec.md](spec.md). Design: [architecture.md](architecture.md).

## W0: verify before building (in progress)

- [x] town-link on Windows: the plugin checks pass, and a live run found the endpoint in `%APPDATA%`, reached `127.0.0.1`, and sent only the folder name for a project with no remote (see [verification.md](verification.md))
- [ ] town-link in an interactive terminal session, the Desktop app's Code tab and VS Code on Windows
- [x] Godot: a Kenney GLB character imported with its animation clips, its shirt recolored at run time, drawn by an orthographic camera tilted 62°
- [x] Godot: a tray icon (`StatusIndicator`) with a menu
- [x] No taskbar button, and the window hidden and shown again: the native add-on TownWindow (`app/windows/native/`), built for x64 and ARM64. It keeps the button away even when Godot rebuilds the window's style (stay on top, a title change)
- [x] Godot: stay on top, and whole-window opacity from 10% to 100%
- [x] Godot: a `TCPServer` on 127.0.0.1 answering a town-link batch with 204
- [x] Godot: a WAV from `C:\Windows\Media` loaded at run time (still to hear it played)
- [x] Godot: Cubic 11 renders English and Traditional Chinese crisply at label sizes
- [x] Godot: the Windows locale read (`OS.get_locale()`); the mapping rule gets a unit test in W1
- [x] Godot: x64 and ARM64 exports build, and the x64 one runs
- [ ] The ARM64 export run on an ARM device or VM

## W1: the first version

- [x] Building state ported (`app/windows/core/`: events, the building, the `seq` sequencer), passing every fixture in `protocol/fixtures/expected/` and the ported unit tests
- [x] Loopback server, endpoint file and store: a live `claude -p` session with town-link drove the whole story (ticket, hat, desk worker, report, close) through `dev/store_check.gd`
- [x] The office: executive block and project blocks in one column, the window growing to fit; furniture, the fixed characters and the Chiefs of Staff at their desks; signs, name tags and context bars
- [x] Scenes 1 to 12 and 16: calls from the CEO (and the Dispatcher) and report calls, paging the bench, staff and operators at desks and consoles, reports and results (with "Failed"), approvals with the CEO's phone ringing, messages, desks carried in and out; checked with the fixtures. Desk workers are still to watch in a live session
- [x] Context bar, block signs with task titles
- [x] A sign whose task titles are wider than 20 columns scrolls sideways in a window 20 columns wide, as on macOS
- [x] Sounds with the duration gate (wired; still to hear them in a live session)
- [x] Tray menu, Settings (language, open at login, stay on top, opacity), About; no taskbar button, close hides the window, its place is remembered (checked from outside the app)
- [x] English and Traditional Chinese, Cubic 11
- [x] Sound settings (`docs/spec.md` → Sounds → Sound settings; the Windows choices in [spec.md](spec.md)): volume; per sound an on/off switch, the sound (every WAV in `C:\Windows\Media`, or a WAV, MP3 or Ogg file of the user's own) and a Play button; the completion threshold

## W2: parity with the macOS app

Each feature is confirmed by the user in the running app before the release.

- [x] Walking the CEO with the keys: arrow keys (diagonals too), sliding along furniture; H back to the desk on a path around it; the view following the CEO; the mobile phone away from the desk; the scroll wheel panning the view (checked with key presses through the input path; to confirm by hand)
- [ ] Walking the CEO with the mouse: clicking the floor or the CEO's desk, clicking a character to walk over and talk
- [ ] Back to the desk when all work is done; back into the executive office when the last project block goes
- [ ] Talking to a character: the statement it gives the CEO about its work
- [ ] The tips at the bottom of the window, and Show tips in the tray menu
- [ ] The Inspector at reception stopping a returned report, with the "Returned" stamp (scene 15)
- [ ] The Dispatcher's schedule board with its cards and the projects line (scenes 13 and 14)
- [ ] Compaction: the stack of notes and "Notes tidied" (scene 17)

## W3: release (last, once every feature is confirmed)


- [ ] An Inno Setup installer `.exe` on GitHub Releases, tagged `windows-v<version>`, titled "agent-town for Windows <version>", published with `--latest=false` so the macOS release stays "Latest"
- [ ] Code signing, free only (for example the SignPath Foundation's program for open-source projects); unsigned until then
- [ ] A `winget` package

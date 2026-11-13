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

- [x] Walking the CEO with the keys: arrow keys (diagonals too), sliding along furniture; H back to the desk on a path around it; the view following the CEO; the mobile phone away from the desk; the scroll wheel panning the view (checked with key presses through the input path; confirmed by the user 2026-11-12)
- [x] Walking the CEO with the mouse: clicking the floor (or into furniture: the nearest free spot) or the CEO's desk, clicking a character or its tags to walk over beside them (checked with clicks through the input path; confirmed by the user 2026-11-12)
- [x] Back to the desk when all work is done (after the report calls; an arrow key, a click or new work calls it off); back into the executive office when the last project block goes
- [x] Talking to a character: the statement it gives the CEO about its work, in a cream bubble with an orange border (the one clicked, else the nearest within 1.1 m)
- [x] The tips at the bottom of the window (the H tip while the CEO is away), and Show tips in Settings → Office (it was in the tray menu until the macOS app 1.0.5 moved it); closing a tip turns Show tips off
- [x] Hide idle project blocks (Settings → Office, off by default) with Hide after N seconds (1 to 3600, default 5), as in the macOS app 1.0.5: a block shows only while it has work and hides once it has settled; characters in a hidden block arrive at once; no block hides while the CEO is away (checked with the two-project demo and `--hide-idle 1`; confirmed by the user 2026-11-12)
- [x] Context bars of hidden blocks stay on screen (checked with the two-project demo and `--hide-idle 1`; to confirm by hand), as in the macOS app 1.0.7 (`docs/spec.md` → The office; `todo.md` section 9): with Hide idle project blocks on, each session in a hidden block keeps its context bar, labeled "<project> · Context …" ("<project> · Desk N · Context …" when the project has several sessions), so the user can see idle sessions. The bars are always under the executive office, in the order the projects opened, even while other project blocks are shown; the project blocks move down to make room, and the window grows to fit. Not under the last block shown: the macOS app 1.0.6 did that, and the user found it wrong.
- [x] The Inspector at reception stopping a returned report, with the "Returned" stamp and the hook's reason (scene 15; checked with fixture 04; to confirm by hand)
- [x] Update notices (checked with `--fake-update` in both languages and a real `--check-now`; to confirm by hand), as in the macOS app 1.0.8 (`docs/spec.md` → Updates; `todo.md` section 9): Settings → Updates (check automatically, on by default; Check now); once a day, the newest `windows-v*` release (by tag, not GitHub's "Latest") and town-link's `plugin.json` on `main`; a red dot on the tray icon, a tray menu line and an Updates window (no Windows notifications) with the installer's Download button and, for town-link, the sessions running an older one and the `claude plugin` commands
- [x] Check now in Settings → Updates opens the Updates window, in front, when the check finds an update (the app or town-link, the same test as the tray dot); nothing when there is none or the check failed. Check now in the Updates window and the automatic checks open nothing. As in the macOS app 1.0.12 (`todo.md` section 9). Tested with a stand-in updater (`tests/check_row_tests.gd`); to confirm by hand with `run-local.ps1 -Live -Settings` while a session runs an older town-link than `main`
- [x] The Dispatcher's schedule board with its cards and the projects line (scenes 13 and 14; checked with fixture 04; to confirm by hand)
- [x] Compaction: the stack of notes and "Notes tidied" (scene 17; checked with a fixture made from 01 plus compact.start and compact.end; to confirm by hand with /compact)

- [x] `app/windows/scripts/run-local.ps1` (and `run-local.sh` for Git Bash), like the Mac's `app/macos/scripts/run-local.sh`: runs the project from the checkout with Godot (no export, no installer), so the user can try a change before a release; a demo by default, `-Live` for real sessions (quits and later restarts an installed copy), and the options listed in `todo.md` section 9 ("a script to try a build before releasing")

- [x] Compact view, small windows (down to 320 × 240) and auto-scroll (checked with `--compact yes` and `--resize 400x300` demos; to confirm by hand), as in the macOS app 1.0.8 (`docs/spec.md` → The office; `todo.md` section 9)

## W3: release (last, once every feature is confirmed)


- [ ] An Inno Setup installer `.exe` on GitHub Releases (built: `scripts/release.ps1`, `installer/agent-town.iss`, [releasing.md](releasing.md); 1.0.0 published 2026-11-13; 1.0.1 allows Windows 10), tagged `windows-v<version>`, titled "agent-town for Windows <version>", published with `--latest=false` so the macOS release stays "Latest"
- [ ] Code signing, free only (for example the SignPath Foundation's program for open-source projects); unsigned until then
- [ ] A `winget` package

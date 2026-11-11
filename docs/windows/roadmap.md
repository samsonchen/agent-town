# Windows app roadmap

Godot 4.7.2 (4.4 or later works), typed GDScript, in `app/windows/`. Scope: [spec.md](spec.md). Design: [architecture.md](architecture.md).

## W0: verify before building (in progress)

- [x] town-link on Windows: the plugin checks pass, and a live run found the endpoint in `%APPDATA%`, reached `127.0.0.1`, and sent only the folder name for a project with no remote (see [verification.md](verification.md))
- [ ] town-link in an interactive terminal session, the Desktop app's Code tab and VS Code on Windows
- [x] Godot: a Kenney GLB character imported with its animation clips, its shirt recolored at run time, drawn by an orthographic camera tilted 62°
- [x] Godot: a tray icon (`StatusIndicator`) with a menu
- [ ] No taskbar button, and closing the window hides it: impossible in GDScript (Godot cannot hide its main window). Works with the Windows tool-window style and `ShowWindow`, so it needs a small native add-on (a GDExtension of one C++ file, built for x64 and ARM64). **Decision for the user:** build that add-on, or accept a taskbar button while the window is open
- [x] Godot: stay on top, and whole-window opacity from 10% to 100%
- [x] Godot: a `TCPServer` on 127.0.0.1 answering a town-link batch with 204
- [x] Godot: a WAV from `C:\Windows\Media` loaded at run time (still to hear it played)
- [x] Godot: Cubic 11 renders English and Traditional Chinese crisply at label sizes
- [x] Godot: the Windows locale read (`OS.get_locale()`); the mapping rule gets a unit test in W1
- [x] Godot: x64 and ARM64 exports build, and the x64 one runs
- [ ] The ARM64 export run on an ARM device or VM

## W1: the first version

- [ ] Building state ported, passing every fixture in `protocol/fixtures/expected/`
- [ ] Loopback server and endpoint file
- [ ] The office: executive block and project blocks in one column, the window growing to fit
- [ ] Scenes 1 to 12: calls, desk workers, staff and the bench, operators, approvals
- [ ] Context bar, block signs with task titles
- [ ] Sounds with the duration gate
- [ ] Tray menu, Settings (language, open at login, stay on top, opacity), About
- [ ] English and Traditional Chinese, Cubic 11

## W2: release

- [ ] An Inno Setup installer `.exe` on GitHub Releases, tagged `windows-v<version>`, titled "agent-town for Windows <version>", published with `--latest=false` so the macOS release stays "Latest"
- [ ] Code signing, free only (for example the SignPath Foundation's program for open-source projects); unsigned until then
- [ ] A `winget` package

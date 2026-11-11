# Windows app roadmap

Godot 4.4 or later, typed GDScript, in `app/windows/`. Scope: [spec.md](spec.md). Design: [architecture.md](architecture.md).

## W0: verify before building (in progress)

- [x] town-link on Windows: the plugin checks pass, and a live run found the endpoint in `%APPDATA%`, reached `127.0.0.1`, and sent only the folder name for a project with no remote (see [verification.md](verification.md))
- [ ] town-link in an interactive terminal session, the Desktop app's Code tab and VS Code on Windows
- [ ] Godot: a Kenney GLB character imported with its animation clips, its shirt recolored at run time, drawn by an orthographic camera tilted 62°
- [ ] Godot: a tray icon (`StatusIndicator`) with a menu; the window shows no taskbar button; closing it hides it
- [ ] Godot: stay on top, and whole-window opacity from 10% to 100%
- [ ] Godot: a `TCPServer` on 127.0.0.1 answering a town-link batch with 204
- [ ] Godot: a WAV from `C:\Windows\Media` loaded and played at run time
- [ ] Godot: Cubic 11 renders English and Traditional Chinese crisply at label sizes
- [ ] Godot: the Windows locale read and mapped by the spec's rule
- [ ] Godot: an ARM64 export that runs (else ship x64 only)

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

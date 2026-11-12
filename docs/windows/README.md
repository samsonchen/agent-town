# agent-town for Windows: docs

The Windows version of the agent-town app, planned and in progress. It draws the same office as the macOS app, from the same protocol and the same town-link plugin. These documents cover only what is specific to Windows. Everything they do not mention follows the main documents in [`docs/`](../README.md): the office, the scenes and the timing rules in [spec.md](../spec.md), the event mapping in [architecture.md](../architecture.md), and the protocol in [protocol.md](../protocol.md).

## Documents

| Document | What it covers |
|---|---|
| [spec.md](spec.md) | What the first version includes, and how it differs from the macOS app |
| [architecture.md](architecture.md) | The Godot app: its modules and how it uses the shared files |
| [roadmap.md](roadmap.md) | Phases W0 to W2 |
| [verification.md](verification.md) | What was checked on Windows, and what is still to check |

## Trying a change

`app/windows/scripts/run-local.ps1` runs the app from the checkout with Godot 4.7.2 (no export, no installer). Set `$env:GODOT` to the Godot exe first, unless `godot` is on `PATH`. From Git Bash or Claude Code's `!` prompt, use `bash app/windows/scripts/run-local.sh` with the same options.

```powershell
.\app\windows\scripts\run-local.ps1                 # a demo: fixture 05 (two projects), no sounds
.\app\windows\scripts\run-local.ps1 -Demo 04 -Zh    # another fixture, in Traditional Chinese
.\app\windows\scripts\run-local.ps1 -Live           # real Claude Code sessions
```

Options, any number and in any order: `-Demo 01`…`05` (or a path), `-Live`, `-FakeUpdate`, `-CheckNow`, `-Updates`, `-Settings`, `-Compact`, `-Resize WxH`, `-Sound`, `-Zh`, `-En`, `-Speed N`, and `--` to pass the rest to the app. `-Help` lists them. A demo starts no server, so a running agent-town keeps working beside it. `-Live` stops a running agent-town (the installed `agent-town.exe`, or one started from Godot with this project) and starts it again when the run ends, also after Ctrl+C. The run keeps its own settings in `%APPDATA%\agent-town\run-local\settings.cfg`.

## Status

W0 (verify before building) is nearly done. town-link works on Windows, and the Godot checks passed, and the native add-on that keeps the window off the taskbar works. What is left: town-link in interactive sessions, and running the ARM64 build on an ARM machine. W2 (parity with the macOS app) is nearly done; the Dispatcher's board and compaction are left. See [roadmap.md](roadmap.md).

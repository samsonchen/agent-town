# Windows verification

What has been checked on Windows, for town-link and for the Godot app. The macOS answers are in [verification.md](../verification.md).

## town-link

Checked 2026-11-11 on Windows 11 Pro (x64) with Claude Code 2.1.322, town-link loaded from the repo with `--plugin-dir plugin`, and `tools/debug-receiver.py` standing in for the app.

| Question | Answer |
|---|---|
| Do the plugin checks pass on Windows? | Yes, `claude plugin validate plugin` and all 52 tests of `claude plugin test plugin`, after one test fix: the host hands `$.fs.read` paths with backslashes on Windows, so a test that matched `/.claude-plugin/plugin.json` failed. The plugin code itself was right. |
| Is `HOME` set? | No. `APPDATA` is (`C:\Users\<user>\AppData\Roaming`), so town-link reads `%APPDATA%\agent-town\endpoint.json`. |
| Does `$.http.fetch` reach `127.0.0.1`? | Yes. A headless run (`claude -p`, `surface: headless`) sent all 14 events of a ticket with one Bash call; every batch passed the schema. |
| Project name with no git remote | Only the folder name (`No Remote Project`), not the path. With a remote, the remote's last part (`agent-town`). |
| Still to check | An interactive terminal session, the Desktop app's Code tab, and VS Code. |

## Godot

Not checked yet. The list is W0 in [roadmap.md](roadmap.md).

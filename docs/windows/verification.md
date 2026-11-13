# Windows verification

What has been checked on Windows, for town-link and for the Godot app. The macOS answers are in [verification.md](../verification.md).

## town-link

Checked 2026-11-11 on Windows 11 Pro (x64) with Claude Code 2.1.322, town-link loaded from the repo with `--plugin-dir plugin`, and `tools/debug-receiver.py` standing in for the app.

| Question | Answer |
|---|---|
| Do the plugin checks pass on Windows? | Yes, `claude plugin validate plugin` and all 52 tests of `claude plugin test plugin`, after one test fix: the host hands `$.fs.read` paths with backslashes on Windows, so a test that matched `/.claude-plugin/plugin.json` failed. The plugin code itself was right. |
| Is `HOME` set? | No. `APPDATA` is (`C:\Users\<user>\AppData\Roaming`), so town-link reads `%APPDATA%\agent-town-claude-code\endpoint.json`. |
| Does `$.http.fetch` reach `127.0.0.1`? | Yes. A headless run (`claude -p`, `surface: headless`) sent all 14 events of a ticket with one Bash call; every batch passed the schema. |
| Project name with no git remote | Only the folder name (`No Remote Project`), not the path. With a remote, the remote's last part (`agent-town`). |
| Still to check | An interactive terminal session, the Desktop app's Code tab, and VS Code. |

## Godot

Checked 2026-11-11 with Godot 4.7.2 (stable, standard build, not .NET) on the same machine, in a throwaway test project. The renderer was Compatibility (OpenGL).

| Question | Answer |
|---|---|
| Kenney characters | The GLB files import directly. Each character arrives with all 32 animation clips already separate (`walk`, `sit`, `idle`, `interact-right`, `holding-right`, `pick-up`, `emote-yes` …), so the macOS step of laying clips on one timeline (`clips.json`) is not needed. Furniture GLBs import too. |
| Shirt recolor | Works: the material's texture is copied, the shirt cell from `catalog/characters.json` is filled with the department color, and the copy is set on that character only. |
| Camera | An orthographic `Camera3D` tilted 62° draws the character behind a desk as on macOS. |
| Cubic 11 | Draws Traditional Chinese and English crisply at 12 px and 24 px with antialiasing and hinting off (「廣播：TypeScript 工程師」「整理筆記中…」「退回」). License: SIL OFL 1.1. The upstream `OFL.txt` opens with short permissive grants for Cubic 11 and the M+ fonts it is based on, then the full OFL 1.1 text; the upstream README states OFL 1.1. Bundle `OFL.txt` with the font, do not sell the font on its own, and do not use the reserved names "Cubic" or "俐方體" for a modified font. |
| Loopback server | Works. A `TCPServer` on 127.0.0.1 with a small HTTP reader in GDScript wrote `%APPDATA%\agent-town-claude-code\endpoint.json`, took all six batches of a real town-link session (`claude -p` with the plugin) and answered each with 204, then removed the endpoint file. |
| System sounds | `AudioStreamWAV.load_from_file` loads all three picks from `C:\Windows\Media` (1.29 s, 1.87 s, 0.06 s); a missing file is detected with `FileAccess.file_exists` first. Playback through the speakers is still to hear. |
| Locale | `OS.get_locale()` returns the Windows locale (`en_US` here). The mapping rule for Chinese locales is to be unit-tested; this machine has no Chinese display language. |
| Stay on top | `Window.always_on_top` works. |
| Opacity | Works as see-through: a transparent window (`transparent`, `transparent_bg`, per-pixel transparency allowed) showing the 3D view through a `TextureRect` whose `modulate.a` is the opacity. The desktop shows through at 60%. Labels need the same alpha. |
| Tray icon | `StatusIndicator` with an icon, a tooltip and a `PopupMenu` works. |
| No taskbar button | **Not possible in GDScript.** Godot has no window flag for it, and it refuses to hide its main window ("Can't change visibility of main window"), so a window owned by a hidden main window cannot work either. At the Windows level it does work: giving Godot's main window the `WS_EX_TOOLWINDOW` style removed its taskbar button, and `ShowWindow` hid and showed it while Godot kept running. The app needs a little native code for this (see [roadmap.md](roadmap.md)). |
| TownWindow add-on | Checked in a real window, inside the app and from outside with the Windows window list. It loads, removes the taskbar button, keeps it removed after stay on top and a title change (the first build did not: Godot rebuilt the style, so the add-on now hooks `WM_STYLECHANGING`), hides the window and shows it again. Built with Visual Studio Build Tools 2026 (MSVC 14.50, Windows SDK 10.0.26100) for x64 and ARM64. |
| Exports | Godot 4.7.2 ships Windows x64 and ARM64 export templates. Both exports build; the files are x64 (`0x8664`) and ARM64 (`0xAA64`) programs. The x64 export runs and draws the scene. The ARM64 export still has to be run on an ARM device or VM. |

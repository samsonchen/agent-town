# Windows app spec

The Windows app runs on Windows 11 on x64, with ARM64 as a nice-to-have (an x64 build also runs on ARM through emulation). It draws the same office from the same protocol and follows the main [spec](../spec.md), except where this document says otherwise.

It has its own version number, separate from the macOS app and from town-link. The protocol version alone decides whether a plugin and an app work together.

## First version

Included: the office and its blocks, the CEO's and the Chief of Staff's calls, staff and the resource bench, desk workers, operators, approvals, the context bar, the sounds, and the tray menu. That is about scenes 1 to 12 of the main spec.

Since W2 ([roadmap.md](roadmap.md)) the Windows app has every scene of the main spec: the Dispatcher's board (13 and 14), the Inspector (15), messages (16) and compaction (17), and walking the CEO, with the tips, Hide idle project blocks (with the hidden blocks' context bars), compact view, small windows, auto-scroll and the update notices. Each is to be confirmed by hand before the release. The installer and signing come last, once every feature is confirmed.

## Differences from the macOS app

| Topic | macOS | Windows |
|---|---|---|
| Where the app lives | Menu bar icon, no Dock icon | Tray icon (notification area), no taskbar button. Closing the office window hides it; the app keeps running. |
| Menu | The menu bar menu | The same items in the tray icon's menu (Show tips is in Settings → Office, as on the Mac). A left click on the icon shows the window. Windows 11 first puts a new tray icon among the hidden icons (the ^ arrow); it can be dragged out to stay in view. |
| Sounds | macOS system sounds (Glass, Ping, Pop) | Windows system sounds from `C:\Windows\Media`, played from there and never bundled: completion `Windows Notify.wav`, approval `Windows Exclamation.wav`, dispatch `Speech Disambiguation.wav` (the user's picks, 2026-11-13). A missing file plays nothing. |
| Sound choices (spec: sound settings) | The sounds in `/System/Library/Sounds` | Every WAV file in `C:\Windows\Media` (70 on Windows 11), listed by name without `.wav`, sorted, with the default first. Defaults: completion `Windows Notify`, approval `Windows Exclamation`, dispatch `Speech Disambiguation`. Own files: WAV, MP3 or Ogg Vorbis (what Godot loads at run time); the path is kept, the file is not copied. |
| Window sizes | Points; the smallest window is 320 × 240 | Pixels; the smallest window is 320 × 240. Compact view keeps its own window size, saved in its own section of `settings.cfg` |
| Update notices | A dot on the menu bar icon; Homebrew's command or the `.dmg` | A red dot on the tray icon; the Download button opens the installer from the newest `windows-v` release. Until the first Windows release, a check finds none and says agent-town is up to date. Dev flags: `--fake-update`, `--check-now`, `--open updates` |
| Open at login | A login item macOS manages | An entry in the user's startup apps (Settings → Apps → Startup) |
| Language | Follows the macOS language list | Follows the Windows display language: `zh_TW`, `zh_HK`, `zh_MO` and any `zh_Hant` locale get Traditional Chinese; every other locale, including Simplified Chinese, gets English |
| Font | System font for now; Cubic 11 planned | Cubic 11 (俐方體11號) from the first version, because Traditional Chinese must show and the engine's default font has no Chinese characters |
| Install | Homebrew cask or a signed `.dmg` | An installer `.exe` on GitHub Releases (a `winget` package later). Not code-signed at first: Windows shows "Windows protected your PC", and the user clicks More info → Run anyway. Signing, when added, must be free. |
| Update notices (spec: Updates) | Newest `v*` release; a red dot on the menu bar icon; the Updates window shows the brew command or the `.dmg` Download button | Newest `windows-v*` release (by tag: GitHub's "Latest" stays on the macOS release); a red dot on the tray icon; the Updates window shows a Download button for the installer, which replaces the installed app when run. Until the first Windows release there is no `windows-v*` tag: show no app update, and say "Not checked yet" only before any check has answered. town-link's part is the same on both. No system notifications on either. |

## Where it works

Claude Code run natively on Windows: the terminal (PowerShell, Command Prompt, Git Bash), the Code tab of the Claude Desktop app, and the VS Code extension.

Not supported: sessions inside WSL or WSL2 (they cannot see the Windows endpoint file), plus everything the main spec lists as unsupported.

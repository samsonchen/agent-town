# Windows app spec

The Windows app runs on Windows 11 on x64, with ARM64 as a nice-to-have (an x64 build also runs on ARM through emulation). It draws the same office from the same protocol and follows the main [spec](../spec.md), except where this document says otherwise.

It has its own version number, separate from the macOS app and from town-link. The protocol version alone decides whether a plugin and an app work together.

## First version

Included: the office and its blocks, the CEO's and the Chief of Staff's calls, staff and the resource bench, desk workers, operators, approvals, the context bar, the sounds, and the tray menu. That is about scenes 1 to 12 of the main spec.

Next, before any release (W2 in [roadmap.md](roadmap.md)): the Dispatcher's board and the Inspector (scenes 13 to 15) and compaction (17). Walking the CEO, with the tips, is in. Messages (16) are already in. Until then, a returned ticket shows as an ordinary ticket. The installer and signing come last, once every feature is confirmed.

## Differences from the macOS app

| Topic | macOS | Windows |
|---|---|---|
| Where the app lives | Menu bar icon, no Dock icon | Tray icon (notification area), no taskbar button. Closing the office window hides it; the app keeps running. |
| Menu | The menu bar menu | The same items in the tray icon's menu, Show tips included. A left click on the icon shows the window. Windows 11 first puts a new tray icon among the hidden icons (the ^ arrow); it can be dragged out to stay in view. |
| Sounds | macOS system sounds (Glass, Ping, Pop) | Windows system sounds from `C:\Windows\Media`, played from there and never bundled: completion `Windows Notify System Generic.wav`, approval `Windows Notify Messaging.wav`, dispatch `Windows Ringout.wav` (an outgoing ring). A missing file plays nothing. |
| Sound choices (spec: sound settings) | The sounds in `/System/Library/Sounds` | Every WAV file in `C:\Windows\Media` (70 on Windows 11), listed by name without `.wav`, sorted, with the default first. Defaults: completion `Windows Notify System Generic`, approval `Windows Notify Messaging`, dispatch `Windows Ringout`. Own files: WAV, MP3 or Ogg Vorbis (what Godot loads at run time); the path is kept, the file is not copied. |
| Open at login | A login item macOS manages | An entry in the user's startup apps (Settings → Apps → Startup) |
| Language | Follows the macOS language list | Follows the Windows display language: `zh_TW`, `zh_HK`, `zh_MO` and any `zh_Hant` locale get Traditional Chinese; every other locale, including Simplified Chinese, gets English |
| Font | System font for now; Cubic 11 planned | Cubic 11 (俐方體11號) from the first version, because Traditional Chinese must show and the engine's default font has no Chinese characters |
| Install | Homebrew cask or a signed `.dmg` | An installer `.exe` on GitHub Releases (a `winget` package later). Not code-signed at first: Windows shows "Windows protected your PC", and the user clicks More info → Run anyway. Signing, when added, must be free. |

## Where it works

Claude Code run natively on Windows: the terminal (PowerShell, Command Prompt, Git Bash), the Code tab of the Claude Desktop app, and the VS Code extension.

Not supported: sessions inside WSL or WSL2 (they cannot see the Windows endpoint file), plus everything the main spec lists as unsupported.

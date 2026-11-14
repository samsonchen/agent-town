# agent-town for Windows: changelog

What changed in each release of the Windows app. Each version is tagged `windows-v<version>` in this repository, and `git log windows-v<previous>..windows-v<version>` lists its commits. The macOS app and the town-link plugin have their own changelogs and version numbers. Whether an app and a town-link work together depends only on the protocol version.

## 1.0.7 (not yet released)

- New: Settings → Office → Hide the window when no Claude Code session is open (off by default). The office window hides 5 seconds after the last session closes and comes back, without taking the focus, when a session opens. Show agent-town in the tray menu shows it anyway.
- When a project has had no work for a while, the characters waiting on the bench pass the time. Any new work, or the CEO coming over to talk, ends it.
- The bench has a straight sofa. The two characters on it sit on its cushions, no longer sunk into the seat, and walk around it to sit down and to leave.
- The update check at launch tries again after 1, 2, 5 and 10 minutes when it fails, for example when the network is not up yet at sign-in.
- Fixed: a Chief of Staff carrying a desk out could stop with a script error, and one whose project closed on the way out raised another.
- Hide after now sits indented under Hide idle project blocks, and is dimmed while that is off.

## 1.0.6 (2026-11-13)

- Fixed: the app could crash when a project block hid while a phone in it was ringing (Settings → Office → Hide idle project blocks). The phone now stops ringing when its block hides.
- New: a Microsoft Store version can be built from the same source. It is updated by the Store, and Open at login for it is turned on in Windows Settings → Apps → Startup. The installer version works as before.

## 1.0.5 (2026-11-13)

- Fixed: Open at login did not start the app. Windows skipped the startup entry because it was written with forward slashes and no quotes. The entry is now a quoted Windows path, and the app rewrites an old entry when it starts.
- Fixed: with Stay on top on, Settings, Updates and About opened behind the office window. They now stay above it.

## 1.0.4 (2026-11-13)

- Check now in Settings → Updates opens the Updates window when it finds a newer app or town-link.

## 1.0.3 (2026-11-13)

- The repository is now `samsonchen/agent-town-claude-code`. The update check, the About link and the installer use it.
- Everything the app keeps on disk is now in `%APPDATA%\agent-town-claude-code` (the endpoint file, settings, logs), and the app installs to `%LOCALAPPDATA%\Programs\agent-town-claude-code`. Use town-link 1.0.4 or later, which looks for the endpoint there.
- The installer removes the old install folder, data folders and startup entry. Settings start afresh.

## 1.0.2 (2026-11-13)

- Fixed: Setup stopped when agent-town was running, because the app hides in the tray instead of closing when asked. Setup now stops the running app itself, and Open agent-town at the end of Setup starts the new one.

## 1.0.1 (2026-11-13)

- The installer allows Windows 10 (1.0.0 required Windows 11). The app is tested only on Windows 11.

## 1.0.0 (2026-11-13)

The first release: the office for Claude Code in the Windows tray, a port of the macOS app.

- The office: the executive block and one block per project, with the CEO, the Inspector, the Dispatcher, Chiefs of Staff, staff, operators and the bench, drawn from town-link's events.
- Calls, approvals, reports and results, the Dispatcher's schedule board, the Inspector stopping a returned report, and compaction notes.
- Walking the CEO with the arrow keys or the mouse, and talking to a character.
- Tray menu, Settings (language, open at login, stay on top, opacity, sounds, office options), About, and update notices.
- Hide idle project blocks, compact view, small windows with auto-scroll, and tips.
- English and Traditional Chinese.
- An installer for the current user only (no administrator prompt), not yet code-signed.

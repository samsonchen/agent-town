# agent-town for macOS: changelog

What changed in each release of the macOS app. Each version is tagged `v<version>` in this repository, and `git log v<previous>..v<version> -- app/macos` lists its commits. The Windows app and the town-link plugin have their own changelogs and version numbers. Whether an app and a town-link work together depends only on the protocol version.

## 1.0.14 (not yet released)

- Settings → Office → Hide the window when no Claude Code session is open (off by default). With it on, the office window hides a few seconds after the last session closes, and comes back when a session opens. Show agent-town in the menu shows it anyway.
- Settings: Hide after is indented under Hide idle project blocks, which it belongs to.
- Break time: when a project has had no work for 3 minutes, the people on its bench pass the time, one now and then: juggling, a puzzle cube, tossing a ball, looking at a phone, chatting, or dozing off. They stop as soon as work comes in.
- The update check at launch tries again after 1, 2, 5 and 10 minutes when it fails, as it can at login before the network is up.
- Fixed: the two seated characters on the bench sat on the sofa's arms, and the corner of the L-shaped sofa covered the one on the right. The bench now has a straight sofa, with both seated on top of its cushions instead of sunk into the seat.

## 1.0.13 (2026-11-13)

- Fixed: with Stay on top on, Settings, Updates and About opened behind the office window. They now open above it.

## 1.0.12 (2026-11-13)

- Check now in Settings → Updates opens the Updates window when it finds a newer app or town-link.

## 1.0.11 (2026-11-13)

- The bundle ID is now `ai.careactive.agenttown-claude-code`. Settings start afresh; remove an older install first.
- The Updates window's town-link commands use the marketplace's new name, `town-link@agent-town-claude-code`.

## 1.0.10 (2026-11-13)

- The repository is now `samsonchen/agent-town-claude-code`, and so is the Homebrew tap. The update check, the About link and the Updates window's commands use it.
- The endpoint file is now in `~/Library/Application Support/agent-town-claude-code`. Use town-link 1.0.4 or later, which looks for it there.
- Release notes give the `.dmg`'s SHA-256.

## 1.0.9 (2026-11-13)

- Releases are titled "agent-town for macOS <version>", beside the Windows app's releases. The update check is unchanged: it goes by the `v<version>` tag.

## 1.0.8 (2026-11-12)

- Update notices: the app checks GitHub once a day for a newer app and a newer town-link. When one is out, a red dot appears on the menu bar icon, the menu says which, and the Updates window shows how to update with Homebrew or the `.dmg`. No system notifications.
- Compact view (Settings): the office at half size, its text at three quarters. It takes effect after a restart.
- The window can be made as small as 320 × 240. When the office doesn't fit, the view scrolls by itself to where people are walking, and pauses for a while after you scroll it yourself.

## 1.0.7 (2026-11-12)

- Hidden blocks' context bars always sit under the executive office.

## 1.0.6 (2026-11-12)

- Hidden project blocks keep their context bars on screen.

## 1.0.5 (2026-11-12)

- Hide idle project blocks (Settings → Office), after a time you choose.
- Show tips moved from the menu to Settings.

## 1.0.4 (2026-11-12)

- Settings → Sounds: Ticket dispatched, Work done and Approval needed, each on or off, and a sound only when a task takes at least a number of seconds you choose. The labels match the Windows app's.

## 1.0.3 (2026-11-11)

- Fixed: started by Open at login, the app did not open the office window. It now does.
- The app has its own version number, apart from town-link's.

## 1.0.2 (2026-11-11)

- The app is checked against the expected building state of each recorded fixture, the same states the Windows app is tested against. Nothing a user would notice.

## 1.0.1 (2026-11-11)

Includes 1.0.0 and 0.3.1, which were not released on their own.

- Fixed: a Chief of Staff whose session ended while walking in with a desk vanished and left the desk behind. The Chief now carries it out.
- A town-link with a newer protocol version is told so (HTTP 426), and `/town` says to update.

## 0.3.0 (2026-11-11)

- Stay on top: a menu bar toggle that keeps the office window above other apps.
- Settings → Opacity, from 10% to 100%.
- Click the floor to walk the CEO there, or the CEO's desk to send the CEO back.
- `release.sh --publish` publishes the release and pushes the Homebrew cask.

## 0.2.9 (2026-11-11)

- Fixed: resumed agents left staff stuck at their desks.
- Messages between agents show as readable notes.

## 0.2.8 (2026-11-11)

- Fixed: operators stayed in the server room after a subagent's background task ended.
- The server room has a label.

## 0.2.7 (2026-11-11)

- The first signed and notarized build: it opens with no "Open Anyway" step.

## 0.2.6 (2026-11-11)

- The menu bar icon is the system building symbol again.

## 0.2.5 (2026-11-11)

- An app icon and a menu bar icon.

## 0.2.4 (2026-11-11)

- A turn that starts without a prompt, such as after a `!` command, shows in the office.

## 0.2.3 (2026-11-11)

The first published build, not signed (macOS asked for Open Anyway once). Installs with Homebrew.

- The office: the executive office as a strip at the top, with the CEO, the Inspector at reception and the Dispatcher's schedule board; under it one block per open project, stacked in one column, with the window growing to fit.
- Each block: its Chief of Staff taking tickets and phoning reports back, staff at desks by role, operators in the server room, the resource bench with its speaker, and the `/compact` scene.
- The context bar, task titles and model badges.
- Walking the CEO with the arrow keys.
- The menu bar menu: show the window, sound, tips, language, Open at login, and About.
- The window opens where it was when the app last quit.
- English and Traditional Chinese.

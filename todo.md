# agent-town: to do

Open items as of 2026-11-11, for the next session to pick up. Everything listed as done is on `main`.

## Where things stand

- Work is committed on `main`.
- town-link 1.0.5 (an icon, for the plugin directory) and the Windows app 1.0.6 (no crash when a ringing phone's block hides; not yet released), after 1.0.5 (Open at login works: the Run entry is written with backslashes and quotes; Settings, Updates and About stay above a Stay-on-top office window; released), after 1.0.4 (Check now in Settings opens the Updates window, released), after 1.0.3 (the repository `samsonchen/agent-town-claude-code` and the data folder `agent-town-claude-code`, released); the macOS app 1.0.14 (Settings: Hide the window when no Claude Code session is open; Hide after indented; break time on the bench; the straight bench sofa; launch update check retries; not yet released), after 1.0.13 (Settings, Updates and About open above a Stay-on-top office window), after 1.0.12 (1.0.11 changed the bundle ID to match the repository; 1.0.12: Check now in Settings opens the Updates window when it finds an update), after 1.0.10 (the repository and the data folder). They move separately. town-link is installed from GitHub on the personal account; the app is installed with Homebrew from this repo's tap (`Casks/agent-town.rb`). v0.2.7 was the first signed and notarized release.
- Versions are separate (since 2026-11-11, both at 1.0.2 then). A plugin change: raise `plugin/.claude-plugin/plugin.json`, commit and push; no release. An app change: raise `AppInfo.fallbackVersion` in `app/macos/Sources/AgentTown/About.swift`, commit and push, then the user runs `app/macos/scripts/release.sh --publish` (auto mode refuses to publish a release): it publishes the release, checks the uploaded `.dmg`'s checksum, and commits and pushes the cask. Users update with `brew upgrade --cask agent-town` and `claude plugin update town-link@agent-town-claude-code`.
- Plugin checks: `claude plugin validate plugin` and `claude plugin test plugin` (53 tests). App checks: `swift build` and `swift test` in `app/macos` (36 tests).
- Two Swift warnings in the release build, harmless: `TownScene+Staff.swift:89` (a weak self inside a strong one) and `TownView.swift:489` (a non-Sendable observer closure). Clean up when convenient.

## 1. Check on a personal (non-Team) account

On a Team account whose organization ([organization]) manages Claude Code's settings, as the maintainer's work account does, In that case, every `classic.*` hook and `session.compact` skip plugins the user installed. `/plugin` → Errors lists them. The built-in guard `cc-plugin-sec-default` loads only with managed settings or a Team or Enterprise login, so a personal account should get every event.

Check these on the personal account:

- [x] `/plugin` → Errors shows nothing for town-link (checked 2026-11-11 on the personal account).
- [ ] Automatic compaction shows the notes scene (`session.compact` with trigger `auto`). Low priority: the user is not worried about it; check it if it comes up.
- [x] The Inspector's "Returned" scene works on the personal account (checked 2026-11-11 with a test Stop hook). `classic.Stop` runs there; town-link read the hook's reason from the wrong field, fixed in 0.2.3 (the reason is `block`'s text).
- [x] The permission mode follows Shift+Tab (checked 2026-11-11): in manual mode a slow approval shows the wait and plays the sound; in auto mode the classifier's quick answers show nothing. A classifier answer slower than 5 seconds can't be forced, so that case is untested.
- [x] The README's known issues say these happen only where an organization manages Claude Code, and `docs/verification.md` item 15 names that cause.

## 2. Waiting on others

- [x] **Developer ID Application certificate** (done 2026-11-11). The maintainer's role in the developer team can't create it. The team's Account Holder ([name]) must accept the latest Program License Agreement and issue the certificate. `docs/releasing.md` has the steps, including the request-file route under "If you are not the Account Holder". Parts B and C (app-specific password, `notarytool store-credentials agent-town-notary`) don't need the certificate.
- [x] **App icon** added (2026-11-11): `assets/icons/app-icon-1024.png`; release.sh makes AppIcon.icns from it. The menu bar keeps the system symbol `building.2`, by the user's choice.

## 3. Release

- [x] The first signed and notarized release, v0.2.7 (2026-11-11). The cask's and the README's "not signed yet" notes are gone.
- [x] Unsigned pre-releases v0.2.3 to v0.2.6 on GitHub Releases.
- [x] The repo is public (2026-11-11). The history was scanned for secrets first: none found.
- [x] Homebrew cask in `Casks/agent-town.rb` (this repo is the tap).
- [ ] Later: signing and notarization in GitHub Actions, the official Homebrew casks (signed apps only), Sparkle updates (roadmap Phase 6).

## 4. README and docs

- [x] README rewritten in the user's order (what it is, installing, the office, known issues, Claude Desktop and Cowork). The install steps now use Homebrew or the `.dmg` from Releases instead of building from source. Was: README "Install (planned)" and "No installer yet": the plugin install from GitHub works now. Update both, and the "Status" section, once the signed app is on Releases.
- [ ] The Traditional Chinese version of the README story ("Why agent-town exists"): the user hasn't decided yet.
- [x] Roadmap updated to match what is built. Was: Roadmap Phase 2 still lists "Settings window" and "An `.app` bundle" as open. The `.app`, the menu bar, the language setting and the About window are done, so update those lines. Threshold, sounds, ticket text, badges and the Cubic 11 font are still open.

## 5. App features still open

From `docs/roadmap.md` and `docs/spec.md`:

- [x] The Dispatcher's board: one card per active schedule (scene 13), `TownScene+Board.swift`.
- [x] Scene 14: the Dispatcher radios a scheduled ticket to the Chief of Staff, and the report goes back to the Dispatcher (checked 2026-11-11 with a one-time CronCreate schedule).
- [x] The Inspector stopping a returned report at reception (scene 15), `TownScene+Inspector.swift`, checked 2026-11-11 with a test Stop hook.
- [x] Staff talking to each other directly (scene 16), checked 2026-11-11 with two background subagents, Legal and Accounting, messaging each other with SendMessage: the sender walks to the receiver's desk, with no Chief of Staff in between.
- [x] Operators stuck in the server room after a subagent's background task ended (fixed in 0.2.7–0.2.8, checked 2026-11-11). The task's notification goes to the subagent, not the main conversation. town-link now also ends a task from `session.receive`, from `TaskStop`, and when the subagent that started it has finished (`$.agent.list()` every 5 s). The server room has a "Server room" (「機房」) label.
- [x] Stay on top (menu bar toggle), Opacity (Settings, 10%–100%), and clicking the floor to walk the CEO there or the CEO's desk to send the CEO back (0.3.0, 2026-11-11). Checked by tests and a demo window (floating level and alpha read back); clicking tried by hand in the installed app (1.0.1).
- [ ] Several sessions in one project block: desks and phones, up to five (the back row's desk spots; a sixth stands on the first desk's spot, a known limit in the README).
- [x] **Hide idle project blocks** (macOS app 1.0.5, 2026-11-12; `docs/spec.md` → The office, and Settings): a Settings switch, off by default; with it on, a project block shows only while it has work and hides after its work has settled for N seconds (1–3600, default 5, set beside the switch). Checked with the two-project demo (`-hideIdleBlocks YES -idleHideSeconds 1`), and by the user in the released 1.0.5. Code: `TownScene+Blocks.swift`.
- [x] **Context bars of hidden blocks stay on screen** (macOS app 1.0.6, 2026-11-12): with Hide idle project blocks on, each session in a hidden block keeps its context bar, named by project, always under the executive office; the project blocks move down to make room. Checked with the two-project demo; the first version put them under the last block shown, which the user found wrong while testing.
- [x] **Show tips moved from the menu bar menu to Settings** (macOS app 1.0.5, 2026-11-12; checked by the user).
- [x] **Update notices** (macOS app 1.0.8 and town-link 1.0.3, 2026-11-12; checked with a demo: `--fake-update` for the window in both languages and the menu bar dot, `--check-now` for a real check; `docs/spec.md` → Updates): once a day the app reads the newest `v*` release and town-link's `plugin.json` on `main` from GitHub; a dot on the menu bar icon, a menu line and an Updates window (no system notifications, by the user's choice) with the steps for Homebrew or the `.dmg`, and for town-link the sessions running an older one. town-link sends `pluginVersion` in `session.open`. Self-update (Sparkle) stays for later (section 3).
- [x] **Compact view, small windows and auto-scroll** (macOS app 1.0.8, 2026-11-12; `docs/spec.md` → The office): Settings → Office → Compact view (off by default, applies after a restart) draws the office at half size and its text at 75%; the window can be as small as 320 × 240 and keeps a height the user made shorter than the office; when the office doesn't fit, the view auto-scrolls to the area with the most walking characters (the CEO being walked, or the user's own scrolling, holds it off for 10 s). Checked with demos (`--compact`, `--resize 400x300` in `run-local.sh`). Tags of side-by-side characters can overlap in compact view (README known issues).
- [ ] **Compact view: a tighter layout** (asked 2026-11-12, deferred by the user until they've tried half size): desks closer (1.0 m apart instead of 1.2; a desk is 0.62 m wide and a character about 0.4 m, so 0.38 m is left to walk through), paths between blocks 0.8 m instead of 1.4, margins 0.5 m instead of 0.9. The bench, the server room and the executive strip keep their sizes (their spots match the furniture). About 15–20% more on top of half scale. Every spot and route reads `Layout`'s fixed distances (about 100 places), so it would apply after a restart.
- [x] Stay on top: the About, Updates and Settings windows sit one level above the floating office window (macOS app 1.0.13, 2026-11-13; `aboveStayOnTop()` in `TownView.swift`). Not yet checked by hand.
- [x] **Windows: Open at login did not start the app** (found 2026-11-13 over Remote Desktop; fixed in the Windows app 1.0.5). The Run value held Godot's path with forward slashes and no quotes (`C:/Users/.../agent-town.exe`); Explorer's log (Microsoft-Windows-Shell-Core/Operational, events 9705–9708) shows it skipped that entry at every sign-in, local or remote, while running the others. Now `LoginItem.command` writes `"C:\...\agent-town.exe"`, and the app rewrites an old entry at launch (`LoginItem.repair`). To confirm by hand: install 1.0.5, start it once, sign out and in (or sign in over Remote Desktop), and the app is back.
- [x] **Windows: the same** (Windows app 1.0.5, 2026-11-13). With Stay on top on, Settings, Updates and About open above the always-on-top office window. They are now owned by the office window (`TownWindow.set_owner`, called by `main.gd` each time one is shown), so Windows keeps them above it in both modes, also when the office is clicked. Checked from outside with the window list in a demo, Stay on top on and off, and confirmed by the user (2026-11-13).
- [x] **Windows: the app crashed when a ringing phone's block hid** (found 2026-11-13 in 1.0.5, twice in two minutes, on Windows 11 on ARM; fixed in the Windows app 1.0.6). Windows logged an access violation (`c0000005`) in `ntdll.dll`, and the app's log (`%APPDATA%\agent-town-claude-code\logs\godot.log`) ended with `Parameter "data.tree" is null` each time. `TownPhone.ring` waits on `device.get_tree()` between shakes; with Hide idle project blocks on, a block hidden mid-ring is out of the tree but not freed, so the tree was null, and the release build has no null check before `create_timer` and crashes. `ring` now stops when the device is out of the tree, and no longer leaves `ringing` set when it stops early. Test: `tests/phone_tests.gd`.
- [ ] Settings for window size and bench size.
- [ ] Zoom, for many project blocks. Blocks are now one column, the window grows up to the screen height, and a taller office scrolls.
- [ ] Phase 3 leftovers: props in hand, more idle life on the bench, workflow subagents reporting to the coordinator, and name tags that move apart when characters stand close together.
- [x] **Sound settings (released in the macOS app 1.0.4, 2026-11-12; Settings → Sounds, `Sounds.swift`; same labels as the Windows app's). Specified 2026-11-11, `docs/spec.md` → Sounds → Sound settings):** in Settings, a volume slider for agent-town's own sounds; for dispatch, completion and approval an on/off switch, a list of the sounds in `/System/Library/Sounds` (the default first: Glass, Ping, Pop) plus Choose a file…, and a Play button; the completion threshold (0–3600 s, default 0) in the completion row. The menu's Sound item still mutes all three; a sound that cannot be played falls back to its default. The Windows app builds the same (`docs/windows/roadmap.md`).
- [ ] Phase 5: hats, model badges with a show or hide setting, the Cubic 11 font, the ticket text setting. Launch at login is done (Settings → Open at login); check it in the packaged app.

## 6. To check by hand

- [ ] Click through every menu bar item in the packaged app: About, Show agent-town, Stay on top, Sound, Settings…, Quit. The About window was checked only as a rendered image.
- [ ] Office blocks: a second project's block appears before its first prompt, stacks under the first one, and the window grows. It goes when that project's last session ends.
- [ ] The window opens where it was after a restart, on the same display.

## 7. Known limits of the dev tools

- The offscreen `--snapshot` sometimes draws only the 2D labels and no 3D scene, in release builds and lately in debug builds too. The live window is fine. To check a scene, run the demo in a window: `AgentTown --demo <fixture> -showWindow YES`, then `screencapture -l <window id>`.
- The plugin test kit's clock doesn't move `Date.now()`, so the outbox timer (approval waits) can't be tested through `register.ts`. Test it in `tests/core.test.ts` instead.

## 8. Decisions still open

- [x] Bundle ID: the organization's reverse-DNS prefix plus `agenttown-claude-code` (`BUNDLE_ID` in `release.sh`; since macOS app 1.0.11, 2026-11-13, matching the repository; the Developer ID certificate signs any bundle ID). Settings are kept by it, so changing it again would make macOS treat the app as new and reset them.
- [ ] Open questions in `docs/roadmap.md`: the default for ticket text, whether `claude -p` runs appear, sound files, bench size, where scheduled reports go, and long-lived operators.

- [x] **Other coding agents (Codex CLI, Grok Build): not now** (decided 2026-11-13). Both have shell-style hooks (session start, prompt, tool calls, stop; Grok also subagent stop), but no mod interface: a hook can't call a model (task titles, roles) and can't see subagents and background tasks the way town-link does, so their office would lack staff, operators, titles and the context bar. The user finds that too dry. agent-town stays Claude Code only, hence the repository name `agent-town-claude-code`. Revisit only if their hooks gain subagents and a model call.

- [x] **Anthropic's plugin directory: not now** (decided 2026-11-13). The portal's validation (main @ 721371f) blocked on the `tool.check` hook: it reads Claude Code's verdict to know a person is being asked and returns it from a variable, and the directory needs `return next(e)` written out. Returning `next(e)` directly loses the verdict; the classic `PermissionRequest` hook would avoid it, but classic hooks skip user-installed plugins where an organization manages Claude Code, so the approval scene would vanish there. The directory will also accept mods only from Verified organizations, and town-link must be a mod. town-link stays on this repository's marketplace. The icon (`.claude-plugin/icon.png`) stays for a later submission. If one comes: a README section on what town-link sends where and what each hook does, re-encode `icon.png` (its bytes tripped a download-and-run pattern), and make the getter at `hooks/core.ts` line 207 a method.

- [x] **Platforms: macOS stays native, Godot for Windows and a future Linux** (decided 2026-11-14). The macOS app stays Swift and RealityKit: a native menu bar app, small, light on battery, with native Settings windows. The Godot app (`app/windows/`) is the base for Linux when it comes. Not started; when it is, check first: a tray icon on Linux (Godot's `StatusIndicator` may not cover every Linux desktop), the Windows-only native add-on (`app/windows/native/`, taskbar and window owner) and what Linux needs instead, an endpoint path for Linux in town-link (`endpointFilePath` in `plugin/hooks/core.ts` knows only `%APPDATA%` and `~/Library/Application Support`; Linux would use `$XDG_CONFIG_HOME` or `~/.config`, a plugin change), Open at login (a `.desktop` file in `~/.config/autostart`), and packaging (AppImage, Flatpak or a `.deb`).

## 9. Before the Windows app: work for the Mac session

A Windows version of the app is planned: Windows 11 on x64, with ARM64 as a nice-to-have. The engine is Godot 4 (see "Windows app: decisions" below). The items below are the groundwork that needs the Mac (`swift build` and `swift test`, the release script) or is best done there. Verifying the plugin on Windows itself is done on the Windows machine: the headless check passed on 2026-11-11 (`docs/windows/verification.md`). The Windows app's own steps are W0 to W2 in `docs/windows/roadmap.md`; all Windows docs are in `docs/windows/`.

**Versions:** the Windows app has its own version number, separate from the macOS app and from town-link. Compatibility comes only from the protocol version (now 1): the app accepts batches whose `protocol` it speaks and answers 426 to others.

### Windows app: decisions (2026-11-11)

- **Engine:** Godot 4 (4.4 or later), in typed GDScript (not C#), in `app/windows/`.
- **First version:** the blocks, CEO and Chief of Staff calls, staff and the bench, operators, approvals, sounds, the tray menu and the context bar (about scenes 1–12). Later: the Dispatcher, the Inspector, walking the CEO, compaction, messages.
- **Where it works:** native Windows Claude Code (terminal, the Desktop app's Code tab, VS Code). WSL and WSL2 sessions are not supported.
- **Chinese:** Traditional Chinese is required from the first version. Bundle the Cubic 11 font (OFL). Pick the language from the Windows locale by explicit rule (`zh_TW`, `zh_HK`, `zh_MO` and any `zh_Hant` → Traditional Chinese; every other `zh`, including `zh_CN`, → English), not by Godot's own nearest-locale match, which could show Traditional Chinese for Simplified.
- **Tray only:** a tray icon, no taskbar button; closing the office window hides it, as on the Mac.
- **Tray only, with native code:** Godot cannot hide its main window or its taskbar button, so the small native add-on TownWindow (`app/windows/native/`, C++, built with Visual Studio Build Tools 2026) does it. Works, checked 2026-11-11 (`docs/windows/verification.md`).
- **Signing: free only.** Start unsigned (SmartScreen shows "Windows protected your PC" → More info → Run anyway; the release notes say so). Deal with signing later; whatever is chosen must be free (for example the SignPath Foundation, which signs open-source projects for free).
- **Installer:** an Inno Setup `.exe` on GitHub Releases; a `winget` package later.
- **Release tooling (2026-11-13):** `app/windows/scripts/release.ps1` builds the installer (tests, Godot export, Inno Setup) and with `-Publish` publishes `windows-v<version>`; see `docs/windows/releasing.md`. Inno Setup 6.7.3 is installed for the user (winget, approved). `windows-v1.0.0` was published 2026-11-13 (the first Windows version is 1.0.0, by the user's choice). 1.0.1 (published) lets the installer run on Windows 10 (untested). 1.0.2: Setup stops a running agent-town itself instead of asking Windows' Restart Manager, which can't close an app that hides in the tray (Setup said it could not close it); the user tries it and publishes.
- **Releases in the same repo:** Windows tags are `windows-v<version>` (for example `windows-v1.0.0`), titled "agent-town for Windows <version>", and published with `--latest=false`, so the macOS `v<version>` release stays GitHub's "Latest" and the Homebrew cask is untouched. macOS releases are titled "agent-town for macOS <version>" (from 1.0.9, 2026-11-13), so the two are told apart.

### Mac session: keep the cask clear of Windows releases

- [x] `Casks/agent-town.rb` uses `livecheck` with `strategy :github_releases`, which reads release tags. Add `regex(/^v(\d+(?:\.\d+)+)$/i)` to its `livecheck` block so a `windows-v…` tag is never taken for a macOS version. `release.sh` already passes `--latest` for macOS releases; keep it. Done (2026-11-12).

### town-link: make it work on Windows (done in 1.0.2, 2026-11-11; still to try on a Windows machine)

- [x] **Endpoint path** (`plugin/hooks/register.ts:273–274`). It is built only for macOS from `HOME`, which is often unset on Windows. On Windows read `%APPDATA%\agent-town-claude-code\endpoint.json`, the path `docs/protocol.md` already names. Find in the installed `claude-code.d.ts` how a mod learns the OS (or fall back to `APPDATA` being set with no `HOME`), and keep the macOS path unchanged. Done: `endpointFilePath` in `core.ts` uses `%APPDATA%\agent-town-claude-code\endpoint.json` when `APPDATA` is set (a mod can't ask for the OS; macOS never sets it). `/town` now also looks for the app itself, so early in a session it no longer says the app is not running.
- [x] **Privacy bug: the project name on Windows** (`plugin/hooks/core.ts:167,171`, `projectIdentity`). The name is cut with `split('/')`, so a Windows root such as `C:\Users\me\code\agent-town` with no remote is sent whole as `projectName`. `docs/architecture.md` promises the full path is never sent. Split on both `/` and `\`, and strip a trailing `\` as well as `/`.
- [x] **One block per project on Windows.** Before hashing a Windows root into `projectId`, normalize it (backslashes to `/`, lowercase drive letter), so `C:\x` and `c:/x` from different surfaces land in the same block.
- [x] **Desk-worker roles from Windows paths** (`core.ts:72`, `fileRole`). The `Dockerfile` and `.github/workflows/` checks fail on backslash paths. Normalize the separators first. Extensions already work.
- [x] **Tests**: add Windows-path cases for `projectIdentity` and `fileRole` to `plugin/tests/core.test.ts` (no remote, trailing separator, drive-letter case, a workflow file, a Dockerfile).
- [x] **Windows commands in the background-role rules** (`catalog/roles.json`): build words `dotnet build`, `msbuild`; test words `dotnet test`; install words `winget install`, `choco install`, `Invoke-WebRequest`. Then run `tools/build-plugin-catalog.py` (and `--check`).
- [x] **Docs**: in `docs/protocol.md`, say how the endpoint file is protected on Windows, where mode 0600 does not apply (the file sits in the user's own `%APPDATA%`, which only that user can read by default). In `docs/architecture.md`, note that paths are normalized before hashing and naming.
- [x] Raise the version (1.0.2), run the plugin checks, commit and push. The user releases.

### Windows app: new settings from the Mac (2026-11-12)

Built in the macOS app 1.0.5; the Windows app should do the same. `docs/spec.md` → The office ("Hide idle project blocks") and → Settings has the details.

- [x] **Hide idle project blocks** (Windows app, 2026-11-12; `--hide-idle N` checks it with a demo): a switch in Settings → Office, off by default. With it on, a project block shows only while it has work (a ticket, a compaction, staff still working, operators, approvals) and hides once everything in it has settled (no work, no calls, nobody walking except bench idle life) for N seconds, set beside the switch (1 to 3600, default 5). The window shrinks and grows with it. A block that opens with no work starts hidden. While hidden, the block keeps its state and its characters still move, but they arrive at once (no animation); the Mac does this in `move()` with `onScreen`. No block hides while the user has walked the CEO away from the desk. Turning the switch off brings every hidden block back. Mac code: `app/macos/Sources/AgentTown/TownScene+Blocks.swift` (`settled`, `startIdleWatch`, `show`, `hide`).
- [x] **Show tips moves from the tray menu to Settings → Office**, as a switch (on by default; closing a tip still turns it off).
- [x] Strings, in the shared `Localizable.strings` (synced to `app/windows/shared/`): "Office" (辦公室), "Hide idle project blocks" (隱藏閒置的專案區塊), "Hide after" (閒置多久後隱藏), "seconds" (秒), and the existing "Show tips" (顯示提示).
- [x] **Context bars of hidden blocks stay on screen** (Windows app done 2026-11-13; macOS app 1.0.6, placement fixed in 1.0.7 and confirmed by the user 2026-11-12; `docs/windows/roadmap.md`): with the switch on, each session in a hidden block keeps its context bar, labeled "<project> · Context …" (with "Desk N" when the project has several sessions). The bars are always listed under the executive office, in the order the projects opened, even while other project blocks are shown; the project blocks move down to make room (the Mac adds `Layout.execExtra(rows:)` to the gap under the executive block), so the office and the window grow. This lets the user see idle sessions. Mac code: `meterItems()`, `relayout()` and `updateOfficeSize()` in `app/macos/Sources/AgentTown/TownScene.swift`; `docs/spec.md` → The office.

### Windows app: update notices (2026-11-12; Windows app done 2026-11-13)

Built in the macOS app 1.0.8; `docs/spec.md` → Updates has the details. The Windows app should do the same:

- [x] Settings → Updates: **Check for updates automatically** (on by default), **Check now**, and when the last check ran. Check shortly after launch and once a day.
- [x] The app's newest version: list `https://api.github.com/repos/samsonchen/agent-town-claude-code/releases`, skip drafts and pre-releases, and take the highest version among tags `windows-v<version>`. Do not use GitHub's "Latest": it stays on the macOS release.
- [x] town-link's newest version: `version` in `https://raw.githubusercontent.com/samsonchen/agent-town-claude-code/main/plugin/.claude-plugin/plugin.json`. Each session's own version is `pluginVersion` in `session.open` (town-link 1.0.3 or later); a session without it runs 1.0.2 or older.
- [x] Compare versions number by number. Show a red dot on the tray icon and a line at the top of the tray menu ("agent-town X is available…", "town-link X is available…") while there is an update, and an Updates window (no Windows notifications: the user does not want system notifications on either platform): for the app, the release notes and a Download button for the installer (running it replaces the installed app); for town-link, the sessions with an older one, the two `claude plugin` commands with Copy buttons, and "Then restart those Claude Code sessions".
- [x] Strings: the macOS app 1.0.8 added them to the shared `Localizable.strings` under `/* Updates */` (already synced to `app/windows/shared/`).
- [x] Details from the Mac, to match:
  - **The red dot:** the dot is red, about half the icon's height, in the top-right corner, with a thin transparent ring cut around it so it stands apart from the building. Without an update the icon is the normal one.
  - **The session list** is grouped by project and version, one line each: "agent-town: 1.0.2 or older (2 sessions)". A session's line goes when it closes; the town-link notice goes when no open session is older.
  - **A failed check** (no network, GitHub's rate limit of 60 requests an hour without login, a 20-second timeout) changes nothing shown, says "The last check failed. It will try again later." next to Check now, and is tried again at the next check. Only an answered check updates "Last checked".
  - **Dev flags** on the Mac, worth copying: `--updates` opens the Updates window, `--fake-update` makes up a newer app and town-link (99.0.0) without the network, `--check-now` makes a real check even in a demo (a demo makes no automatic check).
  - **Mac code:** `app/macos/Sources/TownCore/Updates.swift` (version comparison, picking the release by tag prefix, reading plugin.json; tests in `Tests/TownCoreTests/UpdatesTests.swift`), `app/macos/Sources/AgentTown/Updates.swift` (`Updater`: the daily check, the session list, `MenuIcon`, `UpdatesView`), and `TownStore.pluginVersions` (each open session's version from `session.open`).

### Windows app: Check now opens the Updates window (2026-11-13; macOS app 1.0.12, Windows app 1.0.4)

`docs/spec.md` → Updates has the details. The Windows app should do the same:

- [x] In Settings → Updates, when the user presses **Check now** and the check finds an update (an app update or a town-link update, the same test as the tray dot and menu line), open the Updates window and bring it to the front. If there is no update, do nothing more than now (no window, no message). A failed check also opens nothing.
- [x] Only the Settings button does this. **Check now** inside the Updates window stays as it is (that window is already open), and the automatic checks (after launch, once a day) still only show the red dot and the menu line.
- [x] Add it to `docs/windows/roadmap.md`, and check with `--fake-update` plus a real `--check-now` where it can be tried. Done: `UpdateCheckRow.new(updater, labels, true)` in Settings awaits the check, then `Updater.show_window()` (signal `window_requested`; main.gd opens or raises the window). Tested with a stand-in updater in `tests/check_row_tests.gd` (54 tests pass). A demo can't show the update case (fixtures carry no town-link version, and 1.0.3 is newer than the released 1.0.2), so the user tries it with `run-local.ps1 -Live -Settings` while a session runs town-link 1.0.4 (`main` has 1.0.5).
- Mac code: `CheckRow(opensUpdatesWindow:)` in `app/macos/Sources/AgentTown/Updates.swift` (it calls `Updater.showWindow()` after `check()` when `hasUpdate`); Settings passes `true` in `Preferences.swift`.

### Windows app: hide the window when no session is open, and the Hide after indent (2026-11-14; macOS app 1.0.14)

`docs/spec.md` → Settings (app) and → Menu bar have the details. The Windows app should do the same:

- [ ] A new switch in Settings → Office, off by default, between Compact view and Hide idle project blocks: **Hide the window when no Claude Code session is open** (沒有開著的 Claude Code session 時隱藏視窗; already in the shared `Localizable.strings`). It is independent of Hide idle project blocks.
- [ ] With it on, the whole office window hides 5 seconds after the last session closes (no Chief of Staff in any block, after a `session.close` or a stale session expiring), and comes back without taking the focus when a session opens. A session that opens within the 5 seconds cancels the hide, so a `/clear` does not make the window blink. Hide it the way the tray's Show agent-town does not: the "show the window" setting stays on, and the app keeps the window to show again. Sound still plays while it is hidden. At launch with no session, the window shows, then hides 5 seconds later. Turning the switch off brings a hidden window back.
- [ ] Show agent-town in the tray menu is unchecked while the window is hidden this way; choosing it shows the office anyway (it hides again only after the next session closes). When the user has turned Show agent-town off, a session opening does not bring the window back.
- [ ] Indent **Hide after** under Hide idle project blocks (the Mac pads its label 20 points), since it belongs to it; it stays dimmed while Hide idle project blocks is off.
- [ ] Add it to `docs/windows/roadmap.md` and `CHANGELOG/CHANGELOG_WINDOWS.md`, and check it with demo fixture 01 (one session that opens and closes); the Mac was checked with fixture 01 played twice at `--speed 0.25`, so the window hides between the two sessions and comes back.
- Mac code: `WindowPresence` in `app/macos/Sources/AgentTown/WindowPresence.swift` (watches whether any block has a Chief, hides with `orderOut`, shows with `orderFrontRegardless`), the menu toggle in `TownMenu` and the Settings rows in `SettingsView` (`Preferences.swift`), and `Prefs.hideWithoutSessions` (`hideWithoutSessions`; a demo can turn it on with `-hideWithoutSessions YES`).

### Windows app: break time on the bench, the straight sofa, and retrying the launch update check (2026-11-14; macOS app 1.0.14)

`docs/spec.md` → Resource bench → "Break time", and → Updates, have the details. The Windows app should do the same:

- [ ] **Break time.** Per project block: once the block has been settled (the same test as Hide idle project blocks: no work, no calls, nobody walking or busy except bench characters) for 180 seconds, twice a second there is a 1-in-10 chance that one more free bench character takes a break, for 10 to 25 seconds, while fewer than all but one are on a break. Standing characters are picked first (three times in four); seated ones only doze. Pastimes, picked at random: juggle (three balls, radius 0.045 m, red, yellow and blue, on a loop in front of the chest, a third of a turn apart), cube (a 0.11 m cube with six colored faces in both hands, a quarter turn about a random axis every 0.7 s; the only one with the arms-out holding pose), toss (a white ball, radius 0.05 m, up to 0.5 m above the hand and back), phone (an upright dark phone, 0.07 × 0.12 m, with a light blue screen toward the face, held in front of the face), chat (with the nearest other free standing character: both turn to each other and take turns showing the "• • •" speech bubble every 1.6 s), doze (a bubble cycling "z", "zZ", "zZZ" every 0.8 s, in the speech-bubble style). All but the cube keep the standing pose, arms down: the arms-out holding poses with a dark thing in the hands read as aiming (the user saw this). As soon as a block is not settled, every break there ends at once: props removed, bubbles cleared, the character turns back to its bench facing and settles; the 180 seconds start over. A break runs in the character's action queue, so a call from the bench waits for it; it must end within a frame when stopped.
- [ ] Dev flags as on the Mac: `--break-idle N` (or the Godot equivalent) for the idle seconds, and one to force a single pastime for standing characters; and `run-local.ps1 -Breaks` (10 seconds) and `-Pastime NAME`, matching `run-local.sh --breaks` / `--pastime NAME`.
- [ ] **The bench sofa.** Use `loungeSofa` (the straight one) at normal scale instead of `loungeSofaLong`, move the two seats to x 5.2 and 5.6 at z 3.72, and lift a seated character 0.1 m (`Layout.benchSeatLift`) when it sits down on the bench (walking puts it back on the floor). Unlifted, the sit pose put the body inside the seat, with only the head, hands and knees showing (the user saw this). The long sofa is L-shaped: its corner piece covered the right-hand sitter, and the seats at 5.0 and 5.8 were on its arms (the user saw this on the Mac). Windows: `town_scene.gd` (`place("loungeSofaLong", …)`) and `layout.gd` (bench spots).
- [ ] **Launch update check.** The Windows app already checks 10 seconds after launch; add the retries: if that check fails, try again after 1, 2, 5 and 10 minutes (stop once one succeeds or Check for updates automatically is off).
- [ ] Add these to `docs/windows/roadmap.md` and `CHANGELOG/CHANGELOG_WINDOWS.md`.
- Mac code: `app/macos/Sources/AgentTown/TownScene+Breaks.swift` (`startBreaks`, `startBreak`, `takeBreak`, `chat`), `Actor.onBreak`, `breakEnds`, `idleBubble` (`Actors.swift`, drawn in `labelItems()` in `TownScene.swift`), `settled` in `TownScene+Blocks.swift`, the sofa in `TownScene.swift` and `Layout.benchSpots`; the retries in `Updater.start` (`Updates.swift`).

### Windows app: a script to try a build before releasing (2026-11-12; Windows done 2026-11-13: `-Live` tried only by its process matching, since no app was running)

The Mac has `app/macos/scripts/run-local.sh` (added 2026-11-12; read it for the behavior to match). The Windows app should have the same, so the user can try a change from the checkout without making the installer:

- [x] `app/windows/scripts/run-local.ps1` (PowerShell), plus a `run-local.sh` that runs it from Git Bash, as `native/build.sh` does for `build.ps1`. Usage text at the top, shown by `-Help`.
- [x] Finds Godot 4.7.2 from `GODOT`, else `godot` on `PATH`, else fails with a message saying how to set `GODOT`. Never a path with a user name written into the script. Runs `--path app/windows` with the options after `--`, so the app reads them from `OS.get_cmdline_user_args()`.
- [x] Default, with no options: the demo `protocol/fixtures/05-two-projects-messages.json`, the office window shown, no sounds. A demo starts no server, so an installed agent-town keeps working beside it.
- [x] Options, any number, in any order, matching the Mac's:
  - `-Demo 01`…`05`, or a path to a fixture; a fixture that isn't there fails with a message.
  - `-Live`: real Claude Code sessions instead of a demo (see below).
  - `-FakeUpdate`, `-CheckNow`, `-Updates`: the update notices' dev flags (`todo.md` → "Windows app: update notices"); add them to the app with that feature.
  - `-Settings`: open the Settings window (the app's `--open settings`).
  - `-Sound`: play the demo's sounds.
  - `-Zh`, `-En`: the language (the app's `--language zh-Hant` or `en`).
  - `-Speed N`: play the demo N times as fast.
  - Anything after `--` goes to the app as is.
- [x] `-Live`: the installed agent-town and this run would both write `%APPDATA%\agent-town-claude-code\endpoint.json`. If the installed app is running, quit it first and start it again when this run ends, also after Ctrl+C. Until the installer exists there is nothing to quit; then use the path the installer writes.
- [x] The run keeps its own settings, apart from the installed app's, as on the Mac. If the Godot project and the exported app share `user://`, give the run a separate settings file (for example through a flag the script passes).
- [x] Docs: the usage in `docs/windows/README.md` (or wherever the Windows dev steps are), and a line in `CLAUDE.md` next to the Mac's, so a session points the user to it for testing.

### Windows app: compact view, small windows and auto-scroll (2026-11-12; Windows app done 2026-11-13)

Built in the macOS app 1.0.8; `docs/spec.md` → The office has the details. The Windows app should do the same:

- [x] **Compact view:** a switch in Settings → Office, off by default, above Hide idle project blocks. It applies after a restart, with a note and a "Restart now" button while the choice differs from the running view (as Language does). It draws the office at half scale (the Mac: 55 pixels per meter, at least 35, instead of 110 and 70) and the overlay text at 75% (tags, signs, statements, context bars, with their padding). The layout in meters is unchanged. The space a context bar row takes under the executive office (`Layout.meterRowDepth` on the Mac) grows by 1.5 (75% text on half scale). Compact view keeps its own saved window size; the first time, half the normal window's height, wide enough for the office at the compact scale. Mac code: `ViewScale` in `Layout.swift`, `TownView.pixelsPerMeter`, `Tag.font`, `MeterOverlay`, `WindowPlace`.
- [x] **Small windows:** the minimum is 320 × 240 (was 640 × 480 on the Mac). When a block is added or removed, a window the user made shorter than the office keeps its height instead of growing to fit. Mac code: `TownView.fitWindow(before:)`.
- [x] **Auto-scroll:** whenever the office is bigger than the window, about 30 times a second, ease the view toward the window-sized area (80% of it) with the most walking characters: a character walks if its position inside its block changed since the last look, and counts for 0.6 s after stopping. Keep the view where it is when it already holds as many walkers as any other area, or when nobody walks. Walking the CEO (the view follows the CEO) and the user's own scrolling each hold auto-scroll off for 10 s. Mac code: `AutoScroll` and `autoScrollStep` in `TownView.swift`, `ViewFocus.bestCenter` in `TownCore/ViewFocus.swift` (tests in `ViewFocusTests.swift`), `TownScene.characterSpots()`.
- [x] **Tags out of view:** a tag whose character is more than 20 px above the window's top is not drawn; one just above still slides down to stay in view.
- [x] Strings: "Compact view" (精簡檢視) and "Restart agent-town to change the view." (重新啟動 agent-town 以切換檢視。), already in the shared `Localizable.strings` and synced.
- [x] `run-local` options to match the Mac's: `-Compact` and `-Resize WxH` (8 seconds in, shrink the window as a drag would).

### The repository and the data folder: `agent-town-claude-code` (2026-11-13)

The repository is `samsonchen/agent-town-claude-code` (the product name is Agent-Town; the suffix tells it apart from other projects named agent-town). The Homebrew tap has the same name (`brew tap samsonchen/agent-town-claude-code https://github.com/samsonchen/agent-town-claude-code`, cask `agent-town`); the plugin marketplace is `agent-town-claude-code` too (`town-link@agent-town-claude-code`). Everything the apps keep on disk is in a folder of the same name: macOS `~/Library/Application Support/agent-town-claude-code/` (the endpoint; settings are kept by the bundle ID), Windows `%APPDATA%\agent-town-claude-code\` (the endpoint, settings and the rest). town-link reads the endpoint only there (`docs/protocol.md` → Endpoint file).

**The Mac session:**

- [x] The repository's address everywhere outside `app/windows/` and `docs/windows/`: READMEs, docs, the cask (`url`, `homepage`, `zap`), `AppInfo.repository`, the update check (`UpdateFeed`) and the brew command in the Updates window, `plugin.json`'s `homepage`, the schema's `$id`.
- [x] The marketplace name `agent-town-claude-code` (`.claude-plugin/marketplace.json`), checked with `claude plugin validate` and an install in a throwaway config: install commands in the READMEs, docs, the cask's note and the Updates window.
- [x] The endpoint folder: town-link's `endpointFilePath` (macOS and Windows) with its tests, the macOS app's `Endpoint.defaultURL`, `tools/debug-receiver.py`, `dev/recorder`, `docs/protocol.md`. town-link 1.0.4, macOS app 1.0.10.

**The Windows session** (`git pull` first):

- [x] `app/windows/core/update_feed.gd`: `RELEASES_URL` → `https://api.github.com/repos/samsonchen/agent-town-claude-code/releases?per_page=50`, `PLUGIN_MANIFEST_URL` → `https://raw.githubusercontent.com/samsonchen/agent-town-claude-code/main/plugin/.claude-plugin/plugin.json`.
- [x] `app/windows/shell/updater.gd`: `PLUGIN_COMMANDS` → `claude plugin marketplace update agent-town-claude-code` and `claude plugin update town-link@agent-town-claude-code` (the marketplace has the repository's name).
- [x] `app/windows/shell/about_window.gd`: `REPOSITORY` → `https://github.com/samsonchen/agent-town-claude-code`.
- [x] `app/windows/installer/agent-town.iss`: `AppPublisherURL`, `AppSupportURL` (`…/issues`) and `AppUpdatesURL` (`…/releases`) on `https://github.com/samsonchen/agent-town-claude-code`; its uninstall entries under `{userappdata}\agent-town-claude-code`. Keep the `AppId`.
- [x] `app/windows/scripts/release.ps1`: `--repo samsonchen/agent-town-claude-code`.
- [x] The app's data under `%APPDATA%\agent-town-claude-code\`: `endpoint.json` (where town-link looks), `settings.cfg`, run-local's separate settings, logs and anything else (check Godot's `user://` too). Settings start from scratch.
- [x] Beyond the list, so everything the Windows app keeps uses one name (the user's choice): Godot's `user://` is the same folder (`application/config/custom_user_dir_name`), the install folder is `%LOCALAPPDATA%\Programs\agent-town-claude-code` (`UsePreviousAppDir=no`), and the Open at login value is `agent-town-claude-code`. The 1.0.3 installer also cleans up the folders and the Run value earlier test builds used. The product name (agent-town, `agent-town.exe`) stays, as on the Mac.
- [x] `docs/windows/` to match. Raise the Windows app's version, run the Windows tests, try a demo and `-Live` with `run-local.ps1` against town-link from `main`, commit and push. Tick these boxes. Done (2026-11-13): Windows app 1.0.3, 52 tests pass; a demo, and `-Live` with town-link 1.0.4 from `main` (the endpoint at the new path, a `claude -p` session drawn as the block "agent-town-claude-code").

**The user:** release the macOS app (1.0.10) and the Windows app once both sessions have pushed, then install them fresh, with town-link from the marketplace (`claude plugin marketplace add samsonchen/agent-town-claude-code`, then `claude plugin install town-link@agent-town-claude-code`).

### Windows app: code signing through the SignPath Foundation (2026-11-13)

The project's web page is live for the application: https://samsonchen.github.io/agent-town-claude-code/ (source in `site/`, published by `.github/workflows/pages.yml`), with a privacy policy (`privacy.html`) and the code signing policy (`code-signing-policy.html`: the SignPath attribution, team roles, the privacy statement). The SignPath Foundation's terms (https://signpath.org/terms) also ask for:

- [x] The user: apply at https://signpath.org/apply. Declined on 2026-11-13: the Foundation wants public adoption first (stars, forks, contributors, outside articles or discussions). It can apply again once the project has those; the rest of this list is for that.
- [ ] The privacy notice shown at install: the Windows installer (`agent-town.iss`) shows a short page saying the app checks GitHub once a day for updates (Settings → Updates turns it off) and that nothing else leaves the computer, linking to the privacy policy.
- [ ] Builds that SignPath can trace to the source: build the installer in GitHub Actions from a tagged commit (SignPath's origin verification records the repository, commit and build job), and send it to SignPath for signing from there, with manual approval. `release.ps1` builds locally today.
- [ ] The product name and version in each binary's metadata match the project (agent-town, the release's version).
- [ ] Once approved: the README's and the web page's "not code-signed yet" notes change to say releases are signed.

### Windows app: the Microsoft Store (2026-11-13)

The free way to a signed Windows app for now: the Store signs MSIX packages, so there is no SmartScreen warning and Smart App Control lets it run. See `docs/windows/store.md`.

- [x] The user: an individual Partner Center account, and the product "Agent-Town for Claude Code" reserved (Store ID `9N0G35LW0LNK`; identity in `store.md`).
- [x] The package: `release.ps1 -Store` (preset "Windows x64 Store" with the feature `store`, manifest `app/windows/installer/msix/AppxManifest.xml`, `makeappx`). Tried with Developer Mode: the endpoint file lands in the real `%APPDATA%gent-town-claude-code` (with and without the folder already there), and a `claude -p` session reached the app.
- [x] A Store copy: no check for a newer app (the Store updates it; town-link is still checked), Open at login through the package's startup task (Windows Settings → Apps → Startup), and it never writes the `Run` key.
- [ ] The user: look at a Store copy's Settings (the "Open at login…" button) and Updates window, then submit in Partner Center as `store.md` says (listing, screenshots, age rating, certification notes).
- [ ] Once it is live: the README's and the web page's Windows install sections point to the Store first, with the installer as the other way.

### Shared material a second app needs

- [x] **Expected state for each fixture.** Done (2026-11-11): `protocol/fixtures/expected/`, one file per fixture with the state after each event that changes it; format in its README; checked by `ExpectedStateTests.swift`. The Windows app runs the same fixtures against the same answers.
- [x] **Sound files: decided (2026-11-11), the two apps sound different.** The macOS app keeps the macOS system sounds (`NSSound`: Glass for completion, Ping for approval, Pop for dispatch). The Windows app picks its own sounds; they do not need to match the Mac. Whoever builds the Windows app chooses the files, checks their licenses (CC0 or similar), and lists them in `assets/LICENSES.md`. The three moments that play a sound are the same on both: work done, approval needed, ticket dispatched (see `docs/spec.md`). Synthesized candidates were tried on the Mac and rejected by the user, so start fresh.
  - **Windows picks (2026-11-11):** the Windows system sounds in `C:\Windows\Media`, played from there at run time and never copied into the repo or the installer (they are Microsoft's, not ours to redistribute; this is also why `assets/LICENSES.md` needs no entry). Completion: `Windows Notify System Generic.wav`. Approval: `Windows Notify Messaging.wav`. Dispatch: `Windows Ringout.wav`, an outgoing ring (changed 2026-11-11 from `Windows Navigation Start.wav`, a click too faint to hear). Changed again 2026-11-13 by the user's choice: completion `Windows Notify.wav`, approval `Windows Exclamation.wav`, dispatch `Speech Disambiguation.wav`. If a file is missing, play nothing. Godot 4.4 or later loads a WAV from a path at run time (`AudioStreamWAV.LoadFromFile`), so the volume and mute settings still apply. Change the picks if they don't sound right; no Kenney interface sounds.
- [x] **UI strings: decided (2026-11-11).** The `.strings` files in `app/macos/Sources/AgentTown/Resources/Localization/` stay the only source; the Windows app parses them itself. No change on the Mac side.

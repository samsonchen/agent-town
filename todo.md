# agent-town: to do

Open items as of 2026-11-11, for the next session to pick up. Everything listed as done is on `main`.

## Where things stand

- Work is committed on `main`.
- Version 1.0.2 for both the plugin and the macOS app; they now move separately. town-link is installed from GitHub on the personal account; the app is installed with Homebrew from this repo's tap (`Casks/agent-town.rb`). v0.2.7 was the first signed and notarized release.
- Versions are separate (since 2026-11-11, both at 1.0.2 then). A plugin change: raise `plugin/.claude-plugin/plugin.json`, commit and push; no release. An app change: raise `AppInfo.fallbackVersion` in `app/macos/Sources/AgentTown/About.swift`, commit and push, then the user runs `app/macos/scripts/release.sh --publish` (auto mode refuses to publish a release): it publishes the release, checks the uploaded `.dmg`'s checksum, and commits and pushes the cask. Users update with `brew upgrade --cask agent-town` and `claude plugin update town-link@agent-town`.
- Plugin checks: `claude plugin validate plugin` and `claude plugin test plugin` (52 tests). App checks: `swift build` and `swift test` in `app/macos` (28 tests).
- Two Swift warnings in the release build, harmless: `TownScene+Staff.swift:89` (a weak self inside a strong one) and `TownView.swift:489` (a non-Sendable observer closure). Clean up when convenient.

## 1. Check on a personal (non-Team) account

On the Care Active Team account, Claude Code manages the organization's settings. In that case, every `classic.*` hook and `session.compact` skip plugins the user installed. `/plugin` → Errors lists them. The built-in guard `cc-plugin-sec-default` loads only with managed settings or a Team or Enterprise login, so a personal account should get every event.

Check these on the personal account:

- [x] `/plugin` → Errors shows nothing for town-link (checked 2026-11-11 on the personal account).
- [ ] Automatic compaction shows the notes scene (`session.compact` with trigger `auto`). Low priority: the user is not worried about it; check it if it comes up.
- [x] The Inspector's "Returned" scene works on the personal account (checked 2026-11-11 with a test Stop hook). `classic.Stop` runs there; town-link read the hook's reason from the wrong field, fixed in 0.2.3 (the reason is `block`'s text).
- [x] The permission mode follows Shift+Tab (checked 2026-11-11): in manual mode a slow approval shows the wait and plays the sound; in auto mode the classifier's quick answers show nothing. A classifier answer slower than 5 seconds can't be forced, so that case is untested.
- [x] The README's known issues say these happen only where an organization manages Claude Code, and `docs/verification.md` item 15 names that cause.

## 2. Waiting on others

- [x] **Developer ID Application certificate** (done 2026-11-11). The user's role can't create it. The Account Holder (the product manager) must accept the latest Program License Agreement and issue the certificate. `docs/releasing.md` has the steps, including the request-file route under "If you are not the Account Holder". Parts B and C (app-specific password, `notarytool store-credentials agent-town-notary`) don't need the certificate.
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
- [ ] Settings for window size and bench size.
- [ ] Zoom, for many project blocks. Blocks are now one column, the window grows up to the screen height, and a taller office scrolls.
- [ ] Phase 3 leftovers: props in hand, more idle life on the bench, workflow subagents reporting to the coordinator, and name tags that move apart when characters stand close together.
- [ ] **Sound settings (specified 2026-11-11, `docs/spec.md` → Sounds → Sound settings):** in Settings, a volume slider for agent-town's own sounds; for dispatch, completion and approval an on/off switch, a list of the sounds in `/System/Library/Sounds` (the default first: Glass, Ping, Pop) plus Choose a file…, and a Play button; the completion threshold (0–3600 s, default 0) in the completion row. The menu's Sound item still mutes all three; a sound that cannot be played falls back to its default. The Windows app builds the same (`docs/windows/roadmap.md`).
- [ ] Phase 5: hats, model badges with a show or hide setting, the Cubic 11 font, the ticket text setting. Launch at login is done (Settings → Open at login); check it in the packaged app.

## 6. To check by hand

- [ ] Click through every menu bar item in the packaged app: About, Show agent-town, Sound, Show tips, Settings…, Quit. The About window was checked only as a rendered image.
- [ ] Office blocks: a second project's block appears before its first prompt, stacks under the first one, and the window grows. It goes when that project's last session ends.
- [ ] The window opens where it was after a restart, on the same display.

## 7. Known limits of the dev tools

- The offscreen `--snapshot` sometimes draws only the 2D labels and no 3D scene, in release builds and lately in debug builds too. The live window is fine. To check a scene, run the demo in a window: `AgentTown --demo <fixture> -showWindow YES`, then `screencapture -l <window id>`.
- The plugin test kit's clock doesn't move `Date.now()`, so the outbox timer (approval waits) can't be tested through `register.ts`. Test it in `tests/core.test.ts` instead.

## 8. Decisions still open

- [ ] Bundle ID: it is `ai.careactive.agenttown`. Changing it makes macOS treat the app as new, so saved settings reset.
- [ ] Open questions in `docs/roadmap.md`: the default for ticket text, whether `claude -p` runs appear, sound files, bench size, where scheduled reports go, and long-lived operators.

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
- **Releases in the same repo:** Windows tags are `windows-v<version>` (for example `windows-v0.1.0`), titled "agent-town for Windows <version>", and published with `--latest=false`, so the macOS `v<version>` release stays GitHub's "Latest" and the Homebrew cask is untouched.

### Mac session: keep the cask clear of Windows releases

- [ ] `Casks/agent-town.rb` uses `livecheck` with `strategy :github_releases`, which reads release tags. Add `regex(/^v(\d+(?:\.\d+)+)$/i)` to its `livecheck` block so a `windows-v…` tag is never taken for a macOS version. `release.sh` already passes `--latest` for macOS releases; keep it.

### town-link: make it work on Windows (done in 1.0.2, 2026-11-11; still to try on a Windows machine)

- [x] **Endpoint path** (`plugin/hooks/register.ts:273–274`). It is built only for macOS from `HOME`, which is often unset on Windows. On Windows read `%APPDATA%\agent-town\endpoint.json`, the path `docs/protocol.md` already names. Find in the installed `claude-code.d.ts` how a mod learns the OS (or fall back to `APPDATA` being set with no `HOME`), and keep the macOS path unchanged. Done: `endpointFilePath` in `core.ts` uses `%APPDATA%\agent-town\endpoint.json` when `APPDATA` is set (a mod can't ask for the OS; macOS never sets it). `/town` now also looks for the app itself, so early in a session it no longer says the app is not running.
- [x] **Privacy bug: the project name on Windows** (`plugin/hooks/core.ts:167,171`, `projectIdentity`). The name is cut with `split('/')`, so a Windows root such as `C:\Users\me\code\agent-town` with no remote is sent whole as `projectName`. `docs/architecture.md` promises the full path is never sent. Split on both `/` and `\`, and strip a trailing `\` as well as `/`.
- [x] **One block per project on Windows.** Before hashing a Windows root into `projectId`, normalize it (backslashes to `/`, lowercase drive letter), so `C:\x` and `c:/x` from different surfaces land in the same block.
- [x] **Desk-worker roles from Windows paths** (`core.ts:72`, `fileRole`). The `Dockerfile` and `.github/workflows/` checks fail on backslash paths. Normalize the separators first. Extensions already work.
- [x] **Tests**: add Windows-path cases for `projectIdentity` and `fileRole` to `plugin/tests/core.test.ts` (no remote, trailing separator, drive-letter case, a workflow file, a Dockerfile).
- [x] **Windows commands in the background-role rules** (`catalog/roles.json`): build words `dotnet build`, `msbuild`; test words `dotnet test`; install words `winget install`, `choco install`, `Invoke-WebRequest`. Then run `tools/build-plugin-catalog.py` (and `--check`).
- [x] **Docs**: in `docs/protocol.md`, say how the endpoint file is protected on Windows, where mode 0600 does not apply (the file sits in the user's own `%APPDATA%`, which only that user can read by default). In `docs/architecture.md`, note that paths are normalized before hashing and naming.
- [x] Raise the version (1.0.2), run the plugin checks, commit and push. The user releases.

### Shared material a second app needs

- [x] **Expected state for each fixture.** Done (2026-11-11): `protocol/fixtures/expected/`, one file per fixture with the state after each event that changes it; format in its README; checked by `ExpectedStateTests.swift`. The Windows app runs the same fixtures against the same answers.
- [x] **Sound files: decided (2026-11-11), the two apps sound different.** The macOS app keeps the macOS system sounds (`NSSound`: Glass for completion, Ping for approval, Pop for dispatch). The Windows app picks its own sounds; they do not need to match the Mac. Whoever builds the Windows app chooses the files, checks their licenses (CC0 or similar), and lists them in `assets/LICENSES.md`. The three moments that play a sound are the same on both: work done, approval needed, ticket dispatched (see `docs/spec.md`). Synthesized candidates were tried on the Mac and rejected by the user, so start fresh.
  - **Windows picks (2026-11-11):** the Windows system sounds in `C:\Windows\Media`, played from there at run time and never copied into the repo or the installer (they are Microsoft's, not ours to redistribute; this is also why `assets/LICENSES.md` needs no entry). Completion: `Windows Notify System Generic.wav`. Approval: `Windows Notify Messaging.wav`. Dispatch: `Windows Ringout.wav`, an outgoing ring (changed 2026-11-11 from `Windows Navigation Start.wav`, a click too faint to hear). If a file is missing, play nothing. Godot 4.4 or later loads a WAV from a path at run time (`AudioStreamWAV.LoadFromFile`), so the volume and mute settings still apply. Change the picks if they don't sound right; no Kenney interface sounds.
- [x] **UI strings: decided (2026-11-11).** The `.strings` files in `app/macos/Sources/AgentTown/Resources/Localization/` stay the only source; the Windows app parses them itself. No change on the Mac side.

# agent-town: to do

Open items as of 2026-11-11, for the next session to pick up. Everything listed as done is on `main`.

## Where things stand

- Work is committed on `main`. The `phase2/app` branch points at an older commit on `main` and can be deleted.
- Version 0.2.6 (plugin and app share it). town-link is installed from GitHub on the personal account; the app is installed with Homebrew from this repo's tap (`Casks/agent-town.rb`), as an unsigned pre-release.
- After a change: raise the version in `plugin/.claude-plugin/plugin.json` and `AppInfo.fallbackVersion` in `app/macos/Sources/AgentTown/About.swift`, commit and push. Then the user runs `app/macos/scripts/release.sh --unsigned --publish` (auto mode refuses to publish a release); check the uploaded `.dmg`'s checksum against the cask, commit and push the cask. Users update with `brew upgrade --cask agent-town` and `claude plugin update town-link@agent-town`.
- Plugin checks: `claude plugin validate plugin` and `claude plugin test plugin` (45 tests). App checks: `swift build` and `swift test` in `app/macos` (23 tests).
- Two Swift warnings in the release build, harmless: `TownScene+Staff.swift:72` (a weak self inside a strong one) and `TownView.swift:479` (a non-Sendable observer closure). Clean up when convenient.

## 1. Check on a personal (non-Team) account

On the Care Active Team account, Claude Code manages the organization's settings. In that case, every `classic.*` hook and `session.compact` skip plugins the user installed. `/plugin` → Errors lists them. The built-in guard `cc-plugin-sec-default` loads only with managed settings or a Team or Enterprise login, so a personal account should get every event.

Check these on the personal account:

- [x] `/plugin` → Errors shows nothing for town-link (checked 2026-11-11 on the personal account).
- [ ] Automatic compaction shows the notes scene (`session.compact` with trigger `auto`). Low priority: the user is not worried about it; check it if it comes up.
- [x] The Inspector's "Returned" scene works on the personal account (checked 2026-11-11 with a test Stop hook). `classic.Stop` runs there; town-link read the hook's reason from the wrong field, fixed in 0.2.3 (the reason is `block`'s text).
- [x] The permission mode follows Shift+Tab (checked 2026-11-11): in manual mode a slow approval shows the wait and plays the sound; in auto mode the classifier's quick answers show nothing. A classifier answer slower than 5 seconds can't be forced, so that case is untested.
- [x] The README's known issues say these happen only where an organization manages Claude Code, and `docs/verification.md` item 15 names that cause.

## 2. Waiting on others

- [ ] **Developer ID Application certificate.** The user's role can't create it. The Account Holder (the product manager) must accept the latest Program License Agreement and issue the certificate. `docs/releasing.md` has the steps, including the request-file route under "If you are not the Account Holder". Parts B and C (app-specific password, `notarytool store-credentials agent-town-notary`) don't need the certificate.
- [x] **App icon** added (2026-11-11): `assets/icons/app-icon-1024.png`; release.sh makes AppIcon.icns from it. The menu bar keeps the system symbol `building.2`, by the user's choice.

## 3. Release

- [ ] The first signed and notarized build: `app/macos/scripts/release.sh`, then the downloaded-app test in `docs/releasing.md` Part E.
- [ ] `release.sh --publish`, which creates a draft GitHub release `v<version>` with the signed `.dmg`; publish it, update the cask, and remove the "not signed yet" caveat from the cask and the README.
- [x] Unsigned pre-releases v0.2.3 to v0.2.6 on GitHub Releases.
- [x] The repo is public (2026-11-11). The history was scanned for secrets first: none found.
- [x] Homebrew cask in `Casks/agent-town.rb` (this repo is the tap).
- [ ] Later: signing and notarization in GitHub Actions, the official Homebrew casks (signed apps only), Sparkle updates (roadmap Phase 6).

## 4. README and docs

- [x] README rewritten in the user's order (what it is, installing, the office, known issues, Claude Desktop and Cowork). Still to do: replace the build-from-source steps with the download once the signed app is on Releases. Was: README "Install (planned)" and "No installer yet": the plugin install from GitHub works now. Update both, and the "Status" section, once the signed app is on Releases.
- [ ] The Traditional Chinese version of the README story ("Why agent-town exists"): the user hasn't decided yet.
- [x] Roadmap updated to match what is built. Was: Roadmap Phase 2 still lists "Settings window" and "An `.app` bundle" as open. The `.app`, the menu bar, the language setting and the About window are done, so update those lines. Threshold, sounds, ticket text, badges and the Cubic 11 font are still open.

## 5. App features still open

From `docs/roadmap.md` and `docs/spec.md`:

- [x] The Dispatcher's board: one card per active schedule (scene 13), `TownScene+Board.swift`.
- [x] Scene 14: the Dispatcher radios a scheduled ticket to the Chief of Staff, and the report goes back to the Dispatcher (checked 2026-11-11 with a one-time CronCreate schedule).
- [x] The Inspector stopping a returned report at reception (scene 15), `TownScene+Inspector.swift`, checked 2026-11-11 with a test Stop hook.
- [ ] Several sessions in one project block: desks and phones, up to four.
- [ ] Settings for window size and bench size.
- [ ] Zoom, for many project blocks. Blocks are now one column, the window grows up to the screen height, and a taller office scrolls.
- [ ] Phase 3 leftovers: props in hand, more idle life on the bench, workflow subagents reporting to the coordinator, and name tags that move apart when characters stand close together.
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

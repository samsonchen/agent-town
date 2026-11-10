# agent-town: to do

Open items as of 2026-11-11, for the next session to pick up. Everything listed as done is on `main`.

## Where things stand

- Work is committed on `main`. The `phase2/app` branch points at an older commit on `main` and can be deleted.
- town-link 0.2.3 is installed from GitHub on the personal account (`claude plugin marketplace add samsonchen/agent-town`, then `claude plugin install town-link@agent-town`). After a plugin change, raise the version in `plugin/.claude-plugin/plugin.json` and `AppInfo.fallbackVersion` in `app/macos/Sources/AgentTown/About.swift`, push, then run `claude plugin marketplace update agent-town` and `claude plugin update town-link@agent-town`, and restart Claude Code.
- The app is built with `app/macos/scripts/release.sh --unsigned` and copied to `/Applications` by hand. It runs from the menu bar.
- Plugin checks: `claude plugin validate plugin` and `claude plugin test plugin` (43 tests). App checks: `swift build` and `swift test` in `app/macos` (23 tests).

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
- [ ] **App icon artwork** from the user: a 1024 px master for the app icon, and a template image for the menu bar (about 18 pt, black on transparent). Until then the app uses the system symbol `building.2`.

## 3. Release

- [ ] The first signed and notarized build: `app/macos/scripts/release.sh`, then the downloaded-app test in `docs/releasing.md` Part E.
- [ ] `release.sh --publish`, which creates a draft GitHub release `v<version>` with the `.dmg`.
- [ ] Before making the repo public: scan the whole git history for secrets.
- [ ] Make the repository public after the first release.
- [ ] Later: signing and notarization in GitHub Actions, a Homebrew cask, Sparkle updates (roadmap Phase 6).

## 4. README and docs

- [ ] README "Install (planned)" and "No installer yet": the plugin install from GitHub works now. Update both, and the "Status" section, once the signed app is on Releases.
- [ ] The Traditional Chinese version of the README story ("Why agent-town exists"): the user hasn't decided yet.
- [ ] Roadmap Phase 2 still lists "Settings window" and "An `.app` bundle" as open. The `.app`, the menu bar, the language setting and the About window are done, so update those lines. Threshold, sounds, ticket text, badges and the Cubic 11 font are still open.

## 5. App features still open

From `docs/roadmap.md` and `docs/spec.md`:

- [x] The Dispatcher's board: one card per active schedule (scene 13), `TownScene+Board.swift`.
- [ ] Scene 14: the Dispatcher radios a scheduled ticket to the Chief of Staff, and the report comes back to the Dispatcher. Check how much of it works already with a real `/loop`.
- [x] The Inspector stopping a returned report at reception (scene 15), `TownScene+Inspector.swift`. Still to check with a real Stop hook (section 1).
- [ ] Several sessions in one project block: desks and phones, up to four.
- [ ] Settings for window size and bench size.
- [ ] Zoom, for many project blocks. Blocks are now one column, the window grows up to the screen height, and a taller office scrolls.
- [ ] Phase 3 leftovers: props in hand, more idle life on the bench, workflow subagents reporting to the coordinator, and name tags that move apart when characters stand close together.
- [ ] Phase 5: hats, model badges with a show or hide setting, the Cubic 11 font, the ticket text setting, launch at login.

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

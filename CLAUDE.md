# agent-town

A macOS menu bar app (Swift, RealityKit) that draws Claude Code's work as a small office, and the Claude Code plugin town-link that sends it events over loopback. The README explains the office; `docs/` has the spec, architecture, protocol and release steps; `docs/windows/` has the planned Windows app (Godot), kept apart from the macOS documents. `todo.md` lists what is open.

## Layout

- `plugin/`: town-link. `hooks/register.ts` wires Claude Code events; `hooks/core.ts` (class `Town`) turns them into protocol events. Tests in `plugin/tests/`.
- `app/macos/`: the app. `Sources/TownCore/Building.swift` reduces protocol events to state; `Sources/AgentTown/TownScene*.swift` draws and animates it. Translations in `Sources/AgentTown/Resources/Localization/`.
- `protocol/`: the JSON schema (`schema/v1.schema.json`), recorded fixtures for demos and tests, and `fixtures/expected/`, the building state each fixture must produce (shared with a future Windows app). After changing how events are applied, regenerate with `UPDATE_EXPECTED=1 swift test --filter fixturesMatchTheirExpectedState` in `app/macos` and review the diff.
- `tools/debug-receiver.py`: a stand-in for the app that prints events; `--forward --log FILE` records a live run while the app keeps drawing it. On Windows it writes `%APPDATA%\agent-town-claude-code\endpoint.json`, so a session can be checked there with no app (`claude -p ... --plugin-dir plugin`).
- `Casks/agent-town.rb`: the Homebrew cask (this repo is the tap).
- `app/windows/`: the Windows app (Godot 4.7, typed GDScript), in progress; see `docs/windows/`. It keeps copies of `catalog/*.json`, the Kenney models and the macOS app's `Localizable.strings` in `app/windows/shared/`: after changing any of those, run `python tools/sync-windows-assets.py` and commit the copies (`--check` reports stale ones).

## Checks

- Plugin: `claude plugin validate plugin` and `claude plugin test plugin`.
- App: `swift build` and `swift test` in `app/macos`.
- Windows app: `godot --headless --path app/windows --script res://tests/run_tests.gd` (Godot 4.7.2: set `GODOT` to its console build unless `godot` is on `PATH`). When the macOS building state changes and `protocol/fixtures/expected/` is regenerated, the Windows port must change to match.
- Windows add-on (only after changing `app/windows/native/src/`): `app/windows/native/build.ps1`, run by the user (auto mode refuses to run the `godot-cpp` build). `-Check` checks the prerequisites without building.
- To see a scene: `app/macos/.build/debug/AgentTown --demo <fixture.json> -showWindow YES -sound NO`, then `screencapture -x -l <window id>`. `-sound NO` keeps the demo's own sounds quiet and `-x` skips the shutter sound, so a check makes no noise. A fixture can be made from a `debug-receiver.py --log` recording. Add `--settings` to open the Settings window too (with `--demo`, the app starts no server, so an installed copy keeps working). `--updates` opens the Updates window; with `--demo` there is no automatic update check, `--check-now` makes a real one, and `--fake-update` makes up a newer app and town-link (99.0.0) without the network. `-compactView YES` shows compact view, and `--resize WxH` shrinks the window 8 seconds in, to see auto-scroll. `-breakIdleSeconds N` starts break time on the bench after N idle seconds (`-breakPastime NAME` for one pastime only; `run-local.sh --breaks` / `--pastime NAME`).

## Working rules

- Work on `main`. After a change is done and its checks pass, always commit and push, without waiting to be asked. Hold off only in a critical phase (a risky or hard-to-undo change the user should look at first) or an evaluation-only phase (exploring, testing or answering a question, with no change meant to stay).
- End commit messages with the co-author line the session gives.
- The plugin and the app have separate versions. When the plugin changes, raise `plugin/.claude-plugin/plugin.json` and push: users get plugin changes only through a new version, with no release needed. When the macOS app changes, raise `AppInfo.fallbackVersion` in `app/macos/Sources/AgentTown/About.swift`; `release.sh` reads it. Whether a plugin and an app work together depends only on the protocol version (`protocol` in each batch and in the endpoint file); change that only for a breaking protocol change, and update both.
- `app/macos/scripts/run-local.sh` builds and runs the app for the user to try a change before a release (a demo by default, `--live` for real sessions; `--help`). Point the user to it when they want to test.
- `app/windows/scripts/run-local.ps1` (or `run-local.sh` from Git Bash) runs the Windows app from the checkout with Godot for the user to try a change (a demo by default, `-Live` for real sessions; `-Help`). Point the user to it when they want to test on Windows.
- A release is `app/macos/scripts/release.sh --publish`, run by the user (auto mode refuses to publish). It publishes the GitHub release and pushes the cask; Homebrew sees a new version only after the cask is on `main`.
- A Windows release is `app/windows/scripts/release.ps1 -Publish`, run by the user (see `docs/windows/releasing.md`); without `-Publish` it only builds the installer.
- Each part keeps a changelog in `CHANGELOG/`: `CHANGELOG_MACOS.md` (the macOS app), `CHANGELOG_WINDOWS.md` (the Windows app), `CHANGELOG_PLUGIN.md` (town-link). When raising a version, add its entry at the top: what a user would notice, fixes included.
- Break time on the bench is a surprise for users: in the changelogs, user-facing docs (README, `docs/office.md`, the web page), release notes and commit messages, say only that idle bench characters pass the time, never which pastimes there are. The list stays in `docs/spec.md` and `todo.md`, which developers need.
- Every feature and fix is for every app platform (macOS and Windows now; others later), unless the user says it is for one platform only (for example, the Microsoft Store is Windows only). Build it for the platform this session works on, and in the same change add the steps for each other platform to `todo.md`: what to build, where the details are in `docs/spec.md`, how it was checked, and the code to compare against. The user does not need to ask for this.
- When behavior changes, update the docs that describe it (README, and `README.zh-TW.md` for sections 1–3, `docs/office.md`, `docs/known-issues.md`, `docs/privacy.md` (when town-link's hooks or what it sends change), `docs/development.md` (scripts, flags, checks), `docs/spec.md`, `docs/protocol.md`, `docs/architecture.md`, `docs/releasing.md`; for the Windows app, `docs/windows/`) and `todo.md`.
- Never commit access tokens, passwords or other credentials. Signing and notarization secrets live only in the keychain or GitHub secrets.
- Write in American English or Traditional Chinese (Taiwan); never Simplified Chinese. UI strings are keyed by their English text, with the Traditional Chinese in `zh-Hant.lproj/Localizable.strings`.
- No global installs without asking.

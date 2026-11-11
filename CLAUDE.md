# agent-town

A macOS menu bar app (Swift, RealityKit) that draws Claude Code's work as a small office, and the Claude Code plugin town-link that sends it events over loopback. The README explains the office; `docs/` has the spec, architecture, protocol and release steps. `todo.md` lists what is open.

## Layout

- `plugin/`: town-link. `hooks/register.ts` wires Claude Code events; `hooks/core.ts` (class `Town`) turns them into protocol events. Tests in `plugin/tests/`.
- `app/macos/`: the app. `Sources/TownCore/Building.swift` reduces protocol events to state; `Sources/AgentTown/TownScene*.swift` draws and animates it. Translations in `Sources/AgentTown/Resources/Localization/`.
- `protocol/`: the JSON schema (`schema/v1.schema.json`) and recorded fixtures for demos.
- `tools/debug-receiver.py`: a stand-in for the app that prints events; `--forward --log FILE` records a live run while the app keeps drawing it.
- `Casks/agent-town.rb`: the Homebrew cask (this repo is the tap).

## Checks

- Plugin: `claude plugin validate plugin` and `claude plugin test plugin`.
- App: `swift build` and `swift test` in `app/macos`.
- To see a scene: `app/macos/.build/debug/AgentTown --demo <fixture.json> -showWindow YES`, then `screencapture -l <window id>`. A fixture can be made from a `debug-receiver.py --log` recording.

## Working rules

- Work on `main`. After a change is done and its checks pass, always commit and push, without waiting to be asked. Hold off only in a critical phase (a risky or hard-to-undo change the user should look at first) or an evaluation-only phase (exploring, testing or answering a question, with no change meant to stay).
- End commit messages with the co-author line the session gives.
- When the plugin or the app changes, raise the version in both `plugin/.claude-plugin/plugin.json` and `AppInfo.fallbackVersion` in `app/macos/Sources/AgentTown/About.swift` (they share it). Users get plugin changes only through a new version.
- A release is `app/macos/scripts/release.sh --publish`, run by the user (auto mode refuses to publish). It publishes the GitHub release and pushes the cask; Homebrew sees a new version only after the cask is on `main`.
- When behavior changes, update the docs that describe it (README, and `README.zh-TW.md` for sections 1–4, `docs/spec.md`, `docs/protocol.md`, `docs/architecture.md`, `docs/releasing.md`) and `todo.md`.
- Never commit access tokens, passwords or other credentials. Signing and notarization secrets live only in the keychain or GitHub secrets.
- Write in American English or Traditional Chinese (Taiwan); never Simplified Chinese. UI strings are keyed by their English text, with the Traditional Chinese in `zh-Hant.lproj/Localizable.strings`.
- No global installs without asking.

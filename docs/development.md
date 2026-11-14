# Developing agent-town

How the repository is laid out, how to run the plugin and the apps from source, how to check a change, and how releases are made. The design is in [architecture.md](architecture.md), the messages between the plugin and the apps in [protocol.md](protocol.md), and the Windows app's own documents in [windows/](windows/README.md).

## What you need

- **The plugin:** Claude Code v2.1.287 or later (it runs mods). Its tests run with `claude plugin test`.
- **The macOS app:** macOS 15 or later and Xcode (Swift 6). No other dependencies: the app is a Swift package in `app/macos`.
- **The Windows app:** Windows 11, Godot 4.7.2 (set `GODOT` to the Godot executable unless `godot` is on `PATH`), and for releases Inno Setup 6 and its export templates. See [windows/releasing.md](windows/releasing.md).
- **The tools:** Python 3.
- **Releases:** the GitHub CLI `gh`, signed in to an account that can publish releases on the repository.

## The repository

| Folder | What it holds |
|---|---|
| `plugin/` | town-link. `hooks/register.ts` wires Claude Code's events; `hooks/core.ts` (class `Town`) turns them into protocol events. Tests in `plugin/tests/`. |
| `app/macos/` | The macOS app. `Sources/TownCore/` holds the building state and everything without UI (`Building.swift` applies protocol events); `Sources/AgentTown/` draws and animates it with RealityKit. Translations in `Sources/AgentTown/Resources/Localization/`. |
| `app/windows/` | The Windows app (Godot, typed GDScript). It keeps copies of shared files in `app/windows/shared/` (see "Shared files" below). |
| `protocol/` | The JSON schema (`schema/v1.schema.json`), recorded event streams in `fixtures/`, and in `fixtures/expected/` the building state each fixture must produce, which both apps are tested against. |
| `catalog/` | Roles, departments, task types and models, shared by the plugin and both apps. |
| `tools/` | `debug-receiver.py` (a stand-in for the app), `sync-windows-assets.py`, `build-plugin-catalog.py`, `convert-assets.py`. |
| `site/` | The project's web page (home, privacy policy, code signing policy; English, and Traditional Chinese in `site/zh-TW/`), published to GitHub Pages by `.github/workflows/pages.yml` whenever `site/` changes on `main`. Plain HTML and CSS; preview it with `python3 -m http.server` in `site/`. |
| `Casks/agent-town.rb` | The Homebrew cask: the repository is also a Homebrew tap. |
| `.claude-plugin/marketplace.json` | Makes the repository a plugin marketplace (`agent-town-claude-code`). |

## The plugin

Run Claude Code with the plugin from your checkout, without installing it:

```bash
claude --plugin-dir plugin
```

Without the app, use the stand-in receiver. It writes the endpoint file the app would write and prints each event, checked against the schema:

```bash
python3 tools/debug-receiver.py          # keep it running
claude --plugin-dir plugin               # in another terminal
```

`--forward --log FILE` passes the events on to a running app while recording them, which is how a new fixture for `protocol/fixtures/` is made. On Windows it writes the endpoint file the Windows app would, so a session can be checked there with no app.

Checks:

```bash
claude plugin validate plugin            # what the plugin hooks and calls, and what Claude Code would refuse
claude plugin test plugin
```

Users get a plugin change only through a new version: raise `version` in `plugin/.claude-plugin/plugin.json` with any change to the plugin, and add it to [`CHANGELOG/CHANGELOG_PLUGIN.md`](../CHANGELOG/CHANGELOG_PLUGIN.md). No release is needed; the marketplace reads `main`.

## The macOS app

Run it from source:

```bash
cd app/macos
swift run AgentTown                       # listens for town-link
swift run AgentTown --demo ../../protocol/fixtures/01-basic-ticket.json   # replays a recorded stream
```

Checks:

```bash
cd app/macos
swift build
swift test
```

After changing how events are applied to the building state, regenerate the expected states and review the diff (the Windows app must then change to match):

```bash
UPDATE_EXPECTED=1 swift test --filter fixturesMatchTheirExpectedState
```

### Trying a change: `run-local.sh`

`app/macos/scripts/run-local.sh` builds the app from your checkout and runs it. Nothing is signed, installed or published, and the run keeps its own settings, apart from an installed copy's.

```bash
app/macos/scripts/run-local.sh                         # a demo: fixture 05 (two projects), no sounds
app/macos/scripts/run-local.sh --demo 02 --zh          # another fixture, in Traditional Chinese
app/macos/scripts/run-local.sh --live                  # real Claude Code sessions
app/macos/scripts/run-local.sh --fake-update --updates # the update notices, with a made-up newer version
app/macos/scripts/run-local.sh --demo 02 --pastime juggle  # break time on the bench, juggling only
```

Options, any number and in any order: `--demo 01`…`05` (or a path to a fixture), `--live`, `--fake-update`, `--check-now`, `--updates`, `--settings`, `--compact`, `--resize WxH`, `--breaks` (break time after 10 idle seconds), `--pastime NAME` (only that pastime), `--sound`, `--zh`, `--en`, `--speed N`, and `--` to pass the rest to the app. `--help` lists them.

A demo starts no server, so an installed agent-town keeps working beside it. `--live` quits an installed agent-town first (both would write the same endpoint file) and opens it again when the run ends.

### The app's development flags

These work on the built app, `app/macos/.build/debug/AgentTown`, and through `run-local.sh`:

| Flag | What it does |
|---|---|
| `--demo FILE` | Replays a fixture instead of listening for town-link (`--speed N` plays it faster) |
| `-showWindow YES`, `-sound NO` | Shows the office window; keeps the demo's sounds quiet |
| `--settings`, `--updates` | Opens the Settings or the Updates window |
| `--fake-update` | Makes up a newer app and town-link (99.0.0), without the network |
| `--check-now` | Makes a real update check (a demo makes no automatic one) |
| `-compactView YES` | Compact view, without changing the saved setting |
| `--resize WxH` | Eight seconds in, shrinks the window as a drag would, to see auto-scroll |
| `-breakIdleSeconds N` | Break time on the bench after N idle seconds instead of 180 |
| `-breakPastime NAME` | Standing characters on a break do only NAME (`juggle`, `cube`, `toss`, `phone`, `chat`, `doze`) |
| `-language zh-Hant` | Runs in Traditional Chinese |

Any setting can be given the same way (`-hideIdleBlocks YES -idleHideSeconds 1`). To look at a scene without noise: run a demo with `-showWindow YES -sound NO`, then `screencapture -x -l <window id>`.

## The Windows app

`app/windows/scripts/run-local.ps1` runs the app from the checkout with Godot (no export, no installer). From Git Bash, use `bash app/windows/scripts/run-local.sh` with the same options.

```powershell
.\app\windows\scripts\run-local.ps1                 # a demo: fixture 05 (two projects), no sounds
.\app\windows\scripts\run-local.ps1 -Demo 04 -Zh    # another fixture, in Traditional Chinese
.\app\windows\scripts\run-local.ps1 -Live           # real Claude Code sessions
```

Its options match the macOS script's (`-Demo`, `-Live`, `-FakeUpdate`, `-CheckNow`, `-Updates`, `-Settings`, `-Compact`, `-Resize WxH`, `-Sound`, `-Zh`, `-En`, `-Speed N`); `-Help` lists them.

Checks:

```powershell
godot --headless --path app/windows --script res://tests/run_tests.gd
```

The native add-on that keeps the window off the taskbar is built with `app/windows/native/build.ps1` (Visual Studio Build Tools 2026), only after changing `app/windows/native/src/`; `-Check` checks the prerequisites without building. More in [windows/architecture.md](windows/architecture.md).

## Shared files

The Windows app keeps copies of `catalog/*.json`, the Kenney models and the macOS app's `Localizable.strings` in `app/windows/shared/`. After changing any of those:

```bash
python3 tools/sync-windows-assets.py          # updates the copies; commit them
python3 tools/sync-windows-assets.py --check  # reports stale copies
```

UI strings are keyed by their English text, with the Traditional Chinese in `zh-Hant.lproj/Localizable.strings`. The project is written in American English and Traditional Chinese (Taiwan), never Simplified Chinese.

## Versions

The plugin, the macOS app and the Windows app each have their own version:

| Part | Where the version is | How users get a new one |
|---|---|---|
| town-link | `plugin/.claude-plugin/plugin.json` | Pushed to `main`; users run `claude plugin update` |
| macOS app | `AppInfo.fallbackVersion` in `app/macos/Sources/AgentTown/About.swift` | A release, `v<version>` |
| Windows app | `config/version` in `app/windows/project.godot` (and `export_presets.cfg`) | A release, `windows-v<version>` |

When you raise a version, add it at the top of that part's changelog in `CHANGELOG/` (`CHANGELOG_PLUGIN.md`, `CHANGELOG_MACOS.md`, `CHANGELOG_WINDOWS.md`): what a user would notice, fixes included.

Whether a plugin and an app work together depends only on the protocol version (`protocol` in each batch and in the endpoint file). Change it only for a breaking protocol change, and update both sides.

## Releasing

Both apps are published on this repository's GitHub Releases.

**macOS** (signed with a Developer ID and notarized by Apple; the one-time setup of the certificate and the notarization login is in [releasing.md](releasing.md)):

```bash
app/macos/scripts/release.sh                 # build, sign and notarize; the .dmg is in app/macos/build/release/
app/macos/scripts/release.sh --unsigned      # a test build, not signed
app/macos/scripts/release.sh --publish       # publish release v<version> and push the Homebrew cask
app/macos/scripts/release.sh --publish --draft   # a draft release to review first
```

`--publish` refuses to run with uncommitted changes, off `main`, or when `main` differs from `origin/main`. It publishes the release titled "agent-town for macOS <version>" with the `.dmg` and its SHA-256, checks the uploaded file, and commits and pushes the cask, which is what `brew upgrade` reads. Signing secrets stay in the releasing Mac's keychain; never commit a credential.

**Windows** (the installer isn't code-signed yet):

```powershell
.\app\windows\scripts\release.ps1            # run the tests, export the app, build the installer
.\app\windows\scripts\release.ps1 -Publish   # publish release windows-v<version>
```

See [windows/releasing.md](windows/releasing.md).

## Contributing

Open an issue for a bug, a scene that looks wrong, or one you would like to see. For a change, keep to the checks above, update the documents that describe the behavior (the README, [spec.md](spec.md), [protocol.md](protocol.md), [architecture.md](architecture.md); for Windows, [windows/](windows/README.md)), and raise the version of each part you changed.

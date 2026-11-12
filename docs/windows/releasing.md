# Releasing agent-town for Windows

The Windows app has its own version number, `config/version` in `app/windows/project.godot`. Its releases share this repo's GitHub Releases with the macOS app, under tags `windows-v<version>`, and are published with `--latest=false` so the macOS release stays GitHub's "Latest" and the Homebrew cask is untouched. The update notices of the Windows app read only `windows-v` tags.

## What you need, once

- Godot 4.7.2 and its export templates (Editor → Manage Export Templates, or the templates in `%APPDATA%\Godot\export_templates\4.7.2.stable`). Set `$env:GODOT` to the Godot exe unless `godot` is on `PATH`.
- Inno Setup 6: `winget install JRSoftware.InnoSetup` (it installs for your user, in `%LOCALAPPDATA%\Programs\Inno Setup 6`). `release.ps1` finds it there, on `PATH`, or from `$env:ISCC`.
- The GitHub CLI `gh`, signed in to an account that can publish releases on `samsonchen/agent-town`.

## Making a release

1. Raise the version in two places, to the same number: `config/version` in `app/windows/project.godot`, and `application/file_version` and `application/product_version` in `app/windows/export_presets.cfg` (with a fourth part, `.0`: `1.0.1.0`). `release.ps1` stops if they differ.
2. Build and try it:
   ```powershell
   .\app\windows\scripts\release.ps1
   ```
   It runs the tests, exports `app\windows\build\agent-town.exe` (with the TownWindow DLL next to it), builds `app\windows\build\installer\agent-town-setup-<version>.exe`, and prints its SHA-256. Run the installer and try the installed app, including Settings → Open at login, which works only in the installed app.
3. Commit and push, then publish (the user runs this; auto mode refuses to publish):
   ```powershell
   .\app\windows\scripts\release.ps1 -Publish
   ```
   It creates the release `windows-v<version>`, titled "agent-town for Windows <version>", with the installer and notes (how to get past SmartScreen, the checksum), downloads the installer again and checks its checksum. `-Publish -Draft` makes a draft to look at first.

## The installer

`app/windows/installer/agent-town.iss` (Inno Setup):

- Installs for the current user only, with no administrator prompt, into `%LOCALAPPDATA%\Programs\agent-town`, with a Start menu shortcut and an uninstaller (Settings → Apps → Installed apps).
- A newer installer replaces the installed app; settings in `%APPDATA%\agent-town` are kept. A running copy is stopped first (it hides in the tray rather than quitting when asked to close).
- The uninstaller stops a running copy, removes the "Open at login" entry (`HKCU\...\Run`, value `agent-town`) and a leftover endpoint file. It keeps the settings.
- The installer is in English (Inno Setup ships no Traditional Chinese translation); the app follows the Windows display language.
- Its `AppId` identifies the app across versions: never change it.

The app icon for the exe and the installer is `app/windows/installer/agent-town.ico`, made from the shared app icon by `godot --headless --path app/windows --script res://dev/make_icon.gd`. Run that again after the app icon changes.

## Not signed yet

The installer and the app are not code-signed, so SmartScreen shows "Windows protected your PC" (More info → Run anyway) until enough people have run that file. Signing must be free (for example the SignPath Foundation's program for open-source projects); see [roadmap.md](roadmap.md).

## Windows 10

The installer allows Windows 10 (`MinVersion=10.0`), at the user's choice (2026-11-13), but the app is tested only on Windows 11; the README says so. Nothing in the app needs Windows 11: Godot 4.7, the tray icon, the TownWindow add-on and the default sounds all exist on Windows 10.

## Only x64 for now

The export preset makes an x64 build, which also runs on Windows on ARM through emulation. An ARM64 build waits until one has been run on an ARM machine (`docs/windows/verification.md`).

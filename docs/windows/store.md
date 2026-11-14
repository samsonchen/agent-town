# agent-town in the Microsoft Store

The Windows app can also be published in the Microsoft Store, as an MSIX package. The Store signs the package, so Windows shows no SmartScreen warning and Smart App Control lets it run. The installer on GitHub Releases ([releasing.md](releasing.md)) stays as it is; both are built from the same source and the same version number.

## The product in Partner Center

The Partner Center account is an individual developer account. The product "Agent-Town for Claude Code" (an MSIX app) has this identity, which the package manifest must use exactly:

- Package/Identity/Name: `SamsonChen.Agent-TownforClaudeCode`
- Package/Identity/Publisher: `CN=4A4000D9-1902-48E3-A565-40AF7CF26EC2`
- Publisher display name: `Samson Chen`
- Package family name: `SamsonChen.Agent-TownforClaudeCode_z4f7aag6y3hy2`
- Store ID: `9N0G35LW0LNK`

These are public (they are in every installed package); they are not secrets.

## How a Store copy differs

A Store copy is exported with the preset "Windows x64 Store", which adds the custom feature `store` (`Distribution.is_store()` in `app/windows/shell/distribution.gd`):

- **Updates:** the Store updates the app, so it does not check GitHub for a newer app; the Updates window says "The Microsoft Store keeps agent-town up to date." It still checks town-link's version and tells the user about sessions that run an older one. Settings → Updates keeps Check for updates automatically and Check now for that, with a note saying so.
- **Open at login:** the package declares a startup task (off until the user turns it on). Settings shows "Open at login…", which opens Windows Settings → Apps → Startup. A Store copy never touches the `Run` key: the Store puts each version in a new folder, and `LoginItem.repair()` would otherwise point the installer copy's entry at the package.
- **The data folder:** Windows normally keeps a packaged app's writes under `%APPDATA%` inside the package, where town-link would not find `endpoint.json`. The manifest excludes `%APPDATA%\agent-town-claude-code` from that (`virtualization:ExcludedDirectories`), so the Store copy uses the same folder, endpoint file and settings as the installer copy. Checked 2026-11-13 with no restricted capability (only `runFullTrust`), on a profile with and without the folder, and with a real Claude Code session.

Writes to the registry are not kept inside the package: a test copy's `repair()` rewrote the real `Run` value. Keep it that way: a Store copy must not write the `Run` key.

## Building the package

Needs the Windows SDK (`makeappx.exe`; `$env:MAKEAPPX`, else the newest under `Windows Kits\10\bin`), besides Godot.

```powershell
.\app\windows\scripts\release.ps1 -Store
```

It runs the tests, exports `app\windows\build\store\package\` with the Store preset, makes the icons from `shared\icons\app-icon-1024.png`, fills the manifest template `app\windows\installer\msix\AppxManifest.xml` with the version, and packs `app\windows\build\store\agent-town-<version>.msix`. The package is unsigned: Partner Center signs it.

To try it first, turn on Developer Mode (Settings → System → For developers), quit the installed agent-town, and register the package folder:

```powershell
Add-AppxPackage -Register app\windows\build\store\package\AppxManifest.xml
```

Start it from the Start menu (Agent-Town for Claude Code). Remove it afterwards with `Get-AppxPackage SamsonChen.Agent-TownforClaudeCode | Remove-AppxPackage`; a test copy and the installer copy should not run at the same time, as they share the endpoint file.

## Submitting

In Partner Center, Apps and games → Agent-Town for Claude Code → Start submission (the user does this):

1. **Pricing and availability:** free; markets as wanted.
2. **Properties:** category Developer tools; privacy policy URL `https://samsonchen.github.io/agent-town-claude-code/privacy.html`; website `https://samsonchen.github.io/agent-town-claude-code/`.
3. **Age ratings:** the questionnaire (no user-generated content, no purchases).
4. **Packages:** upload `agent-town-<version>.msix`.
5. **Store listings** (English, and Traditional Chinese if wanted): the description, screenshots (at least one, 1366×768 or larger), and a note that it needs Claude Code with the town-link plugin.
6. **Submission options, notes for certification:** that the app shows Claude Code sessions and needs Claude Code with town-link to show anything beyond an empty office; that `runFullTrust` is needed because it is a desktop app with a tray icon and a local loopback server for the plugin.

A later version: raise the version as [releasing.md](releasing.md) says, build with `-Store`, and upload the new package in a new submission. The version in the package must be higher than the published one.

A product has one submission at a time. When a new version is ready while the last one is still in certification, either let that one finish and then submit the new package (the usual way), or cancel it in Partner Center and submit the new package instead, which starts certification over. In a new submission, Packages: remove the old `.msix` and upload the new one; the listing and the other pages carry over.

<#
.SYNOPSIS
  Builds the agent-town for Windows installer, and with -Publish puts it on GitHub Releases.

.DESCRIPTION
  The version is config/version in app\windows\project.godot (the Windows app's own number). The
  steps: run the tests, export the project with Godot (export_presets.cfg, "Windows x64"), build
  the installer with Inno Setup (installer\agent-town.iss), and print its SHA-256. The installer
  is app\windows\build\installer\agent-town-setup-<version>.exe.

  -Publish then creates the GitHub release windows-v<version>, titled "agent-town for Windows
  <version>", with the installer attached, published with --latest=false so the macOS release
  stays GitHub's "Latest" (and the Homebrew cask is untouched). It downloads the uploaded file
  again and checks its checksum. Publish from main, with everything committed and pushed.

  Needs Godot 4.7.2 ($env:GODOT, else "godot" on PATH), its export templates, Inno Setup 6
  ($env:ISCC, else ISCC.exe on PATH or in its usual install folders), and for -Publish the GitHub
  CLI (gh), signed in.

  -Store builds the Microsoft Store package instead (docs/windows/store.md): the tests, the export
  with the "Windows x64 Store" preset, the icons from shared\icons\app-icon-1024.png, the manifest
  from installer\msix\AppxManifest.xml, and makeappx (Windows SDK: $env:MAKEAPPX, else the newest
  in Windows Kits). The package is app\windows\build\store\agent-town-<version>.msix, unsigned:
  upload it in Partner Center, which signs it. To try it first, register the package folder
  (Developer Mode): Add-AppxPackage -Register app\windows\build\store\package\AppxManifest.xml

.EXAMPLE
    .\app\windows\scripts\release.ps1             # build and check the installer
    .\app\windows\scripts\release.ps1 -Publish    # build, then publish windows-v<version>
    .\app\windows\scripts\release.ps1 -Publish -Draft   # a draft release, to look at first
    .\app\windows\scripts\release.ps1 -Store      # build the Microsoft Store package
#>
param(
  [switch]$Publish,
  [switch]$Store,    # build the Microsoft Store package (.msix) instead of the installer
  [switch]$Draft,    # with -Publish: make a draft release
  [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
function Fail([string]$msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }
function Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path   # app\windows
$repo = (Resolve-Path (Join-Path $project '..\..')).Path
$build = Join-Path $project 'build'
$out = Join-Path $build 'installer'

# -- Version -----------------------------------------------------------------------------------
$m = Select-String -Path (Join-Path $project 'project.godot') -Pattern '^config/version="([0-9]+(\.[0-9]+)+)"' | Select-Object -First 1
if (-not $m) { Fail 'no config/version in project.godot' }
$version = $m.Matches[0].Groups[1].Value
$preset = Get-Content (Join-Path $project 'export_presets.cfg') -Raw
$stamps = [regex]::Matches($preset, 'application/(file|product)_version="([^"]*)"') | ForEach-Object { $_.Groups[2].Value }
if (-not $stamps -or ($stamps | Where-Object { $_ -ne "$version.0" })) {
  Fail "export_presets.cfg's file_version and product_version (both presets) must be $version.0 (project.godot says $version)"
}
$tag = "windows-v$version"
Write-Host "agent-town for Windows $version ($tag)"

# -- Tools -------------------------------------------------------------------------------------
$godot = $env:GODOT
if (-not $godot) {
  foreach ($name in @('godot', 'godot4', 'Godot_v4.7.2-stable_win64_console', 'Godot_v4.7.2-stable_win64')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $godot = $cmd.Source; break }
  }
}
if (-not $godot -or -not (Test-Path $godot)) { Fail 'Godot 4.7.2 not found: set $env:GODOT to the Godot exe' }

$iscc = $env:ISCC
if ($Store) { $iscc = 'not needed' }
if (-not $iscc) {
  $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) {
  foreach ($p in @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe")) {
    if (Test-Path $p) { $iscc = $p; break }
  }
}
if (-not $iscc) { Fail 'Inno Setup 6 not found: install it (winget install JRSoftware.InnoSetup) or set $env:ISCC' }

# From here on, outside programs (git, gh, Godot, Inno Setup) are judged by their exit codes. With
# 'Stop', Windows PowerShell 5.1 turns anything they print to stderr (such as gh's "release not
# found") into a fatal error.
$ErrorActionPreference = 'Continue'

if ($Draft -and -not $Publish) { Fail '-Draft goes with -Publish' }
if ($Store -and $Publish) { Fail '-Store builds the package only: upload it in Partner Center' }
if ($Store) {
  $makeappx = $env:MAKEAPPX
  if (-not $makeappx) {
    $makeappx = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\makeappx.exe" -ErrorAction SilentlyContinue |
      Sort-Object { [version]($_.Directory.Parent.Name) } | Select-Object -Last 1 -ExpandProperty FullName
  }
  if (-not $makeappx -or -not (Test-Path $makeappx)) { Fail 'makeappx.exe not found: install the Windows SDK or set $env:MAKEAPPX' }
}
if ($Publish) {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail '-Publish needs the GitHub CLI (gh)' }
  if (git -C $repo status --porcelain) { Fail 'commit your changes before publishing' }
  if (-not $Draft) {
    if ((git -C $repo rev-parse --abbrev-ref HEAD) -ne 'main') { Fail 'publish from the main branch (or add -Draft)' }
    git -C $repo fetch -q origin main
    if ((git -C $repo rev-parse HEAD) -ne (git -C $repo rev-parse origin/main)) { Fail 'main is not the same as origin/main: push or pull first' }
  }
  gh release view $tag --repo samsonchen/agent-town-claude-code *> $null
  if ($LASTEXITCODE -eq 0) { Fail "the release $tag already exists: raise config/version first" }
  gh auth status *> $null
  if ($LASTEXITCODE -ne 0) { Fail 'gh is not signed in: run gh auth login' }
}

# -- Tests -------------------------------------------------------------------------------------
if (-not $SkipTests) {
  Step 'Running the tests'
  $log = & $godot --headless --path $project --script res://tests/run_tests.gd 2>&1 | Out-String
  $summary = ($log -split "`n" | Where-Object { $_ -match '^\d+ passed, \d+ failed' } | Select-Object -Last 1)
  Write-Host $summary
  if (-not $summary -or $summary -notmatch ', 0 failed') { Write-Host $log; Fail 'the tests did not all pass' }
}

# -- Store package -----------------------------------------------------------------------------
if ($Store) {
  Step 'Exporting the Store copy with Godot'
  $storeDir = Join-Path $build 'store'
  $pkg = Join-Path $storeDir 'package'
  if (Get-AppxPackage SamsonChen.Agent-TownforClaudeCode -ErrorAction SilentlyContinue | Where-Object { $_.InstallLocation -eq $pkg }) {
    Fail "a test copy is registered from ${pkg}: Get-AppxPackage SamsonChen.Agent-TownforClaudeCode | Remove-AppxPackage"
  }
  if (Test-Path $storeDir) { Remove-Item -Recurse -Force $storeDir }
  New-Item -ItemType Directory -Force (Join-Path $pkg 'Assets') | Out-Null
  $exe = Join-Path $pkg 'agent-town.exe'
  & $godot --headless --path $project --export-release 'Windows x64 Store' $exe 2>&1 | Out-Null
  if (-not (Test-Path $exe)) { Fail 'the export made no agent-town.exe' }
  if (-not (Test-Path (Join-Path $pkg 'town_window.windows.template_release.x86_64.dll'))) { Fail 'the export has no TownWindow add-on DLL' }

  Step 'Making the package'
  Add-Type -AssemblyName System.Drawing
  $icon = [System.Drawing.Image]::FromFile((Join-Path $project 'shared\icons\app-icon-1024.png'))
  $sizes = [ordered]@{ 'StoreLogo.png' = 50; 'Square44x44Logo.png' = 44; 'Square44x44Logo.targetsize-44_altform-unplated.png' = 44;
    'Square44x44Logo.targetsize-256_altform-unplated.png' = 256; 'Square150x150Logo.png' = 150 }
  foreach ($name in $sizes.Keys) {
    $n = $sizes[$name]
    $bmp = New-Object System.Drawing.Bitmap $n, $n
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($icon, 0, 0, $n, $n)
    $g.Dispose()
    $bmp.Save((Join-Path $pkg "Assets\$name"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
  }
  $icon.Dispose()
  $manifest = (Get-Content (Join-Path $project 'installer\msix\AppxManifest.xml') -Raw).Replace('{VERSION}', $version)
  [IO.File]::WriteAllText((Join-Path $pkg 'AppxManifest.xml'), $manifest, (New-Object Text.UTF8Encoding $false))
  $msix = Join-Path $storeDir "agent-town-$version.msix"
  & $makeappx pack /d $pkg /p $msix /o | Out-Null
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $msix)) { Fail 'makeappx failed' }
  $mb = [math]::Round((Get-Item $msix).Length / 1MB, 1)
  Write-Host "Package: $msix ($mb MB)"
  Write-Host "`nTry it (Developer Mode): Add-AppxPackage -Register $pkg\AppxManifest.xml"
  Write-Host "Then upload the .msix in Partner Center (Apps and games, Agent-Town for Claude Code, a new submission)."
  exit 0
}

# -- Export ------------------------------------------------------------------------------------
Step 'Exporting with Godot'
# Everything in build\ but the Store package (-Store), which may be registered for a try.
New-Item -ItemType Directory -Force $build | Out-Null
Get-ChildItem $build -Force | Where-Object { $_.Name -ne 'store' } | Remove-Item -Recurse -Force
$exe = Join-Path $build 'agent-town.exe'
& $godot --headless --path $project --export-release 'Windows x64' $exe 2>&1 | Out-Null
if (-not (Test-Path $exe)) { Fail 'the export made no agent-town.exe' }
if (-not (Test-Path (Join-Path $build 'town_window.windows.template_release.x86_64.dll'))) { Fail 'the export has no TownWindow add-on DLL' }
$fv = (Get-Item $exe).VersionInfo.ProductVersion
if ($fv -ne "$version.0") { Fail "agent-town.exe says version $fv, not $version.0" }

# -- Installer ---------------------------------------------------------------------------------
Step 'Building the installer with Inno Setup'
& $iscc /Qp "/DAppVersion=$version" "/DSourceDir=$build" "/DOutputDir=$out" (Join-Path $project 'installer\agent-town.iss')
if ($LASTEXITCODE -ne 0) { Fail 'Inno Setup failed' }
$setup = Join-Path $out "agent-town-setup-$version.exe"
if (-not (Test-Path $setup)) { Fail "no $setup" }
$sha = (Get-FileHash -Algorithm SHA256 $setup).Hash.ToLower()
$mb = [math]::Round((Get-Item $setup).Length / 1MB, 1)
Write-Host "Installer: $setup ($mb MB)"
Write-Host "SHA-256:   $sha"

if (-not $Publish) {
  Write-Host "`nTry it: run the installer, then use the installed app. Publish with -Publish."
  exit 0
}

# -- Publish -----------------------------------------------------------------------------------
Step "Publishing $tag"
$notes = @"
agent-town for Windows ${version}: the office for Claude Code, in the tray.

Download agent-town-setup-$version.exe and run it. It installs for your user only (no administrator prompt). The installer is not code-signed yet, so Windows shows "Windows protected your PC": click More info, then Run anyway. Requires Windows 11 (x64); Windows 10 is allowed but not tested. Install the town-link plugin in Claude Code as the README says.

SHA-256 of agent-town-setup-$version.exe: $sha
"@
$flags = @('--latest=false')
if ($Draft) { $flags += '--draft' }
$target = git -C $repo rev-parse HEAD
# The notes go in a file: Windows PowerShell 5.1 does not escape double quotes inside an argument
# to a program, so gh would get the notes in pieces.
$notesFile = Join-Path $build 'release-notes.md'
[IO.File]::WriteAllText($notesFile, $notes, (New-Object Text.UTF8Encoding $false))
gh release create $tag $setup --repo samsonchen/agent-town-claude-code --target $target --title "agent-town for Windows $version" --notes-file $notesFile @flags
if ($LASTEXITCODE -ne 0) { Fail 'gh release create failed' }

Step 'Checking the uploaded installer'
$check = Join-Path $build 'check'
New-Item -ItemType Directory -Force $check | Out-Null
gh release download $tag --repo samsonchen/agent-town-claude-code --pattern "agent-town-setup-$version.exe" --dir $check --clobber
if ($LASTEXITCODE -ne 0) { Fail 'could not download the uploaded installer' }
$got = (Get-FileHash -Algorithm SHA256 (Join-Path $check "agent-town-setup-$version.exe")).Hash.ToLower()
if ($got -ne $sha) { Fail "the uploaded installer's checksum is $got, not $sha" }
Write-Host "Published $tag; the uploaded installer matches ($sha)."

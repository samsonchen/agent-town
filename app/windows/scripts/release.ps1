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

.EXAMPLE
    .\app\windows\scripts\release.ps1             # build and check the installer
    .\app\windows\scripts\release.ps1 -Publish    # build, then publish windows-v<version>
    .\app\windows\scripts\release.ps1 -Publish -Draft   # a draft release, to look at first
#>
param(
  [switch]$Publish,
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
if ($preset -notmatch "application/file_version=`"$([regex]::Escape($version)).0`"" -or
    $preset -notmatch "application/product_version=`"$([regex]::Escape($version)).0`"") {
  Fail "export_presets.cfg's file_version and product_version must be $version.0 (project.godot says $version)"
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

if ($Draft -and -not $Publish) { Fail '-Draft goes with -Publish' }
if ($Publish) {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail '-Publish needs the GitHub CLI (gh)' }
  if (git -C $repo status --porcelain) { Fail 'commit your changes before publishing' }
  if (-not $Draft) {
    if ((git -C $repo rev-parse --abbrev-ref HEAD) -ne 'main') { Fail 'publish from the main branch (or add -Draft)' }
    git -C $repo fetch -q origin main
    if ((git -C $repo rev-parse HEAD) -ne (git -C $repo rev-parse origin/main)) { Fail 'main is not the same as origin/main: push or pull first' }
  }
  gh release view $tag --repo samsonchen/agent-town *> $null
  if ($LASTEXITCODE -eq 0) { Fail "the release $tag already exists: raise config/version first" }
}

# -- Tests -------------------------------------------------------------------------------------
if (-not $SkipTests) {
  Step 'Running the tests'
  $log = & $godot --headless --path $project --script res://tests/run_tests.gd 2>&1 | Out-String
  $summary = ($log -split "`n" | Where-Object { $_ -match '^\d+ passed, \d+ failed' } | Select-Object -Last 1)
  Write-Host $summary
  if (-not $summary -or $summary -notmatch ', 0 failed') { Write-Host $log; Fail 'the tests did not all pass' }
}

# -- Export ------------------------------------------------------------------------------------
Step 'Exporting with Godot'
if (Test-Path $build) { Remove-Item -Recurse -Force $build }
New-Item -ItemType Directory -Force $build | Out-Null
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

Download agent-town-setup-$version.exe and run it. It installs for your user only (no administrator prompt). The installer is not code-signed yet, so Windows shows "Windows protected your PC": click More info, then Run anyway. Requires Windows 11 (x64). Install the town-link plugin in Claude Code as the README says.

SHA-256 of agent-town-setup-$version.exe: $sha
"@
$flags = @('--latest=false')
if ($Draft) { $flags += '--draft' }
$target = git -C $repo rev-parse HEAD
gh release create $tag $setup --repo samsonchen/agent-town --target $target --title "agent-town for Windows $version" --notes $notes @flags
if ($LASTEXITCODE -ne 0) { Fail 'gh release create failed' }

Step 'Checking the uploaded installer'
$check = Join-Path $build 'check'
New-Item -ItemType Directory -Force $check | Out-Null
gh release download $tag --repo samsonchen/agent-town --pattern "agent-town-setup-$version.exe" --dir $check --clobber
if ($LASTEXITCODE -ne 0) { Fail 'could not download the uploaded installer' }
$got = (Get-FileHash -Algorithm SHA256 (Join-Path $check "agent-town-setup-$version.exe")).Hash.ToLower()
if ($got -ne $sha) { Fail "the uploaded installer's checksum is $got, not $sha" }
Write-Host "Published $tag; the uploaded installer matches ($sha)."

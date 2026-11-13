<#
.SYNOPSIS
  Runs the Windows app from this checkout with Godot, to try a change before releasing it.

.DESCRIPTION
  Nothing is exported, installed or published. Quit it from its tray icon (Quit agent-town) or
  with Ctrl+C.

    .\app\windows\scripts\run-local.ps1                a demo: fixture 05 (two projects), no sounds
    .\app\windows\scripts\run-local.ps1 -Demo 02       another fixture: 01 to 05, or a path to one
    .\app\windows\scripts\run-local.ps1 -Live          real Claude Code sessions instead of a demo

  Options (any number, in any order):
    -FakeUpdate   a made-up newer agent-town and town-link (99.0.0), without the network
    -CheckNow     a real update check against GitHub (a demo makes no automatic check)
    -Updates      open the Updates window
    -Settings     open the Settings window
    -Compact      compact view (the office at half size), without changing the saved setting
    -Resize WxH   8 seconds in, shrink the window to W by H pixels, as a drag would (auto-scroll)
    -Sound        play the demo's sounds
    -Zh, -En      run in Traditional Chinese or English
    -Speed N      play the demo N times as fast
    -- ARGS       pass the rest to the app as is

  Godot 4.7.2 is taken from $env:GODOT, else from "godot" (or a Godot_v4.7.2 exe) on PATH. For
  example, once per PowerShell window:  $env:GODOT = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'

  -Live: an installed agent-town and this run would both write
  %APPDATA%\agent-town-claude-code\endpoint.json, so a running installed copy is stopped first and
  started again when this run ends, also after Ctrl+C. Sessions already open find this run within a few seconds. A demo starts no server, so an
  installed copy keeps working beside it.

  This run keeps its own settings (%APPDATA%\agent-town-claude-code\run-local\settings.cfg),
  apart from the installed app's.

.EXAMPLE
  From PowerShell, in the repo folder:
    .\app\windows\scripts\run-local.ps1 -Demo 04 -Zh
  From Git Bash or Claude Code's ! prompt: bash app/windows/scripts/run-local.sh -Compact
#>
$ErrorActionPreference = 'Stop'

function Fail([string]$msg) { Write-Host "run-local: $msg" -ForegroundColor Red; exit 1 }

function Show-Help {
  Get-Help $PSCommandPath -Detailed | Out-String | Write-Host
}

# Options are read by hand, so they can come in any order and "--" can pass the rest through.
$fixture = '05'
$live = $false
$sound = $false
$open = @()
$appArgs = @()
$i = 0
while ($i -lt $args.Count) {
  $a = [string]$args[$i]
  switch -Regex ($a) {
    '^-(Demo)$' { if ($i + 1 -ge $args.Count) { Fail '-Demo needs a fixture' }; $i++; $fixture = [string]$args[$i] }
    '^-(Live)$' { $live = $true }
    '^-(FakeUpdate)$' { $appArgs += '--fake-update' }
    '^-(CheckNow)$' { $appArgs += '--check-now' }
    '^-(Updates)$' { $open += 'updates' }
    '^-(Settings)$' { $open += 'settings' }
    '^-(Compact)$' { $appArgs += @('--compact', 'yes') }
    '^-(Resize)$' { if ($i + 1 -ge $args.Count) { Fail '-Resize needs WIDTHxHEIGHT' }; $i++; $appArgs += @('--resize', [string]$args[$i]) }
    '^-(Sound)$' { $sound = $true }
    '^-(Zh)$' { $appArgs += @('--language', 'zh-Hant') }
    '^-(En)$' { $appArgs += @('--language', 'en') }
    '^-(Speed)$' { if ($i + 1 -ge $args.Count) { Fail '-Speed needs a number' }; $i++; $appArgs += @('--speed', [string]$args[$i]) }
    '^--$' { if ($i + 1 -lt $args.Count) { $appArgs += $args[($i + 1)..($args.Count - 1)] }; $i = $args.Count; break }
    '^(-h|-Help|--help|/\?)$' { Show-Help; exit 0 }
    default { Fail "unknown option $a (see -Help)" }
  }
  $i++
}

$project = Resolve-Path (Join-Path $PSScriptRoot '..')            # app\windows
$fixtures = Resolve-Path (Join-Path $PSScriptRoot '..\..\..\protocol\fixtures')

# Godot: $env:GODOT, else on PATH.
$godot = $env:GODOT
if (-not $godot) {
  foreach ($name in @('godot', 'godot4', 'Godot_v4.7.2-stable_win64_console', 'Godot_v4.7.2-stable_win64')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $godot = $cmd.Source; break }
  }
}
if (-not $godot -or -not (Test-Path $godot)) {
  Fail 'Godot 4.7.2 not found. Set $env:GODOT to the Godot exe, for example: $env:GODOT = ''C:\path\to\Godot_v4.7.2-stable_win64_console.exe'''
}

$settingsFile = Join-Path $env:APPDATA 'agent-town-claude-code\run-local\settings.cfg'
$appArgs += @('--settings-file', $settingsFile)
if ($open.Count -gt 0) { $appArgs += @('--open', ($open -join ',')) }

if ($live) {
  # Another agent-town that is not a demo uses the same endpoint file: the installed app
  # (agent-town.exe, from the installer), or one started from Godot with this project (until the
  # installer exists). It is stopped, and started again the same way when this run ends.
  $others = @(Get-CimInstance Win32_Process | Where-Object {
      $_.Name -eq 'agent-town.exe' -or
      ($_.Name -like 'Godot*' -and $_.CommandLine -match 'app[\\/]windows' -and $_.CommandLine -notmatch '--demo|--script|--import|--editor|-e\b')
    })
  $restart = @()
  foreach ($p in $others) {
    $exe = $p.ExecutablePath
    # The command line after the exe, which may or may not be quoted.
    $rest = ($p.CommandLine -replace '^\s*("[^"]*"|\S+)\s*', '')
    $restart += [pscustomobject]@{ Exe = $exe; Args = $rest; Dir = (Split-Path $exe) }
    Write-Host "Stopping the running agent-town ($($p.Name)); it starts again when this run ends."
    Stop-Process -Id $p.ProcessId
    Wait-Process -Id $p.ProcessId -Timeout 5 -ErrorAction SilentlyContinue
  }
  try {
    if (-not $sound) { $appArgs += @('--sound', 'no') }
    Write-Host 'Running from the checkout with real sessions. Quit it from its tray icon or with Ctrl+C.'
    & $godot --path $project -- @appArgs
  } finally {
    foreach ($r in $restart) {
      if ($r.Args) { Start-Process -FilePath $r.Exe -ArgumentList $r.Args -WorkingDirectory $r.Dir }
      else { Start-Process -FilePath $r.Exe -WorkingDirectory $r.Dir }
    }
  }
} else {
  if ($fixture -match '[\\/]' -or $fixture -like '*.json') {
    $file = $fixture
  } else {
    $file = Get-ChildItem -Path $fixtures -Filter "$fixture-*.json" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $file -or -not (Test-Path $file)) { Fail "no fixture $fixture in protocol\fixtures" }
  if (-not $sound) { $appArgs += @('--sound', 'no') }
  Write-Host "Running the demo $(Split-Path $file -Leaf). Quit it from its tray icon or with Ctrl+C."
  & $godot --path $project -- --demo (Resolve-Path $file).Path @appArgs
}

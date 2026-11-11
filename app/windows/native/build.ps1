<#
.SYNOPSIS
  Builds the TownWindow add-on into ..\addons\town_window\bin\ for x64 and ARM64.

.DESCRIPTION
  Needs Visual Studio Build Tools (or Visual Studio) with the C++ x64 and ARM64 tools and a
  Windows SDK. SCons is taken from $env:SCONS, else from PATH, else installed into a private
  virtual environment in this folder (.venv, git-ignored). Nothing is installed globally.

.EXAMPLE
  From PowerShell, in the repo folder (the default RemoteSigned policy runs local scripts):
    .\app\windows\native\build.ps1
    .\app\windows\native\build.ps1 -Arch arm64
    .\app\windows\native\build.ps1 -Check
  From Git Bash or Claude Code's ! prompt: bash app/windows/native/build.sh
  (In PowerShell, "bash" is usually WSL's, not Git Bash, so use the .ps1 there.)
#>
param(
  [ValidateSet('all', 'x86_64', 'arm64')] [string]$Arch = 'all',
  [switch]$Check  # only check the prerequisites, build nothing
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$bin = Join-Path $here '..\addons\town_window\bin'
$arches = if ($Arch -eq 'all') { @('x86_64', 'arm64') } else { @($Arch) }
$sconsVersion = '4.11.1'

function Fail([string]$msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }
function Step([string]$msg) { Write-Host "== $msg" -ForegroundColor Cyan }

# --- C++ tools and Windows SDK -------------------------------------------------------------
Step 'Checking the C++ tools'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) { Fail 'Visual Studio Build Tools are not installed (no vswhere.exe). See docs/windows/architecture.md.' }
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { Fail 'No Visual Studio install has the C++ x64 tools ("Desktop development with C++").' }
$msvc = Get-ChildItem (Join-Path $vs 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if (-not $msvc) { Fail "No MSVC toolset under $vs." }
foreach ($a in $arches) {
  $target = if ($a -eq 'x86_64') { 'x64' } else { 'arm64' }
  if (-not (Test-Path (Join-Path $msvc.FullName "bin\Hostx64\$target\cl.exe"))) {
    Fail "The C++ compiler for $a is missing (add ""MSVC ... $target build tools"" in Visual Studio Installer)."
  }
}
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\Include" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if (-not $sdk) { Fail 'No Windows SDK found (add a "Windows 11 SDK" in Visual Studio Installer).' }
Write-Host "   $vs"
Write-Host "   MSVC $($msvc.Name), Windows SDK $($sdk.Name)"

# --- godot-cpp ------------------------------------------------------------------------------
Step 'Checking godot-cpp'
if (-not (Test-Path (Join-Path $here 'godot-cpp\SConstruct'))) {
  if ($Check) { Fail 'godot-cpp is missing; run: git submodule update --init' }
  Write-Host '   fetching the submodule'
  git -C $here submodule update --init godot-cpp
  if ($LASTEXITCODE -ne 0) { Fail 'git submodule update failed.' }
}
Write-Host "   $(git -C (Join-Path $here 'godot-cpp') describe --tags 2>$null)"

# --- SCons ------------------------------------------------------------------------------------
Step 'Finding SCons'
$scons = $null
if ($env:SCONS -and (Test-Path $env:SCONS)) { $scons = @($env:SCONS) }
elseif (Get-Command scons -ErrorAction SilentlyContinue) { $scons = @((Get-Command scons).Source) }
else {
  $venvPy = Join-Path $here '.venv\Scripts\python.exe'
  if (-not (Test-Path $venvPy)) {
    if ($Check) { Write-Host '   not found; a build will install it into native\.venv'; $scons = $null }
    else {
      $py = Get-Command py, python -ErrorAction SilentlyContinue | Select-Object -First 1
      if (-not $py) { Fail 'Python is needed to install SCons (python.org or winget install Python.Python.3.12).' }
      Write-Host "   installing SCons $sconsVersion into native\.venv"
      & $py.Source -m venv (Join-Path $here '.venv')
      if ($LASTEXITCODE -ne 0) { Fail 'Could not create the virtual environment.' }
      & $venvPy -m pip install --quiet --disable-pip-version-check "scons==$sconsVersion"
      if ($LASTEXITCODE -ne 0) { Fail 'Could not install SCons.' }
    }
  }
  if (Test-Path $venvPy) { $scons = @($venvPy, '-m', 'SCons') }
}
if ($scons) { Write-Host "   $($scons -join ' ')" }
if ($Check) { Step 'Prerequisites are in place'; exit 0 }

# --- Build ----------------------------------------------------------------------------------
$machines = @{ 'x86_64' = 0x8664; 'arm64' = 0xAA64 }
foreach ($a in $arches) {
  Step "Building for $a"
  Push-Location $here
  try {
    $cmd = $scons[0]; $rest = @($scons | Select-Object -Skip 1)
    & $cmd @rest platform=windows target=template_release "arch=$a" -j $([Environment]::ProcessorCount)
    if ($LASTEXITCODE -ne 0) { Fail "The $a build failed." }
  } finally { Pop-Location }

  $dll = Join-Path $bin "town_window.windows.template_release.$a.dll"
  if (-not (Test-Path $dll)) { Fail "$dll was not written." }
  $bytes = [IO.File]::ReadAllBytes($dll)
  $pe = [BitConverter]::ToInt32($bytes, 0x3C)
  $machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
  if ($machine -ne $machines[$a]) { Fail ("{0} is for CPU 0x{1:X4}, not {2}." -f $dll, $machine, $a) }
  Write-Host ("   {0} ({1:N0} KB, {2})" -f (Split-Path $dll -Leaf), ((Get-Item $dll).Length / 1KB), $a) -ForegroundColor Green
}
Step 'Done. Commit the DLLs in app\windows\addons\town_window\bin\ with the source change.'

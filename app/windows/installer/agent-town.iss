; The agent-town for Windows installer (Inno Setup 6). scripts/release.ps1 builds it:
;   ISCC.exe /DAppVersion=1.0.0 /DSourceDir=<export folder> /DOutputDir=<folder> installer\agent-town.iss
; It installs for the current user only (no administrator prompt), into
; %LOCALAPPDATA%\Programs\agent-town-claude-code, with a Start menu shortcut and an uninstaller.
; Running a newer installer replaces the installed app; settings in %APPDATA%\agent-town-claude-code
; are kept.

#ifndef AppVersion
  #error AppVersion is not set (pass /DAppVersion=x.y.z)
#endif
#ifndef SourceDir
  #define SourceDir "..\build"
#endif
#ifndef OutputDir
  #define OutputDir "..\build\installer"
#endif

[Setup]
; The AppId identifies the app to Windows across versions: never change it.
AppId={{9E6BD3EB-CFC7-4F62-99C8-0C14483F9159}
AppName=agent-town
AppVersion={#AppVersion}
AppVerName=agent-town {#AppVersion}
AppPublisher=Samson Chen
AppPublisherURL=https://github.com/samsonchen/agent-town-claude-code
AppSupportURL=https://github.com/samsonchen/agent-town-claude-code/issues
AppUpdatesURL=https://github.com/samsonchen/agent-town-claude-code/releases
AppCopyright=Copyright 2026 Samson Chen. Apache License 2.0.
VersionInfoVersion={#AppVersion}.0
DefaultDirName={localappdata}\Programs\agent-town-claude-code
; Always this folder, also when upgrading a copy installed elsewhere ([InstallDelete] removes that one).
UsePreviousAppDir=no
DisableDirPage=yes
DefaultGroupName=agent-town
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Windows 10 is allowed but untested; Windows 11 is what the app is tested on.
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=agent-town-setup-{#AppVersion}
SetupIconFile=agent-town.ico
UninstallDisplayIcon={app}\agent-town.exe
UninstallDisplayName=agent-town
LicenseFile=..\..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; A running copy can't be closed by Windows' Restart Manager: asked to close, the app hides in the
; tray, so Setup reports it could not close it. Setup stops it itself instead (PrepareToInstall
; below), and "Open agent-town" at the end starts the new one.
CloseApplications=no
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\agent-town.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\town_window.windows.template_release.x86_64.dll"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
; Folders of versions before 1.0.3, which kept the app and its data under "agent-town": the old
; install (its exe, add-on and uninstaller), its settings and endpoint, and Godot's logs and shader
; cache. Everything now lives in the agent-town-claude-code folders, and settings start afresh.
Type: filesandordirs; Name: "{localappdata}\Programs\agent-town"
Type: filesandordirs; Name: "{userappdata}\agent-town"
Type: filesandordirs; Name: "{userappdata}\Godot\app_userdata\agent-town"

[Icons]
Name: "{autoprograms}\agent-town"; Filename: "{app}\agent-town.exe"

[Run]
Filename: "{app}\agent-town.exe"; Description: "Open agent-town"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop a running copy (it hides in the tray rather than quitting on a close request).
Filename: "{sys}\taskkill.exe"; Parameters: "/IM agent-town.exe /F"; Flags: runhidden; RunOnceId: "StopApp"

[UninstallDelete]
; The endpoint file of a copy that was stopped rather than quit, and Godot's logs and shader cache.
; settings.cfg is kept.
Type: files; Name: "{userappdata}\agent-town-claude-code\endpoint.json"
Type: filesandordirs; Name: "{userappdata}\agent-town-claude-code\logs"
Type: filesandordirs; Name: "{userappdata}\agent-town-claude-code\shader_cache"

[Registry]
; Settings → Open at login writes this value; the uninstaller removes it.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "agent-town-claude-code"; Flags: uninsdeletevalue dontcreatekey
; The Open at login value of versions before 1.0.3, which pointed at the old install folder.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "agent-town"; Flags: deletevalue dontcreatekey

[Code]
// Before the files are replaced: stop a running agent-town (the installed one; a copy run from
// Godot is a different program), and give Windows a moment to release its files.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM agent-town.exe /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if ResultCode = 0 then
    Sleep(1000);
  Result := '';
end;

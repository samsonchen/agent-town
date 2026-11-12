; The agent-town for Windows installer (Inno Setup 6). scripts/release.ps1 builds it:
;   ISCC.exe /DAppVersion=1.0.0 /DSourceDir=<export folder> /DOutputDir=<folder> installer\agent-town.iss
; It installs for the current user only (no administrator prompt), into
; %LOCALAPPDATA%\Programs\agent-town, with a Start menu shortcut and an uninstaller. Running a newer
; installer replaces the installed app; settings in %APPDATA%\agent-town are kept.

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
AppPublisherURL=https://github.com/samsonchen/agent-town
AppSupportURL=https://github.com/samsonchen/agent-town/issues
AppUpdatesURL=https://github.com/samsonchen/agent-town/releases
AppCopyright=Copyright 2026 Samson Chen. Apache License 2.0.
VersionInfoVersion={#AppVersion}.0
DefaultDirName={localappdata}\Programs\agent-town
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
; The app keeps running in the tray when its window is closed; a newer installer stops it first.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\agent-town.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\town_window.windows.template_release.x86_64.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\agent-town"; Filename: "{app}\agent-town.exe"

[Run]
Filename: "{app}\agent-town.exe"; Description: "Open agent-town"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop a running copy (it hides in the tray rather than quitting on a close request).
Filename: "{sys}\taskkill.exe"; Parameters: "/IM agent-town.exe /F"; Flags: runhidden; RunOnceId: "StopApp"

[UninstallDelete]
; The endpoint file of a copy that was stopped rather than quit.
Type: files; Name: "{userappdata}\agent-town\endpoint.json"

[Registry]
; Settings → Open at login writes this value; the uninstaller removes it.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "agent-town"; Flags: uninsdeletevalue dontcreatekey

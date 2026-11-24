; PIXELSHIFT Windows installer script (Inno Setup 6.3+)
; Build: iscc /DAppVersion=1.0.0 installer\pixelshift.iss
; Source: output of "flutter build windows --release"

#define AppName "PIXELSHIFT"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppPublisher "Furkan"
#define AppExeName "pixelshift.exe"
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{5D2F7A91-3C4B-4E8A-B6D1-9F0E2A7C4B18}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppCopyright=Copyright (C) 2026 {#AppPublisher}
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} Setup
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=PIXELSHIFT-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Kullanıcı projeleri %APPDATA% altında saklanır ve kaldırmada SİLİNMEZ.
Type: filesandordirs; Name: "{app}\PIXELSHIFT-Veri\gecici"

; ══════════════════════════════════════════════════════════════════════════════
; UnifiedShield Enterprise — Inno Setup installer for the FLUTTER Windows app
; Staged by scripts/build-windows-release.sh:
;   iscc setup_flutter.iss /DAppVersion=<ver> /DAppSource=staging
; The staging folder contains the complete flutter build (unified_shield.exe +
; DLLs + data) plus shield-daemon.exe (the Rust tunnel engine).
; ══════════════════════════════════════════════════════════════════════════════

#ifndef AppVersion
#define AppVersion "9.0.0-enterprise"
#endif
#ifndef AppSource
#define AppSource "staging"
#endif

#define AppName "UnifiedShield"
#define AppExeName "unified_shield.exe"

[Setup]
AppId={{8F3A2C1D-9E47-4B6A-B2D0-5C7E1A9F4A10}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion} — Enterprise
AppPublisher="UnifiedShield Enterprise"
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
OutputDir=Output
OutputBaseFilename=unifiedshield-{#AppVersion}-enterprise-windows-installer
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExeName}

; Language support (including Farsi/Persian for Iranian users)
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "farsi"; MessagesFile: "compiler:Languages\Farsi.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The complete Flutter runtime + the Rust daemon engine, staged by the build script
Source: "{#AppSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

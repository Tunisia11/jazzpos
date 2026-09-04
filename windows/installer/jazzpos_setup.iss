; =====================================================================
; JAZZ POS — INNO SETUP SCRIPT FOR WINDOWS POS RELEASES (RC1)
; Target: Windows 10/11 IoT Enterprise (POSBANK Apexa G / AnyPOS)
; =====================================================================

#define MyAppName "JAZZ POS"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "JazzPOS"
#define MyAppURL "https://jazzpos.local"
#define MyAppExeName "jazzpos.exe"
#define MyAppSourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{D37F8E8A-B26C-49E2-8BCF-7519E8F3C92B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\..\dist
OutputBaseFilename=JazzPOS_Setup_v{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "Démarrer JAZZ POS automatiquement au démarrage de Windows (Terminaux caisse)"; GroupDescription: "Options de démarrage:"

[Files]
; 1. Full application bundle (Executable, Flutter engine DLL, sqlite3.dll, plugins, and data folder)
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 2. Bundled Visual C++ 2015-2022 Redistributable for offline clean-machine installations
; Placed into redist/ before building installer. If absent, skipped gracefully.
#if FileExists("redist\vc_redist.x64.exe")
Source: "redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall; Check: VCRedistNeedsInstall
#endif

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; IconFilename: "{app}\{#MyAppExeName}"
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: autostart; IconFilename: "{app}\{#MyAppExeName}"

[Run]
; Install VC++ runtime if needed (exit codes 0=success, 1638=newer already present, 3010=reboot pending)
#if FileExists("redist\vc_redist.x64.exe")
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /passive /norestart"; Check: VCRedistNeedsInstall; StatusMsg: "Vérification des composants d'exécution Microsoft Visual C++..."
#endif

; Launch application at end of installation
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Detect if Visual C++ 2015-2022 Redistributable (x64) is already installed
function VCRedistNeedsInstall: Boolean;
var
  installed: Cardinal;
begin
  // Check Visual Studio 2015-2022 registry key for VC++ x64 runtime
  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', installed) then
  begin
    Result := (installed = 0);
  end
  else
  begin
    Result := True;
  end;
end;

// Critical Data Protection: Never delete store sales, database, or backups on uninstall
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    // Note: %APPDATA%\JazzPOS is deliberately preserved.
    // Retail sales history, tax audit logs, and backups remain intact.
  end;
end;

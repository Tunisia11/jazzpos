; =====================================================================
; JAZZ POS — MODERN BRANDED WINDOWS INSTALLER (VIREX ENTERPRISE EDITION)
; Target: Windows 10 & 11 (64-bit) — Retail & Fashion POS Terminals
; =====================================================================

#define MyAppName "Trace POS"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Virex"
#define MyAppPublisherFull "Virex Enterprise Solutions"
#define MyAppURL "https://virex.io"
#define MyAppSupportURL "https://virex.io/support"
#define MyAppExeName "jazzpos.exe"
#define MyAppSourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Unique application identity (preserved across JAZZ POS -> Trace POS upgrades)
AppId={{D37F8E8A-B26C-49E2-8BCF-7519E8F3C92B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion} (Édition Caisse)
AppPublisher={#MyAppPublisherFull}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppSupportURL}
AppUpdatesURL={#MyAppURL}
AppCopyright=© 2026 {#MyAppPublisherFull}. Tous droits réservés.
AppComments=Solution d'encaissement et de gestion commerciale pour le commerce de détail.

; Installation target directory (Non-admin AppData for single user, or Program Files if elevated)
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UsePreviousAppDir=no
UsePreviousGroup=no
AllowNoIcons=yes
OutputDir=..\..\dist
OutputBaseFilename=Trace-POS-Setup-x64

; Visual Branding & Assets (Virex Enterprise Design)
SetupIconFile=assets\installer_icon.ico
WizardImageFile=assets\wizard_hero_100.bmp,assets\wizard_hero_125.bmp,assets\wizard_hero_150.bmp,assets\wizard_hero_200.bmp
WizardSmallImageFile=assets\wizard_small_100.bmp,assets\wizard_small_125.bmp,assets\wizard_small_150.bmp,assets\wizard_small_200.bmp
WizardStyle=modern
DisableWelcomePage=no
DisableFinishedPage=no

; Compression & Optimization
Compression=lzma2/ultra64
SolidCompression=yes

; Architecture & Permissions
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
; --- French UI Copywriting (Natural, Professional, Trustworthy) ---
french.SetupAppTitle=Installation de Trace POS
french.SetupWindowTitle=Assistant d'installation Trace POS — Par Virex
french.SelectLanguageTitle=Langue de l'installation
french.SelectLanguageLabel=Veuillez choisir la langue d'installation de Trace POS :

; Welcome Page
french.WelcomeLabel1=Bienvenue dans l'installation de Trace POS
french.WelcomeLabel2=Trace POS est votre solution complète de caisse et de gestion commerciale conçue pour fonctionner localement, de manière rapide, fiable et sécurisée.%n%n• Conçu pour le commerce de détail et le prêt-à-porter sur Windows 10 et 11%n• Fonctionnement 100%% autonome (Hors-Ligne) même en cas de panne réseau%n• Reconnaissance immédiate de votre matériel de caisse (imprimante, tiroir, lecteur)%n• Sécurité garantie : les données existantes sont intégralement conservées lors des mises à jour.%n%nCliquez sur Suivant pour continuer.

; Destination Directory
french.WizardSelectDir=Dossier d'installation
french.SelectDirDesc=Choisissez l'emplacement où sera installé Trace POS sur ce terminal.
french.SelectDirLabel3=L'assistant va installer l'application dans le dossier suivant :
french.SelectDirBrowseLabel=Cliquez sur Suivant pour accepter cet emplacement, ou sur Parcourir pour en choisir un autre.

; Tasks Selection
french.WizardSelectTasks=Options du terminal
french.SelectTasksDesc=Personnalisez les raccourcis et le comportement au démarrage.
french.SelectTasksLabel2=Sélectionnez les options souhaitées pour ce poste d'encaissement :

; Ready to Install
french.WizardReady=Prêt pour l'installation
french.ReadyLabel1=L'assistant dispose de toutes les informations pour installer Trace POS sur votre poste.
french.ReadyLabel2a=Cliquez sur Installer pour débuter le déploiement.%n%n(Vos ventes précédentes, votre base de données et vos sauvegardes restent strictement préservées.)
french.ReadyLabel2b=Cliquez sur Installer pour procéder au déploiement.

; Installing Progress
french.WizardInstalling=Installation en cours...
french.InstallingLabel=Veuillez patienter pendant l'installation et la configuration de Trace POS sur votre ordinateur...

; Completion Page
french.FinishedHeadingLabel=Installation de Trace POS réussie !
french.FinishedLabel=L'installation est terminée avec succès. Trace POS est maintenant configuré et prêt à être utilisé sur votre terminal.%n%nVos données de caisse, votre catalogue et vos sauvegardes sont enregistrés de façon sécurisée sur cet ordinateur.
french.FinishedLabelNoIcons=L'installation est terminée avec succès. Trace POS est maintenant prêt pour une utilisation immédiate.
french.ClickFinish=Cliquez sur Terminer pour lancer votre session d'encaissement.

; --- English UI Copywriting ---
english.SetupAppTitle=Trace POS Setup
english.SetupWindowTitle=Trace POS Setup Wizard — By Virex
english.WelcomeLabel1=Welcome to Trace POS Setup
english.WelcomeLabel2=Trace POS is a professional point-of-sale and retail management solution engineered to operate locally with high speed, reliability, and security.%n%n• Tailored for apparel, fashion, and retail stores on Windows 10 and 11%n• 100%% offline-first architecture resilient against network downtime%n• Plug-and-play POS hardware integration (receipt printers, cash drawers, scanners)%n• Data safety guaranteed: existing databases and backups are preserved during updates.%n%nClick Next to proceed with setup.
english.WizardSelectDir=Installation Folder
english.SelectDirDesc=Select the destination folder for Trace POS on this terminal.
english.WizardSelectTasks=Terminal Options
english.SelectTasksDesc=Configure shortcuts and point-of-sale startup settings.
english.WizardReady=Ready to Install
english.ReadyLabel1=Setup is ready to install Trace POS on your computer.
english.ReadyLabel2a=Click Install to begin installation. Existing sales history and databases will remain safe.
english.WizardInstalling=Installing Trace POS...
english.InstallingLabel=Please wait while setup deploys Trace POS on your computer...
english.FinishedHeadingLabel=Trace POS Setup Completed
english.FinishedLabel=Trace POS has been successfully installed on your computer.%n%nYour point-of-sale system is ready for store operation.%n%nStore sales, catalog, and backups are safely stored locally on this terminal.
english.ClickFinish=Click Finish to launch Trace POS.

[Tasks]
Name: "desktopicon"; Description: "Créer une icône d'accès rapide sur le Bureau (Recommandé)"; GroupDescription: "Raccourcis :"
Name: "autostart"; Description: "Démarrer automatiquement Trace POS à l'ouverture de Windows (Terminaux de caisse dédiés)"; GroupDescription: "Démarrage automatique :"

[Files]
; 1. Full application bundle (Executable, Flutter engine DLL, sqlite3.dll, plugins, and data folder)
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 2. Bundled Visual C++ 2015-2022 Redistributable for offline clean-machine installations
#if FileExists("redist\vc_redist.x64.exe")
Source: "redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall; Check: VCRedistNeedsInstall
#endif

[InstallDelete]
Type: files; Name: "{autodesktop}\JAZZ POS.lnk"
Type: files; Name: "{userstartup}\JAZZ POS.lnk"
Type: filesandordirs; Name: "{userprograms}\JAZZ POS"
Type: filesandordirs; Name: "{localappdata}\Programs\JAZZ POS"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Comment: "Point de Vente Trace POS"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; IconFilename: "{app}\{#MyAppExeName}"; Comment: "Point de Vente Trace POS"
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: autostart; IconFilename: "{app}\{#MyAppExeName}"; Comment: "Démarrage automatique Trace POS"

[Run]
; Install VC++ runtime if needed (exit codes 0=success, 1638=newer already present, 3010=reboot pending)
#if FileExists("redist\vc_redist.x64.exe")
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /passive /norestart"; Check: VCRedistNeedsInstall; StatusMsg: "Vérification des composants d'exécution Microsoft Visual C++..."
#endif

; Launch application at end of installation
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer Trace POS immédiatement"; Flags: nowait postinstall skipifsilent

[Code]
// Detect if Visual C++ 2015-2022 Redistributable (x64) is already installed
function VCRedistNeedsInstall: Boolean;
var
  installed: Cardinal;
begin
  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', installed) then
  begin
    Result := (installed = 0);
  end
  else
  begin
    Result := True;
  end;
end;

// Visual & Typography Enhancements for Modern Wizard
procedure InitializeWizard;
var
  TrustLabel: TLabel;
begin
  // Refine Welcome and Finished page typography
  WizardForm.WelcomeLabel1.Font.Size := 13;
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.FinishedHeadingLabel.Font.Size := 13;
  WizardForm.FinishedHeadingLabel.Font.Style := [fsBold];

  // Add subtle trust & publisher badge on Welcome Page
  TrustLabel := TLabel.Create(WizardForm);
  TrustLabel.Parent := WizardForm.WelcomePage;
  TrustLabel.Left := WizardForm.WelcomeLabel2.Left;
  TrustLabel.Top := WizardForm.WelcomePage.Height - 32;
  TrustLabel.Width := WizardForm.WelcomeLabel2.Width;
  TrustLabel.Caption := 'Solution éditée par Virex • Données stockées localement en toute sécurité';
  TrustLabel.Font.Size := 8;
  TrustLabel.Font.Color := $007A6548; // Subtle muted slate/navy
end;

// Post-install cleanup: remove legacy shortcuts if upgrading to avoid duplicates
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    DeleteFile(ExpandConstant('{autodesktop}\JAZZ POS.lnk'));
    DeleteFile(ExpandConstant('{commondesktop}\JAZZ POS.lnk'));
  end;
end;

// Critical Data Protection: Never delete store sales, database, or backups on uninstall
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    // Explicit confirmation: Client retail data under %APPDATA%\JazzPOS\JAZZ POS
    // (sqlite database, sales history, fiscal Z reports, and local backups)
    // is permanently protected and never removed by uninstaller.
  end;
end;

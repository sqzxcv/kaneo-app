; Compile with .github/scripts/package_desktop.py after building and copying the VC runtime.
[Setup]
AppId={{34354BF4-CA0E-462B-A86E-17B30FA3EA6D}
AppName=Kaneo
AppVersion={#AppVersion}+{#BuildNumber}
VersionInfoVersion={#AppVersion}.{#BuildNumber}
AppPublisher=Kaneo App contributors
DefaultDirName={localappdata}\Programs\Kaneo
DefaultGroupName=Kaneo
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\kaneo_app.exe
CloseApplications=yes
RestartApplications=no

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Kaneo"; Filename: "{app}\kaneo_app.exe"; WorkingDir: "{app}"; AppUserModelID: "Kaneo.App"; AppUserModelToastActivatorCLSID: "90e2e9bd-9f59-4fd7-8bbb-fb71af3f631e"

[Run]
Filename: "{app}\kaneo_app.exe"; Description: "Launch Kaneo"; Flags: nowait postinstall skipifsilent

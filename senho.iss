[Setup]
AppName=Senhorita
AppVersion=1.1.10
DefaultDirName={pf}\Senhorita
DefaultGroupName=Senhorita
OutputBaseFilename=Instalador_Senhorita
Compression=lzma
SolidCompression=yes
DisableWelcomePage=no
DisableFinishedPage=no
OutputDir=C:\Users\DH GAMER\senhorita\instalador
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=C:\Users\DH GAMER\senhorita\assets\senhorita.ico

[Files]
Source: "C:\Users\DH GAMER\senhorita\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Senhorita"; Filename: "{app}\senhorita.exe"
Name: "{group}\Desinstalar Senhorita"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Senhorita"; Filename: "{app}\senhorita.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na área de trabalho"; GroupDescription: "Opções adicionais:"

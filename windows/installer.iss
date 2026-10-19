; Установщик «Сократа» для Windows x64 (Inno Setup 6).
; Сборка: SOKRAT_VERSION=1.2.0 ISCC windows\installer.iss  (из корня репозитория)

#define AppVersion GetEnv("SOKRAT_VERSION")
#if AppVersion == ""
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6F1C2B9E-5A3D-4C8E-9B7A-50C0A7E5D1F2}
AppName=Сократ — нейропереводчик
AppVersion={#AppVersion}
AppVerName=Сократ {#AppVersion}
AppPublisher=LuSoft
AppPublisherURL=mailto:armenoid@gmail.com
AppSupportURL=mailto:armenoid@gmail.com
VersionInfoVersion={#AppVersion}
VersionInfoCompany=LuSoft
VersionInfoDescription=Сократ — нейропереводчик
; Установка для текущего пользователя: права администратора не нужны.
PrivilegesRequired=lowest
DefaultDirName={autopf}\Sokrat
DefaultGroupName=Сократ
DisableProgramGroupPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build
OutputBaseFilename=Sokrat-Setup-x64
SetupIconFile=assets\sokrat.ico
UninstallDisplayIcon={app}\Sokrat.exe
UninstallDisplayName=Сократ — нейропереводчик
WizardStyle=modern
; Модель почти не сжимается — упаковываем её без сжатия, остальное быстрым LZMA2.
Compression=lzma2/fast
SolidCompression=no
CloseApplications=force
RestartApplications=no

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "autostart"; Description: "Запускать «Сократ» при входе в Windows"; GroupDescription: "Дополнительно:"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\win\Sokrat\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "..\model\*"; DestDir: "{app}\model"; Flags: recursesubdirs createallsubdirs ignoreversion nocompression

[Icons]
Name: "{group}\Сократ"; Filename: "{app}\Sokrat.exe"
Name: "{group}\Удалить «Сократ»"; Filename: "{uninstallexe}"
Name: "{userdesktop}\Сократ"; Filename: "{app}\Sokrat.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Sokrat"; ValueData: """{app}\Sokrat.exe"""; Tasks: autostart; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Sokrat.exe"; Description: "{cm:LaunchProgram,Сократ}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/IM Sokrat.exe /F"; Flags: runhidden; RunOnceId: "StopSokrat"

[UninstallDelete]
Type: filesandordirs; Name: "{localappdata}\Sokrat"

#define MyAppName "ClashMiao"
#define MyAppPublisher "ClashMiao"
#define MyAppExeName "clashmiao.exe"
#define MyAppVersion GetEnv("CLASHMIAO_VERSION")
#if MyAppVersion == ""
  #define MyAppVersion "0.1.0"
#endif
#define RepoRoot AddBackslash(SourcePath) + "..\..\.."

[Setup]
AppId={{6D63B72C-3FC9-496B-8C72-55A1B9C3DD10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#RepoRoot}\build\installer
OutputBaseFilename=ClashMiao-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "autostart"; Description: "Launch {#MyAppName} automatically when Windows starts"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#RepoRoot}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; 勾选了 "autostart" task 才写：HKCU 而非 HKLM，因为 PrivilegesRequired=lowest
; 装的是当前用户级安装，不能假定有管理员权限写 HKLM。ValueName 用 MyAppName、
; ValueData 用不带引号的裸路径——跟应用内设置页"开机自启动"开关背后的
; launch_at_startup 包（lib/core/auto_start/auto_start_notifier.dart 的
; WindowsAutoStartBackend）写法保持一致，这样安装时勾选的效果和运行时手动
; 打开这个开关是同一个注册表键值，设置页读到的开关状态不会和安装器打架。
; uninsdeletevalue 保证卸载时把这个值删掉，不留垃圾。
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

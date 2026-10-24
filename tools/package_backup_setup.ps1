# Create one self-contained installer for the customer's existing Windows VDS.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$payload=@{}
foreach($name in @('backup-common.ps1','install-backup.ps1','run-backup.ps1','verify-backup.ps1')) {
    $file=Join-Path $repo ('backend\deploy\'+$name)
    $tokens=$null;$errors=$null
    [Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors) | Out-Null
    if($errors) { throw ('Invalid PowerShell: '+$name) }
    $payload[$name]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($file))
}
$json=$payload | ConvertTo-Json -Compress
$base64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
$template=@'
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'PowerShelli yonetici olarak acin.' }
$directory='C:\ProgramData\santiye\backup'
if(!(Test-Path -LiteralPath 'C:\ProgramData\santiye\settings.json')) { throw 'Santiye sunucu ayarlari bulunamadi.' }
New-Item -ItemType Directory -Path $directory -Force | Out-Null
& icacls.exe $directory /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if($LASTEXITCODE -ne 0) { throw 'Yedekleme klasoru izinleri uygulanamadi.' }
$payload=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__')) | ConvertFrom-Json
foreach($entry in $payload.PSObject.Properties) {
    if($entry.Name -cnotmatch '^(backup-common|install-backup|run-backup|verify-backup)\.ps1$') { throw 'Gecersiz arac adi.' }
    [IO.File]::WriteAllBytes((Join-Path $directory $entry.Name),[Convert]::FromBase64String($entry.Value))
}
& (Join-Path $directory 'install-backup.ps1')
'@
$output=Join-Path $repo 'output\backend\yedek.ps1'
New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
[IO.File]::WriteAllText($output,$template.Replace('__PAYLOAD__',$base64),(New-Object Text.UTF8Encoding($true)))
Write-Output $output

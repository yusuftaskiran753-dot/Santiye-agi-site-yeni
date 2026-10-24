param(
    [string]$SettingsPath='C:\ProgramData\santiye\settings.json',
    [string]$InstallDirectory='C:\ProgramData\santiye\backup',
    [string]$BackupRoot='C:\ProgramData\santiye\backups',
    [string]$PostgresBin='C:\Program Files\PostgreSQL\17\bin',
    [ValidateRange(7,365)][int]$RetentionDays=14,
    [string]$DailyAt='03:00'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'backup-common.ps1')
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open PowerShell as Administrator.' }
if(!(Test-Path -LiteralPath $SettingsPath)) { throw 'External settings.json not found.' }
if($DailyAt -cnotmatch '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$') { throw 'DailyAt must be HH:mm.' }
$install=[IO.Path]::GetFullPath($InstallDirectory)
$root=[IO.Path]::GetFullPath($BackupRoot)
$settingsDirectory=Split-Path ([IO.Path]::GetFullPath($SettingsPath)) -Parent
foreach($path in @($install,$root)) {
    $null=Assert-BackupChild $settingsDirectory $path
    if($path.StartsWith('C:\inetpub\',[StringComparison]::OrdinalIgnoreCase) -or $path -eq [IO.Path]::GetPathRoot($path)) { throw 'Backup files must be outside the web root and a drive root.' }
    Protect-BackupDirectory $path
}
$destination=Join-Path $install 'backup-config.json'
$key=Join-Path $install 'recovery.key'
if(!(Test-Path -LiteralPath $key)) {
    if(Get-ChildItem -LiteralPath $root -Filter '*.enc' -File | Select-Object -First 1) { throw 'Recovery key is missing for existing archives. Do not replace it.' }
    $bytes=New-Object byte[] 64; $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    try {$rng.GetBytes($bytes); [IO.File]::WriteAllBytes($key,$bytes)} finally {$rng.Dispose(); [Array]::Clear($bytes,0,$bytes.Length)}
}
foreach($file in @('backup-common.ps1','run-backup.ps1','verify-backup.ps1')) {
    $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $file)); $target=Join-Path $install $file
    if($source -ne $target) { Copy-Item -LiteralPath $source -Destination $target -Force }
}
Write-BackupJson $destination @{SettingsPath=[IO.Path]::GetFullPath($SettingsPath);BackupRoot=$root;PostgresBin=$PostgresBin;RecoveryKeyPath=$key;RetentionDays=$RetentionDays}
# First backup must really restore successfully before enabling its recurring task.
& (Join-Path $install 'run-backup.ps1') -ConfigPath $destination
$taskName='SantiyeAgi-DailyBackup'
$taskAction=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $install 'run-backup.ps1')+'" -ConfigPath "'+$destination+'"')
$trigger=New-ScheduledTaskTrigger -Daily -At $DailyAt
$taskSettings=New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 4)
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($existing -and ($existing.Principal.UserId -notin @('SYSTEM','S-1-5-18','NT AUTHORITY\SYSTEM') -or $existing.Actions.Execute -notmatch 'powershell')) { throw 'A different task already uses the backup task name.' }
Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Settings $taskSettings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
$previousRun=(Get-ScheduledTaskInfo -TaskName $taskName).LastRunTime
Start-ScheduledTask -TaskName $taskName
$deadline=(Get-Date).AddMinutes(3)
$verified=$false
do {
    Start-Sleep -Seconds 2
    $info=Get-ScheduledTaskInfo -TaskName $taskName
    $task=Get-ScheduledTask -TaskName $taskName
    if($info.LastRunTime -gt $previousRun -and $task.State -eq 'Ready') {
        if($info.LastTaskResult -ne 0) { throw ('Scheduled backup failed under SYSTEM. Task result: '+$info.LastTaskResult) }
        $status=Get-Content -LiteralPath (Join-Path $root 'last-success.json') -Raw | ConvertFrom-Json
        if([DateTime]::Parse($status.completed_utc).ToUniversalTime() -lt $info.LastRunTime.ToUniversalTime()) { throw 'Scheduled task did not write a fresh success record.' }
        $verified=$true; break
    }
} while((Get-Date) -lt $deadline)
if(!$verified) { throw 'Scheduled backup verification timed out. Inspect the task before considering setup complete.' }
Write-Output ('Her gun '+$DailyAt+' icin otomatik yedek kuruldu. Yerel saklama: '+$RetentionDays+' gun.')
Write-Output 'SYSTEM gorevi de calisti; gercek geri yukleme kontrolu gecti.'
Write-Output ('Kurtarma anahtarini silmeyin; eski yedekler icin gereklidir: '+$key)
Write-Output 'Musteri tercihi: sunucu disi kopya kapali.'

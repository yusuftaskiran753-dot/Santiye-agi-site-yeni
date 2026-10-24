param(
    [Parameter(Mandatory=$true)][string]$ArchivePath,
    [string]$ConfigPath='C:\ProgramData\santiye\backup\backup-config.json'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'backup-common.ps1')
$config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$root=[IO.Path]::GetFullPath($config.BackupRoot)
$work=Assert-BackupChild $root (Join-Path $root ('verify-'+[guid]::NewGuid().ToString('N')))
Protect-BackupDirectory $work
$previous=$env:PGPASSFILE
try {
    $connection=Read-BackupConnection $config.SettingsPath
    $pass=Join-Path $work 'connection.pgpass'; New-BackupPgPass $connection $pass; $env:PGPASSFILE=$pass
    $zip=Join-Path $work 'backup.zip'; Unprotect-BackupArchive $ArchivePath $zip $config.RecoveryKeyPath
    $payload=Join-Path $work 'payload'; Expand-Archive -LiteralPath $zip -DestinationPath $payload
    $manifest=Get-Content -LiteralPath (Join-Path $payload 'manifest.json') -Raw | ConvertFrom-Json
    foreach($entry in $manifest.files) {
        $file=Assert-BackupChild $payload (Join-Path $payload $entry.path)
        if((Get-FileHash -LiteralPath $file).Hash -cne $entry.sha256) { throw 'Backup integrity mismatch.' }
    }
    $result=Test-BackupRestore $config.PostgresBin $connection (Join-Path $payload 'database.backup')
    Write-Output ('Sifreli yedek acildi; ayri ve yeni test veritabanina geri yuklendi; tablo: '+$result.tables+'. Canli veritabanina yazilmadi.')
} finally {
    $env:PGPASSFILE=$previous
    $safe=Assert-BackupChild $root $work
    if((Get-Item -LiteralPath $safe).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing linked workspace cleanup.' }
    Remove-Item -LiteralPath $safe -Recurse -Force
}

param([string]$ConfigPath = 'C:\ProgramData\santiye\backup\backup-config.json')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'backup-common.ps1')
$config=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$root=[IO.Path]::GetFullPath($config.BackupRoot)
Protect-BackupDirectory $root
$stage=Assert-BackupChild $root (Join-Path $root ('work-'+[guid]::NewGuid().ToString('N')))
Protect-BackupDirectory $stage
$previousPass=$env:PGPASSFILE
$lock=$null; $success=$false; $outputFile=$null
try {
    $lock=[IO.File]::Open((Join-Path $root 'backup.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $connection=Read-BackupConnection $config.SettingsPath
    $pass=Join-Path $stage 'connection.pgpass'; New-BackupPgPass $connection $pass; $env:PGPASSFILE=$pass
    $payload=Join-Path $stage 'payload'; New-Item -ItemType Directory -Path $payload | Out-Null
    $argsBase=@("--host=$($connection.Host)","--port=$($connection.Port)","--username=$($connection.User)",'--no-password')
    $dump=Join-Path $payload 'database.backup'
    $null=Invoke-BackupPg $config.PostgresBin 'pg_dump' ($argsBase+@('--format=custom',"--file=$dump",$connection.Database))
    # Photos are bytea in PostgreSQL and are included in this dump.
    Copy-Item -LiteralPath $config.SettingsPath -Destination (Join-Path $payload 'settings.json')
    $keys=[string]$connection.Settings.DataProtection.KeysPath
    if (!$keys -or !(Test-Path -LiteralPath $keys -PathType Container)) { throw 'Data Protection keys directory missing.' }
    if (!(Get-ChildItem -LiteralPath $keys -Filter '*.xml' -File | Select-Object -First 1)) { throw 'Data Protection key ring is empty.' }
    Copy-Item -LiteralPath $keys -Destination (Join-Path $payload 'data-protection-keys') -Recurse
    $privateFiles=@(
        [string]$connection.Settings.Push.Firebase.ServiceAccountPath,
        [string]$connection.Settings.Billing.GoogleServiceAccountFile,
        [string]$connection.Settings.Billing.ApplePrivateKeyFile
    ) | Where-Object { $_ }
    $references=@(); $index=0
    foreach($file in $privateFiles) {
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw 'A configured service credential file is missing.' }
        $relative='service-key-'+$index+[IO.Path]::GetExtension($file)
        Copy-Item -LiteralPath $file -Destination (Join-Path $payload $relative)
        $references+=@{original_path=$file;backup_file=$relative}; $index++
    }
    $manifest=@{format=1;created_utc=[DateTime]::UtcNow.ToString('o');database=$connection.Database;service_files=$references;data_protection_source=$keys;files=@()}
    $manifest.files=@(Get-ChildItem -LiteralPath $payload -File -Recurse | ForEach-Object {
        @{path=$_.FullName.Substring($payload.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
    Write-BackupJson (Join-Path $payload 'manifest.json') $manifest
    $zip=Join-Path $stage 'payload.zip'
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zip
    $name='santiye-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.enc'
    $outputFile=Assert-BackupChild $root (Join-Path $root $name)
    Protect-BackupArchive $zip $outputFile $config.RecoveryKeyPath
    # Validate the encrypted deliverable, not only the unencrypted working copy.
    $verifiedZip=Join-Path $stage 'verified.zip'
    Unprotect-BackupArchive $outputFile $verifiedZip $config.RecoveryKeyPath
    if((Get-FileHash $verifiedZip).Hash -cne (Get-FileHash $zip).Hash) { throw 'Encrypted backup round-trip mismatch.' }
    $verified=Join-Path $stage 'verified'; Expand-Archive -LiteralPath $verifiedZip -DestinationPath $verified
    foreach($entry in $manifest.files) {
        $target=Assert-BackupChild $verified (Join-Path $verified $entry.path)
        if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $entry.sha256) { throw 'Backup file integrity mismatch.' }
    }
    $restore=Test-BackupRestore $config.PostgresBin $connection (Join-Path $verified 'database.backup')
    Write-BackupJson (Join-Path $root 'last-success.json') @{completed_utc=[DateTime]::UtcNow.ToString('o');file=$name;restore=$restore;offsite='disabled_by_owner';sha256=(Get-FileHash -LiteralPath $outputFile).Hash}
    $success=$true
    # Retain only this tool's encrypted files. Never recursively purge a computed directory.
    $cutoff=[DateTime]::UtcNow.AddDays(-[int]$config.RetentionDays)
    Get-ChildItem -LiteralPath $root -File -Filter 'santiye-*.enc' | Where-Object { $_.Name -cmatch '^santiye-[0-9]{8}-[0-9]{6}-[0-9a-f]{32}\.enc$' -and $_.LastWriteTimeUtc -lt $cutoff -and $_.FullName -ne $outputFile } | ForEach-Object {
        $safe=Assert-BackupChild $root $_.FullName; Remove-Item -LiteralPath $safe
    }
    Write-Output ('Yerel yedek ve ayri test veritabanina geri yukleme basarili. Tablo: '+$restore.tables+'. Sunucu disi kopya kapali.')
} catch {
    Write-BackupJson (Join-Path $root 'last-failure.json') @{failed_utc=[DateTime]::UtcNow.ToString('o');message='Backup or restore verification failed. Run the task manually to diagnose.'}
    throw
} finally {
    $env:PGPASSFILE=$previousPass
    if($lock) { $lock.Dispose() }
    # Stage can contain private settings and DB data. Check absolute bounds before deleting.
    $safe=Assert-BackupChild $root $stage
    if((Get-Item -LiteralPath $safe).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing to delete a linked staging directory.' }
    Remove-Item -LiteralPath $safe -Recurse -Force
    if(!$success -and $outputFile -and (Test-Path -LiteralPath $outputFile)) {
        $safeFile=Assert-BackupChild $root $outputFile; Remove-Item -LiteralPath $safeFile
    }
}

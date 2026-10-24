param(
    [string]$PostgresBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$Database = 'santiye',
    [string]$DatabaseUser = 'postgres',
    [int]$Port = 5432,
    [string]$BackupDirectory = 'C:\SantiyeBackups'
)
$ErrorActionPreference = 'Stop'
if ($Database -notmatch '^[A-Za-z0-9_]+$') { throw 'Veritabanı adı geçersiz.' }
# Zamanlanmış görev için Windows hesabına ait pgpass.conf kullanın; parola bu betiğe yazılmaz.
New-Item -ItemType Directory -Force -Path $BackupDirectory | Out-Null
$file = Join-Path $BackupDirectory ($Database + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.backup')
& (Join-Path $PostgresBin 'pg_dump.exe') --host=127.0.0.1 "--port=$Port" "--username=$DatabaseUser" --no-password --format=custom "--file=$file" $Database
if ($LASTEXITCODE -ne 0) { throw 'Yedek alınamadı; zamanlanmış görev hesabının pgpass.conf dosyasını kontrol edin.' }
& (Join-Path $PostgresBin 'pg_restore.exe') --list $file | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Yedek arşivi doğrulanamadı.' }
Write-Output "Yedek hazır: $file. DataProtection keys klasörünü de güvenli yedekleyin."

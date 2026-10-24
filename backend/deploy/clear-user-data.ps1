param(
    [string]$SettingsPath = 'C:\ProgramData\santiye\settings.json',
    [string]$SitePath = 'C:\inetpub\wwwroot\santiye',
    [string]$PostgresBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$BackupDirectory = 'C:\ProgramData\santiye\account-reset-backups',
    [switch]$Execute
)
# Yalniz sunucuda yonetici tarafindan calistirilir. Internet API'si eklemez.
$ErrorActionPreference = 'Stop'
$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
$connection = New-Object System.Data.Common.DbConnectionStringBuilder
$connection.set_ConnectionString($settings.ConnectionStrings.Postgres)
function ConnectionValue([string[]]$Names, [string]$Default = '') {
    foreach ($name in $Names) { if ($connection.ContainsKey($name)) { return [string]$connection[$name] } }
    return $Default
}
$dbHost = ConnectionValue @('Host', 'Server')
if ($dbHost -notin @('127.0.0.1', 'localhost', '::1')) { throw 'Bu arac yalniz sunucudaki yerel PostgreSQL icindir.' }
$database = ConnectionValue @('Database', 'Initial Catalog')
if ([string]::IsNullOrWhiteSpace($database)) { throw 'Veritabani adi bulunamadi.' }
$psql = Join-Path $PostgresBin 'psql.exe'
$dump = Join-Path $PostgresBin 'pg_dump.exe'
$restore = Join-Path $PostgresBin 'pg_restore.exe'
foreach ($file in @($psql, $dump, $restore)) { if (!(Test-Path -LiteralPath $file)) { throw 'PostgreSQL 17 araclari bulunamadi.' } }
$previous = @{}
foreach ($name in @('PGHOST','PGPORT','PGDATABASE','PGUSER','PGPASSWORD','PGCONNECT_TIMEOUT')) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$maintenance = Join-Path ([IO.Path]::GetFullPath($SitePath)) 'app_offline.htm'
$createdMaintenance = $false
$sqlFile = $null
try {
    $env:PGHOST = $dbHost
    $env:PGPORT = ConnectionValue @('Port') '5432'
    $env:PGDATABASE = $database
    $env:PGUSER = ConnectionValue @('Username', 'User ID', 'UserId', 'User Name')
    $env:PGPASSWORD = ConnectionValue @('Password', 'Pwd')
    $env:PGCONNECT_TIMEOUT = '10'
    $summarySql = 'SELECT json_build_object(''accounts'', (SELECT count(*) FROM santiye."Users"), ''listings'', (SELECT count(*) FROM santiye."Listings"), ''deals'', (SELECT count(*) FROM santiye."Deals"))::text;'
    $before = $summarySql | & $psql -X -w -t -A -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw 'Hesap sayilari okunamadi; hicbir veri silinmedi.' }
    Write-Output "Veritabani: $database / once: $before"
    if (!$Execute) { Write-Output 'Yalniz inceleme yapildi. Yedek alip tum hesaplari silmek icin -Execute kullanilir.'; return }
    if (!(Test-Path -LiteralPath (Join-Path $SitePath 'SantiyeAgi.Api.dll'))) { throw 'SitePath API yayin klasoru olmali.' }
    if (Test-Path -LiteralPath $maintenance) { throw 'Mevcut app_offline.htm bulundu. Once onceki yayin islemini tamamlayin.' }
    New-Item -ItemType Directory -Force -Path $BackupDirectory | Out-Null
    $operatorSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & icacls.exe $BackupDirectory /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "*${operatorSid}:(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Yedek klasoru izinleri ayarlanamadi; hicbir veri silinmedi.' }
    [IO.File]::WriteAllText($maintenance, 'Hesap verileri yenileniyor.')
    $createdMaintenance = $true
    Start-Sleep -Seconds 30
    $backup = Join-Path $BackupDirectory ('before-account-reset-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N') + '.backup')
    & $dump -w --format=custom "--file=$backup"
    if ($LASTEXITCODE -ne 0) { throw 'Yedek alinamadi; hicbir veri silinmedi.' }
    & $restore --list $backup | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Yedek arsivi okunamadi; hicbir veri silinmedi.' }
    # Baska uygulamalara ait semalara zincirleme silme yapma.
    $sql = @'
BEGIN;
SET LOCAL lock_timeout = '10s';
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint k
    JOIN pg_class p ON p.oid=k.confrelid JOIN pg_namespace pn ON pn.oid=p.relnamespace
    JOIN pg_class c ON c.oid=k.conrelid JOIN pg_namespace cn ON cn.oid=c.relnamespace
    WHERE k.contype='f' AND pn.nspname='santiye' AND cn.nspname<>'santiye'
  ) THEN RAISE EXCEPTION 'Baska semadan baglanti var; temizlik iptal edildi.'; END IF;
END $$;
TRUNCATE TABLE santiye."Users" CASCADE;
TRUNCATE TABLE santiye."PhoneChallenges";
COMMIT;
'@
    $sqlFile = Join-Path $BackupDirectory ('account-reset-' + [Guid]::NewGuid().ToString('N') + '.sql')
    [IO.File]::WriteAllText($sqlFile, $sql, (New-Object Text.UTF8Encoding($false)))
    & $psql -X -w -v ON_ERROR_STOP=1 -f $sqlFile
    if ($LASTEXITCODE -ne 0) { throw 'Silme islemi tamamlanamadi; islem geri alindi.' }
    $after = $summarySql | & $psql -X -w -t -A -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw 'Silme sonrasi sayim okunamadi; yedek yolunu koruyun.' }
    Write-Output "Sonra: $after"
    Write-Output "Yedek: $backup"
    Write-Output 'Tum hesaplar ve bagli ilan/anlasma/oturum verileri temizlendi. API semasi ve migration gecmisi korundu.'
} finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
    $settings = $null; $connection = $null
    if ($sqlFile -and (Test-Path -LiteralPath $sqlFile)) { Remove-Item -LiteralPath $sqlFile }
    if ($createdMaintenance) { Remove-Item -LiteralPath $maintenance }
}

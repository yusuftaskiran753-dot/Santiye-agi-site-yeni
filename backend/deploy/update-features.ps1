param([string]$ExpectedZipHash = '')
$ErrorActionPreference='Stop'
$directory='C:\ProgramData\santiye'
$site='C:\inetpub\wwwroot\santiye'
$settings=Join-Path $directory 'settings.json'
$zip=Join-Path $directory 'SantiyeAgi-Backend-IIS.zip'
$offline=Join-Path $site 'app_offline.htm'
$backupTool=Join-Path $directory 'backup\run-backup.ps1'
$backupConfig=Join-Path $directory 'backup\backup-config.json'
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Yonetici PowerShell kullanin.' }
foreach ($path in @($site,$settings,$zip,$backupTool,$backupConfig)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Eksik: $path" }
}
if ($ExpectedZipHash -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $ExpectedZipHash) {
    throw 'Guncel ZIP ve guncelle.ps1 birlikte kopyalanmali; paket dogrulamasi basarisiz.'
}
if (Test-Path -LiteralPath $offline) { throw 'Site zaten bakimda. Once onceki islemin sonucunu kontrol edin.' }
Import-Module WebAdministration
if (!(Test-Path 'IIS:\AppPools\santiye')) { throw 'santiye uygulama havuzu bulunamadi.' }
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$stage=Join-Path $directory ('feature-update-'+$stamp)
$backup=Join-Path $directory ('deployment-backups\'+$stamp)
foreach ($folder in @($stage,$backup)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $folder /inheritance:r /grant:r "${identity}:(OI)(CI)(F)" '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Guncelleme klasoru izinleri ayarlanamadi.' }
}
Expand-Archive -LiteralPath $zip -DestinationPath $stage
foreach ($file in @('SantiyeAgi.Api.dll','deploy\apply-migrations.ps1')) {
    if (!(Test-Path -LiteralPath (Join-Path $stage $file))) { throw 'Paket eksik. Siteye dokunulmadi.' }
}
try {
    Set-Content -LiteralPath $offline -Value 'Guncelleme yapiliyor.'
    if ((Get-WebAppPoolState -Name 'santiye').Value -eq 'Started') { Stop-WebAppPool -Name 'santiye' }
    Start-Sleep -Seconds 3
    # Yazi islemleri durduktan sonra mevcut 14 gunluk yerel yedek sistemiyle gercek geri yukleme kontrolu.
    & $backupTool -ConfigPath $backupConfig
    Copy-Item -LiteralPath $settings -Destination (Join-Path $backup 'settings.json')
    Copy-Item -LiteralPath $site -Destination (Join-Path $backup 'site') -Recurse
    # Harici ayarlar ve mevcut kullanici dosyalari silinmez.
    Get-ChildItem -LiteralPath $stage -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $site -Recurse -Force }
    & (Join-Path $site 'deploy\apply-migrations.ps1') -SitePath $site -SettingsPath $settings
    Remove-Item -LiteralPath $offline
    Start-WebAppPool -Name 'santiye'
    $ready=$false
    for ($attempt=0; $attempt -lt 6; $attempt++) {
        try {
            if ((Invoke-RestMethod 'https://45.59.70.198/health/ready' -TimeoutSec 10).status -eq 'ready') { $ready=$true; break }
        } catch { Start-Sleep -Seconds 2 }
    }
    if (!$ready) { throw 'HTTPS hazirlik kontrolu basarisiz; site bakimda kalacak.' }
    Write-Output "Guncellendi. Hesaplar, SMS/push/satin alma ayarlari korundu. Yedek: $backup"
    Write-Output 'Mevcut dis ayarlar korundu; guncellenen ozelligi uygulamada ayrica kontrol edin.'
} catch {
    Set-Content -LiteralPath $offline -Value 'Guncelleme kontrol ediliyor.' -ErrorAction SilentlyContinue
    Write-Output "Guncelleme durdu; hata kontrol edilmeden bakimi kaldirmayin. Yedek: $backup"
    throw
}

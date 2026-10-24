param(
    [string]$ExpectedZipHash = ''
)
$ErrorActionPreference='Stop'
$directory='C:\ProgramData\santiye'
$site='C:\inetpub\wwwroot\santiye'
$zip=Join-Path $directory 'SantiyeAgi-Backend-IIS.zip'
$accountSetup=Join-Path $directory 'Test-Hesabi-Kur.ps1'
$settings=Join-Path $directory 'settings.json'
$offline=Join-Path $site 'app_offline.htm'
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Yonetici PowerShell ile calistirin.' }
foreach($path in @($zip,$accountSetup,$settings,$site)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Eksik dosya veya klasor: $path" }
}
if ($ExpectedZipHash -eq '' -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $ExpectedZipHash) {
    throw 'ZIP bu kurulum icin beklenen guncel paketle eslesmiyor. Guncel ZIP dosyasini kopyalayin.'
}
Import-Module WebAdministration
if (!(Test-Path 'IIS:\AppPools\santiye')) { throw 'santiye uygulama havuzu bulunamadi.' }
$stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$staging=Join-Path $directory ('update-'+$stamp)
Expand-Archive -LiteralPath $zip -DestinationPath $staging
if (!(Test-Path -LiteralPath (Join-Path $staging 'deploy\set-account-login.ps1')) -or
    !(Test-Path -LiteralPath (Join-Path $staging 'SantiyeAgi.Api.dll'))) {
    throw 'ZIP gerekli API dosyalarini icermiyor. Siteye dokunulmadi.'
}
$backup=Join-Path $directory ('deployment-backups\'+$stamp)
New-Item -ItemType Directory -Force -Path $backup | Out-Null
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $backup /inheritance:r /grant:r "${identity}:(OI)(CI)(F)" '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Yedek klasoru izinleri ayarlanamadi. Siteye dokunulmadi.' }
try {
    Write-Output 'Backend guncelleniyor; mevcut dosyalar yedekleniyor...'
    Set-Content -LiteralPath $offline -Value 'Guncelleme yapiliyor.'
    if ((Get-WebAppPoolState -Name 'santiye').Value -eq 'Started') { Stop-WebAppPool -Name 'santiye' }
    Start-Sleep -Seconds 3
    Copy-Item -LiteralPath $settings -Destination (Join-Path $backup 'settings.json')
    Copy-Item -LiteralPath $site -Destination (Join-Path $backup 'site') -Recurse
    Get-ChildItem -LiteralPath $staging -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $site -Recurse -Force
    }
    & $accountSetup
    Remove-Item -LiteralPath $offline -ErrorAction SilentlyContinue
    if ((Get-WebAppPoolState -Name 'santiye').Value -ne 'Started') { Start-WebAppPool -Name 'santiye' }
    Write-Output "Tamamlandi. Test girisi kuruldu. Onceki dosyalarin yedegi: $backup"
    Write-Output 'Mobilde surum 7 kullanin. Kullanici adi: test. Canli giris ayrica dogrulanacak.'
} catch {
    Set-Content -LiteralPath $offline -Value 'Guncelleme kontrol ediliyor.' -ErrorAction SilentlyContinue
    Write-Output "Guncelleme durdu; siteyi yeniden acmadan once ciktiyi kontrol edin. Yedek klasoru: $backup"
    throw
}

param(
    [string]$SiteName = 'SantiyeAgi',
    [Parameter(Mandatory = $true)][string]$SitePath,
    [Parameter(Mandatory = $true)][string]$HostName,
    [string]$DatabaseName = 'santiye',
    [string]$DatabaseUser = 'postgres',
    [int]$DatabasePort = 5432,
    [string]$CertificateThumbprint = ''
)
# Sunucuda yönetici PowerShell ile, paketi çıkardıktan sonra çalıştırılır.
$ErrorActionPreference = 'Stop'
if ($SiteName -notmatch '^[A-Za-z0-9_-]{1,60}$') { throw 'SiteName yalnız harf, sayı, _ ve - içerebilir.' }
if ($DatabaseName -notmatch '^[A-Za-z0-9_]+$' -or $DatabaseUser -notmatch '^[A-Za-z0-9_]+$') { throw 'Veritabanı ve kullanıcı adı biçimi geçersiz.' }
if ($HostName -notmatch '^[a-zA-Z0-9.-]+$') { throw 'HostName yalnız alan adı olmalı.' }
if ($DatabasePort -lt 1 -or $DatabasePort -gt 65535) { throw 'Veritabanı portu geçersiz.' }
$resolvedSite = (Resolve-Path -LiteralPath $SitePath).ProviderPath
if (!(Test-Path -LiteralPath (Join-Path $resolvedSite 'SantiyeAgi.Api.dll'))) { throw 'SitePath yayın DLL dosyasını içermeli.' }
Import-Module WebAdministration
if (Test-Path "IIS:\Sites\$SiteName") {
    $existingSite = Get-Item "IIS:\Sites\$SiteName"
    if ([IO.Path]::GetFullPath($existingSite.physicalPath) -ne [IO.Path]::GetFullPath($resolvedSite)) { throw 'Mevcut sitenin fiziksel yolu farklı; hiçbir IIS ayarı değiştirilmedi.' }
    if ($existingSite.applicationPool -ne $SiteName) { throw 'Mevcut site farklı havuz kullanıyor; hiçbir IIS ayarı değiştirilmedi.' }
}
if (@(Get-Website | Where-Object { $_.Name -ne $SiteName -and $_.applicationPool -eq $SiteName }).Count -gt 0) { throw 'Bu havuz başka bir site tarafından kullanılıyor; farklı SiteName seçin.' }
$feature = Get-WindowsFeature -Name Web-AppInit
if (!$feature.Installed) {
    $installation = Install-WindowsFeature -Name Web-AppInit
    if (!$installation.Success) { throw 'IIS Application Initialization kurulamadı.' }
}
if ($CertificateThumbprint -ne '') { $cert = Get-Item "Cert:\LocalMachine\My\$CertificateThumbprint" }
if (!(Test-Path "IIS:\AppPools\$SiteName")) { New-WebAppPool -Name $SiteName | Out-Null }
$configDir = Join-Path $env:ProgramData $SiteName
$configFile = Join-Path $configDir 'settings.json'
$keyDir = Join-Path $configDir 'keys'
New-Item -ItemType Directory -Force -Path $configDir, $keyDir | Out-Null
# Parola dosyasını yazmadan önce erişimi sınırla; native komut hatasını denetle.
& icacls.exe $configDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "IIS AppPool\${SiteName}:(OI)(CI)RX" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Ayar klasörüne güvenli izinler uygulanamadı.' }
& icacls.exe $keyDir /grant:r "IIS AppPool\${SiteName}:(OI)(CI)M" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Kalıcı anahtar klasörü izinleri uygulanamadı.' }
if (!(Test-Path -LiteralPath $configFile)) {
    $secret = Read-Host 'PostgreSQL kullanıcısının parolası (ekranda görünmez)' -AsSecureString
    $secretPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try {
        $dbPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPtr).Replace('"', '""')
        $connection = 'Host=127.0.0.1;Port=' + $DatabasePort + ';Database=' + $DatabaseName + ';Username=' + $DatabaseUser + ';Password="' + $dbPassword + '";Pooling=true;Maximum Pool Size=40'
        $random = New-Object byte[] 48
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($random) } finally { $rng.Dispose() }
        $settings = [ordered]@{
            AllowedHosts = $HostName
            ConnectionStrings = @{ Postgres = $connection }
            Auth = @{ SigningKey = [Convert]::ToBase64String($random); AllowDevelopmentAnonymous = $false; RequirePhoneVerification = $false }
            DataProtection = @{ KeysPath = $keyDir }
            Sms = @{ Provider = 'Disabled' }
            Billing = @{ Enabled = $false }
            Push = @{ Enabled = $false }
        }
        $settings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configFile -Encoding UTF8
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPtr)
        $dbPassword = $null; $connection = $null; $settings = $null
    }
}
Set-ItemProperty "IIS:\AppPools\$SiteName" -Name managedRuntimeVersion -Value ''
Set-ItemProperty "IIS:\AppPools\$SiteName" -Name enable32BitAppOnWin64 -Value $false
Set-ItemProperty "IIS:\AppPools\$SiteName" -Name startMode -Value AlwaysRunning
Set-ItemProperty "IIS:\AppPools\$SiteName" -Name processModel.idleTimeout -Value ([TimeSpan]::Zero)
Set-ItemProperty "IIS:\AppPools\$SiteName" -Name processModel.identityType -Value ApplicationPoolIdentity
if (!(Test-Path "IIS:\Sites\$SiteName")) {
    New-Website -Name $SiteName -PhysicalPath $resolvedSite -ApplicationPool $SiteName -Port 80 -HostHeader $HostName | Out-Null
}
Set-ItemProperty "IIS:\Sites\$SiteName" -Name applicationDefaults.preloadEnabled -Value $true
$poolFilter = "system.applicationHost/applicationPools/add[@name='$SiteName']/environmentVariables"
foreach ($item in @(@{name='ASPNETCORE_ENVIRONMENT';value='Production'}, @{name='SANTIYE_CONFIG_FILE';value=$configFile})) {
    $existing = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "$poolFilter/add[@name='$($item.name)']" -Name value -ErrorAction SilentlyContinue
    if ($null -eq $existing) { Add-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $poolFilter -Name '.' -Value $item }
    else { Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter "$poolFilter/add[@name='$($item.name)']" -Name value -Value $item.value }
}
& icacls.exe $resolvedSite /grant "IIS AppPool\${SiteName}:(OI)(CI)RX" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Yayın klasörü okuma izinleri uygulanamadı.' }
if ($CertificateThumbprint -ne '') {
    if ($null -eq (Get-WebBinding -Name $SiteName -Protocol https -HostHeader $HostName)) { New-WebBinding -Name $SiteName -Protocol https -Port 443 -HostHeader $HostName -SslFlags 1 }
    (Get-WebBinding -Name $SiteName -Protocol https -HostHeader $HostName).AddSslCertificate($cert.Thumbprint, 'My')
}
$env:ASPNETCORE_ENVIRONMENT = 'Production'
$env:SANTIYE_CONFIG_FILE = $configFile
& dotnet (Join-Path $resolvedSite 'SantiyeAgi.Api.dll') --migrate
if ($LASTEXITCODE -ne 0) { throw 'Veritabanı kurulamadı. PostgreSQL ve veritabanı adını kontrol edin.' }
Restart-WebAppPool -Name $SiteName
Write-Output "Kurulum hazır. Gizli ayarlar: $configFile"
Write-Output "HTTPS ve DNS tamamlandıktan sonra https://$HostName/health/ready adresini kontrol edin. SMS/mağaza/push ayrıca etkinleştirilir."

param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
if ($OutputDirectory -eq '') { $OutputDirectory = Join-Path $projectRoot ('output\backend\iis-publish-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$publishPath = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $publishPath.StartsWith((Join-Path $projectRoot 'output') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Yayin cikti klasoru proje output klasoru icinde olmali.'
}
New-Item -ItemType Directory -Force -Path $publishPath | Out-Null
if (Get-ChildItem -LiteralPath $publishPath -Force | Select-Object -First 1) { throw 'Yayin klasoru bos olmali; yeni klasor secin.' }
& dotnet publish (Join-Path $projectRoot 'backend\SantiyeAgi.Api\SantiyeAgi.Api.csproj') -c Release -r win-x64 --self-contained false -o $publishPath
if ($LASTEXITCODE -ne 0) { throw 'Yayin derlemesi basarisiz.' }
# Bu teslimde kullanici SMS'i erteledi. Sunucuya ozel Auth ayari bu paket
# varsayilanini ezer; yoksa paket SMS'siz profille baslar.
$packageSettingsFile = Join-Path $publishPath 'appsettings.json'
$packageSettings = Get-Content -LiteralPath $packageSettingsFile -Raw | ConvertFrom-Json
$packageSettings.Auth.RequirePhoneVerification = $false
$packageSettings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $packageSettingsFile -Encoding UTF8
$deploy = Join-Path $publishPath 'deploy'
New-Item -ItemType Directory -Force -Path $deploy | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'configure-iis.ps1'), (Join-Path $PSScriptRoot 'backup-postgres.ps1'), (Join-Path $PSScriptRoot 'set-sms-verification.ps1'), (Join-Path $PSScriptRoot 'set-firebase-push.ps1'), (Join-Path $PSScriptRoot 'clear-user-data.ps1'), (Join-Path $PSScriptRoot 'apply-migrations.ps1') -Destination $deploy
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'set-account-login.ps1') -Destination $deploy
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'set-ai-assistant.ps1') -Destination $deploy
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'set-vatan-sms.ps1') -Destination $deploy
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test-sms-otp.ps1') -Destination $deploy
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'inspect-ios-readiness.ps1') -Destination $deploy
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test-apple-notifications.ps1') -Destination $deploy
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'set-apple-billing.ps1') -Destination $deploy
foreach ($backupTool in @('backup-common.ps1', 'install-backup.ps1', 'run-backup.ps1', 'verify-backup.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $backupTool) -Destination $deploy
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\SUNUCU_PAKETI_TESLIM.md') -Destination (Join-Path $publishPath 'ONCE_BENI_OKU.md')
$guideDirectory = Join-Path $publishPath 'kurulum-notlari'
New-Item -ItemType Directory -Force -Path $guideDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\APPLE_BILLING_KURULUM_2026-10-21.md') -Destination $guideDirectory
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\VATANSMS_KURULUM_2026-10-24.md') -Destination $guideDirectory
foreach ($doc in @('ODEME_KURULUMU.md', 'BILDIRIM_SMS_KURULUMU.md', 'MOBIL_BAGLANTI_VE_YAYIN.md', 'BACKEND_KABUL_KONTROLU.md', 'SMS_AC_KAPAT.md', 'CANLI_GUNCELLEME.md', 'CANLI_KABUL_KONTROLU.md', 'GOOGLE_PLAY_INCELEME_HESABI.md', 'OTOMATIK_YEDEKLEME.md', 'ASISTAN_CANLI_KONUM_KURULUMU.md', 'BACKEND_IOS_YAYIN_SONUC_2026-10-21.md')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot ('docs\' + $doc)) -Destination $guideDirectory
}
$sql = Join-Path (Split-Path $publishPath -Parent) 'postgresql-migrations.sql'
Push-Location (Join-Path $projectRoot 'backend')
try {
    & dotnet tool restore
    if ($LASTEXITCODE -ne 0) { throw 'Yerel EF araci kurulamadi.' }
    & dotnet ef migrations script --idempotent --configuration Release --project SantiyeAgi.Api --output $sql
    if ($LASTEXITCODE -ne 0) { throw 'SQL kurulum dosyasi hazirlanamadi.' }
} finally { Pop-Location }
Copy-Item -LiteralPath $sql -Destination (Join-Path $deploy 'postgresql-migrations.sql')
@{apple_notification_test=1;apple_api_access_check=1;sms_review_readiness=1;assembly_sha256=(Get-FileHash -LiteralPath (Join-Path $publishPath 'SantiyeAgi.Api.dll') -Algorithm SHA256).Hash} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $publishPath 'OPERATIONS-CAPABILITIES.json') -Encoding UTF8
$manifest = [ordered]@{ generated_at = (Get-Date).ToString('o'); target = 'net10.0/win-x64'; source_commit = (& git -C $projectRoot rev-parse HEAD); files = @() }
$manifest.files = @(Get-ChildItem -LiteralPath $publishPath -Recurse -File | ForEach-Object {
    @{ path = $_.FullName.Substring($publishPath.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $publishPath 'PACKAGE-MANIFEST.json') -Encoding UTF8
$zip = Join-Path (Split-Path $publishPath -Parent) 'SantiyeAgi-Backend-IIS.zip'
# Uretim sirlari kaynakta bulunmaz; paket varsayilan bos ayarlari icerir.
Compress-Archive -Path (Join-Path $publishPath '*') -DestinationPath $zip -Force
$packageHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
$updateSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'update-features.ps1') -Raw
$updateSource=$updateSource.Replace("[string]`$ExpectedZipHash = ''", "[string]`$ExpectedZipHash = '$packageHash'")
[IO.File]::WriteAllText((Join-Path (Split-Path $publishPath -Parent) 'guncelle.ps1'), $updateSource, (New-Object Text.UTF8Encoding($true)))
Write-Output "IIS yayin paketi: $zip"
@{publish_directory=$publishPath;zip=$zip;sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path (Split-Path $publishPath -Parent) 'latest-package.json') -Encoding UTF8

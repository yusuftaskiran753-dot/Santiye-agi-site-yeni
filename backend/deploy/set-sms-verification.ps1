param(
    [ValidateSet('On', 'Off')][string]$Mode = 'Off',
    [string]$SettingsPath = 'C:\ProgramData\santiye\settings.json',
    [string]$AppPool = 'santiye',
    [switch]$SkipIisRestart
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $SettingsPath)) { throw 'Sunucunun settings.json dosyasi bulunamadi.' }
if (!$SkipIisRestart) {
    Import-Module WebAdministration
    if (!(Test-Path "IIS:\AppPools\$AppPool")) { throw 'IIS uygulama havuzu bulunamadi.' }
}
$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
if ($null -eq $settings.Auth) { $settings | Add-Member -NotePropertyName Auth -NotePropertyValue ([pscustomobject]@{}) }
$enabled = $Mode -eq 'On'
$settings.Auth | Add-Member -NotePropertyName RequirePhoneVerification -NotePropertyValue $enabled -Force
# Dosyanin mevcut ACL izinlerini ve diger sunucu ayarlarini koru.
[IO.File]::WriteAllText([IO.Path]::GetFullPath($SettingsPath), ($settings | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding($false)))
$settings = $null
if (!$SkipIisRestart) { Restart-WebAppPool -Name $AppPool }
Write-Output "SMS zorunlulugu: $Mode. Uygulamayi yeniden acin."

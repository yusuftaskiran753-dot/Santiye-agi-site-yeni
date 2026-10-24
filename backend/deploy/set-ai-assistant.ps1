param(
    [ValidateSet('On','Off')][string]$Mode='On',
    [string]$SettingsPath='C:\ProgramData\santiye\settings.json',
    [string]$AppPool='santiye',
    [int]$DailyRequestBudget=200,
    [switch]$SkipIisSetup
)
$ErrorActionPreference='Stop'
if ($DailyRequestBudget -lt 1 -or $DailyRequestBudget -gt 1000) { throw 'Gunluk istek siniri 1-1000 arasinda olmali.' }
if (!(Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw 'Mevcut settings.json bulunamadi.' }
$settings=Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
if ($settings -isnot [pscustomobject] -or ($null -ne $settings.AI -and $settings.AI -isnot [pscustomobject])) { throw 'Ayarlar JSON nesnesi olmali.' }
if (!$SkipIisSetup) {
    Import-Module WebAdministration
    if (!(Test-Path "IIS:\AppPools\$AppPool")) { throw 'IIS uygulama havuzu bulunamadi.' }
    foreach ($site in Get-Website) {
        $root=[Environment]::ExpandEnvironmentVariables($site.PhysicalPath)
        if ($root -and [IO.Path]::GetFullPath($SettingsPath).StartsWith([IO.Path]::GetFullPath($root).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) {
            throw 'API anahtari web klasorunde tutulamaz. ProgramData ayarlarini kullanin.'
        }
    }
}
if ($null -eq $settings.AI) { $settings | Add-Member -NotePropertyName AI -NotePropertyValue ([pscustomobject]@{}) }
if ($Mode -eq 'On') {
    # Anahtar komut satirina veya sohbet kaydina yazilmaz.
    $secure=Read-Host 'Gemini API anahtarini yapistirin (gizli)' -AsSecureString
    $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $apiKey=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
    if (!$apiKey -or $apiKey.Length -lt 10 -or $apiKey.Length -gt 512 -or $apiKey -match '\s') { throw 'Anahtar bicimi gecersiz.' }
    $settings.AI | Add-Member -NotePropertyName ApiKey -NotePropertyValue $apiKey -Force
    $settings.AI | Add-Member -NotePropertyName Model -NotePropertyValue 'gemini-3.5-flash-lite' -Force
    $settings.AI | Add-Member -NotePropertyName DailyLimit -NotePropertyValue 30 -Force
    $settings.AI | Add-Member -NotePropertyName PremiumDailyLimit -NotePropertyValue 200 -Force
    $settings.AI | Add-Member -NotePropertyName GlobalDailyRequestLimit -NotePropertyValue $DailyRequestBudget -Force
    $settings.AI | Add-Member -NotePropertyName MaxConcurrency -NotePropertyValue 2 -Force
    $settings.AI | Add-Member -NotePropertyName TimeoutSeconds -NotePropertyValue 12 -Force
    $settings.AI | Add-Member -NotePropertyName MaxOutputTokens -NotePropertyValue 2048 -Force
}
$settings.AI | Add-Member -NotePropertyName Enabled -NotePropertyValue ($Mode -eq 'On') -Force
# Mevcut dosyaya yazarak ACL ve diger tum sunucu ayarlarini korur.
[IO.File]::WriteAllText([IO.Path]::GetFullPath($SettingsPath),($settings | ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
$settings=$null; $apiKey=$null
if (!$SkipIisSetup) { Restart-WebAppPool -Name $AppPool }
Write-Output "Gemini ayari: $Mode. SMS, bildirim, veritabani ve satin alma ayarlari korundu."
Write-Output 'Bu sonuc gercek Gemini yanit testi degildir. Uygulamada acik riza secimiyle ayrica deneyin.'

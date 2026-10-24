param(
    [string]$SitePath = (Split-Path $PSScriptRoot -Parent),
    [string]$SettingsPath = 'C:\ProgramData\santiye\settings.json'
)
$ErrorActionPreference = 'Stop'
$SitePath = (Resolve-Path -LiteralPath $SitePath).ProviderPath
$dll = Join-Path $SitePath 'SantiyeAgi.Api.dll'
if (!(Test-Path -LiteralPath $dll) -or !(Test-Path -LiteralPath $SettingsPath)) { throw 'Yayin DLL veya sunucu settings.json dosyasi bulunamadi.' }
$previousConfig = $env:SANTIYE_CONFIG_FILE
$previousEnvironment = $env:ASPNETCORE_ENVIRONMENT
try {
    $env:SANTIYE_CONFIG_FILE = [IO.Path]::GetFullPath($SettingsPath)
    $env:ASPNETCORE_ENVIRONMENT = 'Production'
    Push-Location -LiteralPath $SitePath
    try {
        & dotnet $dll --migrate
        if ($LASTEXITCODE -ne 0) { throw 'Veritabani guncellemesi basarisiz. Bakim dosyasini kaldirmadan once hatayi kontrol edin.' }
    } finally { Pop-Location }
    Write-Output 'Veritabani guncellendi. Mevcut hesaplar ve kayitlar korundu.'
} finally {
    $env:SANTIYE_CONFIG_FILE = $previousConfig
    $env:ASPNETCORE_ENVIRONMENT = $previousEnvironment
}

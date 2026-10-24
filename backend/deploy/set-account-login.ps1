param(
    [Parameter(Mandatory=$true)][string]$CredentialFile,
    [string]$SettingsPath='C:\ProgramData\santiye\settings.json',
    [string]$AppPool='santiye',
    [switch]$SkipIisRestart
)
$ErrorActionPreference='Stop'
$credential=Get-Content -LiteralPath $CredentialFile -Raw | ConvertFrom-Json
$userId=[guid]::Empty
if (-not [guid]::TryParse([string]$credential.UserId,[ref]$userId) -or $userId -eq [guid]::Empty) { throw 'Hesap kimligi gecersiz.' }
# Base64 is case-sensitive. Culture-sensitive matching on Windows PowerShell 5.1
# can reject ASCII I/i under tr-TR; do not case-fold credential encodings.
if ([string]$credential.Username -cnotmatch '^[a-zA-Z0-9._-]{3,100}$' -or [string]$credential.PasswordHash -cnotmatch '^pbkdf2-sha256\$600000\$[A-Za-z0-9+/]{22}==\$[A-Za-z0-9+/]{43}=$') { throw 'Kimlik bilgisi bicimi gecersiz.' }
if (!$SkipIisRestart) { Import-Module WebAdministration; if (!(Test-Path "IIS:\AppPools\$AppPool")) { throw 'Uygulama havuzu bulunamadi.' } }
$settings=Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
if ($null -eq $settings.Auth) { $settings | Add-Member -NotePropertyName Auth -NotePropertyValue ([pscustomobject]@{}) }
$accounts=@()
if ($null -ne $settings.Auth.AccountLogin -and $null -ne $settings.Auth.AccountLogin.Accounts) {
    $accounts=@($settings.Auth.AccountLogin.Accounts | Where-Object { $_.Username -ine $credential.Username })
}
$accounts+=([pscustomobject]@{Username=$credential.Username; UserId=$userId.ToString(); PasswordHash=$credential.PasswordHash})
$settings.Auth | Add-Member -NotePropertyName AccountLogin -NotePropertyValue ([pscustomobject]@{Enabled=$true; Accounts=$accounts}) -Force
[IO.File]::WriteAllText([IO.Path]::GetFullPath($SettingsPath),($settings | ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($false)))
if (!$SkipIisRestart) {
    if ((Get-WebAppPoolState -Name $AppPool).Value -eq 'Started') { Restart-WebAppPool -Name $AppPool }
    else { Start-WebAppPool -Name $AppPool }
}
Write-Output 'Kullanici adi/parola girisi acildi. SMS, veritabani ve satin alma ayarlari korundu.'

$ErrorActionPreference='Stop'
$helper=Join-Path (Split-Path $PSScriptRoot -Parent) 'set-account-login.ps1'
$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$directory=Join-Path $repo ('tmp\account-login-regression-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$settings=Join-Path $directory 'settings.json'
$credential=Join-Path $directory 'credential.json'
$previousCulture=[Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('tr-TR')
    $salt=[Convert]::ToBase64String([byte[]](0..15))
    $digest=[Convert]::ToBase64String([byte[]](0..31))
    $hash='pbkdf2-sha256$600000$'+$salt+'$'+$digest
    if (!$hash.Contains('I')) { throw 'Regression fixture must contain uppercase ASCII I.' }
    $data=[ordered]@{Username='test';UserId=[guid]::NewGuid().ToString();PasswordHash=$hash}
    [IO.File]::WriteAllText($credential,($data | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($settings,'{"Auth":{"RequirePhoneVerification":true},"Push":{"Enabled":true},"ConnectionStrings":{"Postgres":"local-fixture"}}')
    & $helper -CredentialFile $credential -SettingsPath $settings -SkipIisRestart
    & $helper -CredentialFile $credential -SettingsPath $settings -SkipIisRestart
    $result=Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
    if (!$result.Auth.AccountLogin.Enabled -or @($result.Auth.AccountLogin.Accounts).Count -ne 1 -or $result.Auth.AccountLogin.Accounts[0].PasswordHash -cne $hash) { throw 'Credential roundtrip/idempotency failed.' }
    if (!$result.Auth.RequirePhoneVerification -or !$result.Push.Enabled -or $result.ConnectionStrings.Postgres -ne 'local-fixture') { throw 'Other settings changed.' }
    $data.PasswordHash=$hash.Replace('600000','600001')
    [IO.File]::WriteAllText($credential,($data | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    $rejected=$false
    try { & $helper -CredentialFile $credential -SettingsPath $settings -SkipIisRestart } catch { $rejected=$true }
    if (!$rejected) { throw 'Invalid credential accepted.' }
    Write-Output ('PASS: tr-TR Base64, unchanged settings, repeated install and invalid credential rejection; PowerShell '+$PSVersionTable.PSVersion)
} finally {
    [Threading.Thread]::CurrentThread.CurrentCulture=$previousCulture
}

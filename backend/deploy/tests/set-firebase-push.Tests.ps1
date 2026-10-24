$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$script = Join-Path $root 'backend\deploy\set-firebase-push.ps1'
$testDir = Join-Path (Join-Path $root 'tmp') ('firebase-setup-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
$settingsFile = Join-Path $testDir 'settings.json'
$accountFile = Join-Path $testDir 'fake-service-account.json'
try {
    $before = @{ Auth=@{SigningKey='local-fake-key';RequirePhoneVerification=$false};ConnectionStrings=@{Postgres='local-fake-db'};Sms=@{Enabled=$false};Push=@{OtherSetting=42} }
    $before | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsFile -Encoding UTF8
    $aclBefore = (Get-Acl -LiteralPath $settingsFile).Sddl
    $credential = @{type='service_account';project_id='santiye-agi';token_uri='https://oauth2.googleapis.com/token';client_email='fake@santiye-agi.iam.gserviceaccount.com';private_key="-----BEGIN PRIVATE KEY-----`nFAKE-NOT-A-REAL-KEY`n-----END PRIVATE KEY-----"}
    $credential | ConvertTo-Json | Set-Content -LiteralPath $accountFile -Encoding UTF8
    & $script -ServiceAccountPath $accountFile -SettingsPath $settingsFile -SkipIisSetup | Out-Null
    $after = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
    if (!$after.Push.Enabled -or $after.Push.Firebase.ProjectId -ne 'santiye-agi') { throw 'Enable ayarlari hatali.' }
    if ($after.Auth.SigningKey -ne 'local-fake-key' -or $after.Auth.RequirePhoneVerification -ne $false -or $after.ConnectionStrings.Postgres -ne 'local-fake-db' -or $after.Sms.Enabled -ne $false -or $after.Push.OtherSetting -ne 42) { throw 'Diger ayarlar degisti.' }
    if ((Get-Acl -LiteralPath $settingsFile).Sddl -ne $aclBefore) { throw 'Settings ACL degisti.' }
    if ((Get-Content -LiteralPath $settingsFile -Raw).Contains('BEGIN PRIVATE KEY')) { throw 'Ozel anahtar ayarlara sizdi.' }
    $unchanged = [IO.File]::ReadAllText($settingsFile)
    $credential.project_id = 'wrong-project'
    $credential | ConvertTo-Json | Set-Content -LiteralPath $accountFile -Encoding UTF8
    $rejected = $false
    try { & $script -ServiceAccountPath $accountFile -SettingsPath $settingsFile -SkipIisSetup | Out-Null } catch { $rejected=$true }
    if (!$rejected -or [IO.File]::ReadAllText($settingsFile) -ne $unchanged) { throw 'Yanlis proje reddedilmedi veya ayarlari degistirdi.' }
    $credential.project_id = 'santiye-agi'
    $credential.token_uri = 'https://example.invalid/token'
    $credential | ConvertTo-Json | Set-Content -LiteralPath $accountFile -Encoding UTF8
    $rejected = $false
    try { & $script -ServiceAccountPath $accountFile -SettingsPath $settingsFile -SkipIisSetup | Out-Null } catch { $rejected=$true }
    if (!$rejected -or [IO.File]::ReadAllText($settingsFile) -ne $unchanged) { throw 'Yanlis OAuth adresi reddedilmedi.' }
    & $script -Mode Off -ServiceAccountPath (Join-Path $testDir 'missing.json') -SettingsPath $settingsFile -SkipIisSetup | Out-Null
    $afterOff = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
    if ($afterOff.Push.Enabled -ne $false -or $afterOff.Auth.SigningKey -ne 'local-fake-key' -or $afterOff.Push.Firebase.ProjectId -ne 'santiye-agi') { throw 'Kapatma diger ayarlari bozdu.' }
    Write-Output 'PASS: On/Off, settings preservation, ACL preservation, no key embedding, invalid project/OAuth rejection.'
} finally {
    $safeTestDir = [IO.Path]::GetFullPath($testDir)
    if (!$safeTestDir.StartsWith(([IO.Path]::GetFullPath((Join-Path $root 'tmp')).TrimEnd('\')+'\firebase-setup-test-'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Guvenli test temizleme yolu dogrulanamadi.' }
    Remove-Item -LiteralPath $safeTestDir -Recurse -Force
}

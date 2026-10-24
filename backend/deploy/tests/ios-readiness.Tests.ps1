$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$fixture=Join-Path $root ('tmp\ios-audit-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$settings=Join-Path $fixture 'settings.json';$account=Join-Path $fixture 'fixture.json'
@{type='service_account';project_id='santiye-agi';token_uri='https://oauth2.googleapis.com/token';private_key='CANARY-PRIVATE-NOT-OUTPUT'} | ConvertTo-Json | Set-Content $account -Encoding UTF8
@{Auth=@{SigningKey='CANARY-AUTH';RequirePhoneVerification=$false;AccountLogin=@{Enabled=$true}};AI=@{Enabled=$true;ApiKey='CANARY-AI';Model='gemini-3.5-flash-lite'};Billing=@{Enabled=$false;AllowSandbox=$false;AppleBundleId='com.yusuftaskiran.santiyeagi.pro';AppleAppId=6824034438};Push=@{Enabled=$true;Firebase=@{ProjectId='santiye-agi';ServiceAccountPath=$account}};ConnectionStrings=@{Postgres='CANARY-DB'}} | ConvertTo-Json -Depth 8 | Set-Content $settings -Encoding UTF8
$before=(Get-FileHash $settings).Hash
$out=(& (Join-Path $root 'backend/deploy/inspect-ios-readiness.ps1') -SettingsPath $settings -SiteRoot $fixture -Offline) -join "`n"
if($out -match 'CANARY-'){throw 'Secret leaked'}
$r=$out|ConvertFrom-Json
if(!$r.ReadOnly -or $r.IisConfigPathResolved -or !$r.AppleBundleMatches -or !$r.AppleAppIdMatches -or !$r.FirebaseServiceAccountMatches -or !$r.GeminiKeyPresent -or $r.GeminiBillingVerified -or $r.GeminiProjectBindingVerified -or $r.AppleKeyPurposeVerified -or $r.BillingEnabled -or $r.AllowSandbox -or $r.PhoneVerificationRequired){throw 'Audit flag mismatch'}
if((Get-FileHash $settings).Hash -ne $before){throw 'Settings mutated'}
foreach($file in @('inspect-ios-readiness.ps1','test-apple-notifications.ps1','set-apple-billing.ps1')){
 $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('backend/deploy/'+$file)),[ref]$tokens,[ref]$errors)|Out-Null
 if($errors.Count){throw 'PowerShell parse failed'}
}
Write-Output 'Read-only IOS audit: safe allowlist, no mutation, unresolved billing/purpose flags and PowerShell parsing passed.'

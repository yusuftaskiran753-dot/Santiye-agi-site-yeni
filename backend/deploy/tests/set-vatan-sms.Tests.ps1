$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installer=Join-Path $repository 'backend\deploy\set-vatan-sms.ps1'
$tokens=$null;$parseErrors=$null
[Management.Automation.Language.Parser]::ParseFile($installer,[ref]$tokens,[ref]$parseErrors) | Out-Null
if($parseErrors.Count){throw 'VatanSMS installer PowerShell parse failed.'}
. $installer -FunctionsOnly
$script:checks=0
function Assert-SmsTest([bool]$Condition,[string]$Message){if(!$Condition){throw $Message};$script:checks++}
function Assert-SmsThrows([scriptblock]$Operation,[string]$Message){$failed=$false;try{& $Operation | Out-Null}catch{$failed=$true};Assert-SmsTest $failed $Message}
function Copy-SmsTestValue($Value){return $Value | ConvertTo-Json -Depth 64 -Compress | ConvertFrom-Json}
function Convert-SmsTestJson($Value){return $Value | ConvertTo-Json -Depth 64 -Compress}

# Deliberately fake credentials. No provider request, SMS, database or IIS call
# occurs anywhere in these tests. Only the final boundary functions are mocked.
$testId='123456';$testKey='CANARY-FAKE-SMS-KEY';$testSender='TESTSENDER'
Assert-VatanSmsCredentials $testId $testKey $testSender;$script:checks++
foreach($bad in @(@('bad',$testKey,$testSender),@($testId,'short',$testSender),@($testId,'CANARY key with whitespace',$testSender),@($testId,$testKey,'too-long-sender-name'),@($testId,$testKey,'lowercase'))) {
    Assert-SmsThrows {Assert-VatanSmsCredentials $bad[0] $bad[1] $bad[2]} 'Invalid credentials were accepted.'
}
foreach($body in @(
    '{"status":"success","data":["TESTSENDER"]}',
    '{"status":"SUCCESS","data":{"senders":[{"name":"TESTSENDER"}]}}',
    '{"status":200,"data":["TESTSENDER"]}',
    '{"code":200,"senders":["TESTSENDER"]}',
    '{"success":true,"data":{"sender":"TESTSENDER"}}',
    '{"status":"success","code":200,"success":true,"errors":[],"error":false,"data":["TESTSENDER"]}'
)) {
    $audit=Get-VatanSmsSenderAudit 200 $body $testSender
    Assert-SmsTest ($audit.ApiAccessVerified -and $audit.SenderVerified -and $audit.ResponseSchema -eq 'KNOWN_SUCCESS_EXACT_SENDER') 'Known successful sender response was not accepted.'
}
foreach($body in @(
    '{"data":["TESTSENDER"]}',
    '{"code":"200","data":["TESTSENDER"]}',
    '{"status":"200","data":["TESTSENDER"]}',
    '{"status":true,"data":["TESTSENDER"]}',
    '{"code":200,"status":"error","data":["TESTSENDER"]}',
    '{"status":"success","code":401,"data":["TESTSENDER"]}',
    '{"success":false,"status":"success","data":["TESTSENDER"]}',
    '{"success":"true","data":["TESTSENDER"]}',
    '{"status":"success","error":"CANARY-FAKE-SMS-KEY","data":["TESTSENDER"]}',
    '{"status":"success","errors":["CANARY-FAKE-SMS-KEY"],"data":["TESTSENDER"]}',
    '{"status":"success","errors":{},"data":["TESTSENDER"]}',
    '{"status":"success","metadata":{"sender":"TESTSENDER"}}',
    '{"status":"success","data":["testsEnder"]}',
    '{"status":"success","data":["prefix-TESTSENDER"]}',
    '{"status":"success","data":["TESTSENDER-suffix"]}',
    '{"status":"success","data":{"TESTSENDER":true}}',
    '[]','null','false','CANARY-FAKE-SMS-KEY',
    ('x'*65537)
)) {
    $audit=Get-VatanSmsSenderAudit 200 $body $testSender
    Assert-SmsTest (!$audit.SenderVerified) 'An ambiguous, rejected or unrelated sender response was accepted.'
    Assert-SmsTest ((Convert-SmsTestJson $audit) -notmatch 'CANARY|prefix-TESTSENDER|TESTSENDER-suffix') 'Provider response details leaked into safe audit.'
}
$audit=Get-VatanSmsSenderAudit 401 '{"status":"success","data":["TESTSENDER"]}' $testSender
Assert-SmsTest (!$audit.ApiAccessVerified -and !$audit.SenderVerified) 'HTTP rejection was ignored.'
$deep='TESTSENDER';for($i=0;$i -lt 10;$i++){$deep=[pscustomobject]@{child=$deep}}
Assert-SmsTest (!(Test-VatanSmsExactSender $deep $testSender)) 'Unbounded sender recursion was accepted.'

$original=@'
{"Auth":{"RequirePhoneVerification":false,"AccountLogin":{"Enabled":true,"Accounts":[{"Username":"review-canary","UserId":"fixture-user","PasswordHash":"CANARY-HASH"}]},"SigningKey":"CANARY-AUTH"},"Sms":{"Enabled":false,"Provider":"Disabled","DailyBudget":73,"Unknown":{"Keep":42},"VatanSms":{"Keep":"extra"}},"AI":{"ApiKey":"CANARY-AI","Enabled":true},"Billing":{"Enabled":true,"AllowSandbox":false,"ApplePrivateKeyFile":"CANARY-PATH"},"Push":{"Enabled":true,"Firebase":{"ProjectId":"fixture-project"}},"ConnectionStrings":{"Postgres":"CANARY-DATABASE"},"Extra":{"Nested":[1,2,3]}}
'@ | ConvertFrom-Json
$before=Copy-SmsTestValue $original
$staged=Merge-VatanSmsSettings (Copy-SmsTestValue $original) $testId $testKey $testSender
Assert-SmsTest ($staged.Sms.Enabled -and $staged.Sms.Provider -eq 'VatanSms' -and $staged.Sms.VatanSms.ApiKey -eq $testKey -and $staged.Sms.VatanSms.Sender -eq $testSender) 'Provider configuration was not staged.'
Assert-SmsTest (!$staged.Auth.RequirePhoneVerification -and $staged.Auth.AccountLogin.Enabled) 'Stage changed the authentication policy.'
foreach($property in $original.PSObject.Properties | Where-Object {$_.Name -ne 'Sms'}) {
    Assert-SmsTest ((Convert-SmsTestJson $staged.($property.Name)) -ceq (Convert-SmsTestJson $property.Value)) 'A non-SMS setting changed.'
}
Assert-SmsTest ($staged.Sms.DailyBudget -eq 73 -and $staged.Sms.Unknown.Keep -eq 42 -and $staged.Sms.VatanSms.Keep -eq 'extra') 'Unrelated SMS settings changed.'
Assert-SmsTest ((Convert-SmsTestJson $original) -ceq (Convert-SmsTestJson $before)) 'Fixture was unexpectedly mutated.'
$enabled=Merge-VatanSmsSettings (Copy-SmsTestValue $original) $testId $testKey $testSender -RequirePhone
Assert-SmsTest ($enabled.Auth.RequirePhoneVerification -and $enabled.Auth.AccountLogin.Enabled) 'Explicit enable did not require phones or changed login configuration.'
foreach($missingAuth in @('{}','{"Auth":null,"Sms":null}','{"Auth":{"AccountLogin":null},"Sms":{"VatanSms":null}}')) {
    $value=$missingAuth | ConvertFrom-Json
    $authBefore=Convert-SmsTestJson $value.Auth
    $merged=Merge-VatanSmsSettings $value $testId $testKey $testSender
    Assert-SmsTest ((Convert-SmsTestJson $merged.Auth) -ceq $authBefore) 'Stage invented or modified missing/null Auth settings.'
    Assert-SmsTest $merged.Sms.Enabled 'Missing/null SMS configuration was not created.'
}
foreach($badJson in @('[]','{"Sms":true}','{"Auth":false}','{"Sms":{"VatanSms":"invalid"}}','{"Auth":{"RequirePhoneVerification":"false"}}','{"Auth":{"AccountLogin":{"Enabled":"false"}}}')) {
    Assert-SmsThrows {Assert-VatanSmsSettingsObject ($badJson | ConvertFrom-Json)} ('Malformed settings were accepted: '+$badJson)
}
$readyReview='{"ReadOnly":true,"PasswordLoginEnabled":true,"ConfiguredAccountCount":1,"VerifiedAccountCount":1,"MissingOrInvalidAccountCount":0,"ReadyForRequiredSms":true,"Code":"READY"}'
$review=Convert-VatanSmsReviewReadiness 0 $readyReview
Assert-SmsTest ($review.ReadyForRequiredSms -and $review.ReadOnly -and $review.VerifiedAccountCount -eq 1) 'Verified review readiness was not accepted.'
$disabledReview='{"ReadOnly":true,"PasswordLoginEnabled":false,"ConfiguredAccountCount":0,"VerifiedAccountCount":0,"MissingOrInvalidAccountCount":0,"ReadyForRequiredSms":true,"Code":"READY"}'
Assert-SmsTest (Convert-VatanSmsReviewReadiness 0 $disabledReview).ReadyForRequiredSms 'Disabled password accounts incorrectly blocked explicit enable.'
foreach($badReview in @(
    $readyReview.Replace('"ReadOnly":true','"ReadOnly":false'),
    $readyReview.Replace('"ReadyForRequiredSms":true','"ReadyForRequiredSms":false'),
    $readyReview.Replace('"VerifiedAccountCount":1','"VerifiedAccountCount":0'),
    $readyReview.Replace('"ConfiguredAccountCount":1','"ConfiguredAccountCount":0'),
    $readyReview.Replace('"ConfiguredAccountCount":1','"ConfiguredAccountCount":"1"'),
    $readyReview.Replace('"MissingOrInvalidAccountCount":0','"MissingOrInvalidAccountCount":1'),
    $readyReview.Replace('"Code":"READY"','"Code":"SMS_REVIEW_CHECK_FAILED"'),
    'CANARY-RAW-CLI-ERROR','[]','null'
)) {Assert-SmsThrows {Convert-VatanSmsReviewReadiness 0 $badReview} 'Malformed, unverified or failed review readiness was accepted.'}
Assert-SmsThrows {Convert-VatanSmsReviewReadiness 2 $readyReview} 'Nonzero CLI exit code was ignored.'
try{throw 'SMS_PARENT_WRITABLE_BY_UNTRUSTED_IDENTITY'}catch{$safeCode=Get-VatanSmsSafeFailureCode $_}
Assert-SmsTest ($safeCode -ceq 'SMS_PARENT_WRITABLE_BY_UNTRUSTED_IDENTITY') 'Known local configuration failure was not preserved as its safe code.'
foreach($unknownMessage in @('SMS_PARENT_OWNER_UNTRUSTED CANARY-KEY','SMS_UNKNOWN_PROVIDER_CODE','SMS_CREDENTIAL_FORMAT: CANARY-KEY','sms_admin_required')) {
    try{throw $unknownMessage}catch{$safeCode=Get-VatanSmsSafeFailureCode $_}
    Assert-SmsTest ($safeCode -ceq 'SMS_SETUP_FAILED') 'An arbitrary, extended or differently cased failure escaped the exact error allowlist.'
}

$fixture=Join-Path $repository ('tmp\vatan-sms-tests-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
# Exercise actual File.Move -> File.Replace -> retry and JSON round trips on
# Windows PowerShell 5.1. ACL calls are isolated to this child scope only.
& {
    $aclEvents=New-Object Collections.Generic.List[string]
    function Assert-VatanSmsProtectedParent([string]$Path){}
    function Protect-VatanSmsFile([string]$Path,[string]$Pool=''){$aclEvents.Add($Pool+':'+[IO.Path]::GetExtension($Path))}
    $destination=Join-Path $fixture 'atomic.json'
    Write-VatanSmsProtectedJson $destination $original
    Assert-SmsTest ((Convert-SmsTestJson (Get-Content -LiteralPath $destination -Raw -Encoding UTF8 | ConvertFrom-Json)) -ceq (Convert-SmsTestJson $original)) 'Initial protected JSON creation failed.'
    Write-VatanSmsProtectedJson $destination $staged 'fixture-pool'
    Assert-SmsTest ((Get-Content -LiteralPath $destination -Raw -Encoding UTF8 | ConvertFrom-Json).Sms.Enabled) 'Atomic settings replacement failed.'
    Write-VatanSmsProtectedJson $destination $original 'fixture-pool'
    Assert-SmsTest (!(Get-Content -LiteralPath $destination -Raw -Encoding UTF8 | ConvertFrom-Json).Sms.Enabled) 'Repeated atomic replacement failed.'
    Assert-SmsTest ($aclEvents.Count -eq 6 -and $aclEvents[0] -eq ':.tmp' -and $aclEvents[1] -eq ':.json' -and $aclEvents[2] -eq 'fixture-pool:.tmp' -and $aclEvents[3] -eq 'fixture-pool:.json') 'Temporary or resulting secret files were not protected.'
    Assert-SmsTest (@(Get-ChildItem -LiteralPath $fixture -Filter '*.tmp').Count -eq 0) 'Successful write left temporary secret files.'
    $beforeHash=(Get-FileHash -LiteralPath $destination).Hash
    $lock=[IO.File]::Open($destination,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {Assert-SmsThrows {Write-VatanSmsProtectedJson $destination $staged 'fixture-pool'} 'A locked destination did not stop replacement.'}finally{$lock.Dispose()}
    Assert-SmsTest ((Get-FileHash -LiteralPath $destination).Hash -ceq $beforeHash) 'Failed replacement modified existing settings.'
    Assert-SmsTest (@(Get-ChildItem -LiteralPath $fixture -Filter '*.tmp').Count -eq 0) 'Failed write left temporary secret files.'
}

# Run the complete setup/rollback flow against real local JSON writes. Only
# external IIS/provider/health/secret/ACL boundaries are mocked; a regression in
# policy preservation, write ordering, rollback or safe reports is observable.
& {
    function Assert-VatanSmsProtectedParent([string]$Path){}
    function Protect-VatanSmsFile([string]$Path,[string]$Pool=''){}
    $state=[pscustomobject]@{RequirePhone=$false;PasswordLogin=$true;Available=$false}
    $senderResponse='{"status":"success","data":["TESTSENDER"]}'
    $restarts=New-Object Collections.Generic.List[string]
    $healthChecks=New-Object Collections.Generic.List[object]
    $contextCalls=0;$secretReads=0;$postFailure=$false;$maliciousError=$false;$reviewCalls=New-Object Collections.Generic.List[string];$reviewReady=$false
    function Get-VatanSmsIisContext([string]$ConfigFile,[string]$Root,[string]$PoolName){$contextCalls++;return [pscustomobject]@{SettingsPath=$ConfigFile;SiteRoot=$Root;Pool=$PoolName}}
    function Get-VatanSmsApiState{return $state}
    function Read-VatanSmsSecret{$secretReads++;return $testKey}
    function Get-VatanSmsReviewReadiness([string]$ConfigFile,[string]$Root,$EnvironmentOverrides){
        $reviewCalls.Add($ConfigFile)
        if(!$reviewReady){throw 'SMS_REVIEW_READINESS_NOT_READY'}
        return Convert-VatanSmsReviewReadiness 0 $readyReview
    }
    function Invoke-VatanSmsSenderCheck([string]$Id,[string]$Key,[string]$SenderName){
        if($maliciousError){throw 'CANARY-FAKE-SMS-KEY echoed by provider'}
        return Get-VatanSmsSenderAudit 200 $senderResponse $SenderName
    }
    function Restart-WebAppPool([string]$Name){$restarts.Add($Name)}
    function Invoke-VatanSmsApiCheck([bool]$RequirePhone,[bool]$PasswordLogin,[bool]$Available){
        $healthChecks.Add([pscustomobject]@{RequirePhone=$RequirePhone;PasswordLogin=$PasswordLogin;Available=$Available})
        if($postFailure -and $Available){throw 'SMS_API_HEALTH_OR_AUTH_OPTIONS_FAILED'}
    }
    function New-SmsScenario([string]$Name){
        $folder=Join-Path $fixture $Name;New-Item -ItemType Directory -Path $folder | Out-Null
        $path=Join-Path $folder 'settings.json';[IO.File]::WriteAllText($path,(Convert-SmsTestJson $original),(New-Object Text.UTF8Encoding($false)))
        return $path
    }
    $path=New-SmsScenario 'check'
    $beforeHash=(Get-FileHash -LiteralPath $path).Hash
    $result=Invoke-VatanSmsConfiguration $testId $testSender $path 'unused-root' 'santiye' 'Check'
    Assert-SmsTest ($result.Status -eq 'READ_ONLY_PREFLIGHT' -and $result.SenderAudit.SenderVerified -and !$result.SettingsChanged -and !$result.SmsSent) 'Read-only provider check result was incorrect.'
    Assert-SmsTest ((Get-FileHash -LiteralPath $path).Hash -ceq $beforeHash -and $restarts.Count -eq 0 -and @(Get-ChildItem (Split-Path $path)).Count -eq 1) 'Check wrote configuration, backup or restarted IIS.'

    $path=New-SmsScenario 'stage'
    $result=Invoke-VatanSmsConfiguration $testId $testSender $path 'unused-root' 'santiye'
    $after=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-SmsTest ($result.Status -eq 'SMS_CONFIGURED' -and $result.Mode -eq 'Stage' -and !$result.PhoneVerificationRequired -and $result.PhoneVerificationAvailable -and !$result.SmsSent) 'Default setup was not a staged configuration.'
    Assert-SmsTest ($after.Sms.Enabled -and !$after.Auth.RequirePhoneVerification -and $after.Auth.AccountLogin.Enabled) 'Stage disabled review login or required unverified phones.'
    foreach($property in $original.PSObject.Properties | Where-Object {$_.Name -ne 'Sms'}) {
        Assert-SmsTest ((Convert-SmsTestJson $after.($property.Name)) -ceq (Convert-SmsTestJson $property.Value)) 'Complete setup changed a non-SMS setting.'
    }
    Assert-SmsTest ((Convert-SmsTestJson (Get-Content -LiteralPath $result.BackupPath -Raw -Encoding UTF8 | ConvertFrom-Json)) -ceq (Convert-SmsTestJson $original)) 'Protected backup did not retain original configuration.'
    Assert-SmsTest ($restarts.Count -eq 1 -and $restarts[0] -eq 'santiye' -and $healthChecks.Count -eq 1 -and !$healthChecks[0].RequirePhone -and $healthChecks[0].PasswordLogin -and $healthChecks[0].Available) 'Stage did not restart only the API pool and verify original auth policy with SMS available.'
    Assert-SmsTest ($reviewCalls.Count -eq 0) 'Check or Stage accessed review-account/database readiness.'
    Assert-SmsTest ((Convert-SmsTestJson $result) -notmatch 'CANARY|TESTSENDER|123456') 'Setup result leaked credentials or unrelated settings.'

    $path=New-SmsScenario 'wrong-sender';$beforeHash=(Get-FileHash -LiteralPath $path).Hash
    $senderResponse='{"status":"success","data":["OTHER"]}'
    $result=Invoke-VatanSmsConfiguration $testId $testSender $path 'unused-root' 'santiye' 'Stage'
    Assert-SmsTest ($result.Status -eq 'STOPPED' -and !$result.SettingsWriteAttempted -and $result.Rollback -eq 'NOT_REQUIRED' -and !$result.SenderAudit.SenderVerified) 'Wrong sender did not fail closed.'
    Assert-SmsTest ($result.Code -ceq 'SMS_SENDER_RESPONSE_NOT_VERIFIED') 'Known sender-preflight failure did not report its safe code.'
    Assert-SmsTest ((Get-FileHash -LiteralPath $path).Hash -ceq $beforeHash -and $restarts.Count -eq 1 -and @(Get-ChildItem (Split-Path $path)).Count -eq 1) 'Wrong sender mutated configuration, wrote backup or restarted IIS.'
    $senderResponse='{"status":"success","data":["TESTSENDER"]}'

    $path=New-SmsScenario 'enable-guard';$beforeHash=(Get-FileHash -LiteralPath $path).Hash
    $result=Invoke-VatanSmsConfiguration $testId $testSender $path 'unused-root' 'santiye' 'Enable'
    Assert-SmsTest ($result.Status -eq 'STOPPED' -and !$result.SettingsWriteAttempted -and (Get-FileHash -LiteralPath $path).Hash -ceq $beforeHash -and $restarts.Count -eq 1) 'Enable accepted an unstaged SMS provider.'
    [IO.File]::WriteAllText($path,(Convert-SmsTestJson $staged),(New-Object Text.UTF8Encoding($false)))
    $beforeHash=(Get-FileHash -LiteralPath $path).Hash
    $result=Invoke-VatanSmsConfiguration $testId $testSender $path 'unused-root' 'santiye' 'Enable'
    Assert-SmsTest ($result.Status -eq 'STOPPED' -and $result.Phase -eq 'REVIEW_ACCOUNT_READ_ONLY_CHECK' -and !$result.SettingsWriteAttempted -and $reviewCalls.Count -eq 1 -and (Get-FileHash -LiteralPath $path).Hash -ceq $beforeHash -and $restarts.Count -eq 1) 'Enable locked out an unverified password/review account.'

    $path=New-SmsScenario 'rollback';$postFailure=$true
    $result=Invoke-VatanSmsConfiguration $testId $testSender $path 'unused-root' 'santiye' 'Stage'
    Assert-SmsTest ($result.Status -eq 'STOPPED' -and $result.SettingsWriteAttempted -and $result.Rollback -eq 'RESTORED') 'Failed post-restart health check did not rollback.'
    Assert-SmsTest ((Convert-SmsTestJson (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)) -ceq (Convert-SmsTestJson $original)) 'Rollback did not restore all original settings.'
    Assert-SmsTest ($restarts.Count -eq 3 -and $restarts[1] -eq 'santiye' -and $restarts[2] -eq 'santiye' -and $healthChecks.Count -eq 3 -and !$healthChecks[2].Available -and !$healthChecks[2].RequirePhone -and $healthChecks[2].PasswordLogin) 'Rollback did not restart only the API pool and verify previous runtime auth state.'

    $path=New-SmsScenario 'raw-error';$maliciousError=$true
    $result=Invoke-VatanSmsConfiguration $testId $testSender $path 'unused-root' 'santiye' 'Stage'
    Assert-SmsTest ($result.Status -eq 'STOPPED' -and $result.Code -ceq 'SMS_SETUP_FAILED' -and $result.RawErrorSuppressed -and (Convert-SmsTestJson $result) -notmatch 'CANARY|echoed') 'Raw provider failure was exposed or assigned an unapproved error code.'

    $path=New-SmsScenario 'enable-verified';$reviewReady=$true;$postFailure=$false;$maliciousError=$false
    [IO.File]::WriteAllText($path,(Convert-SmsTestJson $staged),(New-Object Text.UTF8Encoding($false)))
    # Enable must reuse the protected staged key; no second secret prompt.
    function Read-VatanSmsSecret {throw 'UNEXPECTED_SECOND_KEY_PROMPT'}
    $result=Invoke-VatanSmsConfiguration '' '' $path 'unused-root' 'santiye' 'Enable'
    $after=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-SmsTest ($result.Status -eq 'SMS_CONFIGURED' -and $result.PhoneVerificationRequired -and $result.PhoneVerificationAvailable -and !$result.SmsSent -and $reviewCalls.Count -eq 2) 'Verified review accounts did not allow explicit enable using staged credentials.'
    Assert-SmsTest ($after.Auth.RequirePhoneVerification -and $after.Auth.AccountLogin.Enabled -and $after.Auth.AccountLogin.Accounts[0].PasswordHash -ceq $original.Auth.AccountLogin.Accounts[0].PasswordHash) 'Enable changed review credentials or did not require normal phone verification.'
}
Write-Output ('VatanSMS PowerShell checks passed: '+$script:checks+'. No SMS/provider/IIS/DB requests; isolated local fixtures retained under tmp/.')

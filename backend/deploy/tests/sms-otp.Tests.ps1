$ErrorActionPreference='Stop'
$helper=Join-Path $PSScriptRoot '..\test-sms-otp.ps1'
$tokens=$null;$errors=$null
[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { throw 'SMS helper parse failed.' }
. $helper -FunctionsOnly
$script:checks=0
function Assert-SmsOtp([bool]$Value,[string]$Message) { if (!$Value) { throw $Message };$script:checks++ }
foreach ($phoneValue in @('5550000199','05550000199','+905550000199',' 0555 000 01 99 ')) {
    Assert-SmsOtp ((ConvertTo-SmsOtpPhone $phoneValue) -ceq '+905550000199') 'Phone normalization failed.'
}
foreach ($phoneValue in @('','+90555000019','+905550000199x','+904550000199','905550000199','555-000-0199')) {
    $failed=$false;try { ConvertTo-SmsOtpPhone $phoneValue | Out-Null } catch { $failed=$true }
    Assert-SmsOtp $failed 'Invalid phone accepted.'
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('santiye-sms-otp-'+[guid]::NewGuid().ToString('N')+'.json')
$fixtureId='d1f260be-6af1-44bc-878f-a25fc711b114'
$otherId='638c262a-6f30-4c63-9fd6-77d0c6875f1b'
try {
    @{Auth=@{AccountLogin=@{Accounts=@(@{UserId=$fixtureId;PasswordHash='fixture-private-hash'},@{UserId=$fixtureId;PasswordHash='fixture-private-hash'})}}} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fixture -Encoding UTF8
    Assert-SmsOtp (@(Get-SmsOtpReviewIds $fixture).Count -eq 1) 'Review account IDs were not unique.'
    & {
        $script:requestCount=0;$script:verifyCount=0;$script:profileCount=0;$script:codeReadCount=0
        $script:requestStatus=200;$script:verifyStatus=200;$script:verifiedId=$fixtureId
        function Read-SmsOtpCode { $script:codeReadCount++;return '246810' }
        function Invoke-SmsOtpHttp([string]$Method,[string]$Route,$Body,[string]$AccessToken) {
            switch -CaseSensitive ($Route) {
                '/api/v1/auth/phone/request' {
                    $script:requestCount++
                    Assert-SmsOtp ($Method -ceq 'POST' -and $Body.phone -ceq '+905550000199' -and !$AccessToken) 'Request payload/route incorrect.'
                    return [pscustomobject]@{Status=$script:requestStatus;Data=[pscustomobject]@{sent=$true}}
                }
                '/api/v1/auth/phone/verify' {
                    $script:verifyCount++
                    Assert-SmsOtp ($Method -ceq 'POST' -and $Body.code -ceq '246810' -and !$AccessToken) 'Verify payload/route incorrect.'
                    return [pscustomobject]@{Status=$script:verifyStatus;Data=[pscustomobject]@{phone_verified=$true;user_id=$script:verifiedId;access_token='fixture-private-access';refresh_token='fixture-private-refresh'}}
                }
                '/api/v1/profiles/me' {
                    $script:profileCount++
                    Assert-SmsOtp ($Method -ceq 'GET' -and $AccessToken -ceq 'fixture-private-access') 'Profile check token/route incorrect.'
                    return [pscustomobject]@{Status=200;Data=[pscustomobject]@{id=$script:verifiedId}}
                }
                default { throw 'Unexpected route.' }
            }
        }
        $first=Invoke-SmsOtpTest '0555 000 01 99' $fixture
        Assert-SmsOtp ($first.OtpRequested -and $first.PhoneVerified -and $first.ProfileComplete -and $first.ReviewAccountMatched -and $first.Code -ceq 'VERIFIED') 'Successful OTP result incorrect.'
        Assert-SmsOtp ($script:requestCount -eq 1 -and $script:verifyCount -eq 1 -and $script:profileCount -eq 1 -and $script:codeReadCount -eq 1) 'Successful test sent or verified more than once.'
        $captured=$first | ConvertTo-Json -Compress
        foreach ($secret in @('246810','fixture-private-access','fixture-private-refresh','fixture-private-hash','+905550000199',$fixtureId)) {
            Assert-SmsOtp (!$captured.Contains($secret)) 'Sensitive data escaped into output.'
        }
        $script:verifiedId=$otherId
        $different=Invoke-SmsOtpTest '5550000199' $fixture
        Assert-SmsOtp ($different.PhoneVerified -and !$different.ReviewAccountMatched) 'Different review account incorrectly matched.'
        $script:requestCount=0;$script:verifyCount=0;$script:profileCount=0;$script:verifyStatus=400
        $wrongCode=Invoke-SmsOtpTest '5550000199' $fixture
        Assert-SmsOtp ($wrongCode.Code -ceq 'VERIFY_REJECTED' -and !$wrongCode.PhoneVerified -and $script:requestCount -eq 1 -and $script:verifyCount -eq 1 -and $script:profileCount -eq 0) 'Wrong OTP caused a retry or profile access.'
        $script:requestCount=0;$script:verifyCount=0;$script:codeReadCount=0;$script:requestStatus=503
        $unavailable=Invoke-SmsOtpTest '5550000199' $fixture
        Assert-SmsOtp ($unavailable.Code -ceq 'REQUEST_REJECTED' -and $unavailable.HttpStatus -eq 503 -and $script:requestCount -eq 1 -and $script:verifyCount -eq 0 -and $script:codeReadCount -eq 0) '503 caused a retry or OTP prompt.'
        $script:requestStatus=200
        function Invoke-SmsOtpHttp { throw 'fixture-private-access 246810 +905550000199' }
        $failure=Invoke-SmsOtpTest '5550000199' $fixture
        $captured=$failure | ConvertTo-Json -Compress
        Assert-SmsOtp ($failure.Code -ceq 'SAFE_TEST_FAILURE' -and !$captured.Contains('fixture-private-access') -and !$captured.Contains('246810') -and !$captured.Contains('+905550000199')) 'Raw exception escaped.'
    }
    $source=Get-Content -LiteralPath $helper -Raw
    Assert-SmsOtp ($source.Contains('AllowAutoRedirect=$false') -and $source.Contains('FromSeconds(20)')) 'HTTP redirect/timeout policy absent.'
    Assert-SmsOtp (!$source.Contains('SkipCertificateCheck') -and !$source.Contains('ServerCertificateValidationCallback') -and !$source.Contains('DangerousAcceptAnyServerCertificateValidator')) 'TLS bypass present.'
    Assert-SmsOtp ($source.Contains('ZeroFreeBSTR') -and $source.Contains('-AsSecureString')) 'OTP input is not protected.'
    Write-Output ('SMS OTP local checks passed: '+$script:checks+'. No network or SMS calls made.')
} finally {
    if (Test-Path -LiteralPath $fixture -PathType Leaf) { Remove-Item -LiteralPath $fixture -Force }
}

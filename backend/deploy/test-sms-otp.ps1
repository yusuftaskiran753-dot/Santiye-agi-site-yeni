param(
    [string]$Phone,
    [string]$SettingsPath='C:\ProgramData\santiye\settings.json',
    [switch]$FunctionsOnly
)
$ErrorActionPreference='Stop'

function ConvertTo-SmsOtpPhone([string]$Value) {
    $valueWithoutSpaces=$Value -replace '\s',''
    if ($valueWithoutSpaces -cmatch '^5[0-9]{9}$') { return '+90'+$valueWithoutSpaces }
    if ($valueWithoutSpaces -cmatch '^05[0-9]{9}$') { return '+9'+$valueWithoutSpaces }
    if ($valueWithoutSpaces -cmatch '^\+905[0-9]{9}$') { return $valueWithoutSpaces }
    throw 'PHONE_INVALID'
}

function Get-SmsOtpReviewIds([string]$Path) {
    # Read only IDs, and never serialize the settings object or its credentials.
    $settings=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $ids=@()
    foreach ($account in @($settings.Auth.AccountLogin.Accounts)) {
        $id=[guid]::Empty
        if (![guid]::TryParse([string]$account.UserId,[ref]$id) -or $id -eq [guid]::Empty) { throw 'REVIEW_SETTINGS_INVALID' }
        $ids+=$id.ToString()
    }
    if (!$ids.Count) { throw 'REVIEW_SETTINGS_INVALID' }
    return @($ids | Sort-Object -Unique)
}

function Read-SmsOtpCode {
    $secure=Read-Host 'Telefona gelen 6 haneli kodu yazin (gizli)' -AsSecureString
    $pointer=[IntPtr]::Zero
    try {
        $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        if ($null -ne $secure) { $secure.Dispose() }
    }
}

function Invoke-SmsOtpHttp([string]$Method,[string]$Route,$Body,[string]$AccessToken) {
    # Fixed origin and route allowlist: never follow a redirect with an OTP/token.
    $allowed=@('/api/v1/auth/phone/request','/api/v1/auth/phone/verify','/api/v1/profiles/me')
    if ($Route -cnotin $allowed -or ($Method -cne 'POST' -and $Method -cne 'GET')) { throw 'HTTP_ROUTE_INVALID' }
    Add-Type -AssemblyName System.Net.Http
    $handler=New-Object Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect=$false
    $client=New-Object Net.Http.HttpClient($handler)
    $client.Timeout=[TimeSpan]::FromSeconds(20)
    $message=$null;$response=$null;$json=$null;$raw=$null
    try {
        $message=New-Object Net.Http.HttpRequestMessage((New-Object Net.Http.HttpMethod($Method)),('https://45.59.70.198'+$Route))
        if ($AccessToken) { $message.Headers.Authorization=New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer',$AccessToken) }
        if ($null -ne $Body) {
            $json=$Body | ConvertTo-Json -Compress -Depth 4
            $message.Content=New-Object Net.Http.StringContent($json,[Text.Encoding]::UTF8,'application/json')
        }
        $response=$client.SendAsync($message).GetAwaiter().GetResult()
        $status=[int]$response.StatusCode
        if ($status -lt 200 -or $status -ge 300) { return [pscustomobject]@{Status=$status;Data=$null} }
        $raw=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $data=$null
        if (![string]::IsNullOrWhiteSpace($raw)) { $data=$raw | ConvertFrom-Json }
        return [pscustomobject]@{Status=$status;Data=$data}
    } finally {
        $json=$null;$raw=$null
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $message) { $message.Dispose() }
        $client.Dispose();$handler.Dispose()
    }
}

function Invoke-SmsOtpTest([string]$Phone,[string]$SettingsPath) {
    $result=[ordered]@{OtpRequested=$false;PhoneVerified=$false;ProfileComplete=$false;ReviewAccountMatched=$false;HttpStatus=0;Code='NOT_STARTED';PhoneLast4=$null}
    $code=$null;$verified=$null;$token=$null;$profile=$null
    try {
        try { $normalized=ConvertTo-SmsOtpPhone $Phone } catch { $result.Code='PHONE_INVALID';return [pscustomobject]$result }
        $result.PhoneLast4='*******'+$normalized.Substring($normalized.Length-4)
        try { $reviewIds=@(Get-SmsOtpReviewIds $SettingsPath) } catch { $result.Code='REVIEW_SETTINGS_INVALID';return [pscustomobject]$result }
        # Exactly one SMS request; failures are never automatically retried.
        $request=Invoke-SmsOtpHttp 'POST' '/api/v1/auth/phone/request' @{phone=$normalized} $null
        $result.HttpStatus=$request.Status
        if ($request.Status -lt 200 -or $request.Status -ge 300) { $result.Code='REQUEST_REJECTED';return [pscustomobject]$result }
        if ($request.Data.sent -isnot [bool] -or !$request.Data.sent) { $result.Code='REQUEST_RESPONSE_INVALID';return [pscustomobject]$result }
        $result.OtpRequested=$true
        $code=Read-SmsOtpCode
        if ($code -cnotmatch '^[0-9]{6}$') { $result.Code='OTP_FORMAT_INVALID';return [pscustomobject]$result }
        $verified=Invoke-SmsOtpHttp 'POST' '/api/v1/auth/phone/verify' @{phone=$normalized;code=$code} $null
        $code=$null
        $result.HttpStatus=$verified.Status
        if ($verified.Status -lt 200 -or $verified.Status -ge 300) { $result.Code='VERIFY_REJECTED';return [pscustomobject]$result }
        $userId=[guid]::Empty
        if ($verified.Data.phone_verified -isnot [bool] -or !$verified.Data.phone_verified -or
            ![guid]::TryParse([string]$verified.Data.user_id,[ref]$userId) -or $userId -eq [guid]::Empty -or
            [string]::IsNullOrWhiteSpace([string]$verified.Data.access_token)) { $result.Code='VERIFY_RESPONSE_INVALID';return [pscustomobject]$result }
        $result.PhoneVerified=$true
        $result.ReviewAccountMatched=$reviewIds -contains $userId.ToString()
        $token=[string]$verified.Data.access_token
        $profile=Invoke-SmsOtpHttp 'GET' '/api/v1/profiles/me' $null $token
        $result.HttpStatus=$profile.Status
        if ($profile.Status -eq 204) { $result.Code='VERIFIED_PROFILE_INCOMPLETE';return [pscustomobject]$result }
        if ($profile.Status -ne 200) { $result.Code='VERIFIED_PROFILE_CHECK_FAILED';return [pscustomobject]$result }
        $profileId=[guid]::Empty
        $result.ProfileComplete=([guid]::TryParse([string]$profile.Data.id,[ref]$profileId) -and $profileId -eq $userId)
        if ($result.ProfileComplete) { $result.Code='VERIFIED' } else { $result.Code='VERIFIED_PROFILE_INCOMPLETE' }
        return [pscustomobject]$result
    } catch {
        # Never expose HTTP bodies, exception text, credentials, or session tokens.
        $result.Code='SAFE_TEST_FAILURE'
        return [pscustomobject]$result
    } finally { $code=$null;$token=$null;$verified=$null;$profile=$null }
}

if ($FunctionsOnly) { return }
Invoke-SmsOtpTest -Phone $Phone -SettingsPath $SettingsPath | ConvertTo-Json -Depth 3

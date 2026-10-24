param(
    [string]$ApiBaseUrl = 'http://127.0.0.1:5080',
    [string]$Phone = '+905000000001'
)

$ErrorActionPreference = 'Stop'
$apiUri = [Uri]$ApiBaseUrl
if (-not $apiUri.IsAbsoluteUri -or $apiUri.Host -notin @('localhost', '127.0.0.1') -or
    $apiUri.Scheme -notin @('http', 'https') -or $apiUri.UserInfo -or
    $apiUri.Query -or $apiUri.Fragment -or $apiUri.AbsolutePath -ne '/') {
    throw 'Bu arac yalniz yerel test API adresinde kullanilabilir.'
}
if ($Phone -notmatch '^\+905\d{9}$') { throw 'Gecerli bir Turkiye test telefonu gerekli.' }
$apiRoot = $ApiBaseUrl.TrimEnd('/') + '/api/v1'

function Invoke-TestApi {
    param([string]$Method, [string]$Path, [hashtable]$Data, [hashtable]$Headers = @{})
    $requestArgs = @{
        Method = $Method
        Uri = $apiRoot + $Path
        Headers = $Headers
        TimeoutSec = 20
        ErrorAction = 'Stop'
    }
    if ($null -ne $Data) {
        $requestArgs.ContentType = 'application/json; charset=utf-8'
        $requestArgs.Body = [Text.Encoding]::UTF8.GetBytes(($Data | ConvertTo-Json -Compress))
    }
    Invoke-RestMethod @requestArgs
}

# Kod yalniz Development ortamindan gelir. Canli dogrulama taklit edilmez.
$challenge = Invoke-TestApi -Method POST -Path '/auth/phone/request' -Data @{ phone = $Phone }
if ($challenge.development_code -notmatch '^\d{6}$') {
    throw 'Gelistirme kodu alinmadi. Bu arac Production ortaminda kullanilamaz.'
}
$session = Invoke-TestApi -Method POST -Path '/auth/phone/verify' -Data @{
    phone = $Phone
    code = $challenge.development_code
}
$authHeaders = @{
    Authorization = 'Bearer ' + $session.access_token
    'Idempotency-Key' = [Guid]::NewGuid().ToString()
}
$profile = Invoke-TestApi -Method PUT -Path '/profiles/me' -Headers $authHeaders -Data @{
    name = 'Test Kullanıcısı'
    company = 'Şantiye Ağı Test'
    role = 'muteahhit'
    city = 'İstanbul'
    phone = $Phone
}
if (-not $profile.phone_verified) { throw 'Test dogrulama durumu beklenen degeri vermedi.' }

# Oturum anahtarlari ve kodlar terminale ya da dosyaya yazilmaz.
Invoke-TestApi -Method POST -Path '/auth/logout' -Headers $authHeaders | Out-Null
[pscustomobject]@{
    Name = $profile.name
    Phone = $Phone
    UserId = $profile.id
    PhoneVerified = $profile.phone_verified
    Environment = 'Local development test; no SMS sent'
}

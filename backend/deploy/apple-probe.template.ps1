# Generated diagnostic contains public compiled code only, never private keys.
$ErrorActionPreference='Stop'
$files=__PROBE_FILES__
$target=$null
try {
    $base='C:\ProgramData\santiye'
    $target=Join-Path $base ('apple-probe-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $target | Out-Null
    & icacls.exe $target /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' | Out-Null
    if($LASTEXITCODE -ne 0){throw 'ACL'}
    foreach($name in $files.Keys){
        $path=Join-Path $target $name
        [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($files[$name].data))
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $files[$name].sha256){throw 'HASH'}
    }
    $previous=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $raw=@(& dotnet (Join-Path $target 'SantiyeAgi.AppleAccessProbe.dll') 'C:\ProgramData\santiye\keys\AuthKey_CY8L78UR5Q.p8' 2>&1)
        $nativeCode=$LASTEXITCODE
    } finally {$ErrorActionPreference=$previous}
    $found=$false
    foreach($line in $raw){
        try {
            $r=[string]$line | ConvertFrom-Json -ErrorAction Stop
            if($r.Stage -cin @('READ_KEY','SIGN_TOKEN','APPLE_HTTP') -and $r.Code -cin @('KEY_FILE_MISSING','KEY_FILE_TOO_LARGE','KEY_FILE_ACCESS_DENIED','KEY_FILE_READ_FAILED','KEY_MUST_BE_P256','KEY_FORMAT_OR_PRIVATE_KEY_INVALID','PRIVATE_KEY_CANNOT_SIGN','APPLE_AUTH_REJECTED','APPLE_ACCESS_FORBIDDEN','APPLE_APP_OR_ENDPOINT_NOT_FOUND','APPLE_RATE_LIMITED','APPLE_REQUEST_REJECTED','APPLE_RESPONSE_UNEXPECTED','APPLE_API_ACCESS_CONFIRMED','DNS_FAILED','TLS_FAILED','NETWORK_FAILED','NETWORK_TIMEOUT')){
                $status=$null
                if($r.AppleHttpStatus -ge 100 -and $r.AppleHttpStatus -le 599){$status=[int]$r.AppleHttpStatus}
                [pscustomobject]@{Asama=$r.Stage;Sonuc=$r.Code;AppleHttpStatus=$status;ApiErisimiDogrulandi=($r.ApiAccessVerified -eq $true -and $r.Code -ceq 'APPLE_API_ACCESS_CONFIRMED')} | ConvertTo-Json
                $found=$true
            }
        } catch { }
    }
    if(!$found){Write-Output 'Tani programindan guvenli sonuc alinamadi. .NET 10 calisma ortami kontrol edilmeli. Ham cikti yazdirilmadi.'}
    Write-Output 'Bu arac Billing/SMS/TestFlight/IIS ayarlarini degistirmez. TEST istegi satin alma veya callback teslim kaniti degildir.'
} catch {Write-Output 'Tani araci baslatilamadi. Yonetici PowerShell ve ProgramData klasoru izinlerini kontrol edin. Ham hata yazdirilmadi.'}
finally {
    $raw=$null
    if($target){
        foreach($name in $files.Keys){$path=Join-Path $target $name;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}

param(
    [string]$SiteRoot='C:\inetpub\wwwroot\santiye',
    [string]$AppPool='santiye',
    [string]$PrivateKeyFile='C:\ProgramData\santiye\keys\AuthKey_CY8L78UR5Q.p8',
    [string]$KeyId='CY8L78UR5Q',
    [string]$IssuerId='e0061e2a-caf2-40d0-81f4-21d2ead8c973',
    [switch]$VerifyOnly,
    [switch]$PreRelease,
    [string]$AccessProbeDll='',
    [string]$AccessProbeSha256=''
)
# Run elevated on Windows Server. Never accepts key content as an argument.
$ErrorActionPreference='Stop'
$stage=$null; $before=@{}; $changedEnvironment=$false; $saved=$false; $phase='IIS/dosya on kontrolu'
$pattern='^(ConnectionStrings|Auth|Sms|Push|AI|Billing|DataProtection|Logging)__|^SANTIYE_CONFIG_FILE$|^ASPNETCORE_ENVIRONMENT$|^DOTNET_ENVIRONMENT$'
function Test-PrereleaseAppleAccess($result,[string]$expectedHash) {
    foreach($flag in @('ApiAccessVerified','KeyHashMatches','JwtHeaderMatches','JwtPayloadMatches','JwtSignatureValid')){
        if($result.$flag -isnot [bool] -or !$result.$flag){return $false}
    }
    return ($result.AuditVersion -eq 1 -and $result.Code -ceq 'APPLE_API_ACCESS_CONFIRMED' -and
        $result.AppleHttpStatus -is [int] -and $result.AppleHttpStatus -eq 200 -and
        $result.Endpoint -ceq 'https://api.storekit-sandbox.apple.com/inApps/v1/notifications/history' -and
        $result.KeySha256 -ceq $expectedHash -and $result.JwtSignatureBytes -eq 64 -and $result.JwtLifetimeSeconds -eq 300)
}
function Merge-AppleBillingSettings($existing,$appleFields) {
    if($null -eq $existing.Billing){$existing | Add-Member -NotePropertyName Billing -NotePropertyValue ([pscustomobject]@{})}
    foreach($name in $appleFields.Keys){$existing.Billing | Add-Member -NotePropertyName $name -NotePropertyValue $appleFields[$name] -Force}
    return $existing
}
function Protect-File([string]$path,[switch]$PoolRead) {
    $acl=New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-18','S-1-5-32-544')) {
        $identity=New-Object Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','Allow')))
    }
    if($PoolRead){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(('IIS AppPool\'+$AppPool),'Read','Allow')))}
    Set-Acl -LiteralPath $path -AclObject $acl
}
try {
    if($KeyId -notmatch '^[A-Z0-9]{10}$' -or $IssuerId -notmatch '^[a-fA-F0-9-]{36}$'){throw 'Anahtar kimlikleri gecersiz.'}
    Import-Module WebAdministration
    $inspection=Join-Path $PSScriptRoot 'inspect-ios-readiness.ps1'
    if(!(Test-Path -LiteralPath $inspection -PathType Leaf)){$inspection=Join-Path $SiteRoot 'deploy\inspect-ios-readiness.ps1'}
    $check=(& $inspection -SiteRoot $SiteRoot -AppPool $AppPool) | ConvertFrom-Json
    if(!$check.IisConfigPathResolved -or $check.HostingEnvironment -ne 'Production'){throw 'Uretim IIS ayari dogrulanamadi.'}
    $settingsPath=$check.SettingsPath
    $siteFull=[IO.Path]::GetFullPath($SiteRoot).TrimEnd('\')+'\'
    $keyFull=[IO.Path]::GetFullPath($PrivateKeyFile)
    $keysRoot=[IO.Path]::GetFullPath((Join-Path (Split-Path $settingsPath -Parent) 'keys')).TrimEnd('\')+'\'
    if(!$keyFull.StartsWith($keysRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Anahtar secili dis ayarlarin keys klasorunde olmali.'}
    if($keyFull.StartsWith($siteFull,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $keyFull -PathType Leaf)){throw 'P8 dosyasi web klasoru disinda, ProgramData keys altinda olmali. Once guvenli aktarimi tamamlayin.'}
    if((Get-Item -LiteralPath $keyFull).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Anahtar baglanti dosyasi olamaz.'}
    $expectedKeyHash='0a969ec424de180b72a7dcbf7e7b3f39ff954d47397cbb382a4c0b560820f9c2'
    if($PreRelease){
        if($KeyId -cne 'CY8L78UR5Q' -or $IssuerId -cne 'e0061e2a-caf2-40d0-81f4-21d2ead8c973'){throw 'Yayin oncesi kimlikler degisti; yeni kanit gerekir.'}
        if((Get-FileHash -LiteralPath $keyFull -Algorithm SHA256).Hash -ine $expectedKeyHash){throw 'Dogrulanmis anahtar dosyasi degisti.'}
        if($AccessProbeSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or !$AccessProbeDll -or !(Test-Path -LiteralPath $AccessProbeDll -PathType Leaf) -or
           (Get-FileHash -LiteralPath $AccessProbeDll -Algorithm SHA256).Hash -ine $AccessProbeSha256){throw 'Yayin oncesi kontrol araci dogrulanamadi.'}
    }
    $dll=Join-Path $SiteRoot 'SantiyeAgi.Api.dll'
    $cap=Get-Content -LiteralPath (Join-Path $SiteRoot 'OPERATIONS-CAPABILITIES.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($cap.apple_api_access_check -ne 1 -or $cap.assembly_sha256 -ne (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash){throw 'Once yeni backend paketini kurun; bu DLL guvenli anahtar kontrolunu desteklemiyor.'}
    $effective=@{}
    foreach($item in [Environment]::GetEnvironmentVariables('Machine').GetEnumerator()){$effective[$item.Key]=[string]$item.Value}
    foreach($item in (Get-Item ('IIS:\AppPools\'+$AppPool)).environmentVariables.Collection){$effective[[string]$item.name]=[string]$item.value}
    [xml]$web=Get-Content -LiteralPath (Join-Path $SiteRoot 'web.config') -Raw -Encoding UTF8
    foreach($item in $web.SelectNodes('//aspNetCore/environmentVariables/environmentVariable')){$effective[[string]$item.name]=[string]$item.value}
    if(@($effective.Keys | Where-Object {$_ -match '^Billing__'}).Count){throw 'IIS/makine Billing ortam degiskenleri var; dosya ayarini ezebilir. Degistirilmeden once incelenmeli.'}
    $originalHash=(Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash
    $settings=Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($settings -isnot [pscustomobject] -or ($null -ne $settings.Billing -and $settings.Billing -isnot [pscustomobject])){throw 'Ayar bicimi gecersiz.'}
    $phase='Ozel anahtar izinleri / Apple kok sertifikasi'
    Protect-File $keyFull -PoolRead
    $root=Join-Path (Split-Path $keyFull -Parent) 'AppleRootCA-G3.cer'
    if(!(Test-Path -LiteralPath $root -PathType Leaf)){
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri 'https://www.apple.com/certificateauthority/AppleRootCA-G3.cer' -OutFile $root | Out-Null
    }
    if((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Sertifika baglanti dosyasi olamaz.'}
    if((Get-FileHash -LiteralPath $root -Algorithm SHA256).Hash -ne '63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179'){throw 'Apple kok sertifika hash uyusmuyor.'}
    Protect-File $root -PoolRead
    # Minimal temporary config: no live password, connection string or provider key copied.
    $stage=Join-Path (Split-Path $settingsPath -Parent) ('apple-check-'+[guid]::NewGuid().ToString('N')+'.json')
    New-Item -ItemType File -Path $stage | Out-Null
    Protect-File $stage
    $candidate=@{Enabled=$true;AllowSandbox=$false;AppleBundleId='com.yusuftaskiran.santiyeagi.pro';AppleAppId=6824034438;AppleIssuerId=$IssuerId;AppleKeyId=$KeyId;ApplePrivateKeyFile=$keyFull;AppleRootCertificateFiles=@($root)}
    $temporary=@{Auth=@{SigningKey=([guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N'))};ConnectionStrings=@{Postgres='Host=127.0.0.1;Port=1;Database=santiye_test_no_connection;Username=unused'};DataProtection=@{KeysPath=(Split-Path $stage -Parent)};Billing=$candidate;Logging=@{LogLevel=@{Default='None'}}}
    [IO.File]::WriteAllText($stage,($temporary | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
    foreach($item in Get-ChildItem Env:){if($item.Name -match $pattern){$before[$item.Name]=$item.Value}}
    $changedEnvironment=$true
    foreach($item in @(Get-ChildItem Env:)){if($item.Name -match $pattern){[Environment]::SetEnvironmentVariable($item.Name,$null,'Process')}}
    $env:SANTIYE_CONFIG_FILE=$stage; $env:DOTNET_ENVIRONMENT='Production'
    $phase=if($PreRelease){'Apple Sandbox API salt okuma yetki istegi'}else{'Apple satin alma API gercek yetki istegi'}
    $arguments=if($PreRelease){@($AccessProbeDll,'--audit','--sandbox-history',$keyFull)}else{@($dll,'--apple-api-access-check')}
    Push-Location $SiteRoot
    try {
        # Windows PowerShell 5.1 treats redirected native stderr as ErrorRecord.
        # Collect it without terminating before the safe diagnostic can run.
        $previousPreference=$ErrorActionPreference
        try {$ErrorActionPreference='Continue';$raw=@(& dotnet @arguments 2>&1);$code=$LASTEXITCODE}
        finally {$ErrorActionPreference=$previousPreference}
    } finally {Pop-Location}
    $safe=@();$hasSafeError=$false;$auditRecords=0
    foreach($line in $raw){
        try {
            $parsed=([string]$line | ConvertFrom-Json -ErrorAction Stop)
            if($PreRelease){
                if($null -ne $parsed.AuditVersion){$auditRecords++}
                if(Test-PrereleaseAppleAccess $parsed $expectedKeyHash){$safe+=1}
            } elseif($parsed.environment -ceq 'Production' -and $parsed.api_access_verified -is [bool] -and $parsed.api_access_verified){$safe+=1}
            if($parsed.error -cin @('CONFIG','SERVER','APPLE_CHECK_FAILED')){$hasSafeError=$true;Write-Output ('Guvenli API sonucu: '+$parsed.error)}
        } catch { }
    }
    Write-Output ('Kontrol islemi cikis kodu: '+[int]$code)
    if(!$safe.Count -and !$hasSafeError){
        $diagnosis='SAFE_JSON_YOK'
        $text=($raw | ForEach-Object {[string]$_}) -join "`n"
        if($text -match 'You must install or update .NET|compatible framework version|framework.*not found'){$diagnosis='DOTNET_RUNTIME'}
        elseif($text -match 'SigningKey must be|ConnectionStrings:Postgres required|SANTIYE_CONFIG_FILE'){$diagnosis='LOCAL_CONFIG'}
        elseif($text -match 'UnauthorizedAccessException|Access.*denied'){$diagnosis='DOSYA_ERISIMI'}
        Write-Output ('Tani sinifi: '+$diagnosis+'. Ham cikti yazdirilmadi.')
    }
    if($code -ne 0 -or $safe.Count -ne 1 -or ($PreRelease -and $auditRecords -ne 1)){throw 'Apple satin alma API yetkisi dogrulanamadi. Canli Billing ayarlari degistirilmedi; anahtar turu/Issuer/Key ID kontrol edilmeli.'}
    if($PreRelease){
        Write-Output 'Apple Sandbox API bu anahtar/Issuer/uygulama icin gercek okuma istegini kabul etti. Production erisimi ve satin alma/teslim testi bu sonuc ile dogrulanmaz.'
        if((Get-FileHash -LiteralPath $keyFull -Algorithm SHA256).Hash -ine $expectedKeyHash){throw 'Anahtar dosyasi kontrol sirasinda degisti.'}
    } else {Write-Output 'Apple App Store Server API gercek istegi kabul etti. Anahtarin bu uygulama icin API erisimi dogrulandi; satin alma/teslim testi degildir.'}
    if($VerifyOnly){Write-Output 'Yalniz kontrol: canli Billing dosyasi degistirilmedi.';return}
    $phase='Ayarlarin guvenli kaydi'
    if((Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256).Hash -ne $originalHash){throw 'Ayarlar kontrol sirasinda degisti; uzerine yazilmadi. Yeniden calistirin.'}
    $settings=Merge-AppleBillingSettings $settings $candidate
    # Stage inherits no public access; File.Replace preserves the destination ACL.
    [IO.File]::WriteAllText($stage,($settings | ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
    $backup=$stage+'.previous'
    [IO.File]::Replace($stage,$settingsPath,$backup);$stage=$null;$saved=$true
    Protect-File $backup
    $phase='IIS havuzunun yeniden baslatilmasi'
    Restart-WebAppPool -Name $AppPool
    $phase='Kaydedilen ayarlar ve API hazirlik kontrolu'
    $after=(& $inspection -SiteRoot $SiteRoot -AppPool $AppPool) | ConvertFrom-Json
    if(!$after.BillingEnabled -or $after.AllowSandbox -or !$after.AppleBundleMatches -or !$after.AppleAppIdMatches -or
       !$after.AppleIssuerPresent -or !$after.AppleKeyIdPresent -or !$after.ApplePrivateKeyFilePresent -or !$after.AppleRootFilesPresent){throw 'Etkin ayarlar dogrulanamadi.'}
    $ready=$false
    for($attempt=0;$attempt -lt 3;$attempt++){
        try {if((Invoke-RestMethod -Uri 'https://45.59.70.198/health/ready' -TimeoutSec 5).status -ceq 'ready'){$ready=$true;break}}catch { }
        Start-Sleep -Seconds 2
    }
    if(!$ready){throw 'API hazirlik kontrolu gecmedi.'}
    Write-Output 'Apple Billing acildi; Sandbox kapali. SMS, hesap dogrulama, Firebase, Gemini, Google ve veritabani ayarlari korundu.'
    if($PreRelease){Write-Output 'Yayin oncesi ayarlar hazir. Production API ilk yayin sonrasinda tekrar kontrol edilmeli. Sandbox makbuz kabul edilmez; ayri test ortami bekliyor. SMS/TestFlight degistirilmedi.'}
    else {Write-Output 'Simdi deploy/test-apple-notifications.ps1 ile callback teslimini kontrol edin. TestFlight yuklenmedi.'}
}
catch {
    # JSON/parser/native exceptions may contain sensitive input. Never echo them.
    Write-Output ('Kurulum durdu. Asama: '+$phase+'. Apple ayarlari kaydedildi: '+$saved+'. Ham hata guvenlik nedeniyle yazdirilmadi.')
    exit 1
}
finally {
    if($changedEnvironment){
        foreach($item in @(Get-ChildItem Env:)){if($item.Name -match $pattern){[Environment]::SetEnvironmentVariable($item.Name,$null,'Process')}}
        foreach($name in $before.Keys){[Environment]::SetEnvironmentVariable($name,$before[$name],'Process')}
    }
    if($stage -and (Test-Path -LiteralPath $stage)){Remove-Item -LiteralPath $stage -Force}
    $raw=$null;$settings=$null;$temporary=$null
}

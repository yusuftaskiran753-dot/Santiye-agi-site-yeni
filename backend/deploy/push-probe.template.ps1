# Sends exactly one test to the latest active iOS registration of confirmed username test.
$ErrorActionPreference='Stop'
$files=__PROBE_FILES__
$operation='__OPERATION_ID__'
$site='C:\inetpub\wwwroot\santiye';$pool='santiye';$base='C:\ProgramData\santiye'
$target=$null;$previous=@{};$changed=$false;$raw=$null;$settingsPath=$null;$settingsHash=$null
$pattern='^(ConnectionStrings|Auth|Sms|Push|AI|Billing|DataProtection|Logging)__|^SANTIYE_CONFIG_FILE$|^ASPNETCORE_ENVIRONMENT$|^DOTNET_ENVIRONMENT$'
try {
    if((Get-FileHash -LiteralPath (Join-Path $site 'SantiyeAgi.Api.dll') -Algorithm SHA256 -ErrorAction Stop).Hash -cne '9AA6527A290447DD187823EE98CB27815075C89FAFD13D7D8E3FA8E21C5467CF'){throw 'PACKAGE_CHANGED'}
    Import-Module WebAdministration
    $effective=@{}
    foreach($item in [Environment]::GetEnvironmentVariables('Machine').GetEnumerator()){$effective[[string]$item.Key]=[string]$item.Value}
    foreach($item in (Get-Item ('IIS:\AppPools\'+$pool)).environmentVariables.Collection){$effective[[string]$item.name]=[string]$item.value}
    [xml]$web=Get-Content -LiteralPath (Join-Path $site 'web.config') -Raw -Encoding UTF8
    foreach($item in $web.SelectNodes('//aspNetCore/environmentVariables/environmentVariable')){$effective[[string]$item.name]=[string]$item.value}
    $settingsPath=$effective['SANTIYE_CONFIG_FILE']
    if(![IO.Path]::IsPathRooted($settingsPath)){throw 'CONFIG_UNRESOLVED'}
    $settingsHash=(Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256 -ErrorAction Stop).Hash
    $target=Join-Path $base ('push-probe-'+[guid]::NewGuid().ToString('N'))
    $state=Join-Path $base 'push-test-attempts'
    foreach($folder in @($target,$state)){
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        & icacls.exe $folder /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' 2>&1 | Out-Null
        if($LASTEXITCODE -ne 0){throw 'ACL'}
    }
    # Reuse installed API sender/dependencies without deployment, app restart or migrations.
    Get-ChildItem -LiteralPath $site -Filter '*.dll' -File | Copy-Item -Destination $target
    foreach($name in @('SantiyeAgi.PushProbe.dll','SantiyeAgi.PushProbe.deps.json','SantiyeAgi.PushProbe.runtimeconfig.json')){
        $path=Join-Path $target $name
        [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($files[$name].data))
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ine $files[$name].sha256){throw 'PROBE_HASH'}
    }
    foreach($item in Get-ChildItem Env:){if($item.Name -match $pattern){$previous[$item.Name]=$item.Value}}
    $changed=$true
    foreach($item in @(Get-ChildItem Env:)){if($item.Name -match $pattern){[Environment]::SetEnvironmentVariable($item.Name,$null,'Process')}}
    foreach($name in $effective.Keys){if($name -match $pattern){[Environment]::SetEnvironmentVariable($name,$effective[$name],'Process')}}
    $oldPreference=$ErrorActionPreference
    try {$ErrorActionPreference='Continue';$raw=@(& dotnet (Join-Path $target 'SantiyeAgi.PushProbe.dll') $site $state $operation 2>&1)}
    finally {$ErrorActionPreference=$oldPreference}
    $found=$false
    foreach($line in $raw){
        try {
            $r=[string]$line | ConvertFrom-Json -ErrorAction Stop
            if($r.PushProbeVersion -ne 1 -or $r.Username -cne 'test' -or $r.Platform -cne 'ios'){continue}
            $code=if($r.Code -cmatch '^[A-Z_]{1,60}$'){$r.Code}else{'UNKNOWN'}
            $id=[guid]::Empty;$device=[guid]::Empty
            [void][guid]::TryParse([string]$r.AccountId,[ref]$id);[void][guid]::TryParse([string]$r.DeviceId,[ref]$device)
            [pscustomobject]@{Username='test';AccountId=$id;DeviceId=$device;RegisteredAt=$r.RegisteredAt;Platform='ios';FcmRequestCount=$r.FcmRequestCount;FcmHttpStatus=$r.FcmHttpStatus;FcmAccepted=$r.FcmAccepted;Code=$code} | ConvertTo-Json
            $found=$true
        } catch { }
    }
    if(!$found){Write-Output 'Guvenli gonderim sonucu alinamadi. Bildirim gonderilmis olabilir; ayni dosyayi tekrar calistirmak ayni islemi yeniden gondermez. Ham cikti yazdirilmadi.'}
} catch {Write-Output 'Tek cihaz testi baslatilamadi; hesap/kurulu paket/IIS/dosya erisimi kontrol edilmeli. Ham hata yazdirilmadi.'}
finally {
    if($changed){
        foreach($item in @(Get-ChildItem Env:)){if($item.Name -match $pattern){[Environment]::SetEnvironmentVariable($item.Name,$null,'Process')}}
        foreach($name in $previous.Keys){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
    }
    if($settingsPath -and $settingsHash){try {Write-Output ('Sunucu ayarlari degismedi: '+((Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256 -ErrorAction Stop).Hash -ceq $settingsHash))}catch {Write-Output 'Ayar ozeti yeniden okunamadi.'}}
    if($target){
        # No recursion: delete only temporary flat runtime files created/copied here.
        Get-ChildItem -LiteralPath $target -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
    $raw=$null;$effective=$null
}

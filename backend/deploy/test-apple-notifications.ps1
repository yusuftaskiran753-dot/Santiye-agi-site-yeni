param(
    [ValidateSet('Production','Sandbox')][string]$StoreEnvironment='Production',
    [string]$SiteRoot='C:\inetpub\wwwroot\santiye',
    [string]$AppPool='santiye',
    [switch]$IsolatedSandbox
)
$ErrorActionPreference='Stop'
$inspection=Join-Path $PSScriptRoot 'inspect-ios-readiness.ps1'
$check=(& $inspection -SiteRoot $SiteRoot -AppPool $AppPool) | ConvertFrom-Json
if(!$check.IisConfigPathResolved -or !$check.AppleBundleMatches -or !$check.AppleAppIdMatches -or !$check.AppleIssuerPresent -or !$check.AppleKeyIdPresent -or !$check.ApplePrivateKeyFilePresent -or !$check.AppleRootFilesPresent -or !$check.BillingEnabled){throw 'Apple ayarlari tamamlanmadi; herhangi bir test bildirimi istenmedi.'}
if($StoreEnvironment -eq 'Sandbox' -and (!$IsolatedSandbox -or !$check.AllowSandbox)){throw 'Sandbox yalniz ayri API/veritabani ortaminda ve acik izolasyon onayiyla denenebilir.'}
$dll=Join-Path $SiteRoot 'SantiyeAgi.Api.dll'
$capabilityFile=Join-Path $SiteRoot 'OPERATIONS-CAPABILITIES.json'
if(!(Test-Path -LiteralPath $capabilityFile -PathType Leaf)){throw 'Bu backend paketi TEST komutunu desteklemiyor; once yeni paket kurulmalidir.'}
$capability=Get-Content -LiteralPath $capabilityFile -Raw | ConvertFrom-Json
if($capability.apple_notification_test -ne 1 -or $capability.assembly_sha256 -ne (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash){throw 'Backend TEST yetenek dosyasi/DLL dogrulanamadi.'}

$envPattern='^(ConnectionStrings|Auth|Sms|Push|AI|Billing|DataProtection|Logging)__|^SANTIYE_CONFIG_FILE$|^ASPNETCORE_ENVIRONMENT$|^DOTNET_ENVIRONMENT$'
$before=@{}; foreach($item in Get-ChildItem Env:){if($item.Name -match $envPattern){$before[$item.Name]=$item.Value}}
try {
    Import-Module WebAdministration
    foreach($item in @(Get-ChildItem Env:)){if($item.Name -match $envPattern){[Environment]::SetEnvironmentVariable($item.Name,$null,'Process')}}
    foreach($item in [Environment]::GetEnvironmentVariables('Machine').GetEnumerator()){if($item.Key -match $envPattern){[Environment]::SetEnvironmentVariable($item.Key,[string]$item.Value,'Process')}}
    foreach($item in (Get-Item ('IIS:\AppPools\'+$AppPool)).environmentVariables.Collection){[Environment]::SetEnvironmentVariable([string]$item.name,[string]$item.value,'Process')}
    [xml]$web=Get-Content -LiteralPath (Join-Path $SiteRoot 'web.config') -Raw
    foreach($item in $web.SelectNodes('//aspNetCore/environmentVariables/environmentVariable')){[Environment]::SetEnvironmentVariable([string]$item.name,[string]$item.value,'Process')}
    $arguments=@($dll,'--apple-notification-test'); if($StoreEnvironment -eq 'Sandbox'){$arguments+='--sandbox'}
    # Capture startup output in memory; never echo unknown runtime diagnostics.
    Push-Location $SiteRoot
    try { $raw=@(& dotnet @arguments 2>&1); $resultCode=$LASTEXITCODE } finally { Pop-Location }
    $safe=@($raw | Where-Object { [string]$_ -match '^\{"(environment|error)"' })
    if(!$safe.Count){throw 'Guvenli JSON sonuc alinamadi; paket surumu veya calisma ortami kontrol edilmeli.'}
    $safe | ForEach-Object {
        $r=([string]$_ | ConvertFrom-Json)
        # Explicit output allowlist. No JWT, test token, key, JWS or provider body.
        if($r.error){[pscustomobject]@{error=$r.error;status=$r.status} | ConvertTo-Json -Compress}
        else {[pscustomobject]@{environment=$r.environment;requested=$r.requested;delivered=$r.delivered;attempt_results=$r.attempt_results} | ConvertTo-Json -Compress}
    }
    if($resultCode -eq 2){Write-Output 'Apple istegi kabul edildi; teslim sonucu henuz basarili gorunmuyor. Bu, satin alma testi degildir.'}
    exit $resultCode
}
finally {
    foreach($item in @(Get-ChildItem Env:)){if($item.Name -match $envPattern){[Environment]::SetEnvironmentVariable($item.Name,$null,'Process')}}
    foreach($name in $before.Keys){[Environment]::SetEnvironmentVariable($name,$before[$name],'Process')}
    $raw=$null
}

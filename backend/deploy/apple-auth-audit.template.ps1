param([switch]$SandboxHistory)
# Generated read-only audit. Embedded files contain public compiled code only.
# Never print private keys, JWTs, raw provider bodies or unfiltered native output.
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$files=__PROBE_FILES__
$target=$null; $raw=$null
$candidate='C:\ProgramData\santiye\keys\AuthKey_CY8L78UR5Q.p8'
$siteRoot='C:\inetpub\wwwroot\santiye'
$appPool='santiye'
$expectedHash='0a969ec424de180b72a7dcbf7e7b3f39ff954d47397cbb382a4c0b560820f9c2'
$expectedKeyId='CY8L78UR5Q'
$expectedIssuer='e0061e2a-caf2-40d0-81f4-21d2ead8c973'
$expectedBundle='com.yusuftaskiran.santiyeagi.pro'
$settingsPath=$null; $settingsBefore=$null
$configuration=[ordered]@{
    Source='RECONSTRUCTED_IIS_CONFIGURATION_NOT_WORKER_PROCESS_MEMORY'
    ReadOnly=$true; ReconstructionSucceeded=$false; SettingsPath=$null
    BillingEnabled=$null; AllowSandbox=$null
    ActiveKeyIdMatches=$null; ActiveIssuerMatches=$null; ActiveBundleMatches=$null
    ActivePrivateKeyConfigured=$null; ActivePrivateKeyPath=$null; ActivePrivateKeyFileExists=$null
    ActivePrivateKeyIsCandidate=$null; ActivePrivateKeySha256=$null; ActivePrivateKeyHashMatches=$null
    SettingsUnchanged=$null; Status='NOT_CHECKED'
}
$effective=@{}; $overrides=@{}
function Flatten-AuditSettings($node,[string]$prefix='') {
    if($null -eq $node){return}
    foreach($property in $node.PSObject.Properties){
        $name=if($prefix){$prefix+':'+$property.Name}else{$property.Name}
        if($property.Value -is [pscustomobject]){Flatten-AuditSettings $property.Value $name}
        else{$effective[$name]=$property.Value}
    }
}
function Read-AuditValue([string]$name){
    if($overrides.ContainsKey($name)){return $overrides[$name]}
    return $effective[$name]
}
function Safe-AuditPath($value){
    $path=[string]$value
    if([string]::IsNullOrWhiteSpace($path) -or $path.Length -gt 1024 -or $path -match '[\x00-\x1f]' -or ![IO.Path]::IsPathRooted($path)){return $null}
    return [IO.Path]::GetFullPath($path)
}
function Safe-AuditUtc($value){
    if($value -is [DateTimeOffset]){return $value.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
    if($value -is [DateTime]){return $value.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)}
    $date=[DateTimeOffset]::MinValue
    if($value -is [string] -and $value.Length -le 64 -and [DateTimeOffset]::TryParse($value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$date)){
        return $date.ToUniversalTime().ToString('o',[Globalization.CultureInfo]::InvariantCulture)
    }
    return $null
}
function Safe-AuditNumber($value,[double]$maximum=1000000000000){
    if($null -eq $value){return $null}
    if($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]){
        $number=[double]$value
        if(![double]::IsNaN($number) -and ![double]::IsInfinity($number) -and [math]::Abs($number) -le $maximum){return $number}
    }
    return $null
}
function Safe-AuditBool($value){if($value -is [bool]){return $value};return $null}
try {
    Import-Module WebAdministration
    $pool=Get-Item ('IIS:\AppPools\'+$appPool)
    foreach($item in [Environment]::GetEnvironmentVariables('Machine').GetEnumerator()){$overrides[([string]$item.Key).Replace('__',':')]=[string]$item.Value}
    foreach($item in $pool.environmentVariables.Collection){$overrides[([string]$item.name).Replace('__',':')]=[string]$item.value}
    [xml]$web=Get-Content -LiteralPath (Join-Path $siteRoot 'web.config') -Raw -Encoding UTF8
    foreach($item in $web.SelectNodes('//aspNetCore/environmentVariables/environmentVariable')){$overrides[([string]$item.name).Replace('__',':')]=[string]$item.value}
    $settingsPath=Safe-AuditPath $overrides['SANTIYE_CONFIG_FILE']
    if(!$settingsPath -or !(Test-Path -LiteralPath $settingsPath -PathType Leaf)){throw 'CONFIG_PATH'}
    $configuration.SettingsPath=$settingsPath
    $settingsBefore=(Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256 -ErrorAction Stop 2>$null).Hash
    if(!$settingsBefore){throw 'CONFIG_HASH_UNAVAILABLE'}
    $hostingEnvironment=[string]$overrides['DOTNET_ENVIRONMENT']
    if(!$hostingEnvironment){$hostingEnvironment=[string]$overrides['ASPNETCORE_ENVIRONMENT']}
    if(!$hostingEnvironment){$hostingEnvironment='Production'}
    if($hostingEnvironment -notmatch '^[A-Za-z0-9_-]{1,80}$'){throw 'ENVIRONMENT'}
    foreach($path in @((Join-Path $siteRoot 'appsettings.json'),(Join-Path $siteRoot ('appsettings.'+$hostingEnvironment+'.json')),$settingsPath)){
        if(Test-Path -LiteralPath $path -PathType Leaf){Flatten-AuditSettings (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)}
    }
    $configuration.BillingEnabled=([string](Read-AuditValue 'Billing:Enabled') -ieq 'true')
    $configuration.AllowSandbox=([string](Read-AuditValue 'Billing:AllowSandbox') -ieq 'true')
    $configuration.ActiveKeyIdMatches=([string](Read-AuditValue 'Billing:AppleKeyId') -ceq $expectedKeyId)
    $configuration.ActiveIssuerMatches=([string](Read-AuditValue 'Billing:AppleIssuerId') -ieq $expectedIssuer)
    $configuration.ActiveBundleMatches=([string](Read-AuditValue 'Billing:AppleBundleId') -ceq $expectedBundle)
    $keyValue=[string](Read-AuditValue 'Billing:ApplePrivateKeyFile')
    $configuration.ActivePrivateKeyConfigured=![string]::IsNullOrWhiteSpace($keyValue)
    $activePath=Safe-AuditPath $keyValue
    $configuration.ActivePrivateKeyPath=$activePath
    $configuration.ActivePrivateKeyIsCandidate=($null -ne $activePath -and $activePath -ieq [IO.Path]::GetFullPath($candidate))
    $configuration.ActivePrivateKeyFileExists=($null -ne $activePath -and (Test-Path -LiteralPath $activePath -PathType Leaf))
    if($configuration.ActivePrivateKeyFileExists){
        $configuration.ActivePrivateKeySha256=(Get-FileHash -LiteralPath $activePath -Algorithm SHA256 -ErrorAction Stop 2>$null).Hash.ToLowerInvariant()
        $configuration.ActivePrivateKeyHashMatches=($configuration.ActivePrivateKeySha256 -ceq $expectedHash)
    }
    $configuration.ReconstructionSucceeded=$true; $configuration.Status='RECONSTRUCTED'
} catch {$configuration.Status='IIS_CONFIGURATION_UNAVAILABLE';$configuration.ReconstructionSucceeded=$false}
finally {$effective.Clear();$overrides.Clear();$web=$null;$pool=$null;$keyValue=$null}
$timeService='UNAVAILABLE'
try {$service=Get-Service -Name W32Time -ErrorAction Stop;if([string]$service.Status -cin @('Running','Stopped','StartPending','StopPending','ContinuePending','PausePending','Paused')){$timeService=[string]$service.Status}} catch { }
$assemblyMatches=$false
try {$assemblyMatches=((Get-FileHash -LiteralPath (Join-Path $siteRoot 'SantiyeAgi.Api.dll') -Algorithm SHA256 -ErrorAction Stop 2>$null).Hash -ceq '9AA6527A290447DD187823EE98CB27815075C89FAFD13D7D8E3FA8E21C5467CF')} catch { }
$audit=$null; $probeStatus='NO_SAFE_AUDIT_RESULT'
try {
    $allowed=@('SantiyeAgi.AppleAccessProbe.dll','SantiyeAgi.AppleAccessProbe.deps.json','SantiyeAgi.AppleAccessProbe.runtimeconfig.json')
    if($files.Count -ne $allowed.Count){throw 'FILES'}
    foreach($name in $files.Keys){if($name -cnotin $allowed -or $files[$name].sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'FILES'}}
    $target=Join-Path 'C:\ProgramData\santiye' ('apple-auth-audit-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $target | Out-Null
    & icacls.exe $target /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' 2>&1 | Out-Null
    if($LASTEXITCODE -ne 0){throw 'ACL'}
    foreach($name in $allowed){
        $path=Join-Path $target $name
        [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($files[$name].data))
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop 2>$null).Hash -ine $files[$name].sha256){throw 'HASH'}
    }
    $previous=$ErrorActionPreference
    $probeArgs=@((Join-Path $target 'SantiyeAgi.AppleAccessProbe.dll'),'--audit',$candidate)
    if($SandboxHistory){$probeArgs+='--sandbox-history'}
    try {$ErrorActionPreference='Continue';$raw=@(& dotnet @probeArgs 2>&1)}
    finally {$ErrorActionPreference=$previous}
    foreach($line in $raw){
        try {
            $parsed=([string]$line | ConvertFrom-Json -ErrorAction Stop)
            $a=if($null -ne $parsed.Audit){$parsed.Audit}else{$parsed}
            if($null -eq $a -or $a.AuditVersion -ne 1){continue}
            if($null -ne $audit){$audit=$null;$probeStatus='MULTIPLE_AUDIT_RESULTS';break}
            $status=$null
            if($a.AppleHttpStatus -is [int] -and $a.AppleHttpStatus -ge 100 -and $a.AppleHttpStatus -le 599){$status=[int]$a.AppleHttpStatus}
            $code='UNKNOWN'
            if($a.Code -is [string] -and $a.Code -cmatch '^[A-Z][A-Z0-9_]{0,79}$'){$code=$a.Code}
            $hash=$null;if($a.KeySha256 -is [string] -and $a.KeySha256 -cmatch '^[a-fA-F0-9]{64}$'){$hash=$a.KeySha256.ToLowerInvariant()}
            $expectedEndpoint=if($SandboxHistory){'https://api.storekit-sandbox.apple.com/inApps/v1/notifications/history'}else{'https://api.storekit.apple.com/inApps/v1/notifications/test'}
            $endpoint=$null;if($a.Endpoint -ceq $expectedEndpoint){$endpoint=$a.Endpoint}
            $audit=[ordered]@{
                Source='EXPLICIT_CANDIDATE_FILE_NOT_ACTIVE_IIS_CONFIGURATION'
                Environment=$(if($SandboxHistory){'Sandbox'}else{'Production'})
                CandidatePrivateKeyPath=$candidate; KeySha256=$hash; KeyHashMatches=(Safe-AuditBool $a.KeyHashMatches)
                ServerUtc=(Safe-AuditUtc $a.ServerUtc); AppleDateUtc=(Safe-AuditUtc $a.AppleDateUtc)
                ServerMinusAppleSeconds=(Safe-AuditNumber $a.ServerMinusAppleSeconds); TimeMeasurementRttMs=(Safe-AuditNumber $a.TimeMeasurementRttMs 3600000)
                JwtHeaderMatches=(Safe-AuditBool $a.JwtHeaderMatches); JwtPayloadMatches=(Safe-AuditBool $a.JwtPayloadMatches)
                JwtSignatureValid=(Safe-AuditBool $a.JwtSignatureValid); JwtSignatureBytes=(Safe-AuditNumber $a.JwtSignatureBytes 1024)
                JwtLifetimeSeconds=(Safe-AuditNumber $a.JwtLifetimeSeconds 86400); Endpoint=$endpoint
                AppleHttpStatus=$status; Code=$code; ApiAccessVerified=(Safe-AuditBool $a.ApiAccessVerified)
            }
            $probeStatus='SAFE_AUDIT_RESULT'
        } catch { }
    }
} catch {$probeStatus='AUDIT_PROGRAM_UNAVAILABLE'}
finally {
    $raw=$null;$parsed=$null;$a=$null
    if($target){
        foreach($name in @('SantiyeAgi.AppleAccessProbe.dll','SantiyeAgi.AppleAccessProbe.deps.json','SantiyeAgi.AppleAccessProbe.runtimeconfig.json')){
            $path=Join-Path $target $name;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}
        }
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
    if($settingsPath -and $settingsBefore){
        try {$configuration.SettingsUnchanged=((Get-FileHash -LiteralPath $settingsPath -Algorithm SHA256 -ErrorAction Stop 2>$null).Hash -ceq $settingsBefore)}
        catch {$configuration.SettingsUnchanged=$false}
    }
}
[ordered]@{ReadOnly=$true; InstalledAssemblyMatchesReviewedPackage=$assemblyMatches; ActiveConfiguration=$configuration; WindowsTimeService=$timeService; ProbeStatus=$probeStatus; CandidateAudit=$audit} | ConvertTo-Json -Depth 6
Write-Output 'Bu arac ayar, anahtar iptali, IIS, SMS veya TestFlight degisikligi yapmaz. Aday dosya testi ile yeniden olusturulan etkin IIS ayari ayri raporlanir.'

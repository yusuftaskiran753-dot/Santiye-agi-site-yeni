param(
    [string]$SiteRoot='C:\inetpub\wwwroot\santiye',
    [string]$AppPool='santiye',
    [string]$SettingsPath='',
    [switch]$Offline
)
# Read-only. No config/ACL writes, restart, DB request or key output.
$ErrorActionPreference='Stop'
$effective=@{}; $overrides=@{}; $iisVerified=$false
function Flatten-Settings($node,[string]$prefix='') {
    foreach($property in $node.PSObject.Properties) {
        $name=if($prefix){$prefix+':'+$property.Name}else{$property.Name}
        if($property.Value -is [pscustomobject]) { Flatten-Settings $property.Value $name }
        else { $effective[$name]=$property.Value }
    }
}
function Value([string]$name) {
    if($overrides.ContainsKey($name.Replace(':','__'))){return $overrides[$name.Replace(':','__')]}
    return $effective[$name]
}
function Is-True($value) { return [string]$value -ieq 'true' }
function Has-Text($value) { return ![string]::IsNullOrWhiteSpace([string]$value) }
try {
    if(!$Offline) {
        Import-Module WebAdministration
        if(!(Test-Path ('IIS:\AppPools\'+$AppPool))) { throw 'IIS pool missing' }
        foreach($item in [Environment]::GetEnvironmentVariables('Machine').GetEnumerator()){$overrides[$item.Key]=[string]$item.Value}
        $pool=Get-Item ('IIS:\AppPools\'+$AppPool)
        foreach($item in $pool.environmentVariables.Collection){$overrides[[string]$item.name]=[string]$item.value}
        [xml]$web=Get-Content -LiteralPath (Join-Path $SiteRoot 'web.config') -Raw -Encoding UTF8
        foreach($item in $web.SelectNodes('//aspNetCore/environmentVariables/environmentVariable')) {$overrides[[string]$item.name]=[string]$item.value}
        $selected=[string]$overrides['SANTIYE_CONFIG_FILE']
        if(![IO.Path]::IsPathRooted($selected)) { throw 'IIS external config not resolved' }
        if($SettingsPath -and [IO.Path]::GetFullPath($SettingsPath) -ine [IO.Path]::GetFullPath($selected)) { throw 'Selected config differs' }
        $SettingsPath=$selected
        $iisVerified=$true
    }
    if(![IO.Path]::IsPathRooted($SettingsPath) -or !(Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw 'External config unavailable' }
    $base=Join-Path $SiteRoot 'appsettings.json'
    if(Test-Path -LiteralPath $base) { Flatten-Settings (Get-Content -LiteralPath $base -Raw -Encoding UTF8 | ConvertFrom-Json) }
    $hostingEnvironment=[string]$overrides['DOTNET_ENVIRONMENT']
    if(!$hostingEnvironment){$hostingEnvironment=[string]$overrides['ASPNETCORE_ENVIRONMENT']}
    if(!$hostingEnvironment){$hostingEnvironment='Production'}
    if($hostingEnvironment -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid environment'}
    $environmentFile=Join-Path $SiteRoot ('appsettings.'+$hostingEnvironment+'.json')
    if(Test-Path -LiteralPath $environmentFile){Flatten-Settings (Get-Content -LiteralPath $environmentFile -Raw -Encoding UTF8 | ConvertFrom-Json)}
    Flatten-Settings (Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $serviceAccountPath=[string](Value 'Push:Firebase:ServiceAccountPath')
    $firebaseProject=[string](Value 'Push:Firebase:ProjectId')
    $serviceAccountProject='';$serviceAccountMatch=$false
    if($serviceAccountPath -and (Test-Path -LiteralPath $serviceAccountPath -PathType Leaf)) {
        $account=Get-Content -LiteralPath $serviceAccountPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $serviceAccountProject=[string]$account.project_id
        $serviceAccountMatch=$account.type -eq 'service_account' -and $account.project_id -eq $firebaseProject -and $account.token_uri -eq 'https://oauth2.googleapis.com/token'
        $account=$null
    }
    $applePath=[string](Value 'Billing:ApplePrivateKeyFile')
    $applePresent=$applePath -and (Test-Path -LiteralPath $applePath -PathType Leaf)
    $roots=@(Value 'Billing:AppleRootCertificateFiles') | Where-Object {$_}
    for($index=0;$index -lt 32;$index++) {
        $overrideName='Billing__AppleRootCertificateFiles__'+$index
        if($overrides.ContainsKey($overrideName)) {
            if($index -eq 0){$roots=@()};$roots+= $overrides[$overrideName]
        }
    }
    $rootFiles=@($roots | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    $report=[ordered]@{
        ReadOnly=$true; IisConfigPathResolved=$iisVerified; SettingsPath=$SettingsPath; HostingEnvironment=$hostingEnvironment
        BillingEnabled=(Is-True (Value 'Billing:Enabled')); AllowSandbox=(Is-True (Value 'Billing:AllowSandbox'))
        AppleBundleMatches=([string](Value 'Billing:AppleBundleId') -ceq 'com.yusuftaskiran.santiyeagi.pro')
        AppleAppIdMatches=([string](Value 'Billing:AppleAppId') -eq '6824034438')
        AppleIssuerPresent=(Has-Text (Value 'Billing:AppleIssuerId')); AppleKeyIdPresent=(Has-Text (Value 'Billing:AppleKeyId'))
        ApplePrivateKeyFilePresent=[bool]$applePresent; AppleKeyPurposeVerified=$false
        AppleRootFilesPresent=($roots.Count -gt 0 -and $rootFiles.Count -eq $roots.Count)
        PushEnabled=(Is-True (Value 'Push:Enabled')); FirebaseProject=$firebaseProject; ServiceAccountProject=$serviceAccountProject
        FirebaseServiceAccountMatches=$serviceAccountMatch; FirebaseExpectedProject=($firebaseProject -ceq 'santiye-agi')
        GeminiEnabled=(Is-True (Value 'AI:Enabled')); GeminiKeyPresent=(Has-Text (Value 'AI:ApiKey')); GeminiModel=$(if([string](Value 'AI:Model') -cmatch '^gemini-[a-z0-9.-]{1,80}$'){[string](Value 'AI:Model')}else{'UNVERIFIED'})
        GeminiProjectBindingVerified=$false; GeminiBillingVerified=$false
        SmsEnabled=(Is-True (Value 'Sms:Enabled')); PhoneVerificationRequired=(Is-True (Value 'Auth:RequirePhoneVerification'))
        PasswordLoginEnabled=(Is-True (Value 'Auth:AccountLogin:Enabled')); DataProtectionPathConfigured=(Has-Text (Value 'DataProtection:KeysPath'))
    }
    # No key, credential, password/hash, connection string or account token is serialized.
    $report | ConvertTo-Json -Depth 4
}
catch { Write-Error 'IOS_READINESS_CHECK_FAILED: IIS/dosya erisimi veya JSON yapisi kontrol edilmeli. Ayrinti ve sirlar yazdirilmadi.'; exit 1 }

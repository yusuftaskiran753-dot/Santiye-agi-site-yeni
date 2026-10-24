[CmdletBinding(DefaultParameterSetName='Setup')]
param(
    [Parameter(ParameterSetName='Setup')][string]$ApiId='',
    [Parameter(ParameterSetName='Setup')][string]$Sender='',
    [Parameter(ParameterSetName='Setup')][string]$SettingsPath='C:\ProgramData\santiye\settings.json',
    [Parameter(ParameterSetName='Setup')][string]$SiteRoot='C:\inetpub\wwwroot\santiye',
    [Parameter(ParameterSetName='Setup')][string]$AppPool='santiye',
    [Parameter(ParameterSetName='Setup')][ValidateSet('Check','Stage','Enable')][string]$Mode='Stage',
    [Parameter(Mandatory=$true,ParameterSetName='Helpers')][switch]$FunctionsOnly
)

# PowerShell 5.1. No credential command-line argument, SMS submission, DB write,
# PhoneVerified override, global IIS reset or certificate validation bypass.
$ErrorActionPreference='Stop'

function Assert-VatanSmsCredentials([string]$Id,[string]$Key,[string]$SenderName) {
    if($Id -cnotmatch '^[0-9]{1,20}$' -or $Key.Length -lt 10 -or $Key.Length -gt 512 -or $Key -match '\s' -or
       $SenderName -cnotmatch '^[A-Z0-9][A-Z0-9 ._-]{0,10}$' -or $SenderName -match ' $') { throw 'SMS_CREDENTIAL_FORMAT' }
}

function Test-VatanSmsJsonObject($Value) {
    # PowerShell 5.1 can leave a PSObject wrapper around ConvertFrom-Json arrays;
    # '-is [pscustomobject]' alone can consequently accept an array as an object.
    return $null -ne $Value -and $Value.GetType().FullName -ceq 'System.Management.Automation.PSCustomObject'
}

function Test-VatanSmsExactSender($Node,[string]$Expected,[int]$Depth=0) {
    if($Depth -gt 8){return $false}
    if($Node -is [string]){return [string]::Equals($Node,$Expected,[StringComparison]::Ordinal)}
    if(Test-VatanSmsJsonObject $Node) {
        foreach($p in $Node.PSObject.Properties){if(Test-VatanSmsExactSender $p.Value $Expected ($Depth+1)){return $true}}
    } elseif($Node -is [array]) {
        foreach($item in $Node){if(Test-VatanSmsExactSender $item $Expected ($Depth+1)){return $true}}
    }
    return $false
}

function Test-VatanSmsProviderErrors($Node) {
    foreach($name in @('error','errors')) {
        $property=$Node.PSObject.Properties[$name]
        if($null -eq $property -or $null -eq $property.Value -or ($property.Value -is [bool] -and !$property.Value)){continue}
        if($property.Value -is [string] -and [string]::IsNullOrWhiteSpace($property.Value)){continue}
        if($property.Value -is [array] -and $property.Value.Count -eq 0){continue}
        return $true
    }
    return $false
}

function Get-VatanSmsValueKind($Value) {
    if($null -eq $Value){return 'null'}
    if(Test-VatanSmsJsonObject $Value){return 'object'}
    if($Value -is [array]){return 'array'}
    if($Value -is [bool]){return 'boolean'}
    if($Value -is [string]){return 'string'}
    if($Value -is [ValueType]){return 'number'}
    return 'unknown'
}

function Get-VatanSmsSenderAudit([int]$HttpStatus,[string]$Body,[string]$ExpectedSender) {
    # Accept only explicit known success indicators and an exact sender value
    # inside data/senders. Unknown shapes, conflicting indicators or errors fail
    # closed. The raw response can contain secrets and is never returned/logged.
    $report=[ordered]@{HttpStatus=$HttpStatus;ResponseJson=$false;CodeKind='absent';Code200=$false;StatusKind='absent';StatusSuccess=$false;DataKind='absent';SenderExactValuePresent=$false;ApiAccessVerified=$false;SenderVerified=$false;ResponseSchema='UNVERIFIED'}
    if($Body.Length -gt 65536){$report.ResponseSchema='RESPONSE_TOO_LARGE';return [pscustomobject]$report}
    try {$value=$Body | ConvertFrom-Json -ErrorAction Stop} catch {$report.ResponseSchema='INVALID_JSON';return [pscustomobject]$report}
    if(!(Test-VatanSmsJsonObject $value)){return [pscustomobject]$report}
    $report.ResponseJson=$true
    foreach($field in @('code','status','data')) {
        $property=$value.PSObject.Properties[$field]
        if($null -eq $property){continue}
        $report[($field.Substring(0,1).ToUpperInvariant()+$field.Substring(1)+'Kind')]=Get-VatanSmsValueKind $property.Value
    }
    $knownSuccess=$false;$conflict=Test-VatanSmsProviderErrors $value
    if($null -ne $value.PSObject.Properties['code']) {
        $report.Code200=($value.code -is [ValueType] -and $value.code -isnot [bool] -and $value.code -eq 200)
        $knownSuccess=$knownSuccess -or $report.Code200;$conflict=$conflict -or !$report.Code200
    }
    if($null -ne $value.PSObject.Properties['status']) {
        $report.StatusSuccess=($value.status -is [string] -and $value.status -ieq 'success') -or
            ($value.status -is [ValueType] -and $value.status -isnot [bool] -and $value.status -eq 200)
        $knownSuccess=$knownSuccess -or $report.StatusSuccess;$conflict=$conflict -or !$report.StatusSuccess
    }
    if($null -ne $value.PSObject.Properties['success']) {
        $success=$value.success -is [bool] -and $value.success
        $knownSuccess=$knownSuccess -or $success;$conflict=$conflict -or !$success
    }
    foreach($field in @('data','senders')) {
        $property=$value.PSObject.Properties[$field]
        if($null -ne $property -and (Test-VatanSmsExactSender $property.Value $ExpectedSender)){$report.SenderExactValuePresent=$true}
    }
    $report.ApiAccessVerified=$HttpStatus -eq 200 -and $knownSuccess -and !$conflict
    $report.SenderVerified=$report.ApiAccessVerified -and $report.SenderExactValuePresent
    if($report.SenderVerified){$report.ResponseSchema='KNOWN_SUCCESS_EXACT_SENDER'}elseif($conflict){$report.ResponseSchema='PROVIDER_REJECTED_OR_CONFLICTING_STATUS'}
    return [pscustomobject]$report
}

function Invoke-VatanSmsSenderCheck([string]$Id,[string]$Key,[string]$SenderName) {
    Assert-VatanSmsCredentials $Id $Key $SenderName
    if($null -ne [Net.ServicePointManager]::ServerCertificateValidationCallback){throw 'SMS_TLS_CALLBACK_PRESENT'}
    $originalTls=[Net.ServicePointManager]::SecurityProtocol
    $response=$null;$stream=$null;$reader=$null;$body=$null;$bytes=$null
    try {
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $request=[Net.HttpWebRequest]::Create('https://api.vatansms.net/api/v1/senders')
        $request.Method='POST';$request.AllowAutoRedirect=$false;$request.Timeout=15000;$request.ReadWriteTimeout=15000
        $request.ContentType='application/json';$request.Accept='application/json'
        $bytes=[Text.Encoding]::UTF8.GetBytes((@{api_id=$Id;api_key=$Key} | ConvertTo-Json -Compress))
        $request.ContentLength=$bytes.Length
        $stream=$request.GetRequestStream();$stream.Write($bytes,0,$bytes.Length);$stream.Dispose();$stream=$null
        try {$response=$request.GetResponse()} catch [Net.WebException] {
            if($null -eq $_.Exception.Response){throw 'SMS_PROVIDER_CONNECTION_FAILED'}
            $response=$_.Exception.Response
        }
        $status=[int]$response.StatusCode
        if($status -ne 200){return Get-VatanSmsSenderAudit $status '' $SenderName}
        if($response.ContentLength -gt 65536){return Get-VatanSmsSenderAudit $status ('x'*65537) $SenderName}
        $reader=New-Object IO.StreamReader($response.GetResponseStream(),[Text.Encoding]::UTF8)
        $characters=New-Object char[] 65537
        $count=0
        while($count -lt $characters.Length) {
            $read=$reader.Read($characters,$count,($characters.Length-$count))
            if($read -eq 0){break};$count+=$read
        }
        $body=New-Object string -ArgumentList $characters,0,$count
        if($count -eq 0){$body=''}
        return Get-VatanSmsSenderAudit $status $body $SenderName
    } finally {
        if($null -ne $reader){$reader.Dispose()};if($null -ne $stream){$stream.Dispose()};if($null -ne $response){$response.Dispose()}
        if($null -ne $bytes){[Array]::Clear($bytes,0,$bytes.Length)}
        $body=$null;$Key=$null
        [Net.ServicePointManager]::SecurityProtocol=$originalTls
    }
}

function Assert-VatanSmsSettingsObject($Settings) {
    if(!(Test-VatanSmsJsonObject $Settings)){throw 'SMS_SETTINGS_JSON_INVALID'}
    foreach($name in @('Sms','Auth')) {
        if($null -ne $Settings.$name -and !(Test-VatanSmsJsonObject $Settings.$name)){throw 'SMS_SETTINGS_JSON_INVALID'}
    }
    if($null -ne $Settings.Sms -and $null -ne $Settings.Sms.VatanSms -and !(Test-VatanSmsJsonObject $Settings.Sms.VatanSms)){throw 'SMS_SETTINGS_JSON_INVALID'}
    if($null -ne $Settings.Auth -and $null -ne $Settings.Auth.AccountLogin -and !(Test-VatanSmsJsonObject $Settings.Auth.AccountLogin)){throw 'SMS_SETTINGS_JSON_INVALID'}
    foreach($setting in @($Settings.Auth.RequirePhoneVerification,$Settings.Auth.AccountLogin.Enabled)) {
        if($null -ne $setting -and $setting -isnot [bool]){throw 'SMS_AUTH_FLAG_INVALID'}
    }
    return $Settings
}

function Merge-VatanSmsSettings($Settings,[string]$Id,[string]$Key,[string]$SenderName,[switch]$RequirePhone) {
    Assert-VatanSmsCredentials $Id $Key $SenderName
    $null=Assert-VatanSmsSettingsObject $Settings
    if($null -eq $Settings.Sms){$Settings | Add-Member -NotePropertyName Sms -NotePropertyValue ([pscustomobject]@{}) -Force}
    if($null -eq $Settings.Sms.VatanSms){$Settings.Sms | Add-Member -NotePropertyName VatanSms -NotePropertyValue ([pscustomobject]@{}) -Force}
    $Settings.Sms | Add-Member -NotePropertyName Provider -NotePropertyValue 'VatanSms' -Force
    $Settings.Sms | Add-Member -NotePropertyName Enabled -NotePropertyValue $true -Force
    foreach($pair in @(@('ApiId',$Id),@('ApiKey',$Key),@('Sender',$SenderName))) {$Settings.Sms.VatanSms | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force}
    if($RequirePhone) {
        if($null -eq $Settings.Auth){$Settings | Add-Member -NotePropertyName Auth -NotePropertyValue ([pscustomobject]@{}) -Force}
        $Settings.Auth | Add-Member -NotePropertyName RequirePhoneVerification -NotePropertyValue $true -Force
    }
    return $Settings
}

function Assert-VatanSmsNoReparse([string]$Path) {
    $current=[IO.Path]::GetFullPath($Path)
    while($current) {
        if((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'SMS_REPARSE_PATH'}
        $parent=[IO.Path]::GetDirectoryName($current);if($parent -eq $current){break};$current=$parent
    }
}

function Assert-VatanSmsProtectedParent([string]$Path) {
    $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    Assert-VatanSmsNoReparse $parent
    $acl=Get-Acl -LiteralPath $parent
    $trusted=@('S-1-5-18','S-1-5-32-544',[Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if($trusted -notcontains $owner){throw 'SMS_PARENT_OWNER_UNTRUSTED'}
    $writeMask=[Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
           !($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -and
           ($rule.FileSystemRights -band $writeMask) -and $trusted -notcontains $rule.IdentityReference.Value){throw 'SMS_PARENT_WRITABLE_BY_UNTRUSTED_IDENTITY'}
    }
}

function Protect-VatanSmsFile([string]$Path,[string]$Pool='') {
    $acl=New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @('S-1-5-18','S-1-5-32-544')) {
        $identity=New-Object Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','Allow')))
    }
    if($Pool){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(('IIS AppPool\'+$Pool),'Read','Allow')))}
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Write-VatanSmsProtectedJson([string]$Destination,$Value,[string]$Pool='') {
    Assert-VatanSmsNoReparse $Destination
    Assert-VatanSmsProtectedParent $Destination
    $temporary=Join-Path ([IO.Path]::GetDirectoryName($Destination)) ('sms-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        $null=New-Item -ItemType File -Path $temporary
        Protect-VatanSmsFile $temporary $Pool
        [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 64),(New-Object Text.UTF8Encoding($false)))
        if(Test-Path -LiteralPath $Destination){[IO.File]::Replace($temporary,$Destination,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Destination)}
        # File.Replace preserves destination ACLs; explicitly restrict every
        # resulting secret file, including existing backups/configuration.
        Protect-VatanSmsFile $Destination $Pool
    } finally {if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}

function Get-VatanSmsIisContext([string]$ConfigFile,[string]$Root,[string]$PoolName) {
    if($PoolName -cnotmatch '^[A-Za-z0-9_-]{1,60}$' -or ![IO.Path]::IsPathRooted($ConfigFile) -or ![IO.Path]::IsPathRooted($Root)){throw 'SMS_IIS_INPUT_INVALID'}
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(!(New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'SMS_ADMIN_REQUIRED'}
    Import-Module WebAdministration -ErrorAction Stop
    if(!(Test-Path ('IIS:\AppPools\'+$PoolName))){throw 'SMS_IIS_POOL_MISSING'}
    $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $configFull=[IO.Path]::GetFullPath($ConfigFile)
    if($configFull.Substring([IO.Path]::GetPathRoot($configFull).Length).Contains(':')){throw 'SMS_SETTINGS_PATH_INVALID'}
    Assert-VatanSmsNoReparse $configFull;Assert-VatanSmsNoReparse $rootFull
    Assert-VatanSmsProtectedParent $configFull
    if(!(Test-Path -LiteralPath $configFull -PathType Leaf)){throw 'SMS_SETTINGS_MISSING'}
    $selected=@(Get-Website | Where-Object {$_.applicationPool -eq $PoolName})
    if($selected.Count -ne 1 -or [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$selected[0].physicalPath)).TrimEnd('\') -ine $rootFull){throw 'SMS_IIS_POOL_NOT_DEDICATED'}
    $pool=Get-Item ('IIS:\AppPools\'+$PoolName)
    if($pool.processModel.identityType.ToString() -notin @('ApplicationPoolIdentity','4')){throw 'SMS_IIS_POOL_IDENTITY_UNSUPPORTED'}
    if((Get-WebAppPoolState -Name $PoolName).Value -ne 'Started'){throw 'SMS_IIS_POOL_NOT_RUNNING'}
    foreach($website in Get-Website) {
        $webRoot=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$website.physicalPath)).TrimEnd('\')
        if($configFull -ieq $webRoot -or $configFull.StartsWith($webRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'SMS_SETTINGS_INSIDE_WEBROOT'}
        foreach($application in @(Get-WebApplication -Site $website.Name)) {
            if($application.applicationPool -eq $PoolName){throw 'SMS_IIS_POOL_NOT_DEDICATED'}
            $applicationRoot=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$application.physicalPath)).TrimEnd('\')
            if($configFull -ieq $applicationRoot -or $configFull.StartsWith($applicationRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'SMS_SETTINGS_INSIDE_WEBROOT'}
        }
        foreach($directory in @(Get-WebVirtualDirectory -Site $website.Name)) {
            $directoryRoot=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$directory.physicalPath)).TrimEnd('\')
            if($configFull -ieq $directoryRoot -or $configFull.StartsWith($directoryRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'SMS_SETTINGS_INSIDE_WEBROOT'}
        }
    }
    $overrides=@{}
    foreach($item in [Environment]::GetEnvironmentVariables('Machine').GetEnumerator()){$overrides[$item.Key]=[string]$item.Value}
    foreach($item in $pool.environmentVariables.Collection){$overrides[[string]$item.name]=[string]$item.value}
    [xml]$web=Get-Content -LiteralPath (Join-Path $rootFull 'web.config') -Raw -Encoding UTF8
    foreach($item in $web.SelectNodes('//aspNetCore/environmentVariables/environmentVariable')){$overrides[[string]$item.name]=[string]$item.value}
    if(!$overrides.ContainsKey('SANTIYE_CONFIG_FILE') -or ![IO.Path]::IsPathRooted($overrides['SANTIYE_CONFIG_FILE']) -or [IO.Path]::GetFullPath($overrides['SANTIYE_CONFIG_FILE']) -ine $configFull){throw 'SMS_ACTIVE_CONFIG_MISMATCH'}
    if(@($overrides.Keys | Where-Object {$_ -match '^Sms(__|:|$)|^Auth(__|:)RequirePhoneVerification$|^Auth(__|:)AccountLogin(__|:|$)'}).Count){throw 'SMS_ENVIRONMENT_OVERRIDE_PRESENT'}
    $environment=if($overrides['DOTNET_ENVIRONMENT']){$overrides['DOTNET_ENVIRONMENT']}elseif($overrides['ASPNETCORE_ENVIRONMENT']){$overrides['ASPNETCORE_ENVIRONMENT']}else{'Production'}
    if($environment -cne 'Production'){throw 'SMS_PRODUCTION_ENVIRONMENT_REQUIRED'}
    # Environment values remain internal; never include this context in output.
    return [pscustomobject]@{SettingsPath=$configFull;SiteRoot=$rootFull;Pool=$PoolName;Environment=$overrides}
}

function Convert-VatanSmsReviewReadiness([int]$ExitCode,[string]$Body) {
    if($ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($Body) -or $Body.Length -gt 65536){throw 'SMS_REVIEW_READINESS_FAILED'}
    try {$value=$Body | ConvertFrom-Json -ErrorAction Stop}catch{throw 'SMS_REVIEW_READINESS_INVALID'}
    if(!(Test-VatanSmsJsonObject $value) -or $value.ReadOnly -isnot [bool] -or !$value.ReadOnly -or
       $value.PasswordLoginEnabled -isnot [bool] -or $value.ReadyForRequiredSms -isnot [bool] -or
       !$value.ReadyForRequiredSms -or $value.Code -cne 'READY'){throw 'SMS_REVIEW_READINESS_NOT_READY'}
    foreach($name in @('ConfiguredAccountCount','VerifiedAccountCount','MissingOrInvalidAccountCount')) {
        $count=$value.$name
        if(($count -isnot [int] -and $count -isnot [long]) -or $count -lt 0 -or $count -gt 10000){throw 'SMS_REVIEW_READINESS_COUNTS_INVALID'}
    }
    if($value.VerifiedAccountCount -gt $value.ConfiguredAccountCount -or $value.MissingOrInvalidAccountCount -ne 0 -or
       ($value.PasswordLoginEnabled -and ($value.ConfiguredAccountCount -eq 0 -or $value.VerifiedAccountCount -ne $value.ConfiguredAccountCount))){throw 'SMS_REVIEW_READINESS_NOT_READY'}
    # Return a fixed allowlist, not the original CLI object or an error string.
    return [pscustomobject]@{ReadOnly=$true;PasswordLoginEnabled=$value.PasswordLoginEnabled;ConfiguredAccountCount=$value.ConfiguredAccountCount;VerifiedAccountCount=$value.VerifiedAccountCount;MissingOrInvalidAccountCount=0;ReadyForRequiredSms=$true;Code='READY'}
}

function Get-VatanSmsReviewReadiness([string]$ConfigFile,[string]$Root,$EnvironmentOverrides) {
    $assembly=Join-Path $Root 'SantiyeAgi.Api.dll'
    $dotnet=Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
    if(!(Test-Path -LiteralPath $assembly -PathType Leaf) -or !(Test-Path -LiteralPath $dotnet -PathType Leaf)){throw 'SMS_REVIEW_READINESS_COMMAND_MISSING'}
    Assert-VatanSmsNoReparse $assembly;Assert-VatanSmsNoReparse $dotnet
    $process=New-Object Diagnostics.Process
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$dotnet;$start.Arguments='"'+$assembly+'" --sms-review-readiness';$start.WorkingDirectory=$Root
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    if($null -ne $EnvironmentOverrides){foreach($name in $EnvironmentOverrides.Keys){$start.EnvironmentVariables[$name]=[string]$EnvironmentOverrides[$name]}}
    $start.EnvironmentVariables['SANTIYE_CONFIG_FILE']=$ConfigFile
    $start.EnvironmentVariables['DOTNET_ENVIRONMENT']='Production';$start.EnvironmentVariables['ASPNETCORE_ENVIRONMENT']='Production'
    $process.StartInfo=$start;$stdout=$null;$stderr=$null;$body=$null
    try {
        if(!$process.Start()){throw 'SMS_REVIEW_READINESS_START_FAILED'}
        # Drain both redirected streams concurrently to avoid stdout/stderr
        # deadlock. They may contain sensitive framework logs; never print them.
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(!$process.WaitForExit(20000)){$process.Kill();throw 'SMS_REVIEW_READINESS_TIMEOUT'}
        if(!$stdout.Wait(3000) -or !$stderr.Wait(3000)){throw 'SMS_REVIEW_READINESS_OUTPUT_TIMEOUT'}
        $body=$stdout.Result
        return Convert-VatanSmsReviewReadiness $process.ExitCode $body
    }finally{
        try {if(!$process.HasExited){$process.Kill()}}catch{}
        $process.Dispose();$body=$null;$stdout=$null;$stderr=$null;$start=$null
    }
}

function Get-VatanSmsApiState {
    if($null -ne [Net.ServicePointManager]::ServerCertificateValidationCallback){throw 'SMS_TLS_CALLBACK_PRESENT'}
    $originalTls=[Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        $ready=Invoke-RestMethod -Uri 'https://45.59.70.198/health/ready' -TimeoutSec 5 -MaximumRedirection 0
        $options=Invoke-RestMethod -Uri 'https://45.59.70.198/api/v1/auth/options' -TimeoutSec 5 -MaximumRedirection 0
        if($ready.status -cne 'ready' -or $options.phone_verification_required -isnot [bool] -or
           $options.password_login_enabled -isnot [bool] -or $options.phone_verification_available -isnot [bool]){throw 'SMS_API_UPDATED_HEALTH_OR_AUTH_OPTIONS_REQUIRED'}
        return [pscustomobject]@{RequirePhone=$options.phone_verification_required;PasswordLogin=$options.password_login_enabled;Available=$options.phone_verification_available}
    }finally{[Net.ServicePointManager]::SecurityProtocol=$originalTls}
}

function Invoke-VatanSmsApiCheck([bool]$RequirePhone,[bool]$PasswordLogin,[bool]$Available) {
    for($attempt=0;$attempt -lt 4;$attempt++) {
        try {
            $state=Get-VatanSmsApiState
            if($state.RequirePhone -eq $RequirePhone -and $state.PasswordLogin -eq $PasswordLogin -and $state.Available -eq $Available){return}
        } catch { }
        if($attempt -lt 3){Start-Sleep -Seconds 2}
    }
    throw 'SMS_API_HEALTH_OR_AUTH_OPTIONS_FAILED'
}

function Read-VatanSmsSecret {
    $secure=Read-Host 'VatanSMS API anahtari (gizli)' -AsSecureString
    $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer);$secure.Dispose()}
}

function Get-VatanSmsSafeFailureCode($Failure) {
    # Exact allowlist of this script's own constant errors. Never return an
    # arbitrary exception message, provider code/body or parser excerpt.
    $allowed=@(
        'SMS_ACTIVE_CONFIG_MISMATCH','SMS_ADMIN_REQUIRED','SMS_API_HEALTH_OR_AUTH_OPTIONS_FAILED',
        'SMS_API_UPDATED_HEALTH_OR_AUTH_OPTIONS_REQUIRED','SMS_AUTH_FLAG_INVALID','SMS_CREDENTIAL_FORMAT',
        'SMS_ENVIRONMENT_OVERRIDE_PRESENT','SMS_IIS_INPUT_INVALID','SMS_IIS_POOL_IDENTITY_UNSUPPORTED',
        'SMS_IIS_POOL_MISSING','SMS_IIS_POOL_NOT_DEDICATED','SMS_IIS_POOL_NOT_RUNNING',
        'SMS_PARENT_OWNER_UNTRUSTED','SMS_PARENT_WRITABLE_BY_UNTRUSTED_IDENTITY',
        'SMS_PASSWORD_ACCOUNT_PHONE_REVIEW_REQUIRED','SMS_PRODUCTION_ENVIRONMENT_REQUIRED',
        'SMS_PROVIDER_CONNECTION_FAILED','SMS_REPARSE_PATH','SMS_REVIEW_READINESS_COMMAND_MISSING',
        'SMS_REVIEW_READINESS_COUNTS_INVALID','SMS_REVIEW_READINESS_FAILED','SMS_REVIEW_READINESS_INVALID',
        'SMS_REVIEW_READINESS_NOT_READY','SMS_REVIEW_READINESS_OUTPUT_TIMEOUT','SMS_REVIEW_READINESS_START_FAILED',
        'SMS_REVIEW_READINESS_TIMEOUT','SMS_SENDER_RESPONSE_NOT_VERIFIED','SMS_SETTINGS_CHANGED_DURING_CHECK',
        'SMS_SETTINGS_INSIDE_WEBROOT','SMS_SETTINGS_JSON_INVALID','SMS_SETTINGS_MISSING','SMS_SETTINGS_PATH_INVALID',
        'SMS_STAGE_CONFIGURATION_REQUIRED','SMS_STAGED_CREDENTIALS_MISMATCH','SMS_TLS_CALLBACK_PRESENT'
    )
    if($null -ne $Failure.Exception -and $allowed -ccontains $Failure.Exception.Message){return [string]$Failure.Exception.Message}
    return 'SMS_SETUP_FAILED'
}

function Invoke-VatanSmsConfiguration([string]$Id,[string]$SenderName,[string]$ConfigFile,[string]$Root,[string]$Pool,[ValidateSet('Check','Stage','Enable')][string]$SetupMode='Stage') {
$phase='LOCAL_PREFLIGHT';$saved=$false;$backup='';$originalHash='';$apiKey=$null;$settings=$null;$audit=$null;$rollback='NOT_REQUIRED';$originalState=$null;$context=$null
try {
    $context=Get-VatanSmsIisContext $ConfigFile $Root $Pool
    $settings=Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $null=Assert-VatanSmsSettingsObject $settings
    $originalHash=(Get-FileHash -LiteralPath $ConfigFile -Algorithm SHA256).Hash
    $originalState=Get-VatanSmsApiState
    if($SetupMode -eq 'Enable') {
        if($settings.Sms.Enabled -isnot [bool] -or !$settings.Sms.Enabled -or $settings.Sms.Provider -ine 'VatanSms'){throw 'SMS_STAGE_CONFIGURATION_REQUIRED'}
        $phase='REVIEW_ACCOUNT_READ_ONLY_CHECK'
        $review=Get-VatanSmsReviewReadiness $ConfigFile $Root $context.Environment
        if(!$review.ReadyForRequiredSms -or $review.PasswordLoginEnabled -ne $originalState.PasswordLogin){throw 'SMS_PASSWORD_ACCOUNT_PHONE_REVIEW_REQUIRED'}
        if(($Id -and $Id -cne $settings.Sms.VatanSms.ApiId) -or ($SenderName -and $SenderName -cne $settings.Sms.VatanSms.Sender)){throw 'SMS_STAGED_CREDENTIALS_MISMATCH'}
        $Id=[string]$settings.Sms.VatanSms.ApiId;$SenderName=[string]$settings.Sms.VatanSms.Sender;$apiKey=[string]$settings.Sms.VatanSms.ApiKey
    }else{
        if(!$Id){$Id=Read-Host 'VatanSMS API ID'}
        if(!$SenderName){$SenderName=Read-Host 'Onayli gonderici adi'}
        $apiKey=Read-VatanSmsSecret
    }
    Assert-VatanSmsCredentials $Id $apiKey $SenderName
    $phase='PROVIDER_READ_ONLY_PREFLIGHT'
    $audit=Invoke-VatanSmsSenderCheck $Id $apiKey $SenderName
    if($SetupMode -eq 'Check') {
        return [pscustomobject]@{Status='READ_ONLY_PREFLIGHT';SenderAudit=$audit;SettingsChanged=$false;SmsSent=$false}
    }
    if(!$audit.ApiAccessVerified -or !$audit.SenderVerified){throw 'SMS_SENDER_RESPONSE_NOT_VERIFIED'}
    # Enable's preceding read-only readiness check never marks phones verified.
    # Stage/Check do not access the database.
    $phase='PROTECTED_SETTINGS_WRITE'
    $null=Get-VatanSmsIisContext $ConfigFile $Root $Pool
    if((Get-FileHash -LiteralPath $ConfigFile -Algorithm SHA256).Hash -cne $originalHash){throw 'SMS_SETTINGS_CHANGED_DURING_CHECK'}
    $backup=Join-Path (Split-Path $ConfigFile -Parent) ('sms-before-'+[guid]::NewGuid().ToString('N')+'.json')
    Write-VatanSmsProtectedJson $backup $settings
    $requirePhone=if($SetupMode -eq 'Enable'){$true}else{$originalState.RequirePhone}
    $passwordLogin=$originalState.PasswordLogin
    $settings=Merge-VatanSmsSettings $settings $Id $apiKey $SenderName -RequirePhone:($SetupMode -eq 'Enable')
    # A write can replace contents before a later ACL operation fails; rollback
    # is required for any failure from this point, not just a completed write.
    $saved=$true
    Write-VatanSmsProtectedJson $ConfigFile $settings $Pool
    $phase='API_RESTART_AND_CHECK'
    Restart-WebAppPool -Name $Pool
    Invoke-VatanSmsApiCheck $requirePhone $passwordLogin $true
    return [pscustomobject]@{Status='SMS_CONFIGURED';Mode=$SetupMode;PhoneVerificationRequired=$requirePhone;PhoneVerificationAvailable=$true;PasswordLoginPreserved=$true;OtherSettingsPreserved=$true;ProviderReadOnlyCheck=$true;SmsSent=$false;BackupPath=$backup}
}
catch {
    $failureCode=Get-VatanSmsSafeFailureCode $_
    if($saved -and $backup) {
        try {
            $previous=Get-Content -LiteralPath $backup -Raw -Encoding UTF8 | ConvertFrom-Json
            Write-VatanSmsProtectedJson $ConfigFile $previous $Pool
            Restart-WebAppPool -Name $Pool
            Invoke-VatanSmsApiCheck $originalState.RequirePhone $originalState.PasswordLogin $originalState.Available
            $rollback='RESTORED'
        } catch {$rollback='FAILED_NEEDS_ADMIN_CHECK'}
    }
    # ErrorRecord, provider strings and JSON parser excerpts can contain secrets.
    # Emit a fixed vocabulary only, never the original exception.
    return [pscustomobject]@{Status='STOPPED';Code=$failureCode;Phase=$phase;SettingsWriteAttempted=$saved;Rollback=$rollback;SenderAudit=$audit;SmsSent=$false;RawErrorSuppressed=$true}
}
finally {$apiKey=$null;$settings=$null;$audit=$null;$context=$null}
}

if($FunctionsOnly){return}
$result=Invoke-VatanSmsConfiguration $ApiId $Sender $SettingsPath $SiteRoot $AppPool $Mode
$result | ConvertTo-Json -Depth 5
if($result.Status -eq 'STOPPED'){exit 1}

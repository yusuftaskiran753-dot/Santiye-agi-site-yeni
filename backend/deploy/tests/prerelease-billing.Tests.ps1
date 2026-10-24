$ErrorActionPreference='Stop'
$scriptPath=Join-Path $PSScriptRoot '..\set-apple-billing.ps1'
$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$null,[ref]$errors)
if($errors){throw 'Installer parse failed'}
foreach($name in @('Test-PrereleaseAppleAccess','Merge-AppleBillingSettings')){
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name},$true)
    if(!$function){throw 'Policy function missing'}
    . ([scriptblock]::Create($function.Extent.Text))
}
$hash='0a969ec424de180b72a7dcbf7e7b3f39ff954d47397cbb382a4c0b560820f9c2'
$valid=[pscustomobject]@{AuditVersion=1;Code='APPLE_API_ACCESS_CONFIRMED';AppleHttpStatus=200;Endpoint='https://api.storekit-sandbox.apple.com/inApps/v1/notifications/history';ApiAccessVerified=$true;KeyHashMatches=$true;KeySha256=$hash;JwtHeaderMatches=$true;JwtPayloadMatches=$true;JwtSignatureValid=$true;JwtSignatureBytes=64;JwtLifetimeSeconds=300}
if(!(Test-PrereleaseAppleAccess $valid $hash)){throw 'Valid Sandbox authorization rejected'}
$cases=@(
    @('AppleHttpStatus',401),@('AppleHttpStatus',403),@('AppleHttpStatus','200'),
    @('Code','CONFIG'),@('KeySha256',('0'*64)),@('KeyHashMatches',$false),
    @('Endpoint','https://api.storekit.apple.com/inApps/v1/notifications/test'),
    @('JwtSignatureValid','true'),@('JwtHeaderMatches',$false),@('JwtPayloadMatches',$false),
    @('JwtSignatureBytes',63),@('JwtLifetimeSeconds',3601),@('ApiAccessVerified',$null)
)
foreach($case in $cases){
    $bad=($valid | ConvertTo-Json | ConvertFrom-Json)
    $bad.($case[0])=$case[1]
    if(Test-PrereleaseAppleAccess $bad $hash){throw ('Unsafe authorization accepted: '+$case[0])}
}
$settings=[pscustomobject]@{Auth=[pscustomobject]@{RequirePhoneVerification=$false;AccountLogin=[pscustomobject]@{Enabled=$true};SigningKey='CANARY-AUTH'};Sms=[pscustomobject]@{Enabled=$false;ApiKey='CANARY-SMS'};AI=[pscustomobject]@{Enabled=$true;ApiKey='CANARY-AI'};Push=[pscustomobject]@{Enabled=$true};ConnectionStrings=[pscustomobject]@{Postgres='CANARY-DB'};Billing=[pscustomobject]@{Enabled=$false;AllowSandbox=$true;GooglePackageName='existing.package';GoogleServiceAccountFile='CANARY-GOOGLE';CustomField=42}}
$before=($settings | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
$fields=@{Enabled=$true;AllowSandbox=$false;AppleBundleId='com.yusuftaskiran.santiyeagi.pro';AppleAppId=6824034438;AppleKeyId='CY8L78UR5Q';AppleIssuerId='e0061e2a-caf2-40d0-81f4-21d2ead8c973';ApplePrivateKeyFile='C:\ProgramData\santiye\keys\AuthKey_CY8L78UR5Q.p8';AppleRootCertificateFiles=@('root.cer')}
$after=Merge-AppleBillingSettings $settings $fields
foreach($name in @('Auth','Sms','AI','Push','ConnectionStrings')){
    if(($before.$name | ConvertTo-Json -Depth 20 -Compress) -cne ($after.$name | ConvertTo-Json -Depth 20 -Compress)){throw ('Existing section changed: '+$name)}
}
foreach($name in @('GooglePackageName','GoogleServiceAccountFile','CustomField')){if($before.Billing.$name -cne $after.Billing.$name){throw 'Google/custom settings changed'}}
if(!$after.Billing.Enabled -or $after.Billing.AllowSandbox -or $after.Auth.RequirePhoneVerification -or $after.Sms.Enabled){throw 'Unexpected security flags'}
foreach($name in $fields.Keys){if(($after.Billing.$name | ConvertTo-Json -Compress) -cne ($fields[$name] | ConvertTo-Json -Compress)){throw 'Apple field mismatch'}}
Write-Output 'Prerelease policy: valid authorization, 13 rejection cases, exact Apple merge, preserved existing/Google/SMS/phone settings passed.'

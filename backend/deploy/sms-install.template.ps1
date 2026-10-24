param(
    [ValidateSet('Install','Test','Enable','Check')][string]$Mode='Install',
    [string]$Phone='__TEST_PHONE__',
    [string]$ApiId='__SMS_API_ID__',
    [string]$Sender='SANTIYEAGI'
)
$ErrorActionPreference='Stop'
$phase='LOCAL_PREFLIGHT'
$directory='C:\ProgramData\santiye'
$site='C:\inetpub\wwwroot\santiye'
$settings=Join-Path $directory 'settings.json'
$setup=Join-Path $site 'deploy\set-vatan-sms.ps1'
$test=Join-Path $site 'deploy\test-sms-otp.ps1'
$setupResult=$null;$testResult=$null
try {
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'ADMIN_REQUIRED'}
    if($Mode -eq 'Install') {
        $expected=@{
            'SantiyeAgi.Api.dll'='__ASSEMBLY_SHA256__'
            'deploy\set-vatan-sms.ps1'='__SETUP_SHA256__'
            'deploy\test-sms-otp.ps1'='__TEST_SHA256__'
        }
        $current=$true
        foreach($file in $expected.Keys) {
            $path=Join-Path $site $file
            if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $expected[$file]){$current=$false}
        }
        if(!$current) {
            $phase='BACKEND_BACKUP_AND_UPDATE'
            $updater=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__UPDATER_BASE64__'))
            & ([scriptblock]::Create($updater)) -ExpectedZipHash '__ZIP_SHA256__'
            $updater=$null
        }
        foreach($file in $expected.Keys) {
            $path=Join-Path $site $file
            if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $expected[$file]){throw 'INSTALLED_PACKAGE_MISMATCH'}
        }
    }
    if(!(Test-Path -LiteralPath $setup -PathType Leaf) -or !(Test-Path -LiteralPath $settings -PathType Leaf)){throw 'SETUP_OR_SETTINGS_MISSING'}
    if($Mode -in @('Install','Check','Enable')) {
        $phase=if($Mode -eq 'Enable'){'REVIEW_AND_ACTIVATION'}else{'PROVIDER_AND_CONFIGURATION'}
        $setupMode=if($Mode -eq 'Install'){'Stage'}else{$Mode}
        $setupResult=& {
            param($Helper,$IdValue,$SenderValue,$SettingsFile,$SitePath,$SetupMode)
            . $Helper -FunctionsOnly
            Invoke-VatanSmsConfiguration $IdValue $SenderValue $SettingsFile $SitePath 'santiye' $SetupMode
        } $setup $ApiId $Sender $settings $site $setupMode
        $setupResult | ConvertTo-Json -Depth 5
        if($setupResult.Status -eq 'STOPPED'){exit 1}
        if($Mode -in @('Check','Enable')){return}
    }
    $phase='ONE_REAL_OTP_REQUEST_AND_VERIFICATION'
    if(!(Test-Path -LiteralPath $test -PathType Leaf)){throw 'TEST_HELPER_MISSING'}
    $testResult=& {
        param($Helper,$PhoneValue,$SettingsFile)
        . $Helper -FunctionsOnly
        Invoke-SmsOtpTest $PhoneValue $SettingsFile
    } $test $Phone $settings
    $testResult | ConvertTo-Json -Depth 3
    if(!$testResult.PhoneVerified){exit 1}
    # Verifying a different account never rebinds the review credentials. Enable
    # independently checks all configured review users using a read-only query.
    $phase='REVIEW_AND_ACTIVATION'
    $setupResult=& {
        param($Helper,$SettingsFile,$SitePath)
        . $Helper -FunctionsOnly
        Invoke-VatanSmsConfiguration '' '' $SettingsFile $SitePath 'santiye' 'Enable'
    } $setup $settings $site
    $setupResult | ConvertTo-Json -Depth 5
    if($setupResult.Status -eq 'STOPPED'){
        Write-Output 'SMS testi tamamlandi; genel zorunluluk acilmadi. Inceleme hesabinin normal SMS dogrulamasini kontrol edin.'
        exit 1
    }
}catch {
    # Existing updater owns its backup/maintenance recovery. Do not remove an
    # app_offline.htm after a failed update or dump native/framework exceptions.
    [pscustomobject]@{Status='STOPPED';Phase=$phase;RawErrorSuppressed=$true} | ConvertTo-Json
    exit 1
}

param(
    [ValidateSet('On', 'Off')][string]$Mode = 'On',
    [string]$ServiceAccountPath = 'C:\ProgramData\santiye\firebase-service-account.json',
    [string]$ProjectId = 'santiye-agi',
    [string]$SettingsPath = 'C:\ProgramData\santiye\settings.json',
    [string]$AppPool = 'santiye',
    [switch]$SkipIisSetup
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw 'Sunucunun settings.json dosyasi bulunamadi.' }
$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
if ($settings -isnot [pscustomobject]) { throw 'Sunucu ayarlari JSON nesnesi olmali.' }
if ($null -ne $settings.Push -and $settings.Push -isnot [pscustomobject]) { throw 'Mevcut Push ayari JSON nesnesi olmali.' }
if ($Mode -eq 'On' -and $null -ne $settings.Push -and $null -ne $settings.Push.Firebase -and $settings.Push.Firebase -isnot [pscustomobject]) { throw 'Mevcut Firebase ayari JSON nesnesi olmali.' }
if ($Mode -eq 'On') {
    if (![IO.Path]::IsPathRooted($ServiceAccountPath) -or !(Test-Path -LiteralPath $ServiceAccountPath -PathType Leaf)) {
        throw 'Firebase hizmet hesabi dosyasi tam yoluyla belirtilmeli ve mevcut olmali.'
    }
    $keyPath = (Resolve-Path -LiteralPath $ServiceAccountPath).ProviderPath
    $account = Get-Content -LiteralPath $keyPath -Raw | ConvertFrom-Json
    if ($ProjectId -notmatch '^[a-z][a-z0-9-]{4,61}[a-z0-9]$' -or
        $account.type -ne 'service_account' -or $account.project_id -ne $ProjectId -or
        $account.token_uri -ne 'https://oauth2.googleapis.com/token' -or
        $account.client_email -notmatch '@[a-z0-9.-]+\.iam\.gserviceaccount\.com$' -or
        $account.private_key -notmatch '^-----BEGIN PRIVATE KEY-----') {
        throw 'Firebase hizmet hesabi turu, proje kimligi veya anahtar alanlari gecersiz.'
    }
    $account = $null
    if ($keyPath.Equals([IO.Path]::GetFullPath($SettingsPath), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Anahtar ile sunucu ayarlari ayni dosya olamaz.'
    }
}
if (!$SkipIisSetup) {
    Import-Module WebAdministration
    $poolPath = "IIS:\AppPools\$AppPool"
    if (!(Test-Path $poolPath)) { throw 'IIS uygulama havuzu bulunamadi.' }
    if ((Get-Item $poolPath).processModel.identityType.ToString() -notin @('ApplicationPoolIdentity', '4')) {
        throw 'Bu arac ApplicationPoolIdentity bekler; ozel IIS hesabi icin dosya izinleri ayrica yapilandirilmali.'
    }
    if ($Mode -eq 'On') {
        foreach ($site in Get-Website) {
            $webRoot = [Environment]::ExpandEnvironmentVariables($site.PhysicalPath)
            if (![string]::IsNullOrWhiteSpace($webRoot)) {
                $webRoot = [IO.Path]::GetFullPath($webRoot).TrimEnd('\') + '\'
                if ($keyPath.StartsWith($webRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Firebase ozel anahtari web sitesi klasorunde tutulamaz; C:\ProgramData\santiye kullanin.'
                }
            }
        }
        $poolSid = (New-Object Security.Principal.NTAccount("IIS AppPool\$AppPool")).Translate([Security.Principal.SecurityIdentifier])
        $keyAcl = New-Object Security.AccessControl.FileSecurity
        $keyAcl.SetAccessRuleProtection($true, $false)
        foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User, (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')), (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))) {
            $keyAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'Allow')))
        }
        $keyAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($poolSid, 'Read', 'Allow')))
        Set-Acl -LiteralPath $keyPath -AclObject $keyAcl
    }
}
if ($null -eq $settings.Push) { $settings | Add-Member -NotePropertyName Push -NotePropertyValue ([pscustomobject]@{}) }
if ($Mode -eq 'On') {
    if ($null -ne $settings.Push.Firebase -and $settings.Push.Firebase -isnot [pscustomobject]) { throw 'Mevcut Firebase ayari JSON nesnesi olmali.' }
    if ($null -eq $settings.Push.Firebase) { $settings.Push | Add-Member -NotePropertyName Firebase -NotePropertyValue ([pscustomobject]@{}) }
    $settings.Push.Firebase | Add-Member -NotePropertyName ProjectId -NotePropertyValue $ProjectId -Force
    $settings.Push.Firebase | Add-Member -NotePropertyName ServiceAccountPath -NotePropertyValue $keyPath -Force
}
$settings.Push | Add-Member -NotePropertyName Enabled -NotePropertyValue ($Mode -eq 'On') -Force
# Mevcut dosyaya yazarak settings.json izinlerini ve diger ayarlari koru.
[IO.File]::WriteAllText([IO.Path]::GetFullPath($SettingsPath), ($settings | ConvertTo-Json -Depth 50), (New-Object Text.UTF8Encoding($false)))
$settings = $null
if (!$SkipIisSetup) {
    Set-ItemProperty $poolPath -Name startMode -Value AlwaysRunning
    Set-ItemProperty $poolPath -Name processModel.idleTimeout -Value ([TimeSpan]::Zero)
    Restart-WebAppPool -Name $AppPool
}
Write-Output "Firebase push: $Mode. Proje: $ProjectId. Diger sunucu ayarlari korundu."
Write-Output 'Bu sonuc bildirim teslimi degildir. Uygulamayi acip yeni teklif ile gercek teslim testi yapin.'

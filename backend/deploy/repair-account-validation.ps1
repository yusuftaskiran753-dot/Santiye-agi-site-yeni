$ErrorActionPreference='Stop'
$helper='C:\inetpub\wwwroot\santiye\deploy\set-account-login.ps1'
$setup='C:\ProgramData\santiye\Test-Hesabi-Kur.ps1'
$offline='C:\inetpub\wwwroot\santiye\app_offline.htm'
foreach($path in @($helper,$setup)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Dosya bulunamadi: $path" }
}
Import-Module WebAdministration
if (!(Test-Path 'IIS:\AppPools\santiye')) { throw 'santiye havuzu bulunamadi.' }
$content=Get-Content -LiteralPath $helper -Raw
if (!$content.Contains('$credential.PasswordHash -notmatch ') -and !$content.Contains('$credential.PasswordHash -cnotmatch ')) {
    throw 'Beklenen kurulum kontrolu bulunamadi. Dosya degistirilmedi.'
}
$fixed=$content.Replace('$credential.Username -notmatch ', '$credential.Username -cnotmatch ').Replace('$credential.PasswordHash -notmatch ', '$credential.PasswordHash -cnotmatch ')
if ($fixed -cne $content) {
    $backup=Join-Path 'C:\ProgramData\santiye' ('set-account-login-before-fix-'+[guid]::NewGuid().ToString('N')+'.ps1')
    Copy-Item -LiteralPath $helper -Destination $backup
    [IO.File]::WriteAllText($helper,$fixed,(New-Object Text.UTF8Encoding($false)))
}
& $setup
Remove-Item -LiteralPath $offline -ErrorAction SilentlyContinue
if ((Get-WebAppPoolState -Name 'santiye').Value -ne 'Started') { Start-WebAppPool -Name 'santiye' }
Write-Output 'Duzeltme tamam. Test girisi kuruldu, site bakimdan cikarildi. Kullanici adi: test.'

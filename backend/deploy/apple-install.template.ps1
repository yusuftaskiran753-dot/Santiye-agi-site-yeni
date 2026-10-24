# Generated installer: public code only. Uses fresh Sandbox authorization evidence.
$ErrorActionPreference='Stop'
$files=__PROBE_FILES__
$target=$null
try {
    $allowed=@('SantiyeAgi.AppleAccessProbe.dll','SantiyeAgi.AppleAccessProbe.deps.json','SantiyeAgi.AppleAccessProbe.runtimeconfig.json','set-apple-billing.ps1')
    if($files.Count -ne $allowed.Count){throw 'FILES'}
    foreach($name in $files.Keys){if($name -cnotin $allowed -or $files[$name].sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'FILES'}}
    $target=Join-Path 'C:\ProgramData\santiye' ('apple-install-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $target | Out-Null
    & icacls.exe $target /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' 2>&1 | Out-Null
    if($LASTEXITCODE -ne 0){throw 'ACL'}
    foreach($name in $allowed){
        $path=Join-Path $target $name
        [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($files[$name].data))
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ine $files[$name].sha256){throw 'HASH'}
    }
    # Child script emits only bounded operator statuses, not keys/JWT/native output.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $target 'set-apple-billing.ps1') -PreRelease -AccessProbeDll (Join-Path $target 'SantiyeAgi.AppleAccessProbe.dll') -AccessProbeSha256 $files['SantiyeAgi.AppleAccessProbe.dll'].sha256
    $code=$LASTEXITCODE
    if($code -ne 0){Write-Output 'Apple kurulumu tamamlanmadi; yukaridaki guvenli asama sonucunu kontrol edin.'}
} catch {Write-Output 'Apple kurulum araci baslatilamadi. Yonetici PowerShell ve ProgramData izinlerini kontrol edin. Ham hata yazdirilmadi.';$code=1}
finally {
    if($target){
        foreach($name in @('SantiyeAgi.AppleAccessProbe.dll','SantiyeAgi.AppleAccessProbe.deps.json','SantiyeAgi.AppleAccessProbe.runtimeconfig.json','set-apple-billing.ps1')){
            $path=Join-Path $target $name;if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}
        }
        Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    }
}
exit $code

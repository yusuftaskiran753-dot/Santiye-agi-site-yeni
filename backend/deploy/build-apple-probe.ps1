param([switch]$Audit,[switch]$SandboxHistory,[switch]$Install)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$out=Join-Path $root 'output\apple-probe'
& dotnet publish (Join-Path $root 'backend\SantiyeAgi.AppleAccessProbe\SantiyeAgi.AppleAccessProbe.csproj') -c Release --self-contained false -p:UseAppHost=false -o $out
if($LASTEXITCODE -ne 0){throw 'Probe build failed'}
$entries=@()
$names=@('SantiyeAgi.AppleAccessProbe.dll','SantiyeAgi.AppleAccessProbe.deps.json','SantiyeAgi.AppleAccessProbe.runtimeconfig.json')
if($Install){$names+='set-apple-billing.ps1'}
foreach($name in $names){
    $path=if($name -ceq 'set-apple-billing.ps1'){Join-Path $PSScriptRoot $name}else{Join-Path $out $name}
    $data=[Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
    $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $entries+="'$name'=@{data='$data';sha256='$hash'}"
}
$templateName=if($Install){'apple-install.template.ps1'}elseif($Audit -or $SandboxHistory){'apple-auth-audit.template.ps1'}else{'apple-probe.template.ps1'}
$template=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $templateName))
$script=$template.Replace('__PROBE_FILES__',('@{'+($entries -join ";`r`n")+'}'))
if($SandboxHistory){$script=$script.Replace('param([switch]$SandboxHistory)','param([switch]$SandboxHistory=$true)')}
$destination=Join-Path $out $(if($Install){'apple-kur.ps1'}elseif($SandboxHistory){'apple-sandbox.ps1'}elseif($Audit){'apple-detay.ps1'}else{'apple-tani.ps1'})
[IO.File]::WriteAllText($destination,$script,(New-Object Text.UTF8Encoding($true)))
$errors=$null
[Management.Automation.Language.Parser]::ParseFile($destination,[ref]$null,[ref]$errors)|Out-Null
if($errors){throw 'Generated probe script parse failed'}
Write-Output ($(if($Install){'Single-file Apple installer: '}else{'Single-file public diagnostic: '})+$destination)

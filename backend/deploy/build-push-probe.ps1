$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$out=Join-Path $root 'output\ios-push-test'
& dotnet publish (Join-Path $root 'backend\SantiyeAgi.PushProbe\SantiyeAgi.PushProbe.csproj') -c Release --self-contained false -p:UseAppHost=false -o $out
if($LASTEXITCODE -ne 0){throw 'Push probe build failed'}
$entries=@()
foreach($name in @('SantiyeAgi.PushProbe.dll','SantiyeAgi.PushProbe.deps.json','SantiyeAgi.PushProbe.runtimeconfig.json')){
    $path=Join-Path $out $name
    $entries+="'$name'=@{data='$([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)))';sha256='$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash)'}"
}
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'push-probe.template.ps1'))
$operation=[guid]::NewGuid().ToString()
$source=$source.Replace('__PROBE_FILES__',('@{'+($entries -join ";`r`n")+'}')).Replace('__OPERATION_ID__',$operation)
$destination=Join-Path $out 'ios-bildirim.ps1'
[IO.File]::WriteAllText($destination,$source,(New-Object Text.UTF8Encoding($true)))
$errors=$null;[Management.Automation.Language.Parser]::ParseFile($destination,[ref]$null,[ref]$errors)|Out-Null
if($errors){throw 'Push probe parse failed'}
Write-Output ('Single-target test operation '+$operation+': '+$destination)

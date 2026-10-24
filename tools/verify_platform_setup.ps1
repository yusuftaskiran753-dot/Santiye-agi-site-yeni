$ErrorActionPreference = 'Stop'
$originalPath = $env:PATH
$originalLocation = (Get-Location).Path
$project = Split-Path $PSScriptRoot -Parent
$testRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $project 'tmp') ('platform_tests_' + [guid]::NewGuid().ToString('N'))))
if (-not $testRoot.StartsWith($project + '\tmp\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test path' }
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $mockBin = Join-Path $testRoot 'bin'
    New-Item -ItemType Directory -Path $mockBin | Out-Null
    Set-Content -LiteralPath (Join-Path $mockBin 'flutter.bat') -Encoding ASCII -Value '@echo off', 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mock_flutter.ps1" %*', 'exit /b %ERRORLEVEL%'
    Set-Content -LiteralPath (Join-Path $mockBin 'dart.bat') -Encoding ASCII -Value '@echo off', 'if "%SANTIYE_TEST_FAIL%"=="1" exit /b 1', 'exit /b 0'
    Set-Content -LiteralPath (Join-Path $mockBin 'mock_flutter.ps1') -Encoding ASCII -Value @'
$scaffold = $args[-1]
New-Item -ItemType Directory -Force -Path (Join-Path $scaffold 'android'),(Join-Path $scaffold 'ios\Runner.xcodeproj') | Out-Null
Set-Content -LiteralPath (Join-Path $scaffold 'android\gradlew') -Value 'generated android'
Set-Content -LiteralPath (Join-Path $scaffold 'ios\Runner.xcodeproj\project.pbxproj') -Value 'generated ios'
'@
    $env:PATH = $mockBin + ';' + $originalPath
    function New-Case([string]$name) {
        $root = Join-Path $testRoot $name
        New-Item -ItemType Directory -Path (Join-Path $root 'tools') | Out-Null
        Copy-Item -LiteralPath (Join-Path $project 'tools\prepare_platforms.ps1') -Destination (Join-Path $root 'tools\prepare_platforms.ps1')
        return $root
    }
    function Run-Case([string]$root, [string]$option = '') {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\prepare_platforms.ps1') $option *> (Join-Path $root 'result.log')
        return $LASTEXITCODE
    }
    $root = New-Case 'manifest_only'
    New-Item -ItemType Directory -Path (Join-Path $root 'android\app\src\main') | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'android\app\src\main\AndroidManifest.xml') -Value 'custom manifest'
    Set-Content -LiteralPath (Join-Path $root 'android\key.properties') -Value 'custom signing'
    if ((Run-Case $root) -ne 0) { throw 'Manifest-only archive failed' }
    if ((Get-Content (Join-Path $root 'android\app\src\main\AndroidManifest.xml')) -ne 'custom manifest') { throw 'Manifest lost' }
    if ((Get-Content (Join-Path $root 'android\key.properties')) -ne 'custom signing') { throw 'Signing lost' }
    if ((Run-Case $root) -ne 0) { throw 'Second run failed' }
    Write-Output 'PASS: manifest-only archive, preserved manifest/signing, repeated run'

    $root = New-Case 'missing_ios'
    New-Item -ItemType Directory -Path (Join-Path $root 'android') | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'android\gradlew') -Value 'existing android'
    Set-Content -LiteralPath (Join-Path $root 'android\custom.txt') -Value 'keep me'
    if ((Run-Case $root) -ne 0 -or (Get-Content (Join-Path $root 'android\custom.txt')) -ne 'keep me') { throw 'Complete Android changed' }
    Write-Output 'PASS: missing iOS created without replacing existing Android'

    $root = New-Case 'unknown_partial'
    New-Item -ItemType Directory -Path (Join-Path $root 'android') | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'android\custom.txt') -Value 'keep me'
    if ((Run-Case $root) -eq 0 -or (Get-Content (Join-Path $root 'android\custom.txt')) -ne 'keep me') { throw 'Partial project was overwritten' }
    Write-Output 'PASS: unknown partial project rejected without changes'

    $root = New-Case 'rollback'
    New-Item -ItemType Directory -Path (Join-Path $root 'android'),(Join-Path $root 'ios\Runner.xcodeproj') | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'android\gradlew') -Value 'old android'
    Set-Content -LiteralPath (Join-Path $root 'ios\Runner.xcodeproj\project.pbxproj') -Value 'old ios'
    $env:SANTIYE_TEST_FAIL = '1'
    if ((Run-Case $root '--force') -eq 0) { throw 'Expected forced patch failure' }
    if ((Get-Content (Join-Path $root 'android\gradlew')) -ne 'old android' -or
        (Get-Content (Join-Path $root 'ios\Runner.xcodeproj\project.pbxproj')) -ne 'old ios') { throw 'Rollback failed' }
    Write-Output 'PASS: failed forced setup restores both old platforms'
} finally {
    $env:PATH = $originalPath
    Remove-Item Env:\SANTIYE_TEST_FAIL -ErrorAction SilentlyContinue
    Set-Location -LiteralPath $originalLocation
    if ($testRoot.StartsWith($project + '\tmp\', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}


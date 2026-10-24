param([string]$Option = '')
$ErrorActionPreference = 'Stop'
if ($args.Count -eq 1 -and $Option -eq '') { $Option = $args[0] }
elseif ($args.Count -gt 0) { throw 'Kullanim: tools\prepare_platforms.bat [--force]' }
if ($Option -notin @('', '--force')) { throw 'Kullanim: tools\prepare_platforms.bat [--force]' }
$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
Set-Location -LiteralPath $projectRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Flutter SDK bulunamadi.' }

function Assert-ProjectPath([string]$Path) {
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Proje disinda dosya islemi engellendi: $resolvedPath"
    }
    return $resolvedPath
}
function Test-ManifestOnlyAndroid {
    if (-not (Test-Path -LiteralPath 'android')) { return $true }
    foreach ($file in @(Get-ChildItem -LiteralPath 'android' -File -Recurse -Force)) {
        $relative = $file.FullName.Substring((Join-Path $projectRoot 'android').Length + 1)
        if ($relative -ne 'app\src\main\AndroidManifest.xml' -and
            $relative -ne 'key.properties' -and $relative -ne 'key.properties.example' -and
            $relative -notmatch '^(app\\)?[^\\]+\.(jks|keystore)$') { return $false }
    }
    return $true
}
$force = $Option -eq '--force'
$needsAndroid = $force -or -not (Test-Path -LiteralPath 'android\gradlew')
$needsIos = $force -or -not (Test-Path -LiteralPath 'ios\Runner.xcodeproj\project.pbxproj')
if (-not $needsAndroid -and -not $needsIos) { Write-Output 'Platform iskeletleri zaten var.'; exit 0 }
if (-not $force -and $needsAndroid -and -not (Test-ManifestOnlyAndroid)) {
    throw 'Android klasorunde kismi veya ozel proje var; dosyalar korunuyor. Yeniden uretmek icin --force kullanin.'
}
if (-not $force -and $needsIos -and (Test-Path -LiteralPath 'ios') -and
    @(Get-ChildItem -LiteralPath 'ios' -Force).Count -gt 0) {
    throw 'iOS klasorunde kismi veya ozel proje var; dosyalar korunuyor. Yeniden uretmek icin --force kullanin.'
}
$stage = Assert-ProjectPath (Join-Path $projectRoot ('.platform_staging.' + [guid]::NewGuid().ToString('N')))
$scaffold = Join-Path $stage 'scaffold'
$installed = @()
$committed = $false
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    $platforms = @()
    if ($needsAndroid) { $platforms += 'android' }
    if ($needsIos) { $platforms += 'ios' }
    & flutter create --org com.santiyeagi --project-name santiye_agi --platforms ($platforms -join ',') --no-pub $scaffold
    if ($LASTEXITCODE -ne 0) { throw 'Flutter platform olusturma basarisiz; eski dosyalar korunuyor.' }
    if ($needsAndroid) {
        if (-not (Test-Path -LiteralPath (Join-Path $scaffold 'android\gradlew'))) { throw 'Android iskeleti eksik.' }
        $keepFiles = @('android\app\src\main\AndroidManifest.xml', 'android\key.properties', 'android\key.properties.example')
        $keepFiles += @(Get-ChildItem -Path 'android\*.jks','android\*.keystore','android\app\*.jks','android\app\*.keystore' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($projectRoot.Length + 1) })
        foreach ($keepFile in $keepFiles) {
            if (Test-Path -LiteralPath $keepFile) {
                $destination = Join-Path $scaffold $keepFile
                New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
                Copy-Item -LiteralPath $keepFile -Destination $destination -Force
            }
        }
    }
    if ($needsIos -and -not (Test-Path -LiteralPath (Join-Path $scaffold 'ios\Runner.xcodeproj\project.pbxproj'))) { throw 'iOS iskeleti eksik.' }
    foreach ($platform in $platforms) {
        $target = Assert-ProjectPath (Join-Path $projectRoot $platform)
        $backup = Assert-ProjectPath (Join-Path $stage ($platform + '.old'))
        if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $backup }
        $installed += $platform
        Move-Item -LiteralPath (Assert-ProjectPath (Join-Path $scaffold $platform)) -Destination $target
    }
    & dart tools\patch_platforms.dart
    if ($LASTEXITCODE -ne 0) { throw 'Platform ayarlari uygulanamadi.' }
    & dart tools\apply_app_icons.dart
    if ($LASTEXITCODE -ne 0) { throw 'Uygulama ikonlari uygulanamadi.' }
    $committed = $true
    Write-Output 'Eksik platformlar olusturuldu. Mevcut tam platformlar korunuyor.'
} finally {
    if (-not $committed) {
        foreach ($platform in $installed) {
            $target = Assert-ProjectPath (Join-Path $projectRoot $platform)
            $backup = Assert-ProjectPath (Join-Path $stage ($platform + '.old'))
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
            if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $target }
        }
    }
    # Geri yukleme basarisizsa yedekler silinmez.
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath (Assert-ProjectPath $stage) -Recurse -Force }
}

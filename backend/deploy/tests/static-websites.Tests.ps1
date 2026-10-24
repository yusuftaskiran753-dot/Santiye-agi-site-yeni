$ErrorActionPreference='Stop'
$repository=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$installer=Join-Path $repository 'backend\deploy\install-static-websites.ps1'
$parseTokens=$null;$parseErrors=$null
[Management.Automation.Language.Parser]::ParseFile($installer,[ref]$parseTokens,[ref]$parseErrors) | Out-Null
if($parseErrors.Count){throw 'Installer PowerShell parse failed.'}
. $installer -FunctionsOnly
$script:checks=0
function Assert-StaticTest([bool]$Condition,[string]$Message){if(!$Condition){throw $Message};$script:checks++}
function Assert-StaticThrows([scriptblock]$Operation,[string]$Message){$failed=$false;try{& $Operation | Out-Null}catch{$failed=$true};Assert-StaticTest $failed $Message}

$plan=@(Get-StaticWebsitePlan)
Assert-StaticTest ($plan.Count -eq 2 -and $plan[0].Hosts[0] -eq 'santiyeagi.com.tr' -and $plan[1].Hosts[0] -eq 'asfaltik.com.tr') 'Site plan mismatch.'
Assert-StaticTest ($plan[0].Root -ne 'C:\inetpub\wwwroot\santiye' -and $plan[1].Root -ne 'C:\inetpub\wwwroot\santiye') 'API root must not be reused.'
Assert-StaticTest (Test-StaticOwnedPath ($plan[0].Root+'\releases\20261023-abc12345') $plan[0].Root) 'Owned release not accepted.'
foreach($foreign in @('C:\inetpub\wwwroot\santiye','C:\inetpub\wwwroot\santiye-web-other','C:\inetpub\wwwroot\santiye-web\releases\release\child','C:\inetpub\wwwroot\santiye-web\anything')) {
    Assert-StaticTest (!(Test-StaticOwnedPath $foreign $plan[0].Root)) 'Foreign path accepted.'
}
foreach($valid in @('PACKAGE-MANIFEST.json','sites/santiye/index.html','sites/asfaltik/support.html','sites/asfaltik/assets/logo.svg','sites/santiye/web.config')){Assert-StaticPackagePath $valid;$script:checks++}
foreach($invalid in @('../settings.json','/sites/santiye/index.html','sites\santiye\index.html','sites/santiye/../asfaltik/index.html','sites/santiye/.git/config','sites/santiye/appsettings.json','sites/santiye/nested/web.config','sites/santiye/test.ps1','sites/santiye/CON.txt','sites/santiye/trailing.','Sites/santiye/index.html','sites/else/index.html','sites/asfaltik/index.html:secret')) {
    Assert-StaticThrows {Assert-StaticPackagePath $invalid} ('Invalid package path accepted: '+$invalid)
}
$sites=@();$pools=@()
foreach($item in $plan) {
    $sites += [pscustomobject]@{Name=$item.Name;PhysicalPath=$item.Root+'\releases\previous';Pool=$item.Pool;Bindings=@([pscustomobject]@{Protocol='http';Information='*:80:'+$item.Hosts[0]},[pscustomobject]@{Protocol='https';Information='*:443:'+$item.Hosts[1]})}
    $pools += [pscustomobject]@{Name=$item.Pool;Runtime='';Identity='ApplicationPoolIdentity'}
}
Assert-StaticIisPlan $plan $sites @() $pools;$script:checks++
$foreignSite=[pscustomobject]@{Name='Other';PhysicalPath='C:\other';Pool='Other';Bindings=@([pscustomobject]@{Protocol='https';Information='*:443:santiyeagi.com.tr'})}
Assert-StaticThrows {Assert-StaticIisPlan $plan @($sites+$foreignSite) @() $pools} 'Cross-protocol foreign host conflict accepted.'
$wildcardSite=[pscustomobject]@{Name='Other';PhysicalPath='C:\other';Pool='Other';Bindings=@([pscustomobject]@{Protocol='https';Information='*:443:*.com.tr'})}
Assert-StaticThrows {Assert-StaticIisPlan $plan @($sites+$wildcardSite) @() $pools} 'Foreign wildcard host conflict accepted.'
$sites[0].PhysicalPath='C:\inetpub\wwwroot\santiye'
Assert-StaticThrows {Assert-StaticIisPlan $plan $sites @() $pools} 'API path adopted as static site.'
$sites[0].PhysicalPath=$plan[0].Root
Assert-StaticThrows {Assert-StaticIisPlan $plan $sites @([pscustomobject]@{Site='Other';Pool=$plan[0].Pool}) $pools} 'Shared application pool accepted.'
Assert-StaticThrows {Assert-StaticIisPlan $plan $sites @([pscustomobject]@{Site=$plan[0].Name;Pool='Other'}) $pools} 'Nested application accepted.'
$pools[0].Runtime='v4.0'
Assert-StaticThrows {Assert-StaticIisPlan $plan $sites @() $pools} 'Managed existing pool accepted.'
$pools[0].Runtime=''

$fixture=Join-Path $repository ('tmp\static-web-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
# Exercise the real create -> replace -> retry write path without elevation.
# Only ACL operations are stubbed in this child scope; JSON serialization,
# File.Move, File.Replace and the subsequent record/content read are real.
& {
    function Assert-StaticAdminOwnership([string]$Path,[switch]$Directory) {}
    function Set-Acl { param([string]$LiteralPath,$AclObject) }
    $recordRoot=Join-Path $fixture 'record-replacement'
    New-Item -ItemType Directory -Path $recordRoot | Out-Null
    $publicRoot=Join-Path $fixture 'record-public-root'
    $item=[pscustomobject]@{Key='santiye';Name='SantiyeAgi-Web';Pool='SantiyeAgi-Web';Root=$publicRoot;Hosts=@('santiyeagi.com.tr','www.santiyeagi.com.tr')}
    $record=[pscustomobject]@{schemaVersion=1;createdBy='santiye-static-installer-v1';siteName=$item.Name;pool=$item.Pool;physicalRoot=$publicRoot;releases=@()}
    $release=[pscustomobject]@{name='20261023-120000-abcdef12';state='PREPARING';files=@([pscustomobject]@{path='index.html';sha256=('1'*64)},[pscustomobject]@{path='web.config';sha256=('2'*64)})}
    $record.releases=@($release)
    Save-StaticOwnershipRecord $recordRoot 'santiye' $record
    $read=Get-StaticOwnershipRecords @($item) $recordRoot
    Assert-StaticTest ($read['santiye'].releases[0].state -eq 'PREPARING') 'Initial ownership write/read failed.'
    $release.state='COMPLETE'
    Save-StaticOwnershipRecord $recordRoot 'santiye' $record
    $read=Get-StaticOwnershipRecords @($item) $recordRoot
    Assert-StaticTest ($read['santiye'].releases[0].state -eq 'COMPLETE') 'Ownership replacement did not persist COMPLETE.'
    $record.releases += [pscustomobject]@{name='20261023-120001-abcdef12';state='PREPARING';files=$release.files}
    Save-StaticOwnershipRecord $recordRoot 'santiye' $record
    $read=Get-StaticOwnershipRecords @($item) $recordRoot
    Assert-StaticTest ($read['santiye'].releases.Count -eq 2 -and $read['santiye'].releases[1].state -eq 'PREPARING') 'Retry ownership replacement/read failed.'
    Assert-StaticTest (@(Get-ChildItem -LiteralPath $recordRoot -Filter '*.tmp').Count -eq 0) 'Successful record write left a temporary file.'
}
# An interrupted first installation can be retried only for a marker-declared,
# reserved release tree. This exercises filesystem ownership validation without IIS.
$ownedRoot=Join-Path $fixture 'owned-public-root'
$ownedItem=[pscustomobject]@{Key='santiye';Name='SantiyeAgi-Web';Pool='SantiyeAgi-Web';Root=$ownedRoot;Hosts=@('santiyeagi.com.tr','www.santiyeagi.com.tr')}
$ownedReleaseName='20261023-120000-a1b2c3d4'
$ownedRelease=Join-Path $ownedRoot ('releases\'+$ownedReleaseName)
New-Item -ItemType Directory -Path $ownedRelease -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $ownedRelease 'index.html'),'fixture root')
[IO.File]::WriteAllText((Join-Path $ownedRelease 'web.config'),'fixture config')
$ownedFiles=@('index.html','web.config') | ForEach-Object {[pscustomobject]@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $ownedRelease $_)).Hash}}
$ownedRecord=[pscustomobject]@{schemaVersion=1;createdBy='santiye-static-installer-v1';siteName=$ownedItem.Name;pool=$ownedItem.Pool;physicalRoot=$ownedRoot;releases=@([pscustomobject]@{name=$ownedReleaseName;state='COMPLETE';files=@($ownedFiles)})}
$untrustedMarkers=Join-Path $fixture 'untrusted-markers'
New-Item -ItemType Directory -Path $untrustedMarkers | Out-Null
$ownedRecord | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $untrustedMarkers 'santiye-ownership.json') -Encoding UTF8
Assert-StaticThrows {Get-StaticOwnershipRecords @($ownedItem) $untrustedMarkers} 'An unprotected ownership-marker directory was trusted.'
Assert-StaticThrows {Assert-StaticIisPlan @($ownedItem) @() @() @()} 'An existing unowned root was adopted.'
Assert-StaticIisPlan @($ownedItem) @() @() @() @{santiye=$ownedRecord};$script:checks++
$ownedRecord.physicalRoot=Join-Path $fixture 'wrong-root'
Assert-StaticThrows {Assert-StaticOwnershipContents $ownedItem $ownedRecord} 'A marker for another root was accepted.'
$ownedRecord.physicalRoot=$ownedRoot
[IO.File]::WriteAllText((Join-Path $ownedRelease 'index.html'),'partial interrupted copy')
Assert-StaticThrows {Assert-StaticOwnershipContents $ownedItem $ownedRecord} 'A modified COMPLETE release was accepted.'
$ownedRecord.releases[0].state='PREPARING'
Assert-StaticOwnershipContents $ownedItem $ownedRecord;$script:checks++
[IO.File]::WriteAllText((Join-Path $ownedRelease 'unowned.txt'),'unexpected file')
Assert-StaticThrows {Assert-StaticOwnershipContents $ownedItem $ownedRecord} 'An unowned file in a retained release was accepted.'
# Separate new fixture: reject an unrecorded sibling release and loose root files.
$otherRoot=Join-Path $fixture 'unrecorded-root'
New-Item -ItemType Directory -Path (Join-Path $otherRoot 'releases\20261023-120001-a1b2c3d4') -Force | Out-Null
$otherItem=[pscustomobject]@{Key='santiye';Name=$ownedItem.Name;Pool=$ownedItem.Pool;Root=$otherRoot;Hosts=$ownedItem.Hosts}
$otherRecord=[pscustomobject]@{schemaVersion=1;createdBy='santiye-static-installer-v1';siteName=$ownedItem.Name;pool=$ownedItem.Pool;physicalRoot=$otherRoot;releases=@()}
Assert-StaticThrows {Assert-StaticOwnershipContents $otherItem $otherRecord} 'An unrecorded release directory was accepted.'
[IO.File]::WriteAllText((Join-Path $otherRoot 'settings.json'),'unexpected root file')
Assert-StaticThrows {Assert-StaticOwnershipContents $otherItem $otherRecord} 'A loose file in the retained root was accepted.'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function New-StaticTestZip([string]$Name,[string]$BadPath='',[bool]$BadHash=$false,[bool]$Extra=$false) {
    $zipPath=Join-Path $fixture ($Name+'.zip');$zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Create)
    try {
        $files=@()
        foreach($key in @('santiye','asfaltik')) {
            foreach($fileName in @('index.html','web.config')) {
                $path='sites/'+$key+'/'+$fileName
                if($BadPath -and $key -eq 'santiye' -and $fileName -eq 'index.html'){$path=$BadPath}
                $bytes=[Text.Encoding]::UTF8.GetBytes('fixture '+$key+' '+$fileName)
                $entry=$zip.CreateEntry($path);$stream=$entry.Open()
                try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
                $memory=New-Object IO.MemoryStream(,$bytes)
                try{$hash=Get-StaticSha256Stream $memory}finally{$memory.Dispose()}
                if($BadHash){$hash='0'*64}
                $files += [pscustomobject]@{path=$path;sha256=$hash}
            }
        }
        if($Extra){$entry=$zip.CreateEntry('sites/asfaltik/unlisted.txt');$stream=$entry.Open();$stream.Dispose()}
        $manifest=[pscustomobject]@{schemaVersion=1;files=$files} | ConvertTo-Json -Depth 5
        $entry=$zip.CreateEntry('PACKAGE-MANIFEST.json');$stream=$entry.Open();$writer=New-Object IO.StreamWriter($stream,[Text.UTF8Encoding]::new($false))
        try{$writer.Write($manifest)}finally{$writer.Dispose();$stream.Dispose()}
    }finally{$zip.Dispose()}
    return $zipPath
}
$validZip=New-StaticTestZip 'valid'
$validHash=(Get-FileHash -LiteralPath $validZip -Algorithm SHA256).Hash
$verified=Get-StaticVerifiedArchive $validZip $validHash
try{Assert-StaticTest ($verified.Hashes.Count -eq 4) 'Valid archive not accepted.'}finally{$verified.Archive.Dispose()}
Assert-StaticThrows {Get-StaticVerifiedArchive $validZip ('0'*64)} 'Untrusted ZIP hash accepted.'
$badZip=New-StaticTestZip 'traversal' 'sites/santiye/../index.html'
Assert-StaticThrows {Get-StaticVerifiedArchive $badZip (Get-FileHash -LiteralPath $badZip).Hash} 'ZIP traversal accepted.'
$badZip=New-StaticTestZip 'bad-content' '' $true
Assert-StaticThrows {Get-StaticVerifiedArchive $badZip (Get-FileHash -LiteralPath $badZip).Hash} 'Manifest hash mismatch accepted.'
$badZip=New-StaticTestZip 'extra' '' $false $true
Assert-StaticThrows {Get-StaticVerifiedArchive $badZip (Get-FileHash -LiteralPath $badZip).Hash} 'Unlisted file accepted.'
Write-Output ('Static website installer: '+$script:checks+' local path/manifest/ownership/conflict checks and PowerShell parsing passed. No live IIS changes were tested or made.')

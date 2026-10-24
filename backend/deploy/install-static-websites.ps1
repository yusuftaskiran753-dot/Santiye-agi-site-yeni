[CmdletBinding(DefaultParameterSetName='Install')]
param(
    [Parameter(ParameterSetName='Install')][string]$PackagePath='C:\ProgramData\santiye\Web-Siteleri-IIS.zip',
    [Parameter(Mandatory=$true,ParameterSetName='Install')][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
    [Parameter(Mandatory=$true,ParameterSetName='Helpers')][switch]$FunctionsOnly
)

# Public static files only. This installer never imports API settings or changes DNS,
# certificates, HTTPS bindings, Firebase, SMS, app-store or GitHub Pages settings.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2

function Get-StaticWebsitePlan {
    @(
        [pscustomobject]@{Key='santiye';Name='SantiyeAgi-Web';Pool='SantiyeAgi-Web';Root='C:\inetpub\wwwroot\santiye-web';Hosts=@('santiyeagi.com.tr','www.santiyeagi.com.tr')},
        [pscustomobject]@{Key='asfaltik';Name='Asfaltik-Web';Pool='Asfaltik-Web';Root='C:\inetpub\wwwroot\asfaltik-web';Hosts=@('asfaltik.com.tr','www.asfaltik.com.tr')}
    )
}

function Get-StaticFullPath([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path) -or ![IO.Path]::IsPathRooted($Path)){throw 'Mutlak dosya yolu gerekli.'}
    return [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
}

function Assert-StaticNoReparse([string]$Path) {
    $current=Get-StaticFullPath $Path
    while($current) {
        if(Test-Path -LiteralPath $current) {
            $item=Get-Item -LiteralPath $current -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse/junction yolu kabul edilmez.'}
        }
        $parent=[IO.Path]::GetDirectoryName($current)
        if($parent -eq $current){break};$current=$parent
    }
}

function Test-StaticOwnedPath([string]$Path,[string]$Root) {
    $actual=Get-StaticFullPath ([Environment]::ExpandEnvironmentVariables($Path))
    $expected=Get-StaticFullPath $Root
    if($actual -ieq $expected){return $true}
    $prefix=$expected+'\releases\'
    if(!$actual.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){return $false}
    return $actual.Substring($prefix.Length) -cmatch '^[A-Za-z0-9_-]{1,80}$'
}

function Assert-StaticPackagePath([string]$Path) {
    if(!$Path -or $Path.Contains('\') -or $Path.StartsWith('/') -or $Path.Contains(':') -or $Path -match '[\x00-\x1F\x7F]'){throw 'Paket yolu gecersiz.'}
    foreach($part in $Path.Split('/')) {
        if(!$part -or $part -eq '.' -or $part -eq '..' -or $part.StartsWith('.') -or $part -match '[<>"|?*]' -or $part -match '[. ]$' -or $part -match '^(?i:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)'){throw 'Paket dosya adi gecersiz.'}
    }
    if($Path -ceq 'PACKAGE-MANIFEST.json'){return}
    if($Path -cnotmatch '^sites/(santiye|asfaltik)/.+$'){throw 'Paket yalniz iki statik siteyi icerebilir.'}
    $relative=$Path -creplace '^sites/(santiye|asfaltik)/',''
    $extension=[IO.Path]::GetExtension($relative).ToLowerInvariant()
    if($extension -eq '.config') {
        if($relative -cne 'web.config'){throw 'Alt klasor config dosyasi kabul edilmez.'}
    } elseif(@('.html','.htm','.css','.js','.json','.svg','.png','.jpg','.jpeg','.webp','.gif','.ico','.txt','.xml','.woff','.woff2','.ttf','.otf') -notcontains $extension) {
        throw 'Paket dosya turu kabul edilmez.'
    }
    if($relative -match '(?i)(^|/)(appsettings[^/]*|settings\.json|[^/]*service[-_]?account[^/]*|[^/]*private[-_]?key[^/]*|recovery\.key)$'){throw 'Ozel ayar dosyasi statik pakete eklenemez.'}
}

function Get-StaticSha256Stream([IO.Stream]$Stream) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}

function Get-StaticVerifiedArchive([string]$ZipPath,[string]$Hash) {
    if($Hash -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'Beklenen ZIP SHA-256 zorunludur.'}
    $zipFull=Get-StaticFullPath $ZipPath;Assert-StaticNoReparse $zipFull
    if(!(Test-Path -LiteralPath $zipFull -PathType Leaf)){throw 'ZIP dosyasi bulunamadi.'}
    if((Get-Item -LiteralPath $zipFull).Length -gt 100MB){throw 'ZIP boyut sinirini asiyor.'}
    if((Get-FileHash -LiteralPath $zipFull -Algorithm SHA256).Hash -ine $Hash){throw 'ZIP SHA-256 eslesmedi. Kurulum yapilmadi.'}
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($zipFull)
    try {
        if($zip.Entries.Count -gt 4000){throw 'ZIP kayit sayisi sinirini asiyor.'}
        $files=@{};$total=[long]0
        foreach($entry in $zip.Entries) {
            $name=[string]$entry.FullName
            if($name.EndsWith('/')) {
                $directory=$name.TrimEnd('/')
                if($directory -cne 'sites' -and $directory -cnotmatch '^sites/(santiye|asfaltik)(/[^/]+)*$'){throw 'ZIP dizini izinli degil.'}
                # Reuse path checks by appending an ordinary public filename.
                if($directory -cne 'sites'){Assert-StaticPackagePath ($directory+'/directory-check.txt')}
                continue
            }
            Assert-StaticPackagePath $name
            if($files.ContainsKey($name)){throw 'ZIP yinelenen dosya yolu iceriyor.'}
            if($entry.Length -gt 20MB){throw 'Paket dosyasi boyut sinirini asiyor.'}
            $total+=$entry.Length
            if($total -gt 100MB -or $files.Count -ge 2000){throw 'Paket acilmis boyut/dosya sinirini asiyor.'}
            $files[$name]=$entry
        }
        if(!$files.ContainsKey('PACKAGE-MANIFEST.json')){throw 'Paket manifesti eksik.'}
        if($files['PACKAGE-MANIFEST.json'].Length -gt 1MB){throw 'Paket manifesti cok buyuk.'}
        $stream=$files['PACKAGE-MANIFEST.json'].Open();$reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true)
        try{$manifest=$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose();$stream.Dispose()}
        if($manifest.schemaVersion -ne 1 -or @($manifest.files).Count -lt 4){throw 'Manifest semasi gecersiz.'}
        $listed=@{}
        foreach($file in $manifest.files) {
            $name=[string]$file.path;$fileHash=[string]$file.sha256
            Assert-StaticPackagePath $name
            if($name -ceq 'PACKAGE-MANIFEST.json' -or $fileHash -cnotmatch '^[A-Fa-f0-9]{64}$' -or $listed.ContainsKey($name) -or !$files.ContainsKey($name)){throw 'Manifest dosya listesi gecersiz.'}
            $listed[$name]=$fileHash.ToLowerInvariant()
            $stream=$files[$name].Open()
            try{if((Get-StaticSha256Stream $stream) -cne $listed[$name]){throw 'Manifest icerik ozeti eslesmedi.'}}finally{$stream.Dispose()}
        }
        if($listed.Count -ne $files.Count-1){throw 'Manifest disinda dosya var.'}
        foreach($key in @('santiye','asfaltik')) {
            foreach($required in @('index.html','web.config')) {
                if(!$listed.ContainsKey('sites/'+$key+'/'+$required)){throw 'Site index.html veya web.config eksik.'}
            }
        }
        return [pscustomobject]@{Archive=$zip;Files=$files;Hashes=$listed;ZipPath=$zipFull}
    }catch{$zip.Dispose();throw}
}

function Convert-StaticBinding([string]$Information) {
    if($Information -notmatch '^(.*):(\d+):(.*)$'){throw 'IIS binding bicimi taninamadi.'}
    return [pscustomobject]@{Address=$Matches[1];Port=[int]$Matches[2];Host=$Matches[3].ToLowerInvariant().TrimEnd('.')}
}

function Assert-StaticOwnershipContents($PlanItem,$Record) {
    if($Record.schemaVersion -ne 1 -or $Record.createdBy -cne 'santiye-static-installer-v1' -or $Record.siteName -cne $PlanItem.Name -or $Record.pool -cne $PlanItem.Pool -or (Get-StaticFullPath ([string]$Record.physicalRoot)) -ine (Get-StaticFullPath $PlanItem.Root)){throw 'Statik sahiplik kaydi site/root/pool ile eslesmiyor.'}
    $releases=@{}
    foreach($release in @($Record.releases)) {
        $releaseName=[string]$release.name
        if($releaseName -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or $releases.ContainsKey($releaseName) -or @('PREPARING','COMPLETE') -notcontains [string]$release.state){throw 'Statik sahiplik release kaydi gecersiz.'}
        $files=@{}
        foreach($file in @($release.files)) {
            $relative=[string]$file.path
            Assert-StaticPackagePath ('sites/'+$PlanItem.Key+'/'+$relative)
            if($files.ContainsKey($relative) -or [string]$file.sha256 -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'Sahiplik dosya listesi gecersiz.'}
            $files[$relative]=[string]$file.sha256
        }
        if(!$files.ContainsKey('index.html') -or !$files.ContainsKey('web.config')){throw 'Sahiplik dosya listesi eksik.'}
        $releases[$releaseName]=[pscustomobject]@{State=[string]$release.state;Files=$files}
    }
    Assert-StaticNoReparse $PlanItem.Root
    if(!(Test-Path -LiteralPath $PlanItem.Root)){return}
    if(!(Test-Path -LiteralPath $PlanItem.Root -PathType Container)){throw 'Statik root dizin degil.'}
    foreach($entry in @(Get-ChildItem -LiteralPath $PlanItem.Root -Force)) {
        if($entry.Name -cne 'releases' -or !$entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Sahiplik kaydi disinda root icerigi var.'}
    }
    $releasesRoot=Join-Path $PlanItem.Root 'releases'
    if(!(Test-Path -LiteralPath $releasesRoot)){return}
    foreach($directory in @(Get-ChildItem -LiteralPath $releasesRoot -Force)) {
        if(!$directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -or !$releases.ContainsKey($directory.Name)){throw 'Sahiplik kaydi disinda release var.'}
        $declared=$releases[$directory.Name];$seen=@{}
        $pending=New-Object 'Collections.Generic.Stack[string]';$pending.Push($directory.FullName)
        while($pending.Count) {
            $current=$pending.Pop();Assert-StaticNoReparse $current
            foreach($entry in @(Get-ChildItem -LiteralPath $current -Force)) {
                if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Release reparse iceriyor.'}
                $relative=$entry.FullName.Substring($directory.FullName.Length).TrimStart('\').Replace('\','/')
                if($entry.PSIsContainer) {
                    $prefix=$relative+'/'
                    if(!@($declared.Files.Keys | Where-Object {$_.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)}).Count){throw 'Release kayit disi dizin iceriyor.'}
                    $pending.Push($entry.FullName)
                }else {
                    if(!$declared.Files.ContainsKey($relative)){throw 'Release kayit disi dosya iceriyor.'}
                    $seen[$relative]=$true
                    # Interrupted copies can leave partial files only in PREPARING releases.
                    # Such files are never adopted into a new release or served by this retry.
                    if($declared.State -eq 'COMPLETE' -and (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash -ine $declared.Files[$relative]){throw 'Tamamlanmis release degistirilmis.'}
                }
            }
        }
        if($declared.State -eq 'COMPLETE' -and $seen.Count -ne $declared.Files.Count){throw 'Tamamlanmis release dosyalari eksik.'}
    }
}

function Assert-StaticAdminOwnership([string]$Path,[switch]$Directory) {
    Assert-StaticNoReparse $Path
    $acl=Get-Acl -LiteralPath $Path
    $trusted=@('S-1-5-18','S-1-5-32-544')
    $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if($trusted -notcontains $owner -or ($Directory -and !$acl.AreAccessRulesProtected)){throw 'Sahiplik kaydi klasoru guvenilir yonetici sahipliginde degil.'}
    $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    if(!$rules.Count){throw 'Sahiplik kaydi ACL eksik.'}
    foreach($rule in $rules) {
        if($trusted -notcontains $rule.IdentityReference.Value -or $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){throw 'Sahiplik kaydi ACL guvenilir degil.'}
    }
}

function Get-StaticOwnershipRecords($Plan,[string]$OperationsRoot) {
    $records=@{}
    if(!(Test-Path -LiteralPath $OperationsRoot)){return $records}
    Assert-StaticAdminOwnership $OperationsRoot -Directory
    foreach($item in $Plan) {
        $path=Join-Path $OperationsRoot ($item.Key+'-ownership.json')
        if(Test-Path -LiteralPath $path) {
            if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -gt 5MB){throw 'Sahiplik kaydi dosyasi gecersiz.'}
            Assert-StaticAdminOwnership $path
            $record=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-StaticOwnershipContents $item $record
            $records[$item.Key]=$record
        }
    }
    return $records
}

function Save-StaticOwnershipRecord([string]$OperationsRoot,[string]$Key,$Record) {
    Assert-StaticAdminOwnership $OperationsRoot -Directory
    $destination=Join-Path $OperationsRoot ($Key+'-ownership.json')
    $temporary=Join-Path $OperationsRoot ($Key+'-ownership-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $json=$Record | ConvertTo-Json -Depth 10
    if([Text.Encoding]::UTF8.GetByteCount($json) -gt 5MB){throw 'Sahiplik kaydi boyut sinirini asiyor.'}
    [IO.File]::WriteAllText($temporary,$json,[Text.UTF8Encoding]::new($false))
    $acl=New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true,$false)
    $administrators=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544');$acl.SetOwner($administrators)
    foreach($sid in @('S-1-5-18','S-1-5-32-544')) {
        $identity=New-Object Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','Allow')))
    }
    Set-Acl -LiteralPath $temporary -AclObject $acl
    # PowerShell binds plain $null to an empty System.String here. File.Replace
    # needs an actual CLR null for "no backup"; an empty path fails on Windows.
    if(Test-Path -LiteralPath $destination){Assert-StaticAdminOwnership $destination;[IO.File]::Replace($temporary,$destination,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$destination)}
    Assert-StaticAdminOwnership $destination
}

function Assert-StaticIisPlan($Plan,$Sites,$Applications,$Pools,$OwnershipRecords=@{}) {
    foreach($item in $Plan) {
        $owned=@($Sites | Where-Object {$_.Name -ieq $item.Name})
        if($owned.Count -gt 1){throw 'IIS site adi belirsiz.'}
        if($owned.Count -eq 1) {
            if(!(Test-StaticOwnedPath $owned[0].PhysicalPath $item.Root) -or $owned[0].Pool -ine $item.Pool){throw 'Mevcut IIS sitesi bu kuruluma ait degil.'}
            if(@($Applications | Where-Object {$_.Site -ieq $item.Name}).Count){throw 'Statik sitede ek uygulama/virtual directory var.'}
        }elseif(Test-Path -LiteralPath $item.Root) {
            if(!$OwnershipRecords.ContainsKey($item.Key)){throw 'Site yok ancak hedef klasor zaten var; otomatik sahiplenilmedi.'}
            Assert-StaticOwnershipContents $item $OwnershipRecords[$item.Key]
        }
        foreach($site in $Sites) {
            if($site.Pool -ieq $item.Pool -and $site.Name -ine $item.Name){throw 'Statik pool baska site tarafindan kullaniliyor.'}
            foreach($binding in @($site.Bindings)) {
                $parts=Convert-StaticBinding $binding.Information
                $matchesPlanned=$false
                foreach($domain in $item.Hosts) {
                    if($parts.Host -eq $domain -or ($parts.Host.Contains('*') -and $domain -like $parts.Host)){$matchesPlanned=$true}
                }
                if($matchesPlanned -and $site.Name -ine $item.Name){throw 'Alan adi baska IIS sitesinde bagli; kurulum durdu.'}
                if($site.Name -ieq $item.Name) {
                    if($item.Hosts -notcontains $parts.Host -or @('http','https') -notcontains $binding.Protocol){throw 'Mevcut statik sitede beklenmeyen binding var.'}
                    if($binding.Protocol -eq 'http' -and ($parts.Port -ne 80 -or $parts.Address -ne '*')){throw 'Mevcut HTTP binding bu plana uymuyor.'}
                }
            }
        }
        if(@($Applications | Where-Object {$_.Pool -ieq $item.Pool}).Count){throw 'Statik pool baska uygulama tarafindan kullaniliyor.'}
        $pool=@($Pools | Where-Object {$_.Name -ieq $item.Pool})
        if($pool.Count -and ([string]$pool[0].Runtime -ne '' -or [string]$pool[0].Identity -notin @('ApplicationPoolIdentity','4'))){throw 'Mevcut pool statik/ayri pool kosulunu saglamiyor.'}
    }
}

function Get-StaticIisSnapshot {
    $sites=@();$applications=@();$pools=@()
    foreach($site in Get-Website) {
        $bindings=@(Get-WebBinding -Name $site.Name | ForEach-Object {[pscustomobject]@{Protocol=[string]$_.protocol;Information=[string]$_.bindingInformation}})
        $sites += [pscustomobject]@{Name=[string]$site.Name;Id=[int]$site.Id;PhysicalPath=[string]$site.physicalPath;Pool=[string]$site.applicationPool;State=[string]$site.State;Bindings=$bindings}
        foreach($app in @(Get-WebApplication -Site $site.Name)){$applications += [pscustomobject]@{Site=[string]$site.Name;Pool=[string]$app.applicationPool}}
        foreach($directory in @(Get-WebVirtualDirectory -Site $site.Name)) {
            if([string]$directory.path -ne '/'){$applications += [pscustomobject]@{Site=[string]$site.Name;Pool=''}}
        }
    }
    foreach($pool in Get-ChildItem IIS:\AppPools){$pools += [pscustomobject]@{Name=[string]$pool.Name;Runtime=[string]$pool.managedRuntimeVersion;Identity=[string]$pool.processModel.identityType}}
    return [pscustomobject]@{Sites=$sites;Applications=$applications;Pools=$pools}
}

function Set-StaticDirectoryAcl([string]$Path,[string]$Pool='') {
    Assert-StaticNoReparse $Path
    $acl=New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    $inherit=[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
    $propagation=[Security.AccessControl.PropagationFlags]::None
    $allow=[Security.AccessControl.AccessControlType]::Allow
    foreach($sid in @('S-1-5-18','S-1-5-32-544')) {
        $identity=New-Object Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl',$inherit,$propagation,$allow)))
    }
    if($Pool) {
        $iusr=New-Object Security.Principal.SecurityIdentifier('S-1-5-17')
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($iusr,'ReadAndExecute',$inherit,$propagation,$allow)))
        $poolIdentity=New-Object Security.Principal.NTAccount('IIS AppPool\'+$Pool)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($poolIdentity,'ReadAndExecute',$inherit,$propagation,$allow)))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Test-StaticHttp([string]$HostName,[string]$ExpectedIndexHash) {
    $lastStatus=0
    for($attempt=0;$attempt -lt 5;$attempt++) {
        $response=$null
        try {
            $request=[Net.HttpWebRequest]::Create('http://127.0.0.1/')
            $request.Host=$HostName;$request.AllowAutoRedirect=$false;$request.Proxy=$null;$request.Timeout=10000
            $response=$request.GetResponse();$lastStatus=[int]$response.StatusCode
            $stream=$response.GetResponseStream()
            try{$matches=(Get-StaticSha256Stream $stream) -ieq $ExpectedIndexHash}finally{$stream.Dispose()}
            if($lastStatus -eq 200 -and $matches){return [pscustomobject]@{Host=$HostName;Status=200;IndexHashMatches=$true}}
        }catch{if($_.Exception.Response){$lastStatus=[int]$_.Exception.Response.StatusCode}}finally{if($response){$response.Dispose()}}
        Start-Sleep -Milliseconds 500
    }
    throw ('Yerel HTTP Host kontrolu basarisiz: '+$HostName+'; HTTP '+$lastStatus+'.')
}

if($FunctionsOnly){return}

$verified=$null;$changed=@();$createdPools=@();$recordPath=$null
try {
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Yonetici PowerShell gerekli.'}
    Import-Module WebAdministration
    $globalModules=@(Get-WebGlobalModule | ForEach-Object {[string]$_.Name})
    if($globalModules -notcontains 'StaticFileModule' -or $globalModules -notcontains 'DefaultDocumentModule'){throw 'IIS Static Content ve Default Document ozellikleri gerekli.'}
    $plan=@(Get-StaticWebsitePlan)
    $operationsRoot='C:\ProgramData\santiye\static-web-deploy'
    $ownershipRecords=Get-StaticOwnershipRecords $plan $operationsRoot
    foreach($item in $plan){Assert-StaticNoReparse $item.Root}
    $verified=Get-StaticVerifiedArchive $PackagePath $ExpectedSha256
    $snapshot=Get-StaticIisSnapshot
    Assert-StaticIisPlan $plan $snapshot.Sites $snapshot.Applications $snapshot.Pools $ownershipRecords
    $stamp=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    Assert-StaticNoReparse $operationsRoot
    if(!(Test-Path -LiteralPath $operationsRoot)){New-Item -ItemType Directory -Path $operationsRoot | Out-Null}
    Set-StaticDirectoryAcl $operationsRoot
    $operation=Join-Path $operationsRoot $stamp
    New-Item -ItemType Directory -Path $operation | Out-Null
    Set-StaticDirectoryAcl $operation
    $stage=Join-Path $operation 'stage';New-Item -ItemType Directory -Path $stage | Out-Null
    foreach($name in $verified.Hashes.Keys) {
        $destination=Join-Path $stage $name.Replace('/','\')
        $parent=[IO.Path]::GetDirectoryName($destination)
        if(!(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
        $inputStream=$verified.Files[$name].Open();$outputStream=[IO.File]::Open($destination,[IO.FileMode]::CreateNew)
        try{$inputStream.CopyTo($outputStream)}finally{$inputStream.Dispose();$outputStream.Dispose()}
        if((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine $verified.Hashes[$name]){throw 'Stage dosya ozeti eslesmedi.'}
    }
    $packageHashes=$verified.Hashes
    $verified.Archive.Dispose();$verified=$null
    foreach($item in $plan) {
        [xml]$web=Get-Content -LiteralPath (Join-Path $stage ('sites\'+$item.Key+'\web.config')) -Raw -Encoding UTF8
        if($web.SelectNodes('//rewrite|//aspNetCore|//httpRedirect|//handlers|//modules|//location').Count){throw 'Statik pakette yonlendirme/uygulama config kabul edilmez.'}
        if([string]$web.configuration.'system.webServer'.defaultDocument.files.add.value -cne 'index.html'){throw 'Statik varsayilan belge index.html olmali.'}
    }
    # Recheck ownership and collisions after package staging, before IIS writes.
    $snapshot=Get-StaticIisSnapshot
    $ownershipRecords=Get-StaticOwnershipRecords $plan $operationsRoot
    Assert-StaticIisPlan $plan $snapshot.Sites $snapshot.Applications $snapshot.Pools $ownershipRecords
    $backupName='StaticWeb-'+$stamp
    Backup-WebConfiguration -Name $backupName | Out-Null
    $recordPath=Join-Path $operation 'deployment.json'
    [pscustomobject]@{IisBackup=$backupName;PackageSha256=$ExpectedSha256.ToLowerInvariant();Before=$snapshot.Sites | Where-Object {$_.Name -in $plan.Name};Status='PREPARED'} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding UTF8
    foreach($item in $plan) {
        $poolExisted=Test-Path ('IIS:\AppPools\'+$item.Pool)
        if(!$poolExisted) {
            New-WebAppPool -Name $item.Pool | Out-Null;$createdPools += $item.Pool
            Set-ItemProperty ('IIS:\AppPools\'+$item.Pool) -Name managedRuntimeVersion -Value ''
            Set-ItemProperty ('IIS:\AppPools\'+$item.Pool) -Name managedPipelineMode -Value Integrated
            Set-ItemProperty ('IIS:\AppPools\'+$item.Pool) -Name processModel.identityType -Value ApplicationPoolIdentity
        }
        $release=Join-Path $item.Root ('releases\'+$stamp)
        Assert-StaticNoReparse $release
        if(Test-Path -LiteralPath $release){throw 'Release klasoru zaten var.'}
        $before=@($snapshot.Sites | Where-Object {$_.Name -ieq $item.Name})
        # Only record a new, absent root or an already protected installer-owned root.
        # Existing legacy IIS-owned directories are never retroactively adopted.
        $recordOwnership=$ownershipRecords.ContainsKey($item.Key) -or ($before.Count -eq 0 -and !(Test-Path -LiteralPath $item.Root))
        if($recordOwnership) {
            if(!$ownershipRecords.ContainsKey($item.Key)) {
                $ownershipRecords[$item.Key]=[pscustomobject]@{schemaVersion=1;createdBy='santiye-static-installer-v1';siteName=$item.Name;pool=$item.Pool;physicalRoot=$item.Root;releases=@()}
            }
            $record=$ownershipRecords[$item.Key]
            $prefix='sites/'+$item.Key+'/'
            $releaseFiles=@($packageHashes.Keys | Where-Object {$_.StartsWith($prefix,[StringComparison]::Ordinal)} | Sort-Object | ForEach-Object {[pscustomobject]@{path=$_.Substring($prefix.Length);sha256=$packageHashes[$_]}})
            $releaseRecord=[pscustomobject]@{name=$stamp;state='PREPARING';files=$releaseFiles}
            $record.releases=@($record.releases)+@($releaseRecord)
            Save-StaticOwnershipRecord $operationsRoot $item.Key $record
        }
        New-Item -ItemType Directory -Path $release -Force | Out-Null
        Set-StaticDirectoryAcl $release $item.Pool
        $source=Join-Path $stage ('sites\'+$item.Key)
        foreach($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
            $relative=$file.FullName.Substring($source.Length).TrimStart('\')
            $destination=Join-Path $release $relative
            $parent=[IO.Path]::GetDirectoryName($destination)
            if(!(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
            [IO.File]::Copy($file.FullName,$destination,$false)
        }
        if($recordOwnership) {
            $releaseRecord.state='COMPLETE'
            Assert-StaticOwnershipContents $item $record
            Save-StaticOwnershipRecord $operationsRoot $item.Key $record
        }
        $change=[pscustomobject]@{Name=$item.Name;Pool=$item.Pool;NewSite=($before.Count -eq 0);Before=$(if($before.Count){$before[0]}else{$null});AddedBindings=@();Release=$release}
        $changed += $change
        if($change.NewSite) {
            New-Website -Name $item.Name -PhysicalPath $release -ApplicationPool $item.Pool -Port 80 -IPAddress '*' -HostHeader $item.Hosts[0] | Out-Null
        }else{Set-ItemProperty ('IIS:\Sites\'+$item.Name) -Name physicalPath -Value $release}
        foreach($domain in $item.Hosts) {
            $information='*:80:'+$domain
            $exists=@(Get-WebBinding -Name $item.Name -Protocol http | Where-Object {$_.bindingInformation -ieq $information}).Count -gt 0
            if(!$exists) {
                New-WebBinding -Name $item.Name -Protocol http -Port 80 -IPAddress '*' -HostHeader $domain
                $change.AddedBindings += $domain
            }
        }
        Start-Website -Name $item.Name
    }
    $checks=@();$sites=@()
    foreach($change in $changed) {
        $item=$plan | Where-Object {$_.Name -eq $change.Name}
        $hash=(Get-FileHash -LiteralPath (Join-Path $change.Release 'index.html') -Algorithm SHA256).Hash
        foreach($domain in $item.Hosts){$checks += Test-StaticHttp $domain $hash}
        $current=Get-Website -Name $item.Name
        $sites += [pscustomobject]@{Name=$item.Name;Id=[int]$current.Id;Pool=$item.Pool;PhysicalPath=$change.Release;Hosts=$item.Hosts;HttpsBindingPresent=(@(Get-WebBinding -Name $item.Name -Protocol https).Count -gt 0)}
    }
    $result=[pscustomobject]@{Status='HTTP_READY';ServerAddress='45.59.70.198';IisBackup=$backupName;DeploymentRecord=$recordPath;Sites=$sites;HttpChecks=$checks;DnsChanged=$false;GithubPagesChanged=$false;ApiConfigurationChanged=$false;CertificateChanges=$false}
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding UTF8
    $result | ConvertTo-Json -Depth 8
}catch {
    $failure=$_.Exception.Message;$rollbackErrors=@()
    for($rollbackIndex=$changed.Count-1;$rollbackIndex -ge 0;$rollbackIndex--) {
        $change=$changed[$rollbackIndex]
        try {
            if($change.NewSite) {
                if(Test-Path ('IIS:\Sites\'+$change.Name)){Stop-Website -Name $change.Name -ErrorAction SilentlyContinue;Remove-Website -Name $change.Name}
            }else {
                foreach($domain in $change.AddedBindings){Remove-WebBinding -Name $change.Name -Protocol http -BindingInformation ('*:80:'+$domain)}
                Set-ItemProperty ('IIS:\Sites\'+$change.Name) -Name physicalPath -Value $change.Before.PhysicalPath
                if($change.Before.State -eq 'Started'){Start-Website -Name $change.Name}else{Stop-Website -Name $change.Name}
            }
        }catch{$rollbackErrors += $change.Name}
    }
    foreach($poolName in $createdPools) {
        try{if(Test-Path ('IIS:\AppPools\'+$poolName)){Remove-WebAppPool -Name $poolName}}catch{$rollbackErrors += $poolName}
    }
    if($recordPath){[pscustomobject]@{Status='FAILED';Reason=$failure;RollbackErrors=$rollbackErrors;ReleaseFilesRetained=$true} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath -Encoding UTF8}
    Write-Error ('Statik site kurulumu durdu: '+$failure+' Rollback hatasi: '+($rollbackErrors -join ', ')+'. API ve DNS ayarlari degistirilmedi; dosyalar silinmedi.')
    exit 1
}finally{if($verified){$verified.Archive.Dispose()}}

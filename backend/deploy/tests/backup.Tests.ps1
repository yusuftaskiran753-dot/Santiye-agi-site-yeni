param([Parameter(Mandatory=$true)][string]$PostgresBin,[int]$Port=55432,[Parameter(Mandatory=$true)][string]$PasswordFile)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$tools=Join-Path (Split-Path $PSScriptRoot -Parent) 'backup-common.ps1'
. $tools
$workspace=Join-Path $repo ('tmp\backup-regression-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace | Out-Null
# This process is not elevated. Simulate only the ACL command in this fixture;
# dump, encryption, authentication and restore all run for real.
function icacls.exe {
    $path=[string]$args[0]
    if(!$path.StartsWith($workspace,[StringComparison]::OrdinalIgnoreCase)) { throw 'ACL fixture escaped its workspace.' }
    $global:LASTEXITCODE=0
}
$name='santiye_test_'+[guid]::NewGuid().ToString('N')
$password=[IO.File]::ReadAllText($PasswordFile).Trim()
$connection=@{Host='127.0.0.1';Port=$Port;Database=$name;User='santiye_dev';Password=$password}
$previous=$env:PGPASSFILE
$pass=Join-Path $workspace 'test.pgpass'; New-BackupPgPass $connection $pass; $env:PGPASSFILE=$pass
$argsBase=@('--host=127.0.0.1',"--port=$Port",'--username=santiye_dev','--no-password')
$created=$false
try {
    $null=Invoke-BackupPg $PostgresBin 'createdb' ($argsBase+@('--maintenance-db=postgres',$name)); $created=$true
    $null=Invoke-BackupPg $PostgresBin 'psql' ($argsBase+@("--dbname=$name",'--set=ON_ERROR_STOP=1',"--command=CREATE TABLE fixture(id integer PRIMARY KEY, photo bytea NOT NULL); INSERT INTO fixture VALUES(1,decode('89504e47000102','hex')),(2,decode('ff00aa','hex'));"))
    $schemaSql=Join-Path $workspace 'schema.sql'
    [IO.File]::WriteAllText($schemaSql,'CREATE SCHEMA santiye; CREATE TABLE santiye."Users"(id integer PRIMARY KEY); CREATE TABLE santiye."Listings"(id integer PRIMARY KEY); CREATE TABLE santiye."Deals"(id integer PRIMARY KEY); CREATE TABLE santiye."PortfolioPhotos"(id integer PRIMARY KEY);')
    $null=Invoke-BackupPg $PostgresBin 'psql' ($argsBase+@("--dbname=$name",'--set=ON_ERROR_STOP=1',"--file=$schemaSql"))
    $keys=Join-Path $workspace 'keys'; New-Item -ItemType Directory -Path $keys | Out-Null
    [IO.File]::WriteAllText((Join-Path $keys 'fixture.xml'),'<fixture>not-a-production-key</fixture>')
    $settingsPath=Join-Path $workspace 'settings.json'
    $builder=New-Object System.Data.Common.DbConnectionStringBuilder
    $builder['Host']='127.0.0.1';$builder['Port']=$Port;$builder['Database']=$name;$builder['Username']='santiye_dev';$builder['Password']=$password
    Write-BackupJson $settingsPath @{ConnectionStrings=@{Postgres=$builder.get_ConnectionString()};DataProtection=@{KeysPath=$keys}}
    $roundTrip=Read-BackupConnection $settingsPath
    if($roundTrip.Database -cne $name -or $roundTrip.Password -cne $password) { throw 'Connection parsing failed.' }
    $recovery=Join-Path $workspace 'recovery.key'
    $bytes=New-Object byte[] 64;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
    [IO.File]::WriteAllBytes($recovery,$bytes)
    $root=Join-Path $workspace 'backups'
    $configPath=Join-Path $workspace 'backup-config.json'
    Write-BackupJson $configPath @{SettingsPath=$settingsPath;BackupRoot=$root;PostgresBin=$PostgresBin;RecoveryKeyPath=$recovery;RetentionDays=14;OffsiteDirectory=''}
    & (Join-Path (Split-Path $PSScriptRoot -Parent) 'run-backup.ps1') -ConfigPath $configPath
    $status=Get-Content (Join-Path $root 'last-success.json') -Raw | ConvertFrom-Json
    if(!$status.restore.passed -or $status.restore.tables -ne 5 -or $status.restore.critical_application_tables -ne 4 -or $status.offsite -cne 'disabled_by_owner') { throw 'Restore/offsite status incorrect.' }
    $archive=Join-Path $root $status.file
    & (Join-Path (Split-Path $PSScriptRoot -Parent) 'verify-backup.ps1') -ArchivePath $archive -ConfigPath $configPath
    # Independently inspect restored row values, including binary photo bytes.
    $zip=Join-Path $workspace 'inspect.zip'; Unprotect-BackupArchive $archive $zip $recovery
    $payload=Join-Path $workspace 'inspect'; Expand-Archive -LiteralPath $zip -DestinationPath $payload
    $checkName='santiye_test_'+[guid]::NewGuid().ToString('N')
    $null=Invoke-BackupPg $PostgresBin 'createdb' ($argsBase+@('--maintenance-db=postgres',$checkName))
    try {
        $null=Invoke-BackupPg $PostgresBin 'pg_restore' ($argsBase+@("--dbname=$checkName",'--exit-on-error',(Join-Path $payload 'database.backup')))
        $actual=Invoke-BackupPg $PostgresBin 'psql' ($argsBase+@("--dbname=$checkName",'--no-psqlrc','-At',"--command=SELECT id || ':' || encode(photo,'hex') FROM fixture ORDER BY id;"))
        if(($actual -join ',') -cne '1:89504e47000102,2:ff00aa') { throw 'Restored photo data differs.' }
    } finally { $null=Invoke-BackupPg $PostgresBin 'dropdb' ($argsBase+@('--maintenance-db=postgres','--force',$checkName)) }
    $damaged=Join-Path $workspace 'damaged.enc';$data=[IO.File]::ReadAllBytes($archive);$data[40]=$data[40] -bxor 1;[IO.File]::WriteAllBytes($damaged,$data)
    $rejected=$false;try{Unprotect-BackupArchive $damaged (Join-Path $workspace 'bad.zip') $recovery}catch{$rejected=$true}
    if(!$rejected -or (Test-Path (Join-Path $workspace 'bad.zip'))) { throw 'Corrupted archive accepted or decrypted.' }
    $wrong=Join-Path $workspace 'wrong.key';$bytes[63]=$bytes[63] -bxor 1;[IO.File]::WriteAllBytes($wrong,$bytes)
    $rejected=$false;try{Unprotect-BackupArchive $archive (Join-Path $workspace 'wrong.zip') $wrong}catch{$rejected=$true}
    if(!$rejected) { throw 'Wrong recovery key accepted.' }
    $rejected=$false;try{Assert-BackupChild $root (Join-Path $root '..\elsewhere') | Out-Null}catch{$rejected=$true}
    if(!$rejected) { throw 'Unsafe cleanup path accepted.' }
    # Successful repeated runs prune only recognized expired archives.
    $expired=Join-Path $root ('santiye-20000101-000000-'+[guid]::NewGuid().ToString('N')+'.enc')
    Copy-Item -LiteralPath $archive -Destination $expired; (Get-Item -LiteralPath $expired).LastWriteTimeUtc=[DateTime]::UtcNow.AddDays(-20)
    $keep=Join-Path $root 'unrelated.enc';[IO.File]::WriteAllText($keep,'fixture');(Get-Item $keep).LastWriteTimeUtc=[DateTime]::UtcNow.AddDays(-20)
    & (Join-Path (Split-Path $PSScriptRoot -Parent) 'run-backup.ps1') -ConfigPath $configPath
    if((Test-Path $expired) -or !(Test-Path $keep)) { throw 'Retention removed an unrelated file or kept an expired archive.' }
    $sourceRows=Invoke-BackupPg $PostgresBin 'psql' ($argsBase+@("--dbname=$name",'--no-psqlrc','-At','--command=SELECT count(*) FROM fixture;'))
    if(($sourceRows -join '').Trim() -ne '2') { throw 'Source database changed.' }
    # A public migration table alone must not let an incomplete application DB pass.
    [IO.File]::WriteAllText($schemaSql,'DROP TABLE santiye."Deals";')
    $null=Invoke-BackupPg $PostgresBin 'psql' ($argsBase+@("--dbname=$name",'--set=ON_ERROR_STOP=1',"--file=$schemaSql"))
    $incomplete=Join-Path $workspace 'incomplete.backup'
    $null=Invoke-BackupPg $PostgresBin 'pg_dump' ($argsBase+@('--format=custom',"--file=$incomplete",$name))
    $rejected=$false;try{Test-BackupRestore $PostgresBin $connection $incomplete | Out-Null}catch{$rejected=$true}
    if(!$rejected) { throw 'Missing application table accepted.' }
    if(Get-ChildItem -LiteralPath $root -Directory | Select-Object -First 1) { throw 'Private working files left behind.' }
    Write-Output ('PASS: real dump/encrypted restore, binary photo contents, tamper/wrong-key rejection, path bounds, retention, repeated run, unchanged source and cleanup. PowerShell '+$PSVersionTable.PSVersion)
} finally {
    if($created) { $null=Invoke-BackupPg $PostgresBin 'dropdb' ($argsBase+@('--maintenance-db=postgres','--force',$name)) }
    $env:PGPASSFILE=$previous
    # Keep only encrypted output/status for local inspection; clear private fixture files.
    $safe=Assert-BackupChild (Join-Path $repo 'tmp') $workspace
    Remove-Item -LiteralPath $safe -Recurse -Force
}

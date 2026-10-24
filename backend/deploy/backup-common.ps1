# Shared by scheduled backup and the restore verifier. Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
function Assert-BackupChild([string]$Root, [string]$Path) {
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    if (!$full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup path is outside its workspace.' }
    return $full
}
function Protect-BackupDirectory([string]$Path) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Cannot restrict backup directory permissions.' }
}
function Write-BackupJson([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
}
function Read-BackupConnection([string]$SettingsPath) {
    Add-Type -AssemblyName System.Data
    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    $builder = New-Object System.Data.Common.DbConnectionStringBuilder
    $builder.set_ConnectionString([string]$settings.ConnectionStrings.Postgres)
    $hostName = '127.0.0.1'; $port = 5432; $database = ''; $userName = ''; $password = ''
    foreach ($key in $builder.get_Keys()) {
        switch -Regex ($key) {
            '^(Host|Server)$' { $hostName = [string]$builder[$key] }
            '^Port$' { $port = [int]$builder[$key] }
            '^(Database|Initial Catalog)$' { $database = [string]$builder[$key] }
            '^(Username|User ID|UserId|User Name)$' { $userName = [string]$builder[$key] }
            '^Password$' { $password = [string]$builder[$key] }
        }
    }
    if ($hostName -notin @('127.0.0.1', 'localhost') -or $database -notmatch '^[A-Za-z0-9_]+$' -or !$userName -or !$password -or $port -lt 1 -or $port -gt 65535) {
        throw 'Expected a password-protected localhost PostgreSQL connection in settings.json.'
    }
    return @{ Host=$hostName; Port=$port; Database=$database; User=$userName; Password=$password; Settings=$settings }
}
function Invoke-BackupPg([string]$Bin, [string]$Tool, [string[]]$Arguments) {
    $exe = Join-Path $Bin ($Tool + '.exe')
    if (!(Test-Path -LiteralPath $exe)) { throw ('PostgreSQL tool missing: ' + $Tool) }
    # Do not surface raw native errors: SQL and settings paths may contain private data.
    $previousPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $result = & $exe @Arguments 2>&1
        $exitCode=$LASTEXITCODE
    } finally { $ErrorActionPreference=$previousPreference }
    if ($exitCode -ne 0) { throw ('PostgreSQL operation failed: ' + $Tool + '. Check database access and tool version.') }
    return $result
}
function New-BackupPgPass($Connection, [string]$Path) {
    $escaped = @($Connection.Host, [string]$Connection.Port, '*', $Connection.User, $Connection.Password) | ForEach-Object { $_.Replace('\','\\').Replace(':','\:') }
    [IO.File]::WriteAllText($Path, (($escaped -join ':') + "`n"), (New-Object Text.UTF8Encoding($false)))
}
function Get-BackupMac([string]$Path, [byte[]]$Key, [long]$Length) {
    $mac = New-Object Security.Cryptography.HMACSHA256
    $mac.Key = $Key
    $stream = [IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] 65536
        $remaining = $Length
        while ($remaining -gt 0) {
            $count = $stream.Read($buffer, 0, [int][Math]::Min($remaining, $buffer.Length))
            if ($count -le 0) { throw 'Truncated encrypted backup.' }
            $null = $mac.TransformBlock($buffer, 0, $count, $buffer, 0)
            $remaining -= $count
        }
        $null = $mac.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        return ,$mac.Hash
    } finally { $stream.Dispose(); $mac.Dispose() }
}
function Protect-BackupArchive([string]$InputPath, [string]$OutputPath, [string]$KeyPath) {
    $key = [IO.File]::ReadAllBytes($KeyPath)
    if ($key.Length -ne 64) { throw 'Invalid backup recovery key.' }
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.Key = [byte[]]$key[0..31]; $aes.GenerateIV()
    $inputStream = [IO.File]::OpenRead($InputPath)
    $outputStream = [IO.File]::Create($OutputPath)
    try {
        $header = [Text.Encoding]::ASCII.GetBytes('SANTIYE-BACKUP01')
        $outputStream.Write($header, 0, $header.Length)
        $outputStream.Write($aes.IV, 0, 16)
        $crypto = New-Object Security.Cryptography.CryptoStream($outputStream, $aes.CreateEncryptor(), [Security.Cryptography.CryptoStreamMode]::Write)
        try { $inputStream.CopyTo($crypto); $crypto.FlushFinalBlock() } finally { $crypto.Dispose() }
    } finally { $inputStream.Dispose(); $outputStream.Dispose(); $aes.Dispose() }
    $length = (Get-Item -LiteralPath $OutputPath).Length
    $tag = Get-BackupMac $OutputPath ([byte[]]$key[32..63]) $length
    $stream = [IO.File]::Open($OutputPath, [IO.FileMode]::Append)
    try { $stream.Write($tag, 0, $tag.Length) } finally { $stream.Dispose(); [Array]::Clear($key,0,$key.Length) }
}
function Unprotect-BackupArchive([string]$InputPath, [string]$OutputPath, [string]$KeyPath) {
    $key = [IO.File]::ReadAllBytes($KeyPath)
    $length = (Get-Item -LiteralPath $InputPath).Length
    if ($key.Length -ne 64 -or $length -lt 80) { throw 'Invalid encrypted backup or recovery key.' }
    $tag = Get-BackupMac $InputPath ([byte[]]$key[32..63]) ($length-32)
    $inputStream = [IO.File]::OpenRead($InputPath)
    try {
        $inputStream.Position = $length-32
        $expected = New-Object byte[] 32
        if ($inputStream.Read($expected,0,32) -ne 32) { throw 'Truncated authentication tag.' }
        $difference = 0
        for ($i=0;$i -lt 32;$i++) { $difference = $difference -bor ($tag[$i] -bxor $expected[$i]) }
        if ($difference -ne 0) { throw 'Backup authentication failed. Wrong key or damaged archive.' }
        $inputStream.Position=0
        $header=New-Object byte[] 16; $null=$inputStream.Read($header,0,16)
        if ([Text.Encoding]::ASCII.GetString($header) -cne 'SANTIYE-BACKUP01') { throw 'Unknown backup format.' }
        $iv=New-Object byte[] 16; $null=$inputStream.Read($iv,0,16)
        $aes=[Security.Cryptography.Aes]::Create(); $aes.Key=[byte[]]$key[0..31]; $aes.IV=$iv
        $outputStream=[IO.File]::Create($OutputPath)
        try {
            $crypto=New-Object Security.Cryptography.CryptoStream($outputStream,$aes.CreateDecryptor(),[Security.Cryptography.CryptoStreamMode]::Write)
            try {
                $remaining=$length-64; $buffer=New-Object byte[] 65536
                while ($remaining -gt 0) {
                    $count=$inputStream.Read($buffer,0,[int][Math]::Min($remaining,$buffer.Length))
                    if ($count -le 0) { throw 'Truncated encrypted data.' }
                    $crypto.Write($buffer,0,$count); $remaining-=$count
                }
                $crypto.FlushFinalBlock()
            } finally { $crypto.Dispose() }
        } finally { $outputStream.Dispose(); $aes.Dispose() }
    } finally { $inputStream.Dispose(); [Array]::Clear($key,0,$key.Length) }
}
function Test-BackupRestore([string]$Bin, $Connection, [string]$DumpPath) {
    # Always CREATE a new database ourselves; never restore over any existing DB.
    $name='santiye_test_'+[guid]::NewGuid().ToString('N')
    $argsBase=@("--host=$($Connection.Host)", "--port=$($Connection.Port)", "--username=$($Connection.User)", '--no-password')
    $created=$false
    try {
        $null=Invoke-BackupPg $Bin 'createdb' ($argsBase+@('--maintenance-db=postgres','--template=template0',$name)); $created=$true
        $null=Invoke-BackupPg $Bin 'pg_restore' ($argsBase+@("--dbname=$name",'--exit-on-error','--no-owner','--no-privileges',$DumpPath))
        $tables=Invoke-BackupPg $Bin 'psql' ($argsBase+@("--dbname=$name",'--no-psqlrc','--tuples-only','--no-align','--set=ON_ERROR_STOP=1','--command=SELECT count(*) FROM information_schema.tables WHERE table_schema NOT IN (''pg_catalog'',''information_schema'') AND table_schema NOT LIKE ''pg_toast%'' AND table_schema NOT LIKE ''pg_temp%'' AND table_type=''BASE TABLE'';'))
        $count=[int](($tables -join '').Trim())
        $critical=Invoke-BackupPg $Bin 'psql' ($argsBase+@("--dbname=$name",'--no-psqlrc','--tuples-only','--no-align','--set=ON_ERROR_STOP=1','--command=SELECT count(*) FROM information_schema.tables WHERE table_schema=''santiye'' AND table_name IN (''Users'',''Listings'',''Deals'',''PortfolioPhotos'') AND table_type=''BASE TABLE'';'))
        if ([int](($critical -join '').Trim()) -ne 4) { throw 'Restored database is missing critical Santiye application tables.' }
        $null=Invoke-BackupPg $Bin 'psql' ($argsBase+@("--dbname=$name",'--no-psqlrc','--tuples-only','--no-align','--set=ON_ERROR_STOP=1','--command=SELECT query_to_xml(format(''SELECT count(*) FROM %I.%I'',table_schema,table_name),false,true,'''') FROM information_schema.tables WHERE table_schema=''santiye'' AND table_name IN (''Users'',''Listings'',''Deals'',''PortfolioPhotos'');'))
        return @{ database=$name; tables=$count; critical_application_tables=4; passed=$true }
    } finally {
        if ($created) {
            if ($name -cnotmatch '^santiye_test_[0-9a-f]{32}$') { throw 'Unsafe restore database name.' }
            $null=Invoke-BackupPg $Bin 'dropdb' ($argsBase+@('--maintenance-db=postgres','--force',$name))
        }
    }
}

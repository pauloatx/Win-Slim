#requires -Version 5.1

function Get-WinSlimRestorationRelativePath {
    param([string]$Root,[string]$Path)
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    $full=[IO.Path]::GetFullPath($Path)
    if(-not $full.StartsWith($rootPath,[StringComparison]::OrdinalIgnoreCase)){throw 'Restoration path outside root.'}
    return $full.Substring($rootPath.Length).Replace('\','/')
}

function Get-WinSlimRestorationHash {
    param([string]$Path)
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Restoration file is unavailable.'}
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $hasher=[Security.Cryptography.SHA256]::Create()
    try{$bytes=$hasher.ComputeHash($stream)}finally{$hasher.Dispose();$stream.Dispose()}
    return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
}

function Get-WinSlimRestorationBaseline {
    param([string]$Root,[string]$BaselinePath)
    $relative=Get-WinSlimRestorationRelativePath -Root $Root -Path $BaselinePath
    if($relative -ne 'specs/FASE7-R3.2.84-baseline.json'){throw 'Unexpected restoration baseline.'}
    $baseline=Get-Content -LiteralPath $BaselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $fields=@($baseline.PSObject.Properties | Where-Object {$_.Name -match '\Ar[0-9]+Files\z'})
    if($fields.Count -ne 1){throw 'Restoration baseline hash list is missing or ambiguous.'}
    $files=@{}
    foreach($property in $fields[0].Value.PSObject.Properties){$files[[string]$property.Name]=([string]$property.Value).ToLowerInvariant()}
    return $files
}

function Test-WinSlimRestorationHash {
    param([string]$Path,[string]$Expected)
    if($Expected -notmatch '\A[0-9a-f]{64}\z'){throw 'Invalid restoration hash.'}
    return ((Get-WinSlimRestorationHash -Path $Path) -ceq $Expected)
}

function Write-WinSlimRestorationBlob {
    param([string]$Source,[string]$SnapshotDirectory,[string]$ExpectedSHA256)
    $bytes=[IO.File]::ReadAllBytes($Source)
    $memory=New-Object IO.MemoryStream
    $gzip=New-Object IO.Compression.GZipStream($memory,[IO.Compression.CompressionMode]::Compress,$true)
    try{$gzip.Write($bytes,0,$bytes.Length)}finally{$gzip.Dispose()}
    $encoded=[Convert]::ToBase64String($memory.ToArray())
    $memory.Dispose()
    $blobRelative='blobs/'+$ExpectedSHA256+'.json'
    $blobPath=Join-Path $SnapshotDirectory $blobRelative
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $blobPath))
    $blob=[ordered]@{schemaVersion=1;encoding='gzip-base64';sha256=$ExpectedSHA256;content=$encoded}
    [IO.File]::WriteAllText($blobPath,($blob|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
    return $blobRelative
}

function Read-WinSlimRestorationBlob {
    param([string]$BlobPath,[string]$ExpectedSHA256)
    $blob=Get-Content -LiteralPath $BlobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($blob.schemaVersion -ne 1 -or $blob.encoding -cne 'gzip-base64' -or ([string]$blob.sha256).ToLowerInvariant() -cne $ExpectedSHA256){throw 'Restoration blob metadata is invalid.'}
    $compressed=[Convert]::FromBase64String([string]$blob.content)
    $input=New-Object IO.MemoryStream(,$compressed)
    $output=New-Object IO.MemoryStream
    $gzip=New-Object IO.Compression.GZipStream($input,[IO.Compression.CompressionMode]::Decompress)
    try{$gzip.CopyTo($output)}finally{$gzip.Dispose();$input.Dispose()}
    $bytes=$output.ToArray();$output.Dispose()
    $hasher=[Security.Cryptography.SHA256]::Create()
    try{$actual=([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$hasher.Dispose()}
    if($actual -cne $ExpectedSHA256){throw 'Restoration blob content failed integrity check.'}
    return $bytes
}

function New-WinSlimNativeRestorationSnapshot {
    [CmdletBinding()]
    param([string]$Root,[string]$BaselinePath,[string]$SnapshotDirectory)
    if([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($BaselinePath) -or [string]::IsNullOrWhiteSpace($SnapshotDirectory)){throw 'Restoration parameters are incomplete.'}
    $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    $snapshotPath=[IO.Path]::GetFullPath($SnapshotDirectory)
    $logsPath=[IO.Path]::GetFullPath((Join-Path $Root 'logs')).TrimEnd('\')+'\'
    if(-not $snapshotPath.StartsWith($logsPath,[StringComparison]::OrdinalIgnoreCase)){throw 'Snapshot directory must be inside logs.'}
    if(Test-Path -LiteralPath $snapshotPath){throw 'Snapshot directory already exists.'}
    $baseline=Get-WinSlimRestorationBaseline -Root $Root -BaselinePath $BaselinePath
    $exe='bin/WinSlim.UI.Native.R3.2.84.exe'
    $config='bin/WinSlim.UI.Native.R3.2.84.exe.config'
    $cache='logs/build-inputs-r3.2.84.json'
    foreach($relative in @($exe,$config)){if(-not $baseline.ContainsKey($relative)){throw 'Restoration baseline output is missing.'}}
    foreach($relative in @($exe,$config,$cache)){
        $source=Join-Path $Root $relative
        if(-not (Test-Path -LiteralPath $source -PathType Leaf)){throw ('Restoration source is unavailable: '+$relative)}
    }
    foreach($relative in @($exe,$config)){
        if(-not (Test-WinSlimRestorationHash -Path (Join-Path $Root $relative) -Expected $baseline[$relative])){throw ('Delivered output does not match baseline: '+$relative)}
    }
    $cacheData=Get-Content -LiteralPath (Join-Path $Root $cache) -Raw -Encoding UTF8 | ConvertFrom-Json
    if($cacheData.schemaVersion -ne 1 -or [string]$cacheData.exeHash -ine $baseline[$exe] -or [string]$cacheData.configHash -ine $baseline[$config]){throw 'Delivered build cache does not match baseline outputs.'}
    $expected=@{ $exe=$baseline[$exe]; $config=$baseline[$config]; $cache=(Get-WinSlimRestorationHash -Path (Join-Path $Root $cache)) }
    [void][IO.Directory]::CreateDirectory($snapshotPath)
    $blobs=@{}
    foreach($relative in $expected.Keys){
        $blobs[$relative]=Write-WinSlimRestorationBlob -Source (Join-Path $Root $relative) -SnapshotDirectory $snapshotPath -ExpectedSHA256 $expected[$relative]
    }
    $receipt=[ordered]@{schemaVersion=1;createdUtc=[DateTime]::UtcNow.ToString('o');baselineSHA256=(Get-WinSlimRestorationHash -Path $BaselinePath);files=[ordered]@{}}
    foreach($relative in ($expected.Keys|Sort-Object)){$receipt.files[$relative]=[ordered]@{sha256=$expected[$relative];blob=$blobs[$relative]}}
    $receiptPath=Join-Path $snapshotPath 'restoration-snapshot.json'
    [IO.File]::WriteAllText($receiptPath,($receipt|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
    return [pscustomobject]@{SnapshotDirectory=$snapshotPath;ReceiptPath=$receiptPath;ReceiptSHA256=(Get-WinSlimRestorationHash -Path $receiptPath);ExpectedFiles=$expected;BlobFiles=$blobs}
}


function Restore-WinSlimNativeRestorationSnapshot {
    [CmdletBinding()]
    param([string]$Root,[string]$BaselinePath,[string]$SnapshotDirectory,[string]$ReceiptPath,[string]$ExpectedReceiptSHA256)
    if([string]::IsNullOrWhiteSpace($ExpectedReceiptSHA256) -or $ExpectedReceiptSHA256 -notmatch '\A[0-9a-fA-F]{64}\z'){throw 'Expected restoration receipt hash is invalid.'}
    $snapshotPath=[IO.Path]::GetFullPath($SnapshotDirectory)
    $logsPath=[IO.Path]::GetFullPath((Join-Path $Root 'logs')).TrimEnd('\')+'\'
    if(-not $snapshotPath.StartsWith($logsPath,[StringComparison]::OrdinalIgnoreCase)){throw 'Snapshot directory must be inside logs.'}
    $receiptFull=[IO.Path]::GetFullPath($ReceiptPath)
    if(-not $receiptFull.StartsWith($snapshotPath.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Receipt must be inside snapshot directory.'}
    if(-not (Test-Path -LiteralPath $receiptFull -PathType Leaf)){throw 'Restoration receipt is unavailable.'}
    if(-not (Test-WinSlimRestorationHash -Path $receiptFull -Expected $ExpectedReceiptSHA256)){throw 'Restoration receipt integrity check failed.'}
    $receipt=Get-Content -LiteralPath $receiptFull -Raw -Encoding UTF8 | ConvertFrom-Json
    if($receipt.schemaVersion -ne 1 -or $null -eq $receipt.files){throw 'Restoration receipt is invalid.'}
    $baseline=Get-WinSlimRestorationBaseline -Root $Root -BaselinePath $BaselinePath
    if((Get-WinSlimRestorationHash -Path $BaselinePath) -cne ([string]$receipt.baselineSHA256).ToLowerInvariant()){throw 'Restoration baseline changed after snapshot.'}
    $allowed=@('bin/WinSlim.UI.Native.R3.2.84.exe','bin/WinSlim.UI.Native.R3.2.84.exe.config','logs/build-inputs-r3.2.84.json')
    $snapshotFiles=@{}
    $snapshotBlobs=@{}
    foreach($property in $receipt.files.PSObject.Properties){
        $relative=[string]$property.Name
        if($allowed -notcontains $relative){throw ('Unexpected restoration file: '+$relative)}
        $expected=([string]$property.Value.sha256).ToLowerInvariant()
        $blobRelative=[string]$property.Value.blob
        if($blobRelative -notmatch '\Ablobs/[0-9a-f]{64}\.json\z'){throw ('Invalid restoration blob path: '+$relative)}
        $blobPath=Join-Path $snapshotPath $blobRelative
        if(-not (Test-Path -LiteralPath $blobPath -PathType Leaf)){throw ('Snapshot evidence is unavailable: '+$relative)}
        $bytes=Read-WinSlimRestorationBlob -BlobPath $blobPath -ExpectedSHA256 $expected
        $snapshotFiles[$relative]=$expected
        $snapshotBlobs[$relative]=$bytes
    }
    foreach($relative in $allowed){if(-not $snapshotFiles.ContainsKey($relative)){throw ('Snapshot evidence is incomplete: '+$relative)}}
    foreach($relative in @('bin/WinSlim.UI.Native.R3.2.84.exe','bin/WinSlim.UI.Native.R3.2.84.exe.config')){
        if($baseline[$relative] -cne $snapshotFiles[$relative]){throw ('Snapshot output does not match baseline: '+$relative)}
    }
    $validation=[ordered]@{}
    foreach($relative in @('bin/WinSlim.UI.Native.R3.2.84.exe','bin/WinSlim.UI.Native.R3.2.84.exe.config')){
        $current=Join-Path $Root $relative
        $validation[$relative]=if(Test-Path -LiteralPath $current -PathType Leaf){(Get-WinSlimRestorationHash -Path $current)}else{$null}
    }
    $staged=@{};$backups=@{};$replaced=New-Object System.Collections.ArrayList
    try{
        foreach($relative in $allowed){
            $target=Join-Path $Root $relative
            $temporary=$target+'.winslim-restore-'+[Guid]::NewGuid().ToString('N')
            [IO.File]::WriteAllBytes($temporary,$snapshotBlobs[$relative])
            if(-not (Test-WinSlimRestorationHash -Path $temporary -Expected $snapshotFiles[$relative])){throw ('Restore staging failed integrity check: '+$relative)}
            $staged[$relative]=$temporary
        }
        try{
            foreach($relative in $allowed){
                $target=Join-Path $Root $relative
                $temporary=$staged[$relative]
                $backup=$target+'.winslim-restore-backup-'+[Guid]::NewGuid().ToString('N')
                if(Test-Path -LiteralPath $target){[IO.File]::Replace($temporary,$target,$backup);$backups[$relative]=$backup}else{[IO.File]::Move($temporary,$target);$backups[$relative]=$null}
                [void]$replaced.Add($relative)
                if(-not (Test-WinSlimRestorationHash -Path $target -Expected $snapshotFiles[$relative])){throw ('Restored file failed integrity check: '+$relative)}
            }
        }catch{
            $restoreFailure=$_.Exception
            try{
                $rollbackItems=@($replaced.ToArray())
                [array]::Reverse($rollbackItems)
                foreach($relative in $rollbackItems){
                    $target=Join-Path $Root $relative
                    $backup=$backups[$relative]
                    if($null -ne $backup -and (Test-Path -LiteralPath $backup -PathType Leaf)){
                        $rollback=$target+'.winslim-restore-rollback-'+[Guid]::NewGuid().ToString('N')
                        $discard=$target+'.winslim-restore-discard-'+[Guid]::NewGuid().ToString('N')
                        try{Copy-Item -LiteralPath $backup -Destination $rollback -Force;[IO.File]::Replace($rollback,$target,$discard)}finally{if(Test-Path -LiteralPath $rollback){Remove-Item -LiteralPath $rollback -Force};if(Test-Path -LiteralPath $discard){Remove-Item -LiteralPath $discard -Force}}
                    }elseif($null -eq $backup -and (Test-Path -LiteralPath $target)){Remove-Item -LiteralPath $target -Force}
                }
            }catch{throw ('Restoration failed and rollback failed: '+$restoreFailure.Message+' | '+$_.Exception.Message)}
            throw $restoreFailure
        }
    }finally{
        foreach($temporary in $staged.Values){if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
        foreach($backup in $backups.Values){if($null -ne $backup -and (Test-Path -LiteralPath $backup)){Remove-Item -LiteralPath $backup -Force}}
    }
    return [pscustomobject]@{Passed=$true;RestoredSHA256=$snapshotFiles;ValidationBuildSHA256=$validation;ReceiptSHA256=(Get-WinSlimRestorationHash -Path $receiptFull)}
}

function Invoke-WinSlimNativeBuildRestoration {
    [CmdletBinding()]
    param([string]$Root,[string]$BaselinePath,[string]$SnapshotDirectory,[string]$ReceiptPath,[scriptblock]$Operation)
    if($null -eq $Operation){throw 'Restoration operation is missing.'}
    $snapshot=New-WinSlimNativeRestorationSnapshot -Root $Root -BaselinePath $BaselinePath -SnapshotDirectory $SnapshotDirectory
    $operationError=$null
    try{& $Operation $Root | Out-Null}catch{$operationError=$_.Exception}
    try{
        $restore=Restore-WinSlimNativeRestorationSnapshot -Root $Root -BaselinePath $BaselinePath -SnapshotDirectory $snapshot.SnapshotDirectory -ReceiptPath $snapshot.ReceiptPath -ExpectedReceiptSHA256 $snapshot.ReceiptSHA256
        if(-not [string]::IsNullOrWhiteSpace($ReceiptPath)){
            $receipt=[ordered]@{schemaVersion=1;utc=[DateTime]::UtcNow.ToString('o');passed=$true;snapshotReceiptSHA256=$snapshot.ReceiptSHA256;restored=$restore.RestoredSHA256;validationBuild=$restore.ValidationBuildSHA256}
            [IO.File]::WriteAllText($ReceiptPath,($receipt|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
        }
    }catch{if($null -ne $operationError){throw $operationError};throw}
    if($null -ne $operationError){throw $operationError}
    return $snapshot
}

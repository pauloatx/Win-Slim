#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools/validation/NativeBuildRestoration.ps1')

$fixture=Join-Path $Root ('logs/native-restoration-fixture-'+[Guid]::NewGuid().ToString('N'))
$checks=0
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};$script:checks++;Write-Host ('[OK] '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-Bytes([string]$Path,[string]$Value){[IO.File]::WriteAllText($Path,$Value,(New-Object Text.UTF8Encoding($false)))}

try {
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'bin'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'logs'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'specs'))
    $exe='bin/WinSlim.UI.Native.R3.2.84.exe'
    $config=$exe+'.config'
    $cache='logs/build-inputs-r3.2.84.json'
    Write-Bytes (Join-Path $fixture $exe) 'accepted executable bytes'
    Write-Bytes (Join-Path $fixture $config) 'accepted configuration bytes'
    $acceptedExeHash=Hash (Join-Path $fixture $exe)
    $acceptedConfigHash=Hash (Join-Path $fixture $config)
    $cacheData=[ordered]@{schemaVersion=1;inputs=('a'*64);exeHash=$acceptedExeHash.ToUpperInvariant();configHash=$acceptedConfigHash.ToUpperInvariant()}
    [IO.File]::WriteAllText((Join-Path $fixture $cache),($cacheData|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
    $acceptedCacheHash=Hash (Join-Path $fixture $cache)
    $baseline=[ordered]@{revision='FASE7-R3.2.84';r3284Files=[ordered]@{}}
    $baseline.r3284Files[$exe]=$acceptedExeHash
    $baseline.r3284Files[$config]=$acceptedConfigHash
    [IO.File]::WriteAllText((Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json'),($baseline|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
    Write-Bytes (Join-Path $fixture 'specs/unrelated.txt') 'unchanged baseline entry'

    $snapshotRoot=Join-Path $fixture 'logs/snapshot'
    $snapshot=New-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory $snapshotRoot
    Check (Test-Path -LiteralPath $snapshot.ReceiptPath) 'snapshot receipt created'
    Check ($snapshot.ExpectedFiles.Count -eq 3) 'snapshot contains executable, configuration and build cache'

    Write-Bytes (Join-Path $fixture $exe) 'validation executable bytes'
    Write-Bytes (Join-Path $fixture $config) 'validation configuration bytes'
    Write-Bytes (Join-Path $fixture $cache) '{"schemaVersion":1,"inputs":"validation"}'
    $restore=Restore-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory $snapshotRoot -ReceiptPath $snapshot.ReceiptPath -ExpectedReceiptSHA256 $snapshot.ReceiptSHA256
    Check ($restore.Passed -and $restore.ValidationBuildSHA256.Count -eq 2) 'restore records validation build identities'
    Check ((Hash (Join-Path $fixture $exe)) -eq $acceptedExeHash) 'accepted executable restored byte for byte'
    Check ((Hash (Join-Path $fixture $config)) -eq $acceptedConfigHash) 'accepted configuration restored byte for byte'
    Check ((Hash (Join-Path $fixture $cache)) -eq $acceptedCacheHash) 'accepted build cache restored byte for byte'
    Check ((Get-Content -LiteralPath (Join-Path $fixture 'specs/unrelated.txt') -Raw) -eq 'unchanged baseline entry') 'unrelated baseline entry preserved'

    $operation='validation operation failed'
    $threw=$false
    try {
        Invoke-WinSlimNativeBuildRestoration -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory (Join-Path $fixture 'logs/failed-operation') -ReceiptPath (Join-Path $fixture 'logs/failed-operation-receipt.json') -Operation {
            param($targetRoot)
            Write-Bytes (Join-Path $targetRoot 'bin/WinSlim.UI.Native.R3.2.84.exe') 'partial validation executable bytes'
            throw 'validation operation failed'
        }
    } catch {
        $threw=($_.Exception.Message -like ('*'+$operation+'*'))
    }
    Check $threw 'failed validation operation remains failed'
    Check ((Hash (Join-Path $fixture $exe)) -eq $acceptedExeHash) 'failed validation operation restores accepted executable'

    $rollbackSnapshot=New-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory (Join-Path $fixture 'logs/rollback')
    Write-Bytes (Join-Path $fixture $exe) 'rollback validation executable bytes'
    Write-Bytes (Join-Path $fixture $config) 'rollback validation configuration bytes'
    Write-Bytes (Join-Path $fixture $cache) '{"schemaVersion":1,"inputs":"rollback"}'
    $rollbackExeHash=Hash (Join-Path $fixture $exe)
    $rollbackConfigHash=Hash (Join-Path $fixture $config)
    $lock=[IO.File]::Open((Join-Path $fixture $config),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        Reject {Restore-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory $rollbackSnapshot.SnapshotDirectory -ReceiptPath $rollbackSnapshot.ReceiptPath -ExpectedReceiptSHA256 $rollbackSnapshot.ReceiptSHA256 | Out-Null} 'partial restore failure fails closed'
    } finally {$lock.Dispose()}
    Check ((Hash (Join-Path $fixture $exe)) -eq $rollbackExeHash) 'partial restore failure rolls executable back'
    Check ((Hash (Join-Path $fixture $config)) -eq $rollbackConfigHash) 'partial restore failure leaves locked configuration unchanged'
    Write-Bytes (Join-Path $fixture $exe) 'accepted executable bytes'
    Write-Bytes (Join-Path $fixture $config) 'accepted configuration bytes'
    [IO.File]::WriteAllText((Join-Path $fixture $cache),($cacheData|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))

    $tamperedSnapshot=New-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory (Join-Path $fixture 'logs/tampered')
    Write-Bytes (Join-Path $tamperedSnapshot.SnapshotDirectory $tamperedSnapshot.BlobFiles[$exe]) 'tampered evidence'
    $beforeRejected=@{}
    foreach($relative in $tamperedSnapshot.ExpectedFiles.Keys){$beforeRejected[$relative]=Hash (Join-Path $fixture $relative)}
    Reject {Restore-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory $tamperedSnapshot.SnapshotDirectory -ReceiptPath $tamperedSnapshot.ReceiptPath -ExpectedReceiptSHA256 $tamperedSnapshot.ReceiptSHA256 | Out-Null} 'tampered snapshot evidence fails closed'
    foreach($relative in $beforeRejected.Keys){Check ((Hash (Join-Path $fixture $relative)) -eq $beforeRejected[$relative]) "tampered evidence rejection leaves $relative unchanged"}

    $missingSnapshot=New-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory (Join-Path $fixture 'logs/missing')
    Remove-Item -LiteralPath (Join-Path $missingSnapshot.SnapshotDirectory $missingSnapshot.BlobFiles[$config])
    Reject {Restore-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory $missingSnapshot.SnapshotDirectory -ReceiptPath $missingSnapshot.ReceiptPath -ExpectedReceiptSHA256 $missingSnapshot.ReceiptSHA256 | Out-Null} 'missing snapshot evidence fails closed'

    $outsideRoot=Join-Path ([IO.Path]::GetTempPath()) ('winslim-outside-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($outsideRoot)
    try {
        Reject {New-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath (Join-Path $fixture 'specs/FASE7-R3.2.84-baseline.json') -SnapshotDirectory $outsideRoot | Out-Null} 'snapshot directory outside root fails closed'
    } finally {if(Test-Path -LiteralPath $outsideRoot){Remove-Item -LiteralPath $outsideRoot -Recurse -Force}}

    $badBaseline=Join-Path $fixture 'specs/bad-baseline.json'
    $bad=[ordered]@{revision='FASE7-R3.2.84';r3284Files=[ordered]@{$exe=('b'*64);$config=$acceptedConfigHash}}
    [IO.File]::WriteAllText($badBaseline,($bad|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
    $beforeBad=Hash (Join-Path $fixture $exe)
    Reject {New-WinSlimNativeRestorationSnapshot -Root $fixture -BaselinePath $badBaseline -SnapshotDirectory (Join-Path $fixture 'logs/bad-baseline') | Out-Null} 'baseline identity mismatch fails closed'
    Check ((Hash (Join-Path $fixture $exe)) -eq $beforeBad) 'baseline mismatch leaves executable unchanged'

    Write-Host ('NativeBuildRestoration: '+$checks+' behavioral checks passed.')
} finally {
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}


#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools/validation/NativeBuildIntegrity.ps1')
$fixture=Join-Path $Root ('logs/build-identity-fixture-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'bin'))
$checks=0
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};$script:checks++;Write-Host ('[OK] '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}
function Hash([string]$Name){(Get-FileHash -LiteralPath (Join-Path $fixture $Name) -Algorithm SHA256).Hash.ToLowerInvariant()}
$exe='bin/WinSlim.UI.Native.R3.2.84.exe';$config=$exe+'.config';$source='production.cs'
# Inert bytes: no fixture executable, compiler, collector or driver is run.
[IO.File]::WriteAllText((Join-Path $fixture $exe),'delivered binary identity')
[IO.File]::WriteAllText((Join-Path $fixture $config),'reviewed configuration')
[IO.File]::WriteAllText((Join-Path $fixture $source),'reviewed source')
$expected=@{$exe=(Hash $exe);$config=(Hash $config);$source=(Hash $source)}
$before=@(Get-WinSlimNativeIntegrityResults $fixture $expected BeforeBuild)
Check (@($before | Where-Object {-not $_.Passed}).Count -eq 0 -and $before.Count -eq 3) 'every delivered file matches before compilation'
$oldReceipt=[pscustomobject]@{schemaVersion=1;inputs=('a'*64);exeHash=(Hash $exe);configHash=(Hash $config)}
[IO.File]::WriteAllText((Join-Path $fixture $exe),'new official build identity')
Check (@(Get-WinSlimNativeIntegrityResults $fixture $expected BeforeBuild | Where-Object {-not $_.Passed}).Count -eq 1) 'historical identity cannot validate a newly built binary (original failure)'
$receipt=[pscustomobject]@{schemaVersion=1;inputs=('b'*64);exeHash=(Hash $exe);configHash=(Hash $config)}
$after=@(Get-WinSlimNativeIntegrityResults $fixture $expected AfterBuild $receipt)
Check (@($after | Where-Object {-not $_.Passed}).Count -eq 0 -and $after.Count -eq 3) 'fresh official receipt validates new output and unchanged source/configuration'
Check ($expected[$exe] -eq $before[0].ExpectedSHA256) 'delivered expected hash is never overwritten'
Check (@(Get-WinSlimNativeIntegrityResults $fixture $expected AfterBuild $oldReceipt | Where-Object {-not $_.Passed}).Count -eq 1) 'stale output receipt is rejected'
[IO.File]::WriteAllText((Join-Path $fixture $source),'unreviewed source')
Check (@(Get-WinSlimNativeIntegrityResults $fixture $expected AfterBuild $receipt | Where-Object {-not $_.Passed}).Count -eq 1) 'changed production input remains rejected after successful build'
[IO.File]::WriteAllText((Join-Path $fixture $source),'reviewed source')
[IO.File]::WriteAllText((Join-Path $fixture $exe),'changed after self-test')
Check (@(Get-WinSlimNativeIntegrityResults $fixture $expected AfterBuild $receipt | Where-Object {-not $_.Passed}).Count -eq 1) 'binary alteration after self-test is rejected'
Reject {Get-WinSlimNativeIntegrityResults $fixture $expected AfterBuild $null} 'missing receipt fails closed'
Reject {Get-WinSlimNativeIntegrityResults $fixture $expected AfterBuild ([pscustomobject]@{schemaVersion=1})} 'partial receipt fails closed'
Reject {Get-WinSlimNativeIntegrityResults $fixture @{} BeforeBuild} 'empty input set fails closed'
Reject {Get-WinSlimNativeIntegrityResults $fixture @{'../outside.txt'=('a'*64)} BeforeBuild} 'outside path is rejected without writing'
$missing=@{'missing.txt'=('a'*64)}
Check (-not (Get-WinSlimNativeIntegrityResults $fixture $missing BeforeBuild).Passed) 'unavailable input is an explicit failed result'
Check ((Hash $config) -eq $expected[$config] -and (Hash $source) -eq $expected[$source]) 'related input/configuration bytes preserved'
Write-Host ('NativeBuildIntegrity: '+$checks+' behavioral checks passed.')

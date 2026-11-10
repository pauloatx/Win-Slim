#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools/validation/WinSlimCaptureData.ps1')
Import-WinSlimCaptureDataTypes -Root $Root
$checks=0
function Check([bool]$Ok,[string]$Text){if(-not $Ok){throw $Text};$script:checks++;Write-Host ('[OK] '+$Text)}
function Reject([scriptblock]$Action,[string]$Text){$rejected=$false;try{& $Action | Out-Null}catch{$rejected=$true};Check $rejected $Text}
function Call($Object,[string]$Method,[object[]]$Arguments=@()){Invoke-WinSlimCaptureMember PresentMonMonitor $Method $Object $Arguments}
function Value($Object,[string]$Name){Get-WinSlimCaptureValue $Object $Name}
$dataRoot=Join-Path $script:CaptureBuild 'fixture'
[void][IO.Directory]::CreateDirectory($dataRoot)
# Construct the production data state only. StartCore/Run/StopAsync are never called in this fixture.
# The binary argument deliberately does not exist; no collector process can be launched.
$monitor=New-WinSlimCaptureObject PresentMonMonitor @($dataRoot,(Join-Path $dataRoot 'no-process.exe'),7301,'game.exe')
$header='Application,ProcessID,SwapChainAddress,MsBetweenPresents'
Call $monitor AcceptFrameLine @($header,[DateTime]::UtcNow) | Out-Null
Check ((Value $monitor State) -ceq 'Coletando amostras' -and $null -eq (Value $monitor Snapshot)) 'data state awaits sufficient frames with no invented metrics'
$session=Value $monitor Session
for($i=0;$i -lt 40;$i++){Call $monitor AcceptFrameLine @('game.exe,7301,0x1,10',[DateTime]::UtcNow) | Out-Null}
Check ($null -ne (Value $monitor Snapshot) -and -not (Test-Path (Join-Path $dataRoot 'Benchmarks'))) 'live metrics available without a benchmark or permanent CSV'
$cts=New-Object Threading.CancellationTokenSource
$pending=Call $monitor RecordAsync @(10,$cts.Token)
for($i=0;$i -lt 50;$i++){Call $monitor AcceptFrameLine @('game.exe,7301,0x1,10',[DateTime]::UtcNow) | Out-Null}
Reject {Wait-WinSlimCaptureTask (Call $monitor RecordAsync @(10,[Threading.CancellationToken]::None))} 'second concurrent recording rejected without changing selected session'
$cts.Cancel();Reject {Wait-WinSlimCaptureTask $pending} 'cancelled recording never yields a partial accepted result'
Check ((Value $monitor Running) -and (Value $monitor Session) -ceq $session -and $null -ne (Value $monitor Snapshot)) 'recording cancellation preserves monitor data and session identity'
$cts.Dispose()
foreach($duration in @(0,9,121)){Reject {Wait-WinSlimCaptureTask (Call $monitor RecordAsync @($duration,[Threading.CancellationToken]::None))} 'recording duration contract preserved'}
$record=Call $monitor RecordAsync @(10,[Threading.CancellationToken]::None)
for($i=0;$i -lt 100;$i++){Call $monitor AcceptFrameLine @('game.exe,7301,0x1,10',[DateTime]::UtcNow) | Out-Null}
Call $monitor AcceptFrameLine @('game.exe,7301,0x1,0',[DateTime]::UtcNow) | Out-Null
$result=Wait-WinSlimCaptureTask $record
Check ((Value $result Frames) -eq 100 -and (Value $result InvalidFrames) -eq 1 -and (Value $result RequestedSeconds) -eq 10 -and (Value $result Session) -ceq $session) 'completed fixture benchmark uses real production recorder, parser and invalid interval accounting'
$csv=Value $result CsvPath;$hash=(Get-FileHash $csv -Algorithm SHA256).Hash
$cts=New-Object Threading.CancellationTokenSource;$cts.Cancel()
Reject {Wait-WinSlimCaptureTask (Call $monitor RecordAsync @(10,$cts.Token))} 'pre-cancelled restart yields no replacement result'
Check ((Get-FileHash $csv -Algorithm SHA256).Hash -ceq $hash -and (Value $result Frames) -eq 100) 'previous completed result and reference-compatible data preserved after cancellation'
$cts.Dispose()
$pending=Call $monitor RecordAsync @(10,[Threading.CancellationToken]::None)
Call $monitor EndFrameStream @('data-unavailability fixture') | Out-Null
Reject {Wait-WinSlimCaptureTask $pending} 'stream loss fails a pending benchmark'
Check (-not (Value $monitor Running) -and $null -eq (Value $monitor Snapshot) -and (Value $monitor Error) -ceq 'data-unavailability fixture') 'ended/unavailable stream clears current live values and records reason'
$count=Value $monitor BufferedCount
Call $monitor AcceptFrameLine @('game.exe,7301,0x1,10',[DateTime]::UtcNow) | Out-Null
Check ((Value $monitor BufferedCount) -eq $count -and (Get-FileHash $csv -Algorithm SHA256).Hash -ceq $hash) 'late frames cannot revive ended stream or alter prior result'
Reject {Wait-WinSlimCaptureTask (Call $monitor RecordAsync @(10,[Threading.CancellationToken]::None))} 'ended stream cannot start another recording'
$stream=New-WinSlimCaptureObject PresentMonMonitor @($dataRoot,(Join-Path $dataRoot 'no-process.exe'),7301,'game.exe')
$text=$header+"`r`n"+(('game.exe,7301,0x1,10'+"`r`n")*10000)
$inputReader=New-Object IO.StringReader($text)
try{Wait-WinSlimCaptureTask (Call $stream ReadFrameStreamAsync @($inputReader)) | Out-Null}finally{$inputReader.Dispose()}
Check ((Value $stream BufferedCount) -eq 4096 -and $null -ne (Value $stream Snapshot)) 'production stdout reader drains chunked CSV larger than a pipe buffer with bounded samples'
foreach($invalid in @('unterminated',('x'*65537),($header+"`n"+'game.exe,7301,0x1'+"`n"))){
 $inputReader=New-Object IO.StringReader($invalid)
 try{Reject {Wait-WinSlimCaptureTask (Call $stream ReadFrameStreamAsync @($inputReader))} 'truncated, oversized or malformed frame stream rejected'}finally{$inputReader.Dispose()}
}
$errorReader=New-Object IO.StringReader(('e'*200000))
try{
 $errors=Wait-WinSlimCaptureTask (Invoke-WinSlimCaptureMember PresentMonMonitor ReadErrorStreamAsync $null @($errorReader))
 Check ($errors.Length -eq 4096 -and $errorReader.Peek() -eq -1) 'production stderr reader drains 200000 characters while bounding retained diagnostics'
}finally{$errorReader.Dispose()}
& (Join-Path $Root 'tests/Test-Fase7-R3.2.84-OverlaySensors.ps1') -Root $Root
Write-Host ('Monitor data: '+$checks+' checks; only in-memory CSV/state fixtures, no harness or process transport. '+$script:CaptureBuild)

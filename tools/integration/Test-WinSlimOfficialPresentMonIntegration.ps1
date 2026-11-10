#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][int]$ProcessId,[Parameter(Mandatory=$true)][string]$Application,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root);$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $OutputDirectory.StartsWith($Root.TrimEnd('\')+'\logs\',[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence must remain under workspace logs'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
. (Join-Path $Root 'tools/TestExecutionPolicy.ps1')
Assert-WinSlimTestExecutionAllowed -Family OfficialPresentMonIntegration
$binary=Join-Path $Root 'third_party/PresentMon/PresentMon-2.6.0-x64.exe'
$hash=(Get-FileHash $binary -Algorithm SHA256).Hash.ToLowerInvariant();$signature=Get-AuthenticodeSignature $binary
if($hash -cne 'b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af' -or $signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Intel Corporation(,|$)'){throw 'Official provider identity not verified'}
$target=Get-Process -Id $ProcessId -ErrorAction Stop
if(($target.ProcessName+'.exe') -ine $Application){throw 'Selected PID and application differ'}
[ordered]@{StartUtc=[DateTime]::UtcNow.ToString('o');Binary=$binary;SHA256=$hash;SignatureStatus=[string]$signature.Status;Signer=$signature.SignerCertificate.Subject;Pid=$ProcessId;Application=$Application;PhysicalGameAcceptance=$false;HarnessUsed=$false} | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'before-execution.json') -Encoding UTF8
. (Join-Path $Root 'tools/validation/WinSlimCaptureData.ps1')
Import-WinSlimCaptureDataTypes -Root $Root
$checks=New-Object Collections.ArrayList;$monitor=$null;$cts=$null
function Value($Object,[string]$Name){Get-WinSlimCaptureValue $Object $Name}
function Call($Object,[string]$Method,[object[]]$Arguments=@()){Invoke-WinSlimCaptureMember PresentMonMonitor $Method $Object $Arguments}
function Check([bool]$Ok,[string]$Text){if(-not $Ok){throw $Text};[void]$checks.Add($Text);Write-Host ('[OK] '+$Text)}
function Wait-Live($Object){
 $clock=[Diagnostics.Stopwatch]::StartNew()
 do{
  $snapshot=Value $Object Snapshot
  if($null -ne $snapshot){return $snapshot}
  if(-not (Value $Object Running)){throw ('Official stream ended: '+(Value $Object Error))}
  Start-Sleep -Milliseconds 100
 }while($clock.Elapsed.TotalSeconds -lt 12)
 throw 'No live samples within 12 seconds'
}
function Result-Record($Result){
 [ordered]@{Frames=(Value $Result Frames);InvalidFrames=(Value $Result InvalidFrames);Seconds=(Value $Result RequestedSeconds);Session=(Value $Result Session);CsvPath=(Value $Result CsvPath);CsvSHA256=(Get-FileHash (Value $Result CsvPath) -Algorithm SHA256).Hash;Fps=(Value $Result AverageFps);Mean=(Value $Result MeanFrameMs);Low=(Value $Result OnePercentLowFps);P99=(Value $Result P99FrameMs)}
}
try{
 $monitor=Wait-WinSlimCaptureTask (Invoke-WinSlimCaptureMember PresentMonMonitor StartAsync $null @($Root,$ProcessId,$Application))
 $session=Value $monitor Session;$snapshot=Wait-Live $monitor
 Check ((Value $snapshot Fps) -gt 0 -and (Value $snapshot Mean) -gt 0) 'official ETW stream produces live production metrics before benchmark'
 $first=Wait-WinSlimCaptureTask (Call $monitor RecordAsync @(10,[Threading.CancellationToken]::None))
 $firstRecord=Result-Record $first
 Check ($firstRecord.Frames -ge 30 -and $firstRecord.Session -ceq $session) 'ten-second benchmark records the existing official monitoring session'
 $cts=New-Object Threading.CancellationTokenSource
 $cancelled=Call $monitor RecordAsync @(10,$cts.Token)
 Start-Sleep -Milliseconds 600;$cts.Cancel();$cancelObserved=$false
 try{Wait-WinSlimCaptureTask $cancelled | Out-Null}catch [OperationCanceledException]{$cancelObserved=$true}
 Check $cancelObserved 'real shared-session benchmark cancellation yields no accepted partial result'
 $cts.Dispose();$cts=$null;$snapshot=Wait-Live $monitor
 Check ((Value $monitor Running) -and (Value $monitor Session) -ceq $session -and $null -ne $snapshot) 'cancellation preserves the selected live collector and metrics'
 $second=Wait-WinSlimCaptureTask (Call $monitor RecordAsync @(10,[Threading.CancellationToken]::None))
 $secondRecord=Result-Record $second
 $comparison=Invoke-WinSlimCaptureMember PresentMonBenchmark Compare $null @($first,$second)
 Check ($secondRecord.Frames -ge 30 -and -not [double]::IsNaN($comparison) -and -not [double]::IsInfinity($comparison)) 'capture after cancellation supplies a compatible comparison without restarting monitoring'
 Check ((Get-FileHash $firstRecord.CsvPath -Algorithm SHA256).Hash -ceq $firstRecord.CsvSHA256) 'previous capture remains byte-identical as comparison reference'
 Wait-WinSlimCaptureTask (Call $monitor StopAsync) | Out-Null
 Check (-not (Value $monitor Running) -and $null -eq (Value $monitor Snapshot)) 'owned official session stops and clears live snapshot'
 $monitor=$null
 $monitor=Wait-WinSlimCaptureTask (Invoke-WinSlimCaptureMember PresentMonMonitor StartAsync $null @($Root,$ProcessId,$Application))
 $snapshot=Wait-Live $monitor;$restartSession=Value $monitor Session
 Check ($restartSession -cne $session -and (Value $snapshot Fps) -gt 0) 'fresh official session restarts successfully after stop'
 Wait-WinSlimCaptureTask (Call $monitor StopAsync) | Out-Null;$monitor=$null
 $cts=New-Object Threading.CancellationTokenSource;$cts.CancelAfter(600)
 $oneShot=Invoke-WinSlimCaptureMember PresentMonBenchmark CaptureAsync $null @($Root,$ProcessId,$Application,10,$cts.Token,$null)
 $cancelObserved=$false
 try{Wait-WinSlimCaptureTask $oneShot | Out-Null}catch [OperationCanceledException]{$cancelObserved=$true}
 Check $cancelObserved 'one-shot public benchmark API cancels and disposes its owned official session'
 $cts.Dispose();$cts=$null
 [ordered]@{Success=$true;EndUtc=[DateTime]::UtcNow.ToString('o');SHA256=$hash;Version='2.6.0';Application=$Application;Pid=$ProcessId;PhysicalGameAcceptance=$false;HarnessUsed=$false;ProductionSourceLibrary=$script:CaptureBuild;Checks=@($checks);First=$firstRecord;Second=$secondRecord;ComparisonPercent=$comparison;RestartSession=$restartSession} | ConvertTo-Json -Depth 7 | Set-Content (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
}catch{
 [ordered]@{Success=$false;Utc=[DateTime]::UtcNow.ToString('o');Error=$_.Exception.ToString();PassedChecks=@($checks);HarnessUsed=$false} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'failure.json') -Encoding UTF8
 throw
}finally{
 if($cts){$cts.Dispose()}
 if($monitor){Wait-WinSlimCaptureTask (Call $monitor StopAsync) | Out-Null}
}

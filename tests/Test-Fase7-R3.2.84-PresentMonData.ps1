#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools/validation/WinSlimCaptureData.ps1')
Import-WinSlimCaptureDataTypes -Root $Root
$checks=0
function Check([bool]$Ok,[string]$Text){if(-not $Ok){throw $Text};$script:checks++;Write-Host ('[OK] '+$Text)}
function Reject([scriptblock]$Action,[string]$Text){$rejected=$false;try{& $Action | Out-Null}catch{$rejected=$true};Check $rejected $Text}
function Call([string]$Method,[object[]]$Values){Invoke-WinSlimCaptureMember PresentMonBenchmark $Method $null $Values}
function Value($Object,[string]$Name){Get-WinSlimCaptureValue $Object $Name}
$file=Join-Path $script:CaptureBuild 'data.csv'
$header='Application,ProcessID,SwapChainAddress,MsBetweenPresents'
$rows=@($header)+@(1..99 | ForEach-Object {'"Game, test.exe",42,0x1,10'})+@('"Game, test.exe",42,0x1,100','"Game, test.exe",42,0x1,0','"Game, test.exe",42,0x1,-1','"Game, test.exe",42,0x1,NaN','"Game, test.exe",42,0x1,Infinity')+@(1..200 | ForEach-Object {'other.exe,99,0x2,2'})
[IO.File]::WriteAllLines($file,[string[]]$rows)
$result=Call ReadCsv @($file,42)
Check ((Value $result Frames) -eq 100 -and (Value $result InvalidFrames) -eq 4 -and (Value $result Application) -ceq 'Game, test.exe') 'quoted CSV, invalid interval accounting and PID isolation'
Check ((Value (Call ReadCsv @($file,0)) ProcessId) -eq 99) 'dominant process selection never mixes processes'
Check ([Math]::Abs((Value $result MeanFrameMs)-10.9) -lt 1e-9 -and [Math]::Abs((Value $result AverageFps)-(1000/10.9)) -lt 1e-9 -and (Value $result P99FrameMs) -eq 10 -and (Value $result OnePercentLowFps) -eq 10) 'approved mean, nearest-rank P99 and slowest-one-percent definitions preserved'
Reject {Call CsvFields @('"unfinished')} 'CSV field parser rejects unmatched quotes'
Check ((Call CsvFields @('"a,""b""",42,0x1,10'))[0] -ceq 'a,"b"') 'quoted commas and escaped quotes parsed as data'
foreach($text in @('','Application,ProcessID,SwapChainAddress,WrongMs','Application,ProcessID,SwapChainAddress,MsBetweenPresents,ProcessID',($header+"`n"+'game.exe,42,0x1'),($header+"`n"+'"unclosed,42,0x1,10'),($header+"`n"+'game.exe,bad,0x1,10'))){[IO.File]::WriteAllText($file,$text);Reject {Call ReadCsv @($file,42)} 'missing/duplicate/malformed/truncated CSV fails without invented result'}
Reject {Call ReadCsv @((Join-Path $script:CaptureBuild 'absent.csv'),42)} 'absent input rejected'
$session='WinSlim-'+[Guid]::NewGuid().ToString('N')
$arguments=Call CaptureArguments @(42,30,$file,$session)
Check ($arguments -match '--process_id 42' -and $arguments -match [regex]::Escape($session) -and $arguments -notmatch '--stop_existing_session|--restart_as_admin') 'arguments bind explicit PID and unique owned session without global stop or autoelevation'
foreach($values in @(@(0,30,$file,$session),@(42,121,$file,$session),@(42,30,$file,'PresentMon'),@(42,30,'x" --process_id 1',$session))){Reject {Call CaptureArguments $values} 'invalid PID/duration/session/argument injection rejected'}
$missing=Join-Path $script:CaptureBuild 'missing-root'
Reject {Wait-WinSlimCaptureTask (Call CaptureAsync @($missing,42,'game.exe',10,[Threading.CancellationToken]::None,$null))} 'runtime rejects absent official provider'
$bad=Join-Path $missing 'third_party/PresentMon';[void][IO.Directory]::CreateDirectory($bad)
[IO.File]::WriteAllText((Join-Path $bad 'PresentMon-2.6.0-x64.exe'),'inert text, never executable')
Reject {Wait-WinSlimCaptureTask (Call CaptureAsync @($missing,42,'game.exe',10,[Threading.CancellationToken]::None,$null))} 'runtime rejects altered provider bytes before launch'
# No executable exists at this path: the pre-fix demonstration cannot launch any collector.
Reject {Invoke-WinSlimCaptureMember PresentMonMonitor StartCore $null @($script:CaptureBuild,(Join-Path $script:CaptureBuild 'not-a-provider.exe'),42,'game.exe')} 'internal entry rejects a nonofficial provider synchronously before starting a process task'
$live=New-WinSlimCaptureObject BenchmarkLiveReader @(42,'game.exe',$true)
$now=[DateTime]::UtcNow
Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $live @($header,$now) | Out-Null
$times=@(0..399 | ForEach-Object {if($_ -eq 123){120.0}elseif($_ -eq 399){90.0}else{10.0}})
foreach($time in $times){Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $live @(('game.exe,42,0x1,'+$time.ToString([Globalization.CultureInfo]::InvariantCulture)),$now) | Out-Null}
$snapshot=Invoke-WinSlimCaptureMember BenchmarkLiveReader Snapshot $live @($now)
$chart=Value $snapshot Times
Check ($chart.Count -le 360 -and ($chart | Measure-Object -Maximum).Maximum -eq 120 -and $chart[-1] -eq 90) 'off-stride and final-range frame-time peaks preserved'
[IO.File]::WriteAllLines($file,[string[]](@($header)+@($times | ForEach-Object {'game.exe,42,0x1,'+$_.ToString([Globalization.CultureInfo]::InvariantCulture)})))
$complete=Call ReadCsv @($file,42)
Check ((Value $complete Frames) -eq 400 -and (Value $complete P99FrameMs) -eq 10 -and [Math]::Abs((Value $complete OnePercentLowFps)-(1000/57.5)) -lt 1e-9 -and [Math]::Abs((Value $complete MeanFrameMs)-(Value $snapshot Mean)) -lt 1e-9) 'chart reduction does not alter full capture statistics'
Reject {Call Compare @($complete,$complete)} 'imported data with no matching capture duration is not a valid comparison'
foreach($name in @('RequestedSeconds','AverageFps')){
 $field=$complete.GetType().GetField($name,$script:CaptureFlags)
 $field.SetValue($complete,[Management.Automation.LanguagePrimitives]::ConvertTo($(if($name -eq 'RequestedSeconds'){10}else{100}),$field.FieldType))
}
Check ((Call Compare @($complete,$complete)) -eq 0) 'compatible data-only capture comparison preserves exact zero difference'
$complete.GetType().GetField('Cancelled',$script:CaptureFlags).SetValue($complete,$true)
Reject {Call Compare @($complete,$complete)} 'cancelled capture is not accepted as reference'
Reject {Call StopSession @((Join-Path $script:CaptureBuild 'absent-provider.exe'),'PresentMon')} 'foreign or global session rejected before any stop process'
Check ($null -eq (Invoke-WinSlimCaptureMember BenchmarkLiveReader Snapshot $live @($now.AddSeconds(3)))) 'stale live data is unavailable instead of zero or recycled sample'
Invoke-WinSlimCaptureMember BenchmarkLiveReader Snapshot $live @($now.AddSeconds(6)) | Out-Null
Check ((Value $live BufferedCount) -eq 0) 'five-second moving window evicts old data'
$bounded=New-WinSlimCaptureObject BenchmarkLiveReader @(42,'game.exe',$true)
Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $bounded @($header,$now) | Out-Null
for($i=0;$i -lt 5000;$i++){Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $bounded @('game.exe,42,0x1,10',$now) | Out-Null}
Check ((Value $bounded BufferedCount) -eq 4096) 'moving sample buffer is bounded without fake transport'
$sampleCount=Value $bounded BufferedCount
foreach($row in @('other.exe,42,0x1,10','game.exe,99,0x1,10','game.exe,42,0x1,NaN','game.exe,42,0x1,0')){Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $bounded @($row,$now) | Out-Null}
Check ((Value $bounded BufferedCount) -eq $sampleCount) 'foreign application, PID and invalid values preserve accepted samples'
$separate=New-WinSlimCaptureObject BenchmarkLiveReader @(42,'game.exe',$true)
Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $separate @($header,$now) | Out-Null
for($i=0;$i -lt 40;$i++){Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $separate @('game.exe,42,0x1,10',$now) | Out-Null}
for($i=0;$i -lt 40;$i++){Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $separate @('game.exe,42,0x1,20',$now.AddSeconds(2)) | Out-Null}
$sample=Invoke-WinSlimCaptureMember BenchmarkLiveReader Snapshot $separate @($now.AddSeconds(2))
Check ([Math]::Abs((Value $sample CurrentFps)-50) -lt 1e-9 -and [Math]::Abs((Value $sample Fps)-(1000/15.0)) -lt 1e-9) 'current FPS uses one second while mean FPS uses five seconds'
for($i=0;$i -lt 35;$i++){Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $separate @('game.exe,42,0x2,100',$now.AddSeconds(2)) | Out-Null}
$sample=Invoke-WinSlimCaptureMember BenchmarkLiveReader Snapshot $separate @($now.AddSeconds(2))
Check ([Math]::Abs((Value $sample Mean)-15) -lt 1e-9) 'secondary swap chain never pollutes the dominant live stream'
Reject {Invoke-WinSlimCaptureMember BenchmarkLiveReader Accept $bounded @('game.exe,42,0x1',$now)} 'malformed live row explicitly rejected'
$incremental=New-WinSlimCaptureObject BenchmarkLiveReader @(42,'game.exe',$false)
$partial=Join-Path $script:CaptureBuild 'partial.csv'
[IO.File]::WriteAllText($partial,$header+"`n"+((1..29 | ForEach-Object {'game.exe,42,0x1,10'}) -join "`n")+"`n"+'game.exe,42,0x1,')
Check ($null -eq (Invoke-WinSlimCaptureMember BenchmarkLiveReader Poll $incremental @($partial,$now))) 'partial final line never becomes a valid interval'
[IO.File]::AppendAllText($partial,"10`n")
Check ($null -ne (Invoke-WinSlimCaptureMember BenchmarkLiveReader Poll $incremental @($partial,$now))) 'completing a partial line publishes a snapshot'
[IO.File]::WriteAllText($partial,'')
Reject {Invoke-WinSlimCaptureMember BenchmarkLiveReader Poll $incremental @($partial,$now)} 'truncated incremental file rejected without publishing a complete capture'
Write-Host ('PresentMon data: '+$checks+' checks; production classes + CSV data only, no harness, no ETW or collector process. '+$script:CaptureBuild)

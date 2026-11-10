#requires -Version 5.1
[CmdletBinding()]
param([AllowEmptyString()][string]$Root,[int]$ProcessId=0,[ValidateRange(1,15)][int]$Seconds=3,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($Root)){$Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)}
$Root=[IO.Path]::GetFullPath($Root)
. (Join-Path $Root 'tools/TestExecutionPolicy.ps1')
Assert-WinSlimTestExecutionAllowed -Family OfficialPresentMonIntegration
$binary=Join-Path $Root 'third_party/PresentMon/PresentMon-2.6.0-x64.exe'
if($ProcessId -lt 0){throw 'Invalid PID'}
if(-not $OutputDirectory){$OutputDirectory=Join-Path $Root ('logs/official-presentmon-probe-'+[Guid]::NewGuid().ToString('N'))}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $OutputDirectory.StartsWith($Root.TrimEnd('\')+'\logs\',[StringComparison]::OrdinalIgnoreCase)){throw 'Probe evidence must remain under workspace logs'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$hash=(Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant()
$signature=Get-AuthenticodeSignature -LiteralPath $binary
if($hash -cne 'b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af' -or $signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)CN=Intel Corporation(,|$)'){throw 'Official binary identity/signature not verified; do not execute'}
$session='WinSlim-'+[Guid]::NewGuid().ToString('N')
[ordered]@{StartUtc=[DateTime]::UtcNow.ToString('o');Binary=$binary;SHA256=$hash;SignatureStatus=[string]$signature.Status;Signer=$signature.SignerCertificate.Subject;Session=$session;Pid=$ProcessId;Seconds=$Seconds;Provider='official release console; no harness'} | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory 'before-execution.json') -Encoding UTF8
function Invoke-Official([string]$Arguments,[string]$Stem,[int]$TimeoutSeconds){
 if((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash){throw 'Binary changed before execution'}
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=$binary;$start.Arguments=$Arguments;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $process=New-Object Diagnostics.Process;$process.StartInfo=$start
 try{
  if(-not $process.Start()){throw 'Official collector did not start'}
  $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit($TimeoutSeconds*1000)){
   # Only the process created by this invocation; the timed collector owns a unique session.
   $process.Kill();[void]$process.WaitForExit(5000);throw 'Official probe timeout; no capture accepted'
  }
  $process.WaitForExit()
  [IO.File]::WriteAllText((Join-Path $OutputDirectory ($Stem+'.stdout.log')),$stdout.Result,(New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText((Join-Path $OutputDirectory ($Stem+'.stderr.log')),$stderr.Result,(New-Object Text.UTF8Encoding($false)))
  [pscustomobject]@{ExitCode=$process.ExitCode;Arguments=$Arguments;Utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $OutputDirectory ($Stem+'.process.json')) -Encoding UTF8
  return [pscustomobject]@{ExitCode=$process.ExitCode;Stdout=$stdout.Result;Stderr=$stderr.Result}
 }finally{$process.Dispose()}
}
try{
 $help=Invoke-Official '--help' 'help' 10
 # This release prints help on stderr and returns 1 for an informational help request.
 # Capture below still requires exit 0 and real CSV rows.
 if($help.ExitCode -notin @(0,1) -or ($help.Stdout+$help.Stderr) -notmatch 'PresentMon 2\.6\.0' -or ($help.Stdout+$help.Stderr) -notmatch 'Capture Target Options'){throw 'Official version banner not verified'}
 $arguments='--timed '+$Seconds+' --terminate_after_timed --output_stdout --no_console_stats --v1_metrics --no_track_gpu --no_track_display --no_track_input --session_name '+$session
 if($ProcessId -gt 0){$arguments+=' --process_id '+$ProcessId}
 $capture=Invoke-Official $arguments 'capture' ($Seconds+15)
 $rows=@();if($capture.Stdout.Trim()){$rows=@($capture.Stdout | ConvertFrom-Csv)}
 $summary=[ordered]@{EndUtc=[DateTime]::UtcNow.ToString('o');OfficialVersion='2.6.0';SHA256=$hash;ExitCode=$capture.ExitCode;Session=$session;Rows=$rows.Count;Targets=@($rows | Group-Object Application,ProcessID | Select-Object Name,Count);PhysicalGameAcceptance=$false;HarnessUsed=$false;Success=($capture.ExitCode -eq 0 -and $rows.Count -ge 30)}
 $summary | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
 $summary | ConvertTo-Json -Depth 5
 if(-not $summary.Success){throw 'No verified official frame stream; preserve evidence and do not approve integration'}
}catch{
 [ordered]@{Utc=[DateTime]::UtcNow.ToString('o');Error=$_.Exception.ToString();Session=$session;Success=$false;HarnessUsed=$false} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutputDirectory 'failure.json') -Encoding UTF8
 throw
}

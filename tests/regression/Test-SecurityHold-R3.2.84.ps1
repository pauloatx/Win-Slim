#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools\TestExecutionPolicy.ps1')
. (Join-Path $Root 'tools\TestArtifactProvenance.ps1')
& (Join-Path $Root 'tests/regression/Test-ContainedScope-R3.2.84.ps1') -Root $Root
function Check([bool]$Value,[string]$Message){if(-not $Value){throw $Message};Write-Host ('[OK] '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Message}
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$temp=Join-Path $tempRoot ('winslim-security-policy-'+[guid]::NewGuid().ToString('N'))
try{
 [void][IO.Directory]::CreateDirectory($temp)
 $policy=Join-Path $temp 'policy.json'
 $incident=@{id='AV-FIXTURE';status='investigating';families=@('PresentMonHarness');detection='fixture'}
 @{schemaVersion=1;incidents=@($incident)} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $policy -Encoding UTF8
 $marker=Join-Path $temp 'unexpected-action.txt'
 Reject {Assert-WinSlimTestExecutionAllowed -Family PresentMonHarness -PolicyPath $policy;[IO.File]::WriteAllText($marker,'unexpected')} 'pending incident blocks compilation/launch action'
 Check (-not (Test-Path -LiteralPath $marker)) 'blocked action leaves no side effect'
 Reject {Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate -PolicyPath $policy} 'full gate cannot approve a partially blocked registry'
 Assert-WinSlimTestExecutionAllowed -Family UnrelatedFixture -PolicyPath $policy
 Check ((Get-Content -LiteralPath $policy -Raw).Contains('investigating')) 'unrelated check preserves the original incident state'
 Reject {Assert-WinSlimTestExecutionAllowed -Family PresentMonHarness -PolicyPath (Join-Path $temp 'missing.json')} 'missing policy fails closed'
 [IO.File]::WriteAllText($policy,'invalid json')
 Reject {Assert-WinSlimTestExecutionAllowed -Family PresentMonHarness -PolicyPath $policy} 'unreadable policy fails closed'
 $incident.status='cleared'
 @{schemaVersion=1;incidents=@($incident)} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $policy -Encoding UTF8
 Reject {Assert-WinSlimTestExecutionAllowed -Family PresentMonHarness -PolicyPath $policy} 'clear disposition requires a recorded review resolution'
 $incident.resolution='Fixture-only vendor review, no real sample involved'
 @{schemaVersion=1;incidents=@($incident)} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $policy -Encoding UTF8
 Assert-WinSlimTestExecutionAllowed -Family PresentMonHarness -PolicyPath $policy
 Check $true 'reviewed fixture resolution permits its own inert action; real policy never modified'
 # A project-owner decision can permit local validation while retaining package/production holds.
 $incident.status='controlled-local-validation'
 $incident.resolution='Project-owner fixture assessment; no manufacturer verdict asserted'
 $incident.localValidationAuthorization=@{authority='project-owner';assessmentRecord='release/owner-fixture.json';
  allowedScopes=@('affected-test-component-generation-and-execution','full-regression-gate');
  blockedScopes=@('application-package-publication','production-release');productionApproved=$false;stopOnFailure=$true}
 @{schemaVersion=1;incidents=@($incident)} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $policy -Encoding UTF8
 Assert-WinSlimTestExecutionAllowed -Family PresentMonHarness -PolicyPath $policy
 [IO.File]::WriteAllText($marker,'authorized inert action')
 Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate -PolicyPath $policy
 Check ((Get-Content -LiteralPath $marker -Raw) -ceq 'authorized inert action') 'scoped owner decision permits only the local inert action and gate'
 Check (Test-WinSlimControlledLocalValidation -PolicyPath $policy) 'controlled run requests failure stop independently of production clearance'
 $valid=Get-Content -LiteralPath $policy -Raw
 foreach($field in @('authority','assessmentRecord','allowedScopes','blockedScopes','productionApproved','stopOnFailure')){
  $bad=$valid | ConvertFrom-Json
  $auth=$bad.incidents[0].localValidationAuthorization
  switch($field){
   'authority'{$auth.authority='unreviewed'}
   'assessmentRecord'{$auth.assessmentRecord=''}
   'allowedScopes'{$auth.allowedScopes+= 'production-release'}
   'blockedScopes'{$auth.blockedScopes=@('production-release')}
   'productionApproved'{$auth.productionApproved=$true}
   'stopOnFailure'{$auth.stopOnFailure=$false}
  }
  $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $policy -Encoding UTF8
  Reject {Assert-WinSlimTestExecutionAllowed -Family PresentMonHarness -PolicyPath $policy} ('incomplete or excessive local authorization rejected: '+$field)
 }
 [IO.File]::WriteAllText($policy,$valid)
 Check ((Get-Content -LiteralPath $marker -Raw) -ceq 'authorized inert action') 'rejected authorization changes preserve unrelated fixture state'
 # Run unchanged entry-point source in an isolated root with a pending fixture policy.
 # This must remain a guard test even when the real project authorizes local execution.
 $entryRoot=Join-Path $temp 'entry-fixture'
 foreach($folder in @('tools','tests','tests/regression','release','logs')){[void][IO.Directory]::CreateDirectory((Join-Path $entryRoot $folder))}
 foreach($relative in @('tools/TestExecutionPolicy.ps1','tools/TestArtifactProvenance.ps1','Executar-Regressoes.ps1','tests/regression/RegressionPaths.ps1','tests/regression/RegressionProcess.ps1',
  'tests/Test-Fase7-R3.2.83-PresentMon.ps1','tests/Test-Fase7-R3.2.84-PresentMon.ps1','tests/Test-Fase7-R3.2.84-Monitor.ps1')){
  Copy-Item -LiteralPath (Join-Path $Root $relative) -Destination (Join-Path $entryRoot $relative)
  Check ((Get-FileHash -LiteralPath (Join-Path $Root $relative)).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $entryRoot $relative)).Hash) ('entry fixture preserves actual source: '+$relative)
 }
 $entryPolicy=Join-Path $entryRoot 'release/security-incidents.json'
 @{schemaVersion=1;incidents=@(@{id='AV-ENTRY-FIXTURE';status='investigating';families=@('PresentMonHarness','MonitorHarness');detection='inert fixture'})} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $entryPolicy -Encoding UTF8
 # Exercise the actual entry points. The guard runs before directory creation or csc.
 $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 foreach($script in @('tests/Test-Fase7-R3.2.83-PresentMon.ps1','tests/Test-Fase7-R3.2.84-PresentMon.ps1','tests/Test-Fase7-R3.2.84-Monitor.ps1')){
  $start=New-Object Diagnostics.ProcessStartInfo
  $start.FileName=$shell;$start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $entryRoot $script)+'" -Root "'+$entryRoot+'"'
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $start.EnvironmentVariables['TEMP']=$temp;$start.EnvironmentVariables['TMP']=$temp
  $process=New-Object Diagnostics.Process;$process.StartInfo=$start
  try{[void]$process.Start();$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();if(-not $process.WaitForExit(15000)){$process.Kill();throw 'Guard entry point timed out.'};$text=$stdout.Result+$stderr.Result;Check ($process.ExitCode -ne 0 -and $text.Contains('AV-ENTRY-FIXTURE')) ('actual entry point blocks before compiler: '+$script)}finally{$process.Dispose()}
 }
 Check (@(Get-ChildItem -LiteralPath $temp -Directory | Where-Object {$_.Name -ne 'entry-fixture'}).Count -eq 0 -and @(Get-ChildItem -LiteralPath $temp -Filter '*.exe' -Recurse).Count -eq 0) 'no temporary helper directory or executable created'
 # Whole executor stops before a second inert script after a failure in controlled mode.
 [IO.File]::WriteAllText($entryPolicy,$valid)
 $secondMarker=Join-Path $entryRoot 'unexpected-second-action.txt'
 [IO.File]::WriteAllText((Join-Path $entryRoot 'tests/first.ps1'),'param([string]$Root) exit 7')
 [IO.File]::WriteAllText((Join-Path $entryRoot 'tests/second.ps1'),'param([string]$Root) [IO.File]::WriteAllText((Join-Path $Root "unexpected-second-action.txt"),"should not run"); exit 0')
 $cases=@(@{id='REG-FIRST-001';bugs=@('fixture');scenario='controlled failure';script='tests/first.ps1';timeoutSeconds=15},@{id='REG-SECOND-001';bugs=@('fixture');scenario='must not run';script='tests/second.ps1';timeoutSeconds=15})
 @{schemaVersion=1;cases=$cases} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $entryRoot 'tests/regression/cases.json') -Encoding UTF8
 . (Join-Path $Root 'tests/regression/RegressionProcess.ps1')
 $fixtureRun=Invoke-WinSlimRegressionProcess -Executable $shell -Arguments ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $entryRoot 'Executar-Regressoes.ps1')+'" -Root "'+$entryRoot+'"') -WorkingDirectory $entryRoot -Stdout (Join-Path $entryRoot 'logs/executor.stdout.log') -Stderr (Join-Path $entryRoot 'logs/executor.stderr.log') -TimeoutSeconds 30
 $fixtureReport=Get-ChildItem -LiteralPath (Join-Path $entryRoot 'logs') -Filter resultado.json -Recurse | Select-Object -First 1
 $report=Get-Content -LiteralPath $fixtureReport.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
 Check ($fixtureRun.ExitCode -ne 0 -and -not $report.Passed -and @($report.Results).Count -eq 1 -and -not (Test-Path -LiteralPath $secondMarker)) 'controlled failure halts executor, preserves failed report and prevents subsequent action'
 $inert=Join-Path $temp 'inert-data.bin';[IO.File]::WriteAllText($inert,'inert provenance fixture, never executable')
 $source=Join-Path $temp 'source.txt';[IO.File]::WriteAllText($source,'source fixture')
 $before=(Get-FileHash -LiteralPath $inert).Hash
 $record=Write-WinSlimTestArtifactRecord -Root $temp -Artifact $inert -Compiler $source -Sources @($source) -CompilerExit 0
 $saved=Get-Content -LiteralPath $record.Path -Raw | ConvertFrom-Json
 Check ($saved.Artifact.SHA256 -ceq $before -and $saved.Sources[0].SHA256 -ceq (Get-FileHash -LiteralPath $source).Hash -and $saved.ExecutedByRecorder -eq $false) 'provenance records exact binary/source hashes without executing either fixture'
 $absent=Write-WinSlimTestArtifactRecord -Root $temp -Artifact (Join-Path $temp 'missing.bin') -Compiler $source -Sources @($source) -CompilerExit 0
 Check (-not $absent.ArtifactReadable -and (Test-Path -LiteralPath $absent.Path)) 'removed or quarantined output leaves an explicit missing-hash record'
 $missingInput=Write-WinSlimTestArtifactRecord -Root $temp -Artifact $inert -Compiler $source -Sources @((Join-Path $temp 'missing-source.txt')) -CompilerExit 0
 Check (-not $missingInput.InputsReadable -and $missingInput.ArtifactReadable) 'unavailable source cannot be treated as complete provenance'
 $failed=Write-WinSlimTestArtifactRecord -Root $temp -Artifact $inert -Compiler $source -Sources @($source) -CompilerExit 0 -Stage ExecutionFailed
 Check ((Get-FileHash -LiteralPath $inert).Hash -ceq $before -and (Test-Path -LiteralPath $record.Path) -and $failed.Path -ne $record.Path) 'failure recording preserves original evidence and creates a separate record'
 # Python is a development dependency for packager fixtures, never for the app runtime.
 $python=Join-Path $Root 'logs\dev-python313\python.exe'
 if(-not (Test-Path -LiteralPath $python)){$python=(Get-Command python.exe -ErrorAction Stop).Source}
 & $python -m unittest discover -s (Join-Path $Root 'tests') -p test_package_release.py -v
 if($LASTEXITCODE -ne 0){throw 'Packager behavior regressions failed.'}
 Write-Host '[OK] REG-SECURITY-001: policy and packaging fixtures passed; no detected sample or variant executed.'
}finally{
 $full=[IO.Path]::GetFullPath($temp)
 if($full.StartsWith($tempRoot+'\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full) -match '\Awinslim-security-policy-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $full)){Remove-Item -LiteralPath $full -Recurse -Force}
}

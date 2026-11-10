#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools/TestExecutionPolicy.ps1')
$fixture=Join-Path $Root ('logs/scope-fixture-'+[Guid]::NewGuid().ToString('N'))
foreach($folder in @('release','tests/regression')){[void][IO.Directory]::CreateDirectory((Join-Path $fixture $folder))}
$policy=Join-Path $fixture 'release/security-incidents.json'
$registry=Join-Path $fixture 'tests/regression/cases.json'
$manifest=Join-Path $fixture 'release/review.json'
$active=Join-Path $fixture 'tests/active.ps1';[IO.File]::WriteAllText($active,'exit 0')
[IO.File]::WriteAllText((Join-Path $fixture 'tests/retired.ps1'),'inert guard-only source; never executed')
[IO.File]::WriteAllText((Join-Path $fixture 'review.md'),'review fixture; not a manufacturer resolution')
[IO.File]::WriteAllText((Join-Path $fixture 'held.txt'),'inert source fixture')
$case=[ordered]@{id='REG-FIXTURE-001';script='tests/active.ps1'}
$incident=[ordered]@{id='AV-FIXTURE';status='component-contained';detection='fixture';families=@('PresentMonHarness','MonitorHarness');scopeReview=[ordered]@{authority='project-owner-authorized-technical-review';record='review.md';manifest='release/review.json';manifestSHA256=('0'*64);historicalIncidentResolved=$false;productionApproved=$false}}
function SaveFixture {
 @{schemaVersion=1;cases=@($case)} | ConvertTo-Json -Depth 8 | Set-Content $registry -Encoding UTF8
 $data=[ordered]@{schemaVersion=1;incident='AV-FIXTURE';requiredIds=@('REG-FIXTURE-001');registrySHA256=(Get-FileHash $registry).Hash.ToLowerInvariant();activeFiles=@{'tests/active.ps1'=(Get-FileHash $active).Hash.ToLowerInvariant()};guardOnlyFiles=@{'tests/retired.ps1'=(Get-FileHash (Join-Path $fixture 'tests/retired.ps1')).Hash.ToLowerInvariant()};heldSourceFiles=@{'held.txt'=(Get-FileHash (Join-Path $fixture 'held.txt')).Hash.ToLowerInvariant()}}
 $data | ConvertTo-Json -Depth 8 | Set-Content $manifest -Encoding UTF8
 $incident.scopeReview.manifestSHA256=(Get-FileHash $manifest).Hash.ToLowerInvariant()
 @{schemaVersion=1;incidents=@($incident)} | ConvertTo-Json -Depth 10 | Set-Content $policy -Encoding UTF8
}
$checks=0
function Check([bool]$Value,[string]$Text){if(-not $Value){throw $Text};$script:checks++;Write-Host ('[OK] '+$Text)}
function Reject([scriptblock]$Action,[string]$Text){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Text}
SaveFixture
Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate -PolicyPath $policy
Check $true 'documented contained review permits only the reviewed current gate'
foreach($family in @('PresentMonHarness','MonitorHarness')){Reject {Assert-WinSlimTestExecutionAllowed -Family $family -PolicyPath $policy} ('retired family remains blocked: '+$family)}
Check (Test-WinSlimControlledLocalValidation -PolicyPath $policy) 'contained gate stops on first failure without granting affected execution'
[IO.File]::WriteAllText($active,'changed')
Reject {Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate -PolicyPath $policy} 'changed active dependency invalidates permission'
[IO.File]::WriteAllText($active,'exit 0');SaveFixture
[IO.File]::WriteAllText($registry,'{}')
Reject {Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate -PolicyPath $policy} 'changed registry invalidates permission'
SaveFixture
$case.script='tests/retired.ps1';SaveFixture
Reject {Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate -PolicyPath $policy} 'held entry cannot enter active case set even with reviewed registry digest'
$case.script='tests/active.ps1';SaveFixture
foreach($field in @('authority','historicalIncidentResolved','productionApproved','manifestSHA256','record')){
 $original=$incident.scopeReview[$field]
 $incident.scopeReview[$field]=switch($field){'authority'{'unreviewed'};'historicalIncidentResolved'{$true};'productionApproved'{$true};'manifestSHA256'{''};'record'{''}}
 @{schemaVersion=1;incidents=@($incident)} | ConvertTo-Json -Depth 10 | Set-Content $policy -Encoding UTF8
 Reject {Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate -PolicyPath $policy} ('missing or excessive review rejected: '+$field)
 $incident.scopeReview[$field]=$original
}
SaveFixture
Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate -PolicyPath $policy
Check ((Get-Content $active -Raw) -ceq 'exit 0' -and @(Get-ChildItem $fixture -Recurse -Filter '*.exe').Count -eq 0) 'restored review works; tests created no executable or acted on production'
Write-Host ('Contained scope: '+$checks+' behavioral checks; fixture preserved at '+$fixture)

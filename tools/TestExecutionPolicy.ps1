#requires -Version 5.1
# This policy concerns test tools only; it never changes antivirus configuration.
$script:WinSlimTestIncidentPolicy=Join-Path (Split-Path -Parent $PSScriptRoot) 'release\security-incidents.json'
function Assert-WinSlimContainedReview {
 param($Incident,[string]$PolicyPath)
 $review=$Incident.scopeReview
 if($null -eq $review -or $review.authority -cne 'project-owner-authorized-technical-review' -or
    $review.historicalIncidentResolved -isnot [bool] -or $review.historicalIncidentResolved -ne $false -or
    $review.productionApproved -isnot [bool] -or $review.productionApproved -ne $false -or
    [string]::IsNullOrWhiteSpace([string]$review.record) -or $review.manifestSHA256 -notmatch '\A[0-9a-f]{64}\z'){
  throw 'Contained-component review invalid; gate blocked.'
 }
 $root=Split-Path -Parent (Split-Path -Parent ([IO.Path]::GetFullPath($PolicyPath)))
 function ReviewFile([string]$Relative){
  $path=[IO.Path]::GetFullPath((Join-Path $root $Relative))
  if(-not $path.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf)){throw 'Review dependency missing or outside root.'}
  return $path
 }
 $manifestPath=ReviewFile ([string]$review.manifest)
 [void](ReviewFile ([string]$review.record))
 if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $review.manifestSHA256){throw 'Scope review manifest changed; gate blocked.'}
 $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if($manifest.schemaVersion -ne 1 -or $manifest.incident -cne $Incident.id -or @($manifest.activeFiles.PSObject.Properties).Count -eq 0 -or
    @($manifest.requiredIds).Count -eq 0 -or @($manifest.guardOnlyFiles.PSObject.Properties).Count -eq 0){throw 'Scope review dependencies incomplete.'}
 foreach($group in @($manifest.activeFiles,$manifest.guardOnlyFiles,$manifest.heldSourceFiles)){
  foreach($entry in $group.PSObject.Properties){
   if($entry.Value -notmatch '\A[0-9a-f]{64}\z' -or (Get-FileHash -LiteralPath (ReviewFile $entry.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $entry.Value){throw ('Reviewed dependency changed: '+$entry.Name)}
  }
 }
 $registryPath=ReviewFile 'tests/regression/cases.json'
 if((Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $manifest.registrySHA256){throw 'Reviewed regression registry changed.'}
 $registry=Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if(@($registry.cases).Count -ne @($manifest.requiredIds).Count -or @($manifest.requiredIds | Sort-Object -Unique).Count -ne @($manifest.requiredIds).Count){throw 'Reviewed case set incomplete.'}
 foreach($case in $registry.cases){
  $relative=([string]$case.script).Replace('\','/')
  if($case.id -cnotin @($manifest.requiredIds) -or $null -eq $manifest.activeFiles.PSObject.Properties[$relative] -or $null -ne $manifest.guardOnlyFiles.PSObject.Properties[$relative]){throw 'Held or unreviewed test cannot enter active gate.'}
 }
}
function Assert-WinSlimTestExecutionAllowed {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$Family,[string]$PolicyPath=$script:WinSlimTestIncidentPolicy)
 if(-not (Test-Path -LiteralPath $PolicyPath -PathType Leaf)){throw 'Security incident policy missing; test execution blocked.'}
 try{$policy=Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json}catch{throw 'Security incident policy unreadable; test execution blocked.'}
 if($policy.schemaVersion -ne 1 -or $null -eq $policy.incidents){throw 'Security incident policy invalid; test execution blocked.'}
 foreach($incident in @($policy.incidents)){
  if([string]::IsNullOrWhiteSpace([string]$incident.id) -or @('investigating','controlled-local-validation','component-contained','cleared') -notcontains [string]$incident.status -or @($incident.families).Count -eq 0){throw 'Security incident policy invalid; test execution blocked.'}
  if($incident.status -eq 'component-contained'){
   if(@($incident.families) -contains $Family){throw ('Security hold '+$incident.id+': retired affected family remains blocked.')}
   if($Family -eq 'FullRegressionGate'){Assert-WinSlimContainedReview -Incident $incident -PolicyPath $PolicyPath}
  }
  if($incident.status -in @('cleared','controlled-local-validation') -and [string]::IsNullOrWhiteSpace([string]$incident.resolution)){throw 'Security incident lacks a review resolution; test execution blocked.'}
  if($incident.status -eq 'controlled-local-validation'){
   $authorization=$incident.localValidationAuthorization
   $allowed=@($authorization.allowedScopes);$blocked=@($authorization.blockedScopes)
   if($null -eq $authorization -or $authorization.authority -cne 'project-owner' -or
      [string]::IsNullOrWhiteSpace([string]$authorization.assessmentRecord) -or
      $authorization.productionApproved -isnot [bool] -or $authorization.productionApproved -ne $false -or
      $authorization.stopOnFailure -isnot [bool] -or $authorization.stopOnFailure -ne $true -or
      $allowed.Count -ne 2 -or @($allowed | Sort-Object -Unique).Count -ne 2 -or
      @($allowed | Where-Object {$_ -cnotin @('affected-test-component-generation-and-execution','full-regression-gate')}).Count -ne 0 -or
      $blocked.Count -ne 2 -or @($blocked | Sort-Object -Unique).Count -ne 2 -or
      @($blocked | Where-Object {$_ -cnotin @('application-package-publication','production-release')}).Count -ne 0){
    throw 'Controlled local validation authorization invalid; execution blocked.'
   }
  }
  if($incident.status -eq 'investigating' -and ($Family -eq 'FullRegressionGate' -or @($incident.families) -contains $Family)){
   throw ('Security hold '+$incident.id+': '+$incident.detection+'. Test compilation/execution blocked pending review. No antivirus exclusion or renamed retry is permitted.')
  }
 }
}
function Test-WinSlimControlledLocalValidation {
 [CmdletBinding()]
 param([string]$PolicyPath=$script:WinSlimTestIncidentPolicy)
 Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate -PolicyPath $PolicyPath
 $policy=Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
 return (@($policy.incidents | Where-Object {$_.status -in @('controlled-local-validation','component-contained')}).Count -gt 0)
}

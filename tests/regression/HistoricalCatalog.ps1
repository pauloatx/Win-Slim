# Historical catalog integrity accepts only an explicitly reviewed transition with both versions pinned.
function Test-WinSlimHistoricalCatalogFile {
 param([string]$Root,[string]$RelativePath,[string]$ExpectedSHA256)
 try{
  $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
  $current=[IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
  if(-not $current.StartsWith($rootPath,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $current -PathType Leaf)){return $false}
  $hash=(Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash
  if($hash -ieq $ExpectedSHA256){return $true}
  $manifest=Get-Content -LiteralPath (Join-Path $Root 'specs/EDGE-CATALOG-TRANSITION-R3.2.84.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($manifest.schemaVersion -ne 1){return $false}
  $entries=@($manifest.entries | Where-Object {$_.path -ceq $RelativePath.Replace('\','/')})
  if($entries.Count -ne 1){return $false}
  $entry=$entries[0]
  if($entry.originalSHA256 -ine $ExpectedSHA256 -or $entry.reviewedCurrentSHA256 -ine $hash -or @($entry.changes).Count -eq 0){return $false}
  $original=[IO.Path]::GetFullPath((Join-Path $Root $entry.originalSnapshot))
  $snapshotRoot=[IO.Path]::GetFullPath((Join-Path $Root 'specs/history/edge-before-completion')).TrimEnd('\')+'\'
  if(-not $original.StartsWith($snapshotRoot,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $original -PathType Leaf) -or
     (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ine $ExpectedSHA256){return $false}
  foreach($change in $entry.changes){
   if($change.id -cnotmatch '\AEDGE-[0-9]{3}\z' -or $change.field -cnotin @('description','activationNote','compatibilityNote','reviewedWindowsEdgeMinimum','reviewedWindowsEdgeMaximum','policyLifecycle')){return $false}
  }
  return $true
 }catch{return $false}
}

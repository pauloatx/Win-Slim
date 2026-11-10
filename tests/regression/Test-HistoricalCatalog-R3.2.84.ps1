#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tests/regression/HistoricalCatalog.ps1')
$fixture=Join-Path $Root ('logs/catalog-history-fixture-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$manifest=Get-Content -LiteralPath (Join-Path $Root 'specs/EDGE-CATALOG-TRANSITION-R3.2.84.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$checks=0
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};$script:checks++;Write-Host ('[OK] '+$Message)}
foreach($relative in @('specs/EDGE-CATALOG-TRANSITION-R3.2.84.json')+@($manifest.entries.path)+@($manifest.entries.originalSnapshot)){
 $target=Join-Path $fixture $relative
 [void][IO.Directory]::CreateDirectory((Split-Path -Parent $target))
 Copy-Item -LiteralPath (Join-Path $Root $relative) -Destination $target
}
foreach($entry in $manifest.entries){
 Check (Test-WinSlimHistoricalCatalogFile $fixture $entry.path $entry.originalSHA256) 'reviewed Edge metadata transition retains verified original and current catalog'
 $current=Join-Path $fixture $entry.path;$snapshot=Join-Path $fixture $entry.originalSnapshot
 $bytes=[IO.File]::ReadAllBytes($current)
 [IO.File]::WriteAllText($current,'{}')
 Check (-not (Test-WinSlimHistoricalCatalogFile $fixture $entry.path $entry.originalSHA256)) 'unreviewed catalog content rejected without modifying preserved original'
 [IO.File]::WriteAllBytes($current,$bytes)
 Check (-not (Test-WinSlimHistoricalCatalogFile $fixture $entry.path ('0'*64))) 'different historical identity cannot use approved transition'
 $old=[IO.File]::ReadAllBytes($snapshot);[IO.File]::WriteAllText($snapshot,'{}')
 Check (-not (Test-WinSlimHistoricalCatalogFile $fixture $entry.path $entry.originalSHA256)) 'missing or changed original evidence rejects transition'
 [IO.File]::WriteAllBytes($snapshot,$old)
 Check (Test-WinSlimHistoricalCatalogFile $fixture $entry.path $entry.originalSHA256) 'restoring original evidence restores only reviewed acceptance'
 [IO.File]::WriteAllBytes($current,$old)
 Check (Test-WinSlimHistoricalCatalogFile $fixture $entry.path $entry.originalSHA256) 'unchanged historical catalog remains valid without transition'
 [IO.File]::WriteAllBytes($current,$bytes)
}
Check (-not (Test-WinSlimHistoricalCatalogFile $fixture 'unknown.json' ('0'*64))) 'unavailable catalog rejected'
Write-Host ('HistoricalCatalog: '+$checks+' behavioral checks passed; original R4 baseline unchanged.')

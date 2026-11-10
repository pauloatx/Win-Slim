#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools/integration/EdgeVmEvidence.ps1')
$script:checks=0
function Check([bool]$Ok,[string]$Text){if(-not $Ok){throw $Text};$script:checks++;Write-Host ('[OK] '+$Text)}
function Reject([scriptblock]$Action,[string]$Text){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Text}
$guest='C:\WinSlim\EdgeIsolated\fixture'
$hash='A'*64
$entries=@([pscustomobject]@{Path=$guest+'\evidence\status.json';SHA256=$hash},[pscustomobject]@{Path=$guest+'\evidence\cancelled.json';SHA256=$hash})
$json=ConvertTo-Json -InputObject $entries -Depth 4
$preserved=$json
$files=@(ConvertFrom-WinSlimEdgeVmInventory $json $guest)
Check ($files.Count -eq 2 -and $files[0].Path -is [string]) 'JSON array produces two individual records on PowerShell 5.1'
Check (@(Get-WinSlimEdgeVmDirectoryFiles $files $guest 'evidence').Count -eq 2) 'evidence directory selected completely'
Check (@(Get-WinSlimEdgeVmDirectoryFiles $files $guest 'Backups').Count -eq 0) 'absent backup directory never selected or copied'
$withBackup=@($entries)+@([pscustomobject]@{Path=$guest+'\Backups\id\snapshot.json';SHA256=$hash})
$both=@(ConvertFrom-WinSlimEdgeVmInventory (ConvertTo-Json -InputObject $withBackup) $guest)
Check (@(Get-WinSlimEdgeVmDirectoryFiles $both $guest 'Backups').Count -eq 1) 'existing backup selected once without losing other evidence'
$one=@(ConvertFrom-WinSlimEdgeVmInventory (ConvertTo-Json -InputObject $entries[0]) $guest)
Check ($one.Count -eq 1) 'single record remains usable'
Reject {ConvertFrom-WinSlimEdgeVmInventory '[]' $guest} 'empty inventory does not authorize restoration'
Reject {ConvertFrom-WinSlimEdgeVmInventory 'invalid' $guest} 'malformed JSON does not authorize collection'
Reject {ConvertFrom-WinSlimEdgeVmInventory (ConvertTo-Json -InputObject @($entries[0],$entries[0])) $guest} 'duplicate record rejected'
foreach($path in @('C:\Other\secret.txt',($guest+'\evidence\..\..\outside.txt'),($guest+'\evidence\status.json:stream'))) {
    Reject {ConvertFrom-WinSlimEdgeVmInventory (ConvertTo-Json -InputObject ([pscustomobject]@{Path=$path;SHA256=$hash})) $guest} 'outside/traversal/alternate-stream record rejected'
}
Reject {ConvertFrom-WinSlimEdgeVmInventory (ConvertTo-Json -InputObject ([pscustomobject]@{Path=$entries[0].Path;SHA256='wrong'})) $guest} 'invalid hash rejected'
Check ($json -ceq $preserved) 'input inventory and unrelated state preserved'
$newtab=[pscustomobject]@{type='page';url='edge://newtab/';webSocketDebuggerUrl='ws://127.0.0.1:19284/devtools/page/tab'}
$worker=[pscustomobject]@{type='worker';url='';webSocketDebuggerUrl='ws://127.0.0.1:19284/devtools/page/worker'}
$target=Get-WinSlimEdgeCdpPolicyTarget (ConvertTo-Json -InputObject @($newtab,$worker)) 19284
Check ($target.type -eq 'page' -and $target.url -eq 'edge://newtab/') 'initial new-tab is usable for explicit policy navigation'
$policy=[pscustomobject]@{type='page';url='edge://policy/';webSocketDebuggerUrl='ws://127.0.0.1:19284/devtools/page/policy'}
$target=Get-WinSlimEdgeCdpPolicyTarget (ConvertTo-Json -InputObject @($newtab,$worker,$policy)) 19284
Check ($target.url -eq 'edge://policy/') 'existing policy page preferred over worker/new-tab'
Reject {Get-WinSlimEdgeCdpPolicyTarget (ConvertTo-Json -InputObject @($worker)) 19284} 'no real page rejected'
$external=[pscustomobject]@{type='page';url='edge://policy/';webSocketDebuggerUrl='ws://outside.invalid:19284/page'}
Reject {Get-WinSlimEdgeCdpPolicyTarget (ConvertTo-Json -InputObject @($external)) 19284} 'non-loopback endpoint rejected'
Reject {Get-WinSlimEdgeCdpPolicyTarget (ConvertTo-Json -InputObject @($policy)) 19285} 'wrong local port rejected'
. (Join-Path $Root 'tools/integration/EdgeVmBatch.ps1')
$batch=Get-WinSlimEdgeVmBatch 'Core'
Check (($batch.Ids -join ',') -ceq 'EDGE-003,EDGE-004,EDGE-005,EDGE-006') 'next batch selects only four pending IDs'
Check ($batch.Fixture -ceq 'Test-Fase7-R3.2.84-EdgeBatch.ps1') 'next batch uses its own fixture suite'
Check (@($batch.Ids | Where-Object {$_ -in @('EDGE-019','EDGE-020','EDGE-024','EDGE-025')}).Count -eq 0) 'accepted privacy batch is not repeated by Core'
$batch.Ids[0]='tampered'
Check ((Get-WinSlimEdgeVmBatch 'Core').Ids[0] -ceq 'EDGE-003') 'caller changes cannot alter later batch definitions'
Check (((Get-WinSlimEdgeVmBatch 'Privacy').Ids -join ',') -ceq 'EDGE-019,EDGE-020,EDGE-024,EDGE-025') 'historical batch contract preserved without executing it'
Reject {Get-WinSlimEdgeVmBatch '../unknown'} 'unknown batch cannot expand execution scope'
$next=Get-WinSlimEdgeVmBatch 'Next';$startup=Get-WinSlimEdgeVmBatch 'Startup'
Check (($next.Ids -join ',') -ceq 'EDGE-008,EDGE-011,EDGE-012,EDGE-016') 'next reviewed policy batch stays isolated'
Check (($startup.Ids -join ',') -ceq 'EDGE-001,EDGE-002') 'legacy evidence gap selects only startup policies'
$newIds=@(foreach($name in @('Identity','Forms','Services','Diagnostics','Sleep')){(Get-WinSlimEdgeVmBatch $name).Ids})
Check (@($newIds | Sort-Object -Unique).Count -eq 18) 'completion batches cover 17 new IDs and one explicit dependency'
Check (((Get-WinSlimEdgeVmBatch 'Sleep').SelectedIds -join ',') -ceq 'EDGE-007') 'planner must expand sleeping-tabs dependency'
Write-Host ('[OK] REG-VMEDGE-001: '+$script:checks+' evidence collection fixture checks; no VM, Edge or held helper executed.')

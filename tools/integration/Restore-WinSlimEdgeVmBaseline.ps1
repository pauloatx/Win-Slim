#requires -Version 5.1
# Restore only after completed Edge Undo and complete host evidence verification.
param([Parameter(Mandatory=$true)][string]$CollectionDirectory)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$folder=[IO.Path]::GetFullPath($CollectionDirectory)
if(-not ($folder.StartsWith($workspace.TrimEnd('\')+'\logs\edge-vm-',[StringComparison]::OrdinalIgnoreCase) -or $folder.StartsWith($workspace.TrimEnd('\')+'\logs\edge-completion-',[StringComparison]::OrdinalIgnoreCase))){throw 'Expected workspace collection path required.'}
. (Join-Path $PSScriptRoot 'EdgeVmEvidence.ps1')
$receipt=Get-Content -LiteralPath (Join-Path $folder 'collection-receipt.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($receipt.Collected -ne $true -or $receipt.HashesVerified -ne $true -or $receipt.Guest -notmatch '^C:\\WinSlim\\EdgeIsolated\\edge-priority-[0-9a-f]{8}$'){throw 'Invalid evidence receipt.'}
$files=@(ConvertFrom-WinSlimEdgeVmInventory -Text (Get-Content -LiteralPath (Join-Path $folder 'guest-file-inventory.json') -Raw -Encoding UTF8) -GuestRoot $receipt.Guest)
if($files.Count -ne $receipt.Files){throw 'Partial collection.'}
foreach($entry in $files){$relative=$entry.Path.Substring($receipt.Guest.Length+1);$local=Join-Path $folder $relative;if((Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash -ine $entry.SHA256){throw 'Collected evidence changed.'}}
$status=Get-Content -LiteralPath (Join-Path $folder 'evidence\status.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($status.Status -ne 'Completed' -or -not $status.Elevated -or -not $status.ApplyVerified -or -not $status.UndoVerified -or -not $status.UndoExact){throw 'Completed real Apply and exact Undo required before automatic baseline restore.'}
$vm='teste win-slim-win11';$vbox=Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
function VBox([string[]]$Arguments){$saved=$ErrorActionPreference;try{$ErrorActionPreference='Continue';$output=@(& $vbox --nologo @Arguments 2>&1);$code=$LASTEXITCODE}finally{$ErrorActionPreference=$saved};if($code -ne 0){throw ('VBox failed '+$code+': '+($output -join "`n"))};$output | ForEach-Object {[string]$_}}
function Read-VM {,@(VBox @('showvminfo',$vm,'--machinereadable'))}
$before=Read-VM
if($before -notcontains 'UUID="b71b4588-2e83-461c-9585-64ee77b9c851"' -or $before -notcontains 'CurrentSnapshotUUID="4aa21603-c0b4-4139-9630-1e5d0acaef20"'){throw 'VM/snapshot identity mismatch.'}
if($before -contains 'VMState="running"'){
    VBox @('controlvm',$vm,'acpipowerbutton') | Out-Null
    $off=$false
    for($i=0;$i -lt 24;$i++){Start-Sleep -Seconds 5;$current=Read-VM;if($current -contains 'VMState="poweroff"'){$off=$true;break}}
    if(-not $off){throw 'Normal shutdown did not complete; no forced poweroff or restoration performed.'}
}elseif($before -notcontains 'VMState="poweroff"'){throw 'Unexpected VM state.'}
$snapshotOutput=VBox @('snapshot',$vm,'restore','4aa21603-c0b4-4139-9630-1e5d0acaef20')
$snapshotOutput | Set-Content -LiteralPath (Join-Path $folder 'baseline-restore.log') -Encoding UTF8
$after=Read-VM
if($after -notcontains 'VMState="poweroff"' -or $after -notcontains 'CurrentSnapshotUUID="4aa21603-c0b4-4139-9630-1e5d0acaef20"'){throw 'Restored baseline not confirmed.'}
$after | Set-Content -LiteralPath (Join-Path $folder 'vm-after-baseline.txt') -Encoding UTF8
@{Restored=$true;VM=$vm;Snapshot='WINSLIM_BASELINE';SnapshotUUID='4aa21603-c0b4-4139-9630-1e5d0acaef20';CollectedFilesVerifiedBeforeRestore=$files.Count;ExactUndoBeforeSnapshot=$true;Utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'baseline-restore-receipt.json') -Encoding UTF8
Write-Output 'Evidence verified before shutdown; baseline restored; VM poweroff. No production approval.'

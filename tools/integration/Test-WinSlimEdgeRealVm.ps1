#requires -Version 5.1
# Explicitly authorized real Edge-only acceptance. NEVER run on the host.
param([ValidateSet('Privacy','Core','Next','Startup','Identity','Forms','Services','Diagnostics','Sleep')][string]$Batch='Privacy')
$ErrorActionPreference='Stop'
$computer=Get-CimInstance Win32_ComputerSystem
if($env:COMPUTERNAME -ine 'TESTE' -or $computer.Model -notmatch 'VirtualBox' -or
   -not $PSScriptRoot.StartsWith('C:\WinSlim\EdgeIsolated\',[StringComparison]::OrdinalIgnoreCase)) {throw 'VM TESTE and isolated lab root required.'}
$root=$PSScriptRoot;$evidence=Join-Path $root 'evidence'
. (Join-Path $root 'EdgeVmEvidence.ps1')
. (Join-Path $root 'EdgeVmBatch.ps1')
$definition=Get-WinSlimEdgeVmBatch $Batch
[void][IO.Directory]::CreateDirectory($evidence)
function Save-Evidence([string]$Name,$Data) {ConvertTo-Json -InputObject $Data -Depth 40 | Set-Content -LiteralPath (Join-Path $evidence $Name) -Encoding UTF8}
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $admin) {
    Save-Evidence 'status.json' @{Status='WaitingForUac';PolicyWrites=0;Elevated=$false;Utc=[DateTime]::UtcNow.ToString('o')}
    try {Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Batch '+$Batch) -WindowStyle Hidden | Out-Null}
    catch {Save-Evidence 'status.json' @{Status='UacUnavailableOrCancelled';PolicyWrites=0;Elevated=$false;Error=$_.Exception.Message}}
    return
}
$summary=[ordered]@{Status='Running';Elevated=$admin;Computer=$env:COMPUTERNAME;Model=$computer.Model;Session=(Get-Process -Id $PID).SessionId;ApplyVerified=$false;UndoVerified=$false;UndoExact=$false;PolicyUi='pending';AffectedHelpersExecuted=$false;FullGate='blocked';ProductionApproved=$false;Errors=@()}
Save-Evidence 'status.json' $summary
Save-Evidence 'batch.json' $definition
$script:cdp=$null;$script:commandId=0;$port=19284
function Send-Cdp([string]$Method,$Parameters) {
    $script:commandId++;$id=$script:commandId
    $message=@{id=$id;method=$Method;params=$Parameters} | ConvertTo-Json -Depth 15 -Compress
    $bytes=[Text.Encoding]::UTF8.GetBytes($message)
    $timeout=New-Object Threading.CancellationTokenSource;$timeout.CancelAfter(15000)
    try {
        $script:cdp.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,$timeout.Token).GetAwaiter().GetResult()
        while($true) {
            $memory=New-Object IO.MemoryStream
            try {
                do {$buffer=New-Object byte[] 65536;$part=$script:cdp.ReceiveAsync([ArraySegment[byte]]::new($buffer),$timeout.Token).GetAwaiter().GetResult();$memory.Write($buffer,0,$part.Count)} while(-not $part.EndOfMessage)
                $reply=[Text.Encoding]::UTF8.GetString($memory.ToArray()) | ConvertFrom-Json
            } finally {$memory.Dispose()}
            if($reply.id -eq $id) {if($reply.error){throw ($reply.error | ConvertTo-Json -Compress)};return $reply.result}
        }
    } finally {$timeout.Dispose()}
}
function Open-PolicyBrowser {
    $edge=@('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe') | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
    if(-not $edge){throw 'Edge Stable missing.'}
    $script:edgeVersion=(Get-Item -LiteralPath $edge).VersionInfo.ProductVersion
    $profile=Join-Path $root 'EdgeAcceptanceProfile'
    Start-Process -FilePath $edge -ArgumentList ('--user-data-dir="'+$profile+'" --no-first-run --remote-debugging-address=127.0.0.1 --remote-debugging-port='+$port+' --new-window edge://policy') | Out-Null
    $target=$null
    for($i=0;$i -lt 30;$i++) {
        try {$list=Invoke-WebRequest -UseBasicParsing -Uri ('http://127.0.0.1:'+$port+'/json/list') -TimeoutSec 2;$target=Get-WinSlimEdgeCdpPolicyTarget -Json $list.Content -Port $port;if($target){break}} catch {}
        Start-Sleep -Milliseconds 500
    }
    if(-not $target){throw 'Isolated Edge policy page / loopback CDP unavailable.'}
    $script:cdp=New-Object Net.WebSockets.ClientWebSocket
    $script:cdp.ConnectAsync([Uri]$target.webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    Send-Cdp 'Runtime.enable' @{} | Out-Null
    Send-Cdp 'Page.navigate' @{url='edge://policy/'} | Out-Null
    Start-Sleep -Seconds 2
}
function Capture-Policy([string]$Stage) {
    $expression=@'
(()=>{const roots=[];function scan(r){roots.push(r);for(const e of r.querySelectorAll('*'))if(e.shadowRoot)scan(e.shadowRoot)}scan(document);
return {url:location.href,title:document.title,text:roots.map(r=>r.innerText||r.textContent||'').join('\n'),
 rows:roots.flatMap(r=>Array.from(r.querySelectorAll('policy-row,policy-table')).map(e=>({tag:e.tagName,keys:Object.keys(e),data:e.policy||e.policies||e.policyValues||null,text:e.shadowRoot?(e.shadowRoot.innerText||e.shadowRoot.textContent):e.innerText}))),
 buttons:roots.flatMap(r=>Array.from(r.querySelectorAll('button')).map(e=>({id:e.id,text:e.innerText})))}})()
'@
    $read=Send-Cdp 'Runtime.evaluate' @{expression=$expression;returnByValue=$true;awaitPromise=$true}
    if($read.exceptionDetails){throw ('Policy DOM read failed: '+($read.exceptionDetails | ConvertTo-Json -Compress))}
    if($read.result.value.url -notmatch '^edge://policy/?$'){throw 'Real policy page did not load; no acceptance inferred.'}
    Save-Evidence ($Stage+'-edge-policy.json') $read.result.value
    $image=Send-Cdp 'Page.captureScreenshot' @{format='png';captureBeyondViewport=$true}
    [IO.File]::WriteAllBytes((Join-Path $evidence ($Stage+'-edge-policy.png')),[Convert]::FromBase64String($image.data))
}
function Close-PolicyBrowser {
    if($script:cdp){try {Send-Cdp 'Browser.close' @{} | Out-Null} catch {}; $script:cdp.Dispose();$script:cdp=$null;Start-Sleep -Seconds 2}
}
$apply=$null;$before=$null;$targets=$null
try {
    # This library path has no PresentMon/Monitor test launcher. No gate/build entry point is called.
    . (Join-Path $root 'src/UI/Native/R3_2_84/WinSlim.UiBridge.ps1') -LibraryOnly -RootPath $root
    Save-Evidence 'handshake.json' (Invoke-WinSlimBridgeAction -Name handshake)
    $ids=@($definition.Ids)
    $selectedIds=if($definition.PSObject.Properties.Name -contains 'SelectedIds'){@($definition.SelectedIds)}else{$ids}
    $request=[pscustomobject]@{selectedIds=$selectedIds;customName='Aceite Edge isolado VM';levelSelections=[pscustomobject]@{}}
    $report=Get-WinSlimCustomValidationReport $request
    Save-Evidence 'planner.json' $report
    $preview=Get-WinSlimBridgePreview -Request $request -CustomReport $report
    Save-Evidence 'live-preview.json' $preview
    $authorization=New-WinSlimRegistryApplyPreview ([pscustomobject]@{previewToken=$preview.registryPreviewToken})
    Save-Evidence 'apply-review.json' $authorization
    if($authorization.count -ne $ids.Count -or $authorization.tweakCount -ne $ids.Count -or @($authorization.excluded).Count -ne 0){throw 'Exactly the reviewed batch targets required.'}
    $targets=@($authorization.items)
    $before=@(foreach($t in $targets){[pscustomobject]@{Id=$t.TweakId;Name=$t.Name;State=(Read-WinSlimRestoreTarget $t)}})
    Save-Evidence 'original-values.json' $before
    Open-PolicyBrowser;Capture-Policy 'before';Close-PolicyBrowser
    $apply=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$authorization.token})
    Save-Evidence 'apply-result.json' $apply
    $summary.ApplyVerified=[bool]$apply.verified
    if(-not $apply.verified){throw 'Apply/Verify did not complete.'}
    $summary.BackupId=$apply.backupId
    $backup=Read-WinSlimVerifiedBackup (Join-Path (Join-Path $root 'Backups/UI') $apply.backupId)
    Save-Evidence 'backup-verification.json' $backup
    if(-not $backup.Verified -or $backup.Snapshot.CapturedCount -ne $ids.Count){throw 'Verified backup missing.'}
    Save-Evidence 'applied-values.json' @(foreach($t in $targets){[pscustomobject]@{Id=$t.TweakId;Name=$t.Name;State=(Read-WinSlimRestoreTarget $t)}})
    Open-PolicyBrowser;Capture-Policy 'applied';Close-PolicyBrowser
    $summary.EdgeVersion=$script:edgeVersion
    $summary.PolicyUi='Captured real edge://policy before/applied; inspect statuses separately from registry Verify'
} catch {$summary.Errors+=($_.Exception.Message);Save-Evidence 'failure.json' @{Error=$_.Exception.ToString();Position=$_.InvocationInfo.PositionMessage;Stack=$_.ScriptStackTrace}}
finally {
    Close-PolicyBrowser
    if($apply -and $apply.backupId) {
        try {
            $review=New-WinSlimRestorePreview ([pscustomobject]@{backupId=$apply.backupId})
            Save-Evidence 'undo-review.json' $review
            $undo=Invoke-WinSlimBackupRestore ([pscustomobject]@{backupId=$apply.backupId;token=$review.token})
            Save-Evidence 'undo-result.json' $undo
            $summary.UndoVerified=[bool]$undo.verified
            $restored=@(foreach($t in $targets){[pscustomobject]@{Id=$t.TweakId;Name=$t.Name;State=(Read-WinSlimRestoreTarget $t)}})
            Save-Evidence 'restored-values.json' $restored
            $same=$true
            for($i=0;$i -lt $before.Count;$i++){if(-not (Test-WinSlimRestoreEqual $before[$i].State $restored[$i].State)){$same=$false}}
            $summary.UndoExact=$same -and $summary.UndoVerified
            if(-not $summary.UndoExact){throw 'Exact original value presence/type/data not restored.'}
            Open-PolicyBrowser;Capture-Policy 'restored';Close-PolicyBrowser
        } catch {$summary.Errors+=('Undo/evidence: '+$_.Exception.Message)}
    }
    $summary.Status=if($summary.Errors.Count -eq 0 -and $summary.UndoExact){'Completed'}else{'FailedOrBlocked'}
    Save-Evidence 'status.json' $summary
    Save-Evidence 'file-hashes.json' @(Get-ChildItem -LiteralPath $evidence -File | Where-Object {$_.Name -ne 'file-hashes.json'} | ForEach-Object {[pscustomobject]@{Name=$_.Name;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
}

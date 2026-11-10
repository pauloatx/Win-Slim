#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Launch','RunPrepared','RetryUac','BrowserProbe','CloseFailedBrowser','Status','Collect')][string]$Phase='Status',
      [ValidatePattern('^edge-priority-[0-9a-f]{8}$')][string]$RunLeaf='edge-priority-dbd0a284',
      [ValidateSet('Privacy','Core','Next','Startup','Identity','Forms','Services','Diagnostics','Sleep')][string]$Batch='Privacy',
      [Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'EdgeVmEvidence.ps1')
. (Join-Path $PSScriptRoot 'EdgeVmBatch.ps1')
$definition=Get-WinSlimEdgeVmBatch $Batch
$out=[IO.Path]::GetFullPath($EvidenceDirectory)
if(-not $out.StartsWith($workspace.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Workspace evidence path required.'}
$payload=Join-Path $out $RunLeaf;$guest='C:\WinSlim\EdgeIsolated\'+$RunLeaf
$vm='teste win-slim-win11';$vbox=Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
function VBox([string[]]$Arguments) {
    $saved=$ErrorActionPreference
    try {$ErrorActionPreference='Continue';$data=@(& $vbox --nologo @Arguments 2>&1);$code=$LASTEXITCODE} finally {$ErrorActionPreference=$saved}
    if($code -ne 0){throw ('VBox operation failed '+$code+': '+(($data | ForEach-Object {[string]$_}) -join "`n"))}
    $data | ForEach-Object {[string]$_}
}
$info=@(VBox @('showvminfo',$vm,'--machinereadable'))
if($info -notcontains 'UUID="b71b4588-2e83-461c-9585-64ee77b9c851"' -or $info -notcontains 'VMState="running"'){throw 'Expected running lab VM required.'}
$cred=Import-Clixml -LiteralPath (Join-Path $env:LOCALAPPDATA 'WinSlim-Integracao\CredencialVM.xml')
$secret=Join-Path $out ('.guest-secret-'+[Guid]::NewGuid().ToString('N')+'.tmp');$bstr=[IntPtr]::Zero
try {
    [IO.File]::WriteAllText($secret,'')
    $acl=New-Object Security.AccessControl.FileSecurity;$acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))){$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')))}
    (Get-Item -LiteralPath $secret).SetAccessControl($acl)
    $bstr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password)
    [IO.File]::WriteAllText($secret,[Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr),(New-Object Text.UTF8Encoding($false)))
    function Guest([string]$Body) {
        $guard='$c=Get-CimInstance Win32_ComputerSystem;if($env:COMPUTERNAME -ine ''TESTE'' -or $c.Model -notmatch ''VirtualBox''){throw ''Wrong guest''};'
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('$ErrorActionPreference=''Stop'';'+$guard+$Body))
        VBox @('guestcontrol',$vm,'run','--exe=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',('--username='+$cred.UserName),('--passwordfile='+$secret),'--wait-stdout','--wait-stderr','--timeout=180000','--','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded)
    }
    if($Phase -in @('Launch','RunPrepared')) {
        $manifest=Get-Content -LiteralPath (Join-Path $payload 'payload-sha256.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach($file in Get-ChildItem -LiteralPath $payload -Recurse -File){
            if($file.Extension -notin @('.ps1','.json') -or $file.Name -match 'PresentMonHarness|MonitorHarness|Test-Fase7.*-(PresentMon|Monitor)\.ps1'){throw 'Forbidden payload file.'}
        }
        foreach($property in $manifest.PSObject.Properties){$file=Join-Path $payload $property.Name;if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $property.Value){throw 'Payload hash mismatch.'}}
        if($Phase -eq 'Launch') {
            Guest "if(Test-Path -LiteralPath '$guest'){throw 'Guest staging exists; preserve previous run'};[void][IO.Directory]::CreateDirectory('C:\WinSlim\EdgeIsolated')" | Out-Null
            VBox @('guestcontrol',$vm,'copyto',('--username='+$cred.UserName),('--passwordfile='+$secret),'--recursive',$payload,'C:\WinSlim\EdgeIsolated\') | Out-Null
        }
        Guest "`$m=Get-Content -LiteralPath '$guest\payload-sha256.json' -Raw -Encoding UTF8 | ConvertFrom-Json;foreach(`$p in `$m.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path '$guest' `$p.Name) -Algorithm SHA256).Hash -ine `$p.Value){throw 'Guest payload mismatch'}};if(Test-Path -LiteralPath '$guest\evidence\status.json'){throw 'Real test already requested; preserve state and inspect status'}" | Out-Null
        # Isolated fixtures first. They override registry I/O; this is never real acceptance.
        $fixtureArguments=if($definition.Fixture -eq 'Test-Fase7-R3.2.84-EdgeCompletion.ps1'){' -Batch '+$Batch}else{''}
        $fixture=Guest "& '$guest\tests\$($definition.Fixture)' -Root '$guest'$fixtureArguments;if(`$LASTEXITCODE -ne 0 -and `$null -ne `$LASTEXITCODE){exit `$LASTEXITCODE}"
        $fixture | Set-Content -LiteralPath (Join-Path $out ($Batch.ToLowerInvariant()+'-fixtures.log')) -Encoding UTF8
        $launch="Start-Process -FilePath (Join-Path `$PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File $guest\Test-WinSlimEdgeRealVm.ps1 -Batch $Batch' | Out-Null;Write-Output 'EDGE_ONLY_UAC_REQUEST_STARTED'"
        Guest $launch
    } elseif($Phase -eq 'RetryUac') {
        Guest "`$p='$guest\evidence\status.json';`$s=Get-Content -LiteralPath `$p -Raw -Encoding UTF8 | ConvertFrom-Json;if(`$s.Status -ne 'UacUnavailableOrCancelled' -or `$s.PolicyWrites -ne 0 -or `$s.Elevated -ne `$false -or (Test-Path -LiteralPath '$guest\Backups')){throw 'Retry allowed only after cancelled UAC with no writes or backup'};Move-Item -LiteralPath `$p -Destination ('$guest\evidence\uac-cancelled-'+[DateTime]::UtcNow.ToString('HHmmssfff')+'.json');Start-Process -FilePath (Join-Path `$PSHOME 'powershell.exe') -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File $guest\Test-WinSlimEdgeRealVm.ps1 -Batch $Batch' | Out-Null;Write-Output 'UAC_REOPENED_NO_PREVIOUS_POLICY_WRITES'"
    } elseif($Phase -eq 'CloseFailedBrowser') {
        $body=@'
$s=Get-Content -LiteralPath '__ROOT__\evidence\status.json' -Raw -Encoding UTF8 | ConvertFrom-Json
if($s.Status -ne 'FailedOrBlocked' -or $s.ApplyVerified){throw 'Only a failed pre-Apply browser may be closed here.'}
$connection=Get-NetTCPConnection -LocalPort 19284 -State Listen -ErrorAction Stop | Select-Object -First 1
$owner=Get-CimInstance Win32_Process -Filter ('ProcessId='+$connection.OwningProcess)
if($owner.Name -ne 'msedge.exe' -or $owner.CommandLine -notlike '*__ROOT__\EdgeAcceptanceProfile*'){throw 'Endpoint belongs to another browser.'}
$version=Invoke-RestMethod http://127.0.0.1:19284/json/version
$socket=New-Object Net.WebSockets.ClientWebSocket
try {$socket.ConnectAsync([Uri]$version.webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult();$bytes=[Text.Encoding]::UTF8.GetBytes('{"id":1,"method":"Browser.close"}');$socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult();Write-Output 'OWN_FAILED_TEST_BROWSER_CLOSE_REQUESTED'}finally{$socket.Dispose()}
'@
        Guest ($body.Replace('__ROOT__',$guest))
    } elseif($Phase -eq 'BrowserProbe') {
        $body=@'
$result=[ordered]@{Version=$null;Targets=$null;Errors=@();Ports=@();Processes=@()}
try {$result.Version=Invoke-RestMethod -Uri http://127.0.0.1:19284/json/version -TimeoutSec 3} catch {$result.Errors+=$_.Exception.Message}
try {$result.Targets=Invoke-RestMethod -Uri http://127.0.0.1:19284/json/list -TimeoutSec 3} catch {$result.Errors+=$_.Exception.Message}
$result.Ports=@(Get-NetTCPConnection -LocalPort 19284 -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,State,OwningProcess)
$result.Processes=@(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -Property ProcessId,SessionId,CommandLine | Select-Object ProcessId,SessionId,CommandLine)
$result | ConvertTo-Json -Depth 8
'@
        $data=Guest $body
        $data | Set-Content -LiteralPath (Join-Path $out ('browser-probe-'+[DateTime]::UtcNow.ToString('HHmmssfff')+'.json')) -Encoding UTF8
        $data
    } elseif($Phase -eq 'Status') {
        $body="`$p='$guest\evidence\status.json';if(Test-Path -LiteralPath `$p){Get-Content -LiteralPath `$p -Raw -Encoding UTF8}else{[pscustomobject]@{Status='NoStatus'} | ConvertTo-Json}"
        $status=Guest $body
        $status | Set-Content -LiteralPath (Join-Path $out ('guest-status-'+[DateTime]::UtcNow.ToString('HHmmssfff')+'.json')) -Encoding UTF8
        $status
    } else {
        $leaf='collection-'+[DateTime]::UtcNow.ToString('HHmmssfff');$destination=Join-Path $out $leaf
        [void][IO.Directory]::CreateDirectory($destination)
        $inventory=Guest "`$dirs=@('$guest\evidence','$guest\Backups');@(foreach(`$d in `$dirs){if(Test-Path -LiteralPath `$d){Get-ChildItem -LiteralPath `$d -Recurse -File | ForEach-Object {[pscustomobject]@{Path=`$_.FullName;SHA256=(Get-FileHash -LiteralPath `$_.FullName -Algorithm SHA256).Hash}}}}) | ConvertTo-Json -Depth 4"
        $inventory -join "`n" | Set-Content -LiteralPath (Join-Path $destination 'guest-file-inventory.json') -Encoding UTF8
        $files=@(ConvertFrom-WinSlimEdgeVmInventory -Text ($inventory -join "`n") -GuestRoot $guest)
        if($files.Count -eq 0){throw 'No guest evidence to collect.'}
        foreach($dir in @('evidence','Backups')) {
            if(@(Get-WinSlimEdgeVmDirectoryFiles -Files $files -GuestRoot $guest -Directory $dir).Count -gt 0){
                VBox @('guestcontrol',$vm,'copyfrom',('--username='+$cred.UserName),('--passwordfile='+$secret),'--recursive',($guest+'\'+$dir),($destination+'\')) | Out-Null
            }
        }
        foreach($entry in $files){$relative=$entry.Path.Substring($guest.Length+1);$copied=Join-Path $destination $relative;if(-not (Test-Path -LiteralPath $copied) -or (Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash -ine $entry.SHA256){throw ('Evidence missing/mismatch: '+$relative)}}
        @{Collected=$true;Files=$files.Count;HashesVerified=$true;Guest=$guest;Utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'collection-receipt.json') -Encoding UTF8
        Write-Output ('Evidence collected and hashes verified: '+$destination)
    }
} finally {
    if($bstr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)}
    if(Test-Path -LiteralPath $secret){Remove-Item -LiteralPath $secret -Force}
}

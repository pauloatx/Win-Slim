#requires -Version 5.1
# Read-only guest inspection. Does not apply policies or restore a snapshot.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$vm='teste win-slim-win11'
$vbox=Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
$vmId='b71b4588-2e83-461c-9585-64ee77b9c851'
function VBox([string[]]$Arguments) {
    $saved=$ErrorActionPreference
    try { $ErrorActionPreference='Continue';$data=@(& $vbox --nologo @Arguments 2>&1);$code=$LASTEXITCODE }
    finally { $ErrorActionPreference=$saved }
    if($code -ne 0) { throw ('VBox command failed, exit '+$code+': '+(($data | ForEach-Object {[string]$_}) -join "`n")) }
    $data | ForEach-Object {[string]$_}
}
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
$workspace=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if(-not $evidence.StartsWith($workspace.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must remain in workspace.' }
[void][IO.Directory]::CreateDirectory($evidence)
$info=@(VBox @('showvminfo',$vm,'--machinereadable'))
if($info -notcontains ('UUID="'+$vmId+'"')) { throw 'Unexpected VM identity.' }
$info | Set-Content -LiteralPath (Join-Path $evidence 'vm-before.txt') -Encoding UTF8
if($info -contains 'VMState="poweroff"') { VBox @('startvm',$vm,'--type=gui') | Out-Null }
elseif($info -notcontains 'VMState="running"') { throw 'VM must be stopped or running; saved state is not accepted.' }
$cred=Import-Clixml -LiteralPath (Join-Path $env:LOCALAPPDATA 'WinSlim-Integracao\CredencialVM.xml')
$secret=Join-Path $evidence ('.guest-secret-'+[Guid]::NewGuid().ToString('N')+'.tmp')
$bstr=[IntPtr]::Zero
try {
    [IO.File]::WriteAllText($secret,'')
    $acl=New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')))
    }
    (Get-Item -LiteralPath $secret).SetAccessControl($acl)
    $bstr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password)
    [IO.File]::WriteAllText($secret,[Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr),(New-Object Text.UTF8Encoding($false)))
    $probe=@'
$ErrorActionPreference='Stop'
$computer=Get-CimInstance Win32_ComputerSystem
if($env:COMPUTERNAME -ine 'TESTE' -or $computer.Model -notmatch 'VirtualBox'){throw 'Wrong guest.'}
$elevated=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$task=$null;$taskError=$null
try {$task=Get-ScheduledTask -TaskName WinSlimLabElevado -ErrorAction Stop} catch {$taskError=[pscustomobject]@{Message=$_.Exception.Message;Id=$_.FullyQualifiedErrorId}}
$edge=@('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe') | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
$policies=@(foreach($hive in @('LocalMachine','CurrentUser')){foreach($view in @('Registry64','Registry32')){
    $base=$null;$key=$null
    try {
        $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]([Enum]::Parse([Microsoft.Win32.RegistryHive],$hive)),[Microsoft.Win32.RegistryView]([Enum]::Parse([Microsoft.Win32.RegistryView],$view)))
        $key=$base.OpenSubKey('SOFTWARE\Policies\Microsoft\Edge',$false)
        [pscustomobject]@{Hive=$hive;View=$view;KeyExists=($null -ne $key);Values=@(if($key){foreach($name in $key.GetValueNames()){[pscustomobject]@{Name=$name;Kind=[string]$key.GetValueKind($name);Value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}}});SubKeys=@(if($key){$key.GetSubKeyNames()})}
    } catch {[pscustomobject]@{Hive=$hive;View=$view;Error=$_.Exception.Message}}
    finally {if($key){$key.Dispose()};if($base){$base.Dispose()}}
}})
[pscustomobject]@{Computer=$env:COMPUTERNAME;Model=$computer.Model;PartOfDomain=$computer.PartOfDomain;Elevated=$elevated;SessionId=(Get-Process -Id $PID).SessionId;EdgePath=$edge;EdgeVersion=$(if($edge){(Get-Item -LiteralPath $edge).VersionInfo.ProductVersion});ElevatedTaskExists=($null -ne $task);ElevatedTaskQueryError=$taskError;TaskPrincipal=$(if($task){$task.Principal | Select-Object UserId,LogonType,RunLevel});TaskActions=$(if($task){$task.Actions | Select-Object Execute,Arguments,WorkingDirectory});Policies=$policies;GuestDesktopProcesses=@(Get-Process explorer,msedge -ErrorAction SilentlyContinue | Select-Object ProcessName,Id,SessionId)} | ConvertTo-Json -Depth 8
'@
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))
    $ready=$false
    for($attempt=0;$attempt -lt 12;$attempt++) {
        try {
            $output=@(VBox @('guestcontrol',$vm,'run','--exe=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',('--username='+$cred.UserName),('--passwordfile='+$secret),'--wait-stdout','--wait-stderr','--timeout=15000','--','-NoProfile','-NonInteractive','-EncodedCommand',$encoded))
            $json=$output -join "`n";$null=$json | ConvertFrom-Json
            $json | Set-Content -LiteralPath (Join-Path $evidence 'guest-probe.json') -Encoding UTF8
            Write-Output $json;$ready=$true;break
        } catch { Write-Output ('Guest not ready, attempt '+($attempt+1));Start-Sleep -Seconds 3 }
    }
    if(-not $ready) { throw 'Guest inspection unavailable. No policy write attempted.' }
} finally {
    if($bstr -ne [IntPtr]::Zero) {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)}
    if(Test-Path -LiteralPath $secret) {Remove-Item -LiteralPath $secret -Force}
}

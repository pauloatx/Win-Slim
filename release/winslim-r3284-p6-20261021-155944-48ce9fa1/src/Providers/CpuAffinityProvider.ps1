# Win-Slim Suite - FASE 5 R2
# Afinidade de CPU baseada em topologia real (GetLogicalProcessorInformationEx).
# Politica Seal recuperada: P-core = EfficiencyClass >= 1.
# Win-Slim adiciona guardas: exige topologia hibrida distinguivel, um unico
# processor group e mascara que caiba com seguranca em IntPtr/ProcessorAffinity.

function Initialize-WinSlimCpuTopologyNative {
    if ('WinSlim.CpuTopologyNative' -as [type]) { return }

    $src = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WinSlim
{
    public sealed class CpuCoreInfo
    {
        public byte EfficiencyClass { get; set; }
        public ushort Group { get; set; }
        public ulong Mask { get; set; }
    }

    public static class CpuTopologyNative
    {
        private enum LOGICAL_PROCESSOR_RELATIONSHIP
        {
            RelationProcessorCore = 0
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetLogicalProcessorInformationEx(
            LOGICAL_PROCESSOR_RELATIONSHIP RelationshipType,
            IntPtr Buffer,
            ref uint ReturnedLength);

        public static CpuCoreInfo[] GetCores()
        {
            uint length = 0;
            GetLogicalProcessorInformationEx(LOGICAL_PROCESSOR_RELATIONSHIP.RelationProcessorCore, IntPtr.Zero, ref length);
            int err = Marshal.GetLastWin32Error();
            if (length == 0)
                throw new Win32Exception(err == 0 ? 122 : err);

            IntPtr buffer = Marshal.AllocHGlobal((int)length);
            try
            {
                if (!GetLogicalProcessorInformationEx(LOGICAL_PROCESSOR_RELATIONSHIP.RelationProcessorCore, buffer, ref length))
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                var result = new List<CpuCoreInfo>();
                long offset = 0;
                while (offset < length)
                {
                    IntPtr cur = new IntPtr(buffer.ToInt64() + offset);
                    int relationship = Marshal.ReadInt32(cur, 0);
                    int size = Marshal.ReadInt32(cur, 4);
                    if (size <= 0) break;

                    if (relationship == 0)
                    {
                        int pr = 8; // payload PROCESSOR_RELATIONSHIP after EX header
                        byte efficiencyClass = Marshal.ReadByte(cur, pr + 1);
                        ushort groupCount = unchecked((ushort)Marshal.ReadInt16(cur, pr + 22));
                        int gaOffset = pr + 24;
                        int gaSize = IntPtr.Size == 8 ? 16 : 12;

                        for (int i = 0; i < groupCount; i++)
                        {
                            int o = gaOffset + (i * gaSize);
                            ulong mask = IntPtr.Size == 8
                                ? unchecked((ulong)Marshal.ReadInt64(cur, o))
                                : unchecked((uint)Marshal.ReadInt32(cur, o));
                            ushort group = unchecked((ushort)Marshal.ReadInt16(cur, o + IntPtr.Size));
                            result.Add(new CpuCoreInfo { EfficiencyClass = efficiencyClass, Group = group, Mask = mask });
                        }
                    }
                    offset += size;
                }
                return result.ToArray();
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
    }
}
'@
    Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
}

function Get-WinSlimBitCount64 {
    param([UInt64]$Value)
    $count = 0
    $v = [UInt64]$Value
    while ($v -ne 0) {
        if (($v -band [UInt64]1) -ne 0) { $count++ }
        $v = $v -shr 1
    }
    return $count
}

function Get-WinSlimProcessorTopology {
    Initialize-WinSlimCpuTopologyNative
    $native = @([WinSlim.CpuTopologyNative]::GetCores())
    $cores = @()
    foreach ($c in $native) {
        $cores += [PSCustomObject]@{
            EfficiencyClass = [int]$c.EfficiencyClass
            Group = [int]$c.Group
            Mask = [UInt64]$c.Mask
            LogicalCount = Get-WinSlimBitCount64 -Value ([UInt64]$c.Mask)
        }
    }

    $groups = @($cores | Select-Object -ExpandProperty Group -Unique | Sort-Object)
    $classes = @($cores | Select-Object -ExpandProperty EfficiencyClass -Unique | Sort-Object)
    $logical = 0
    foreach ($c in $cores) { $logical += [int]$c.LogicalCount }
    $hasPerf = @($cores | Where-Object { [int]$_.EfficiencyClass -ge 1 }).Count -gt 0
    $hasEff  = @($cores | Where-Object { [int]$_.EfficiencyClass -lt 1 }).Count -gt 0
    $isHybrid = $hasPerf -and $hasEff -and $classes.Count -gt 1

    return [PSCustomObject]@{
        Cores = @($cores)
        Groups = @($groups)
        EfficiencyClasses = @($classes)
        LogicalProcessorCount = $logical
        PhysicalCoreEntries = @($cores).Count
        IsHybrid = [bool]$isHybrid
        SingleProcessorGroup = [bool]($groups.Count -eq 1)
        Api = 'GetLogicalProcessorInformationEx(RelationProcessorCore)'
    }
}

function Get-WinSlimPCoreMaskFromTopology {
    param([Parameter(Mandatory)]$Topology)

    $cores = @($Topology.Cores)
    $groups = @($Topology.Groups)
    if ($groups.Count -eq 0) { $groups = @($cores | Select-Object -ExpandProperty Group -Unique | Sort-Object) }
    $logical = if ($Topology.PSObject.Properties.Name -contains 'LogicalProcessorCount') { [int]$Topology.LogicalProcessorCount } else {
        $n=0; foreach($c in $cores){ $n += Get-WinSlimBitCount64 ([UInt64]$c.Mask) }; $n
    }
    $classes = @($cores | Select-Object -ExpandProperty EfficiencyClass -Unique | Sort-Object)
    $perf = @($cores | Where-Object { [int]$_.EfficiencyClass -ge 1 })
    $eff  = @($cores | Where-Object { [int]$_.EfficiencyClass -lt 1 })

    if ($groups.Count -ne 1) {
        return [PSCustomObject]@{ Applicable=$false; Mask=[UInt64]0; MaskHex='0x0'; Reason='Mais de um processor group detectado; ProcessorAffinity simples nao e seguro.'; PCoreCount=0; LogicalProcessorCount=$logical }
    }
    if ($classes.Count -lt 2 -or $perf.Count -eq 0 -or $eff.Count -eq 0) {
        return [PSCustomObject]@{ Applicable=$false; Mask=[UInt64]0; MaskHex='0x0'; Reason='EfficiencyClass nao distingue P-cores e E-cores com confianca.'; PCoreCount=0; LogicalProcessorCount=$logical }
    }
    # Guardrail: [Diagnostics.Process]::ProcessorAffinity usa IntPtr. Evitamos
    # bit 63 / mascaras multi-group para nao depender de conversao signed.
    if ($logical -gt 63) {
        return [PSCustomObject]@{ Applicable=$false; Mask=[UInt64]0; MaskHex='0x0'; Reason='Mais de 63 processadores logicos; caminho IntPtr simples nao e seguro.'; PCoreCount=0; LogicalProcessorCount=$logical }
    }

    [UInt64]$mask = 0
    foreach ($c in $perf) { $mask = $mask -bor [UInt64]$c.Mask }
    if ($mask -eq 0) {
        return [PSCustomObject]@{ Applicable=$false; Mask=[UInt64]0; MaskHex='0x0'; Reason='Mascara P-core calculada ficou vazia.'; PCoreCount=0; LogicalProcessorCount=$logical }
    }
    return [PSCustomObject]@{
        Applicable=$true
        Mask=$mask
        MaskHex=('0x{0:X}' -f $mask)
        Reason=$null
        PCoreCount=$perf.Count
        LogicalProcessorCount=$logical
        EfficiencyRule='EfficiencyClass >= 1'
    }
}

function Get-WinSlimLowestSetBitMask {
    param([UInt64]$Mask)
    if ($Mask -eq 0) { return [UInt64]0 }
    [UInt64]$bit = 1
    for ($i=0; $i -lt 63; $i++) {
        if (($Mask -band $bit) -ne 0) { return $bit }
        $bit = $bit -shl 1
    }
    return [UInt64]0
}

function Get-WinSlimSuggestedGpuInterruptMask {
    <#
      Politica Win-Slim: escolher UM processador logico representativo de
      dois nucleos fisicos distintos. Em CPU hibrida, prefere P-cores
      (EfficiencyClass >= 1). Evita CPU0 quando ha pelo menos 3 candidatos.
      Em um layout SMT comum 0x3,0xC,0x30,... resulta em 0x14, coincidindo
      com a mascara referência técnica observada sem hardcode-la.
    #>
    param([Parameter(Mandatory)]$Topology)
    $cores = @($Topology.Cores)
    $groups = @($Topology.Groups)
    if ($groups.Count -eq 0) { $groups = @($cores | Select-Object -ExpandProperty Group -Unique | Sort-Object) }
    $logical = if ($Topology.PSObject.Properties.Name -contains 'LogicalProcessorCount') { [int]$Topology.LogicalProcessorCount } else { 0 }
    if ($groups.Count -ne 1) { return [PSCustomObject]@{ Applicable=$false; Mask=[UInt64]0; Bytes=$null; Reason='Mais de um processor group.' } }
    if ($logical -lt 8) { return [PSCustomObject]@{ Applicable=$false; Mask=[UInt64]0; Bytes=$null; Reason='Menos de 8 processadores logicos.' } }
    if ($logical -gt 63) { return [PSCustomObject]@{ Applicable=$false; Mask=[UInt64]0; Bytes=$null; Reason='Mais de 63 processadores logicos no caminho de afinidade atual.' } }

    $perf = @($cores | Where-Object { [int]$_.EfficiencyClass -ge 1 })
    $eff  = @($cores | Where-Object { [int]$_.EfficiencyClass -lt 1 })
    $eligible = if ($perf.Count -gt 0 -and $eff.Count -gt 0) { $perf } else { $cores }
    $bits = @()
    foreach ($c in $eligible) {
        $b = Get-WinSlimLowestSetBitMask -Mask ([UInt64]$c.Mask)
        if ($b -ne 0 -and $bits -notcontains $b) { $bits += [UInt64]$b }
    }
    if ($bits.Count -lt 2) { return [PSCustomObject]@{ Applicable=$false; Mask=[UInt64]0; Bytes=$null; Reason='Menos de dois nucleos fisicos elegiveis.' } }
    if ($bits.Count -ge 3 -and $bits[0] -eq [UInt64]1) { $bits = @($bits | Select-Object -Skip 1) }
    [UInt64]$mask = ([UInt64]$bits[0]) -bor ([UInt64]$bits[1])
    return [PSCustomObject]@{
        Applicable=$true; Mask=$mask; MaskHex=('0x{0:X}' -f $mask)
        Bytes=[BitConverter]::GetBytes($mask); SelectedBits=@([UInt64]$bits[0],[UInt64]$bits[1])
        Reason=$null; Policy='TwoPhysicalCoreRepresentatives'
    }
}

function New-CpuAffinityTaskXml {
    param([Parameter(Mandatory)][string]$ScriptPath)
    $escapedPath = [Security.SecurityElement]::Escape($ScriptPath)
    $args = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File &quot;$escapedPath&quot;"
    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Win-Slim Suite - aplica afinidade P-core ao CS2 quando o processo existir.</Description></RegistrationInfo>
  <Triggers><LogonTrigger><Enabled>true</Enabled><Repetition><Interval>PT1M</Interval><Duration>P3650D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition></LogonTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><LogonType>ServiceAccount</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><AllowHardTerminate>true</AllowHardTerminate><StartWhenAvailable>true</StartWhenAvailable><RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable><IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings><AllowStartOnDemand>true</AllowStartOnDemand><Enabled>true</Enabled><Hidden>true</Hidden><RunOnlyIfIdle>false</RunOnlyIfIdle><WakeToRun>false</WakeToRun><ExecutionTimeLimit>PT1M</ExecutionTimeLimit><Priority>7</Priority></Settings>
  <Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>$args</Arguments></Exec></Actions>
</Task>
"@
}

function New-CpuAffinityWorkerScript {
    param([Parameter(Mandatory)][UInt64]$Mask, [string]$ProcessName='cs2.exe')
    $base = [IO.Path]::GetFileNameWithoutExtension($ProcessName)
    return @"
# Win-Slim Suite generated worker - FASE 5 R2
`$mask = [Int64]$Mask
Get-Process -Name '$base' -ErrorAction SilentlyContinue | ForEach-Object {
    try { `$_.ProcessorAffinity = [IntPtr]`$mask } catch { }
}
"@
}

function New-CpuAffinityWindowsAdapter {
    return [PSCustomObject]@{
        GetTaskState = {
            param($TaskName)
            if (Get-Command Get-ScheduledTaskState -ErrorAction SilentlyContinue) { return Get-ScheduledTaskState -TaskName $TaskName -TaskPath '\' }
            $t = Get-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction SilentlyContinue
            if (-not $t) { return [PSCustomObject]@{ TaskName=$TaskName; TaskPath='\'; Exists=$false; State=$null; Xml=$null } }
            $xml=$null; try { $xml=Export-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction Stop } catch { }
            return [PSCustomObject]@{ TaskName=$TaskName; TaskPath='\'; Exists=$true; State=$t.State.ToString(); Xml=$xml }
        }
        RegisterTask = {
            param($TaskName,$Xml)
            Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -Xml $Xml -Force -ErrorAction Stop | Out-Null
        }
        RestoreTask = {
            param($State)
            $now = Get-ScheduledTask -TaskName $State.TaskName -TaskPath $State.TaskPath -ErrorAction SilentlyContinue
            if (-not $State.Exists) {
                if ($now) { Unregister-ScheduledTask -TaskName $State.TaskName -TaskPath $State.TaskPath -Confirm:$false -ErrorAction Stop }
            } else {
                if (-not $State.Xml) { throw 'XML original da tarefa nao foi preservado.' }
                Register-ScheduledTask -TaskName $State.TaskName -TaskPath $State.TaskPath -Xml $State.Xml -Force -ErrorAction Stop | Out-Null
            }
        }
        GetFileState = {
            param($Path)
            if (-not (Test-Path -LiteralPath $Path)) { return [PSCustomObject]@{ Path=$Path; Exists=$false; Bytes=$null } }
            return [PSCustomObject]@{ Path=$Path; Exists=$true; Bytes=[IO.File]::ReadAllBytes($Path) }
        }
        WriteFile = {
            param($Path,$Text)
            $dir=Split-Path -Parent $Path; if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
            [IO.File]::WriteAllText($Path,[string]$Text,(New-Object Text.UTF8Encoding($false)))
        }
        RestoreFile = {
            param($State)
            if ($State.Exists) {
                $dir=Split-Path -Parent $State.Path; if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
                [IO.File]::WriteAllBytes($State.Path,[byte[]]$State.Bytes)
            } elseif (Test-Path -LiteralPath $State.Path) { Remove-Item -LiteralPath $State.Path -Force -ErrorAction Stop }
        }
        GetProcesses = {
            param($ProcessName)
            $base=[IO.Path]::GetFileNameWithoutExtension($ProcessName)
            $list=@()
            foreach($p in @(Get-Process -Name $base -ErrorAction SilentlyContinue)) {
                try { $list += [PSCustomObject]@{ Id=[int]$p.Id; Affinity=[Int64]$p.ProcessorAffinity.ToInt64() } } catch { }
            }
            return @($list)
        }
        SetProcessAffinity = {
            param($ProcessId,$Mask)
            $p=Get-Process -Id ([int]$ProcessId) -ErrorAction SilentlyContinue
            if ($p) { $p.ProcessorAffinity=[IntPtr]([Int64]$Mask) }
        }
    }
}

function Invoke-CpuAffinityProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [ValidateSet('Apply','Undo')][string]$Action='Apply',
        [string]$ProcessName='cs2.exe',
        [string]$TaskName='WinSlimSuite-AffinityCs2',
        [string]$ScriptPath="$env:ProgramData\WinSlimSuite\Tasks\affinity-cs2.ps1",
        $Topology=$null,
        $Adapter=$null,
        $BackupData=$null
    )

    if (-not $Adapter) { $Adapter=New-CpuAffinityWindowsAdapter }
    $errorMsg=$null; $warningMsg=$null; $changed=$false; $referenceState=$null; $after=$null

    try {
        if ($Action -eq 'Apply') {
            if (-not $Topology) { $Topology=Get-WinSlimProcessorTopology }
            $decision=Get-WinSlimPCoreMaskFromTopology -Topology $Topology
            if (-not $decision.Applicable) {
                return New-ProviderResult -Id $Id -Action $Action -Success $true -Changed $false -StateBefore $null -StateAfter $null `
                    -Verification ([PSCustomObject]@{ Applicable=$false; Success=$true; Checks=@([PSCustomObject]@{Type='CpuAffinity';Target=$ProcessName;Expected='topologia hibrida confiavel';Actual=$decision.Reason;Pass=$true}) }) `
                    -Restart 'None' -WarningMessage $decision.Reason
            }
            $taskBefore=& ($Adapter.GetTaskState) $TaskName
            $fileBefore=& ($Adapter.GetFileState) $ScriptPath
            $procBefore=@(& ($Adapter.GetProcesses) $ProcessName)
            $referenceState=[PSCustomObject]@{ Task=$taskBefore; Script=$fileBefore; Processes=@($procBefore); Mask=[UInt64]$decision.Mask; ProcessName=$ProcessName; TaskName=$TaskName; ScriptPath=$ScriptPath }

            $worker=New-CpuAffinityWorkerScript -Mask ([UInt64]$decision.Mask) -ProcessName $ProcessName
            & ($Adapter.WriteFile) $ScriptPath $worker
            $xml=New-CpuAffinityTaskXml -ScriptPath $ScriptPath
            & ($Adapter.RegisterTask) $TaskName $xml
            foreach($p in $procBefore){ & ($Adapter.SetProcessAffinity) $p.Id ([Int64]$decision.Mask) }
            $changed=$true
        } else {
            if (-not $BackupData) { throw "Undo de '$Id' requer BackupData persistido." }
            $referenceState=$BackupData
            & ($Adapter.RestoreTask) $referenceState.Task
            & ($Adapter.RestoreFile) $referenceState.Script
            foreach($p in @($referenceState.Processes)) { & ($Adapter.SetProcessAffinity) $p.Id ([Int64]$p.Affinity) }
            $changed=$true
        }
    } catch { $errorMsg=$_.Exception.Message }

    try {
        $taskNow=& ($Adapter.GetTaskState) $TaskName
        $fileNow=& ($Adapter.GetFileState) $ScriptPath
        $procNow=@(& ($Adapter.GetProcesses) $ProcessName)
        $after=[PSCustomObject]@{ Task=$taskNow; Script=$fileNow; Processes=@($procNow) }
    } catch { if (-not $errorMsg){$errorMsg=$_.Exception.Message} }

    $checks=@()
    if (-not $errorMsg) {
        if ($Action -eq 'Apply') {
            $taskPass=[bool]($after.Task -and $after.Task.Exists)
            $filePass=[bool]($after.Script -and $after.Script.Exists)
            $procPass=$true
            foreach($p in @($after.Processes)){ if ([Int64]$p.Affinity -ne [Int64]$referenceState.Mask){$procPass=$false} }
            $checks += [PSCustomObject]@{Type='CpuAffinity';Target='ScheduledTask';Expected='Exists=True';Actual="Exists=$($after.Task.Exists)";Pass=$taskPass}
            $checks += [PSCustomObject]@{Type='CpuAffinity';Target='WorkerScript';Expected='Exists=True';Actual="Exists=$($after.Script.Exists)";Pass=$filePass}
            $checks += [PSCustomObject]@{Type='CpuAffinity';Target=$ProcessName;Expected=('Mask=0x{0:X}' -f [UInt64]$referenceState.Mask);Actual=$(if(@($after.Processes).Count){(@($after.Processes|ForEach-Object{"PID=$($_.Id):$($_.Affinity)"}) -join ';')}else{'processo nao esta em execucao'});Pass=$procPass}
        } else {
            $taskPass=([bool]$after.Task.Exists -eq [bool]$referenceState.Task.Exists)
            $filePass=([bool]$after.Script.Exists -eq [bool]$referenceState.Script.Exists)
            if ($taskPass -and $referenceState.Task.Exists -and $referenceState.Task.Xml) { $taskPass=([string]$after.Task.Xml -eq [string]$referenceState.Task.Xml) }
            if ($filePass -and $referenceState.Script.Exists) { $filePass=([Convert]::ToBase64String([byte[]]$after.Script.Bytes) -eq [Convert]::ToBase64String([byte[]]$referenceState.Script.Bytes)) }
            $procPass=$true
            foreach($old in @($referenceState.Processes)) {
                $cur=@($after.Processes|Where-Object{$_.Id -eq $old.Id}|Select-Object -First 1)
                if($cur.Count -gt 0 -and [Int64]$cur[0].Affinity -ne [Int64]$old.Affinity){$procPass=$false}
            }
            $checks += [PSCustomObject]@{Type='CpuAffinity';Target='ScheduledTask';Expected="original Exists=$($referenceState.Task.Exists)";Actual="Exists=$($after.Task.Exists)";Pass=$taskPass}
            $checks += [PSCustomObject]@{Type='CpuAffinity';Target='WorkerScript';Expected="original Exists=$($referenceState.Script.Exists)";Actual="Exists=$($after.Script.Exists)";Pass=$filePass}
            $checks += [PSCustomObject]@{Type='CpuAffinity';Target=$ProcessName;Expected='afinidades originais dos PIDs ainda existentes';Actual='verificado por PID';Pass=$procPass}
        }
    }
    $verifyOk=(-not $errorMsg) -and @($checks).Count -eq 3 -and (-not (@($checks)|Where-Object{-not $_.Pass}))
    return New-ProviderResult -Id $Id -Action $Action -Success ([bool]$verifyOk) -Changed $changed -StateBefore $referenceState -StateAfter $after `
        -Verification ([PSCustomObject]@{Applicable=$true;Success=[bool]$verifyOk;Checks=@($checks)}) -Restart 'None' -WarningMessage $warningMsg -ErrorMessage $errorMsg
}

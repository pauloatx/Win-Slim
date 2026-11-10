<#
    Win-Slim Suite - FASE 5 R3
    Bridge seguro entre catalogo type=provider e Providers avancados.

    Objetivos:
    - whitelist explicita de Providers/entry points;
    - capturar BackupData ANTES do Apply para o Transaction Manager R13;
    - permitir seams de teste por AdditionalArguments sem acoplar o Planner;
    - manter SKIP de applicability como resultado do proprio Provider.

    Compatibilidade: Windows PowerShell 5.1.
#>

function Get-WinSlimBridgeProperty {
    param($InputObject,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if($null -eq $InputObject){ return $Default }
    if($InputObject -is [System.Collections.IDictionary]){
        try { if($InputObject.Contains($Name)){ return $InputObject[$Name] } } catch { }
        try { if($InputObject.ContainsKey($Name)){ return $InputObject[$Name] } } catch { }
    }
    try {
        $p=$InputObject.PSObject.Properties[$Name]
        if($null -ne $p){ return $p.Value }
    } catch { }
    return $Default
}

function ConvertTo-WinSlimBridgeHashtable {
    param($InputObject)
    $map=@{}
    if($null -eq $InputObject){ return $map }
    if($InputObject -is [System.Collections.IDictionary]){
        foreach($k in @($InputObject.Keys)){ $map[[string]$k]=$InputObject[$k] }
        return $map
    }
    foreach($p in @($InputObject.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })){
        $map[[string]$p.Name]=$p.Value
    }
    return $map
}

function Merge-WinSlimBridgeArguments {
    param($Base,$Extra)
    $result=@{}
    foreach($src in @($Base,$Extra)){
        $m=ConvertTo-WinSlimBridgeHashtable $src
        foreach($k in @($m.Keys)){ $result[$k]=$m[$k] }
    }
    return $result
}

function Get-WinSlimAdvancedProviderDefinition {
    param([Parameter(Mandatory)]$Tweak)
    $type=[string](Get-WinSlimBridgeProperty $Tweak 'type' '')
    if($type -ne 'provider'){ throw "Tweak '$([string](Get-WinSlimBridgeProperty $Tweak 'id' '?'))' nao e type=provider." }
    $p=Get-WinSlimBridgeProperty $Tweak 'provider' $null
    if($null -eq $p){ throw "Tweak provider nao possui bloco 'provider'." }
    $name=[string](Get-WinSlimBridgeProperty $p 'name' '')
    $entry=[string](Get-WinSlimBridgeProperty $p 'entryPoint' '')
    $expected=$null
    switch($name){
        'CoreParkingProvider'          { $expected='Invoke-CoreParkingProvider' }
        'CpuAffinityProvider'          { $expected='Invoke-CpuAffinityProvider' }
        'GpuInterruptAffinityProvider' { $expected='Invoke-GpuInterruptAffinityProvider' }
        default { throw "Provider nao permitido pelo bridge R3: '$name'." }
    }
    if($entry -and $entry -ne $expected){ throw "EntryPoint '$entry' nao corresponde ao Provider '$name' (esperado '$expected')." }
    return [PSCustomObject]@{ Name=$name; EntryPoint=$expected; Arguments=(Get-WinSlimBridgeProperty $p 'arguments' $null) }
}

function Resolve-WinSlimAdvancedProviderArguments {
    param([Parameter(Mandatory)]$Tweak,$AdditionalArguments=$null)
    $def=Get-WinSlimAdvancedProviderDefinition -Tweak $Tweak
    $args=Merge-WinSlimBridgeArguments -Base $def.Arguments -Extra $AdditionalArguments
    foreach($k in @($args.Keys)){
        if($args[$k] -is [string] -and ([string]$args[$k]).Contains('%')){
            $args[$k]=[Environment]::ExpandEnvironmentVariables([string]$args[$k])
        }
    }
    return $args
}

function Select-WinSlimBridgeCommandArguments {
    param([Parameter(Mandatory)][string]$CommandName,[hashtable]$Arguments)
    $cmd=Get-Command $CommandName -ErrorAction Stop
    $filtered=@{}
    foreach($k in @($Arguments.Keys)){
        if($cmd.Parameters.ContainsKey([string]$k)){ $filtered[$k]=$Arguments[$k] }
    }
    return $filtered
}

function Get-WinSlimAdvancedProviderBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Tweak,
        $Context=$null,
        $AdditionalArguments=$null
    )
    $def=Get-WinSlimAdvancedProviderDefinition -Tweak $Tweak
    $a=Resolve-WinSlimAdvancedProviderArguments -Tweak $Tweak -AdditionalArguments $AdditionalArguments

    switch($def.Name){
        'CoreParkingProvider' {
            $readArgs=@{}
            foreach($k in @('StateReader','SubgroupGuid','SettingGuid')){ if($a.ContainsKey($k)){ $readArgs[$k]=$a[$k] } }
            $state=Get-CoreParkingState @readArgs
            if($null -eq $state){
                return [PSCustomObject]@{ Provider=$def.Name; Applicable=$false; Reason='CPMINCORES state unavailable'; Queryable=$false }
            }
            return $state
        }
        'CpuAffinityProvider' {
            $topology=if($a.ContainsKey('Topology') -and $a.Topology){$a.Topology}else{Get-WinSlimProcessorTopology}
            $decision=Get-WinSlimPCoreMaskFromTopology -Topology $topology
            if(-not $decision.Applicable){
                return [PSCustomObject]@{ Provider=$def.Name; Applicable=$false; Reason=$decision.Reason; Mask=[UInt64]0 }
            }
            $adapter=if($a.ContainsKey('Adapter') -and $a.Adapter){$a.Adapter}else{New-CpuAffinityWindowsAdapter}
            $processName=if($a.ContainsKey('ProcessName')){[string]$a.ProcessName}else{'cs2.exe'}
            $taskName=if($a.ContainsKey('TaskName')){[string]$a.TaskName}else{'WinSlimSuite-AffinityCs2'}
            $scriptPath=if($a.ContainsKey('ScriptPath')){[string]$a.ScriptPath}else{"$env:ProgramData\WinSlimSuite\Tasks\affinity-cs2.ps1"}
            $task=& ($adapter.GetTaskState) $taskName
            $file=& ($adapter.GetFileState) $scriptPath
            $procs=@(& ($adapter.GetProcesses) $processName)
            return [PSCustomObject]@{
                Provider=$def.Name; Applicable=$true; Task=$task; Script=$file; Processes=@($procs)
                Mask=[UInt64]$decision.Mask; ProcessName=$processName; TaskName=$taskName; ScriptPath=$scriptPath
            }
        }
        'GpuInterruptAffinityProvider' {
            $topology=if($a.ContainsKey('Topology') -and $a.Topology){$a.Topology}else{Get-WinSlimProcessorTopology}
            $logical=if($topology.PSObject.Properties.Name -contains 'LogicalProcessorCount'){[int]$topology.LogicalProcessorCount}else{0}
            if($logical -lt 8){ return [PSCustomObject]@{Provider=$def.Name;Applicable=$false;Reason='Menos de 8 processadores logicos.'} }
            if($a.ContainsKey('AssignmentMask') -and $null -ne $a.AssignmentMask){ [UInt64]$mask=[UInt64]$a.AssignmentMask }
            else {
                $md=Get-WinSlimSuggestedGpuInterruptMask -Topology $topology
                if(-not $md.Applicable){ return [PSCustomObject]@{Provider=$def.Name;Applicable=$false;Reason=$md.Reason} }
                [UInt64]$mask=[UInt64]$md.Mask
            }
            $ids=@()
            if($a.ContainsKey('InstanceIds')){ $ids=@($a.InstanceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) }
            if($ids.Count -eq 0){ $ids=@(Get-WinSlimGpuPciInstances) }
            if($ids.Count -eq 0){ return [PSCustomObject]@{Provider=$def.Name;Applicable=$false;Reason='Nenhuma GPU PCI detectavel.'} }
            $root=if($a.ContainsKey('RegistryRoot')){[string]$a.RegistryRoot}else{'HKLM:\SYSTEM\CurrentControlSet\Enum'}
            $entries=@()
            foreach($instance in $ids){
                $path=Get-WinSlimGpuAffinityPath -RegistryRoot $root -InstanceId ([string]$instance)
                $entries += [PSCustomObject]@{
                    InstanceId=[string]$instance; Path=$path
                    DevicePolicy=(Backup-RegistryValue -Path $path -Name 'DevicePolicy')
                    AssignmentSetOverride=(Backup-RegistryValue -Path $path -Name 'AssignmentSetOverride')
                }
            }
            return @($entries)
        }
    }
}

function Invoke-WinSlimAdvancedProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Tweak,
        [ValidateSet('Apply','Undo')][string]$Action='Apply',
        $BackupData=$null,
        $Context=$null,
        $AdditionalArguments=$null
    )
    $def=Get-WinSlimAdvancedProviderDefinition -Tweak $Tweak
    $id=[string](Get-WinSlimBridgeProperty $Tweak 'id' '')
    if([string]::IsNullOrWhiteSpace($id)){ throw 'Tweak provider sem id.' }
    $a=Resolve-WinSlimAdvancedProviderArguments -Tweak $Tweak -AdditionalArguments $AdditionalArguments
    $a['Id']=$id
    $a['Action']=$Action
    if($Action -eq 'Undo'){ $a['BackupData']=$BackupData }
    $filtered=Select-WinSlimBridgeCommandArguments -CommandName $def.EntryPoint -Arguments $a
    switch($def.Name){
        'CoreParkingProvider'          { return Invoke-CoreParkingProvider @filtered }
        'CpuAffinityProvider'          { return Invoke-CpuAffinityProvider @filtered }
        'GpuInterruptAffinityProvider' { return Invoke-GpuInterruptAffinityProvider @filtered }
    }
}

function Get-WinSlimAdvancedContextArguments {
    <#
      R3.2: seam transacional PS5.1-safe.
      Permite transportar argumentos/adapters sinteticos pelo Context do
      Transaction Manager, evitando depender de closures aninhadas para estado
      mutavel. O mapa esperado e Context.AdvancedProviderArguments[TweakId].

      Opcionalmente uma entrada pode conter submapas Apply/Backup/Undo; caso
      contrario a mesma entrada e usada em todos os stages.
    #>
    param(
        $Context,
        [Parameter(Mandatory)][string]$TweakId,
        [ValidateSet('Apply','Backup','Undo')][string]$Stage='Apply'
    )

    if($null -eq $Context -or [string]::IsNullOrWhiteSpace($TweakId)){ return $null }
    $map=Get-WinSlimBridgeProperty $Context 'AdvancedProviderArguments' $null
    if($null -eq $map){ return $null }

    $entry=$null
    if($map -is [System.Collections.IDictionary]){
        try { if($map.Contains($TweakId)){ $entry=$map[$TweakId] } } catch { }
        if($null -eq $entry){ try { if($map.ContainsKey($TweakId)){ $entry=$map[$TweakId] } } catch { } }
    } else {
        try {
            $p=$map.PSObject.Properties[$TweakId]
            if($null -ne $p){ $entry=$p.Value }
        } catch { }
    }
    if($null -eq $entry){ return $null }

    # Suporte opcional a argumentos diferentes por stage.
    $stageSpecific=Get-WinSlimBridgeProperty $entry $Stage $null
    if($null -ne $stageSpecific){ return $stageSpecific }
    return $entry
}

function Resolve-WinSlimAdvancedRuntimeArguments {
    param(
        [Parameter(Mandatory)]$Tweak,
        $Context=$null,
        [ValidateSet('Apply','Backup','Undo')][string]$Stage='Apply',
        [scriptblock]$ArgumentResolver=$null
    )
    if($ArgumentResolver){
        $resolved=& $ArgumentResolver $Tweak $Context $Stage
        if($null -ne $resolved){ return $resolved }
    }
    $id=[string](Get-WinSlimBridgeProperty $Tweak 'id' '')
    return Get-WinSlimAdvancedContextArguments -Context $Context -TweakId $id -Stage $Stage
}

function Set-WinSlimBridgeContextProperty {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][string]$Name,
        $Value
    )
    if($Context -is [System.Collections.IDictionary]){
        $Context[$Name]=$Value
        return
    }
    $prop=$null
    try { $prop=$Context.PSObject.Properties[$Name] } catch { }
    if($null -ne $prop){
        $prop.Value=$Value
    } else {
        Add-Member -InputObject $Context -MemberType NoteProperty -Name $Name -Value $Value -Force
    }
}

function Get-WinSlimAdvancedHandlerRuntime {
    param($Context)
    if($null -eq $Context){ return $null }
    return Get-WinSlimBridgeProperty $Context 'AdvancedProviderHandlerRuntime' $null
}

function Invoke-WinSlimAdvancedTransactionApplyHandler {
    param($Tweak,$Level,$Context)

    $runtime=Get-WinSlimAdvancedHandlerRuntime -Context $Context
    $type=[string](Get-WinSlimBridgeProperty $Tweak 'type' '')
    if($type -ne 'provider'){
        $fallback=Get-WinSlimBridgeProperty $runtime 'FallbackApplyHandler' $null
        if($fallback){ return & $fallback $Tweak $Level $Context }
        throw "Sem FallbackApplyHandler para tweak nao-provider '$([string](Get-WinSlimBridgeProperty $Tweak 'id' '?'))'."
    }

    $resolver=Get-WinSlimBridgeProperty $runtime 'ArgumentResolver' $null
    $extra=Resolve-WinSlimAdvancedRuntimeArguments -Tweak $Tweak -Context $Context -Stage 'Apply' -ArgumentResolver $resolver
    return Invoke-WinSlimAdvancedProvider -Tweak $Tweak -Action Apply -Context $Context -AdditionalArguments $extra
}

function Invoke-WinSlimAdvancedTransactionBackupHandler {
    param($Tweak,$Level,$Context,$Step)

    $runtime=Get-WinSlimAdvancedHandlerRuntime -Context $Context
    $type=[string](Get-WinSlimBridgeProperty $Tweak 'type' '')
    if($type -ne 'provider'){
        $fallback=Get-WinSlimBridgeProperty $runtime 'FallbackBackupHandler' $null
        if($fallback){ return & $fallback $Tweak $Level $Context $Step }
        throw "Sem FallbackBackupHandler para tweak nao-provider '$([string](Get-WinSlimBridgeProperty $Tweak 'id' '?'))'."
    }

    $resolver=Get-WinSlimBridgeProperty $runtime 'ArgumentResolver' $null
    $extra=Resolve-WinSlimAdvancedRuntimeArguments -Tweak $Tweak -Context $Context -Stage 'Backup' -ArgumentResolver $resolver
    return Get-WinSlimAdvancedProviderBackup -Tweak $Tweak -Context $Context -AdditionalArguments $extra
}

function Invoke-WinSlimAdvancedTransactionUndoHandler {
    param($Tweak,$Level,$Context,$BackupData,$Step)

    $runtime=Get-WinSlimAdvancedHandlerRuntime -Context $Context
    $type=[string](Get-WinSlimBridgeProperty $Tweak 'type' '')
    if($type -ne 'provider'){
        $fallback=Get-WinSlimBridgeProperty $runtime 'FallbackUndoHandler' $null
        if($fallback){ return & $fallback $Tweak $Level $Context $BackupData $Step }
        throw "Sem FallbackUndoHandler para tweak nao-provider '$([string](Get-WinSlimBridgeProperty $Tweak 'id' '?'))'."
    }

    $resolver=Get-WinSlimBridgeProperty $runtime 'ArgumentResolver' $null
    $extra=Resolve-WinSlimAdvancedRuntimeArguments -Tweak $Tweak -Context $Context -Stage 'Undo' -ArgumentResolver $resolver
    return Invoke-WinSlimAdvancedProvider -Tweak $Tweak -Action Undo -BackupData $BackupData -Context $Context -AdditionalArguments $extra
}

function New-WinSlimAdvancedTransactionHandlers {
    <#
      R3.3: handlers sem GetNewClosure().

      No Windows PowerShell 5.1, ScriptBlock.GetNewClosure() cria um modulo
      dinamico. Quando o handler era executado posteriormente pelo Transaction
      Manager, esse modulo nao enxergava as funcoes auxiliares dot-sourced do
      AdvancedProviderBridge (ex.: Get-WinSlimBridgeProperty).

      A R3.3 guarda apenas o estado variavel (fallbacks/resolver) no Context e
      devolve ScriptBlocks de funcoes normais da sessao. Assim, a resolucao das
      funcoes auxiliares permanece no session state do Win-Slim, sem depender
      de closure/module scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        [scriptblock]$ArgumentResolver=$null,
        [scriptblock]$FallbackApplyHandler=$null,
        [scriptblock]$FallbackBackupHandler=$null,
        [scriptblock]$FallbackUndoHandler=$null
    )

    $runtime=[PSCustomObject]@{
        ArgumentResolver=$ArgumentResolver
        FallbackApplyHandler=$FallbackApplyHandler
        FallbackBackupHandler=$FallbackBackupHandler
        FallbackUndoHandler=$FallbackUndoHandler
    }
    Set-WinSlimBridgeContextProperty -Context $Context -Name 'AdvancedProviderHandlerRuntime' -Value $runtime

    return [PSCustomObject]@{
        Apply=${function:Invoke-WinSlimAdvancedTransactionApplyHandler}
        Backup=${function:Invoke-WinSlimAdvancedTransactionBackupHandler}
        Undo=${function:Invoke-WinSlimAdvancedTransactionUndoHandler}
        Mode='ContextBoundStatic'
    }
}

#requires -Version 5.1
<#
  Win-Slim Suite - FASE 6.5 R3
  Transaction Manager shadow otimizado.

  Objetivos:
  - preservar a semantica do Transaction Manager R13;
  - manter o PRIMEIRO backup imutavel por TweakId;
  - preservar rollback LIFO e recovery cross-process;
  - reduzir scans repetidos de Steps;
  - evitar += nos hot paths de Steps/StatusHistory/RestartScopes;
  - evitar regravar plan.json imutavel em todo checkpoint;
  - evitar IO atomico quando o JSON de um sidecar nao mudou;
  - continuar compativel com Windows PowerShell 5.1.

  Esta R3 e shadow validation: Transaction.ps1 continua canônico/congelado.
#>

function New-WinSlimArrayList65R3 {
    param($Items = @())
    $list = New-Object System.Collections.ArrayList
    foreach($item in @($Items)){ [void]$list.Add($item) }
    return ,$list
}

function Get-WinSlimTransactionRuntime65R3 {
    param([Parameter(Mandatory)] $Transaction)
    if($Transaction.PSObject.Properties.Name -contains 'Runtime65R3' -and $null -ne $Transaction.Runtime65R3){
        return $Transaction.Runtime65R3
    }

    $firstBackup = @{}
    $restartSet = @{}
    $maxSequence = 0
    foreach($step in @($Transaction.Steps)){
        $seq = [int]$step.Sequence
        if($seq -gt $maxSequence){ $maxSequence = $seq }
        if(($step.BackupFile -or $null -ne $step.BackupData) -and -not $firstBackup.ContainsKey([string]$step.TweakId)){
            $firstBackup[[string]$step.TweakId] = $step
        }
    }
    foreach($scope in @($Transaction.RestartScopes)){
        if(-not [string]::IsNullOrWhiteSpace([string]$scope)){ $restartSet[[string]$scope] = $true }
    }

    $cache = @{}
    $planFile = Join-Path ([string]$Transaction.TransactionPath) 'plan.json'
    $rt = [PSCustomObject]@{
        FirstBackupByTweakId = $firstBackup
        RestartScopeSet      = $restartSet
        NextSequence         = ($maxSequence + 1)
        LastJsonByName       = $cache
        JsonWriteCountByName = @{}
        PlanWritten          = [bool](Test-Path -LiteralPath $planFile)
        JsonWrites           = 0
        JsonSkips            = 0
    }
    Add-Member -InputObject $Transaction -NotePropertyName Runtime65R3 -NotePropertyValue $rt -Force
    return $rt
}

function Write-WinSlimJsonTextAtomic65R3 {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [AllowNull()] [string]$Json
    )
    $dir = Split-Path -Parent $Path
    if(-not(Test-Path -LiteralPath $dir)){ New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $tmp = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    $bak = "$Path.bak"
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($tmp, $Json, $utf8Bom)
    try {
        if(Test-Path -LiteralPath $Path){
            try {
                [System.IO.File]::Replace($tmp,$Path,$bak,$true)
                if(Test-Path -LiteralPath $bak){ Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue }
            } catch {
                Move-Item -LiteralPath $tmp -Destination $Path -Force
            }
        } else {
            [System.IO.File]::Move($tmp,$Path)
        }
    } finally {
        if(Test-Path -LiteralPath $tmp){ Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-WinSlimTransactionJson65R3 {
    param(
        [Parameter(Mandatory)] $Transaction,
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [AllowNull()] $Data,
        [switch]$Force
    )
    $rt = Get-WinSlimTransactionRuntime65R3 -Transaction $Transaction
    $json = ConvertTo-TransactionJsonText -Data $Data -Depth 32
    $path = Join-Path $Transaction.TransactionPath $Name
    if(-not $Force -and $rt.LastJsonByName.ContainsKey($Name) -and [string]$rt.LastJsonByName[$Name] -ceq [string]$json -and (Test-Path -LiteralPath $path)){
        $rt.JsonSkips++
        return $false
    }
    Write-WinSlimJsonTextAtomic65R3 -Path $path -Json $json
    $rt.LastJsonByName[$Name] = $json
    if(-not $rt.JsonWriteCountByName.ContainsKey($Name)){ $rt.JsonWriteCountByName[$Name]=0 }
    $rt.JsonWriteCountByName[$Name]=[int]$rt.JsonWriteCountByName[$Name]+1
    $rt.JsonWrites++
    return $true
}

function Save-WinSlimTransactionOptimized {
    param([Parameter(Mandatory)] $Transaction)
    if(-not $Transaction.Persist){ return }
    $rt = Get-WinSlimTransactionRuntime65R3 -Transaction $Transaction
    $Transaction.UpdatedAt = (Get-Date -Format 'o')
    if(-not(Test-Path -LiteralPath $Transaction.TransactionPath)){ New-Item -Path $Transaction.TransactionPath -ItemType Directory -Force | Out-Null }

    $meta = Get-TransactionMetadataSnapshot -Transaction $Transaction
    $steps = @(Get-TransactionOperationsPersistenceSnapshot -Transaction $Transaction)
    $rollback = @(Get-TransactionRollbackPersistenceSnapshot -Transaction $Transaction)

    [void](Write-WinSlimTransactionJson65R3 -Transaction $Transaction -Name 'transaction.json' -Data $meta -Force)
    if(-not $rt.PlanWritten -or -not(Test-Path -LiteralPath (Join-Path $Transaction.TransactionPath 'plan.json'))){
        [void](Write-WinSlimTransactionJson65R3 -Transaction $Transaction -Name 'plan.json' -Data @($Transaction.Plan) -Force)
        $rt.PlanWritten = $true
    }
    [void](Write-WinSlimTransactionJson65R3 -Transaction $Transaction -Name 'operations.json' -Data $steps)
    [void](Write-WinSlimTransactionJson65R3 -Transaction $Transaction -Name 'rollback.json' -Data $rollback)
}

function New-WinSlimTransactionOptimized {
    param(
        [ValidateSet('Apply','Undo','Recovery')] [string]$Mode='Apply',
        [ValidateSet('RollbackTransaction','Stop','Continue')] [string]$FailurePolicy='RollbackTransaction',
        [string]$RootPath,
        [string]$BackupRootPath,
        $Plan=@(),
        [switch]$NoPersist
    )
    $id = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8))
    $txRoot = Get-WinSlimTransactionRoot -RootPath $RootPath
    $backupRoot = Get-WinSlimTransactionBackupRoot -RootPath $BackupRootPath
    $txPath = Join-Path $txRoot $id
    $backupPath = Join-Path $backupRoot $id
    if(-not $NoPersist){
        New-Item -Path $txPath -ItemType Directory -Force | Out-Null
        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    }
    $history = New-WinSlimArrayList65R3 @([PSCustomObject]@{Status='Created';At=(Get-Date -Format 'o');Detail=$null})
    $tx=[PSCustomObject]@{
        SchemaVersion=$script:TransactionSchemaVersion
        Id=$id; Mode=$Mode; FailurePolicy=$FailurePolicy; Status='Created'
        CreatedAt=(Get-Date -Format 'o'); UpdatedAt=(Get-Date -Format 'o'); CompletedAt=$null
        ProcessId=$PID; PowerShell=$PSVersionTable.PSVersion.ToString()
        TransactionPath=$txPath; BackupPath=$backupPath; Persist=(-not $NoPersist)
        Plan=@($Plan); Steps=(New-WinSlimArrayList65R3); StatusHistory=$history
        RestartRequired=$false; RestartScopes=(New-WinSlimArrayList65R3)
        Failure=$null; Recovery=[PSCustomObject]@{Required=$false;LastKnownStep=$null}
    }
    [void](Get-WinSlimTransactionRuntime65R3 -Transaction $tx)
    if($tx.Persist){ Save-WinSlimTransactionOptimized -Transaction $tx }
    return $tx
}

function Set-WinSlimTransactionStatusOptimized {
    param(
        [Parameter(Mandatory)] $Transaction,
        [Parameter(Mandatory)] [string]$Status,
        [string]$Detail,
        [switch]$Force
    )
    if(-not $Force -and ($script:TransactionTerminalStates -contains [string]$Transaction.Status) -and $Transaction.Status -ne $Status){
        throw "Transacao '$($Transaction.Id)' ja esta em estado terminal '$($Transaction.Status)' e nao pode mudar para '$Status'."
    }
    $Transaction.Status=$Status
    $Transaction.UpdatedAt=(Get-Date -Format 'o')
    if($script:TransactionTerminalStates -contains $Status){ $Transaction.CompletedAt=(Get-Date -Format 'o') }
    if($Transaction.StatusHistory -is [System.Collections.ArrayList]){
        [void]$Transaction.StatusHistory.Add([PSCustomObject]@{Status=$Status;At=(Get-Date -Format 'o');Detail=$Detail})
    } else {
        $tmp=New-WinSlimArrayList65R3 @($Transaction.StatusHistory)
        [void]$tmp.Add([PSCustomObject]@{Status=$Status;At=(Get-Date -Format 'o');Detail=$Detail})
        $Transaction.StatusHistory=$tmp
    }
    Save-WinSlimTransactionOptimized -Transaction $Transaction
}

function Set-WinSlimTransactionPlanOptimized {
    param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)]$Plan)
    $Transaction.Plan=@($Plan)
    $rt=Get-WinSlimTransactionRuntime65R3 -Transaction $Transaction
    $rt.PlanWritten=$false
    Set-WinSlimTransactionStatusOptimized -Transaction $Transaction -Status 'Planned' -Detail "$(@($Plan).Count) operacao(oes) planejada(s)."
}

function Add-WinSlimTransactionStepOptimized {
    param(
        [Parameter(Mandatory)]$Transaction,
        [Parameter(Mandatory)]$Tweak,
        [int]$Level=-1,
        [string]$Status='Pending'
    )
    $rt=Get-WinSlimTransactionRuntime65R3 -Transaction $Transaction
    $id=if($Tweak.PSObject.Properties.Name -contains 'id'){[string]$Tweak.id}else{[string]$Tweak.Id}
    $step=[PSCustomObject]@{
        Sequence=[int]$rt.NextSequence; TweakId=$id; Level=$Level; Status=$Status
        StartedAt=$null; CompletedAt=$null; Changed=$false; Tweak=(Copy-TransactionObject $Tweak)
        StateBefore=$null; StateAfter=$null; BackupData=$null; BackupFile=$null
        ApplyResult=$null; VerifyResult=$null; Restart='None'; RollbackStatus='NotRequired'
        UndoResult=$null; Warning=$null; Error=$null
    }
    $rt.NextSequence++
    if($Transaction.Steps -is [System.Collections.ArrayList]){ [void]$Transaction.Steps.Add($step) }
    else {
        $list=New-WinSlimArrayList65R3 @($Transaction.Steps); [void]$list.Add($step); $Transaction.Steps=$list
    }
    Save-WinSlimTransactionOptimized -Transaction $Transaction
    return $step
}

function Get-WinSlimTransactionFirstBackupOptimized {
    param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)][string]$TweakId)
    $rt=Get-WinSlimTransactionRuntime65R3 -Transaction $Transaction
    if(-not $rt.FirstBackupByTweakId.ContainsKey($TweakId)){ return $null }
    $step=$rt.FirstBackupByTweakId[$TweakId]
    if($step.BackupFile -and (Test-Path -LiteralPath ([string]$step.BackupFile))){
        return Read-TransactionBackupFile -Path ([string]$step.BackupFile)
    }
    if($null -ne $step.BackupData){ return Copy-TransactionObject -InputObject $step.BackupData }
    return $null
}

function Save-WinSlimTransactionBackupOptimized {
    param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)]$Step,$BackupData)
    if($null -eq $BackupData){ return }
    $rt=Get-WinSlimTransactionRuntime65R3 -Transaction $Transaction
    $id=[string]$Step.TweakId
    if($rt.FirstBackupByTweakId.ContainsKey($id)){
        $prior=$rt.FirstBackupByTweakId[$id]
        $Step.BackupData=Get-WinSlimTransactionFirstBackupOptimized -Transaction $Transaction -TweakId $id
        $Step.BackupFile=$prior.BackupFile
    } elseif($Transaction.Persist){
        $safeId=($id -replace '[^A-Za-z0-9_.-]','_')
        $file='{0:D4}-{1}.clixml' -f [int]$Step.Sequence,$safeId
        $path=Join-Path $Transaction.BackupPath $file
        Write-TransactionBackupAtomic -Path $path -Data $BackupData
        $Step.BackupFile=$path
        $Step.BackupData=Read-TransactionBackupFile -Path $path
        $rt.FirstBackupByTweakId[$id]=$Step
    } else {
        $Step.BackupData=Copy-TransactionObject -InputObject $BackupData
        $rt.FirstBackupByTweakId[$id]=$Step
    }
    Save-WinSlimTransactionOptimized -Transaction $Transaction
}

function Add-WinSlimRestartScopeOptimized {
    param([Parameter(Mandatory)]$Transaction,[string]$Scope)
    if([string]::IsNullOrWhiteSpace($Scope) -or $Scope -eq 'None'){ return }
    $rt=Get-WinSlimTransactionRuntime65R3 -Transaction $Transaction
    if(-not $rt.RestartScopeSet.ContainsKey($Scope)){
        $rt.RestartScopeSet[$Scope]=$true
        if($Transaction.RestartScopes -is [System.Collections.ArrayList]){ [void]$Transaction.RestartScopes.Add($Scope) }
        else { $Transaction.RestartScopes=New-WinSlimArrayList65R3 @(@($Transaction.RestartScopes)+@($Scope)) }
    }
    $Transaction.RestartRequired=$true
}

function Invoke-WinSlimTransactionStepOptimized {
    param(
        [Parameter(Mandatory)]$Transaction,
        [Parameter(Mandatory)]$Step,
        $Context=$null,
        [scriptblock]$ApplyHandler,
        [scriptblock]$BackupHandler
    )
    if(-not $ApplyHandler){
        $ApplyHandler={ param($Tweak,$Level,$Context) Invoke-Tweak -Tweak $Tweak -Action 'Apply' -Level $Level -Context $Context -StrictVerify }
    }

    $preBackup=Get-WinSlimTransactionFirstBackupOptimized -Transaction $Transaction -TweakId $Step.TweakId
    if($null -eq $preBackup -and $BackupHandler){
        $Step.Status='BackingUp'
        Set-WinSlimTransactionStatusOptimized -Transaction $Transaction -Status 'BackingUp' -Detail "Backup pre-apply de $($Step.TweakId)."
        try { $preBackup=& $BackupHandler $Step.Tweak $Step.Level $Context $Step }
        catch {
            $Step.Status='Failed'; $Step.Error="Backup pre-apply falhou: $($_.Exception.Message)"; $Step.CompletedAt=(Get-Date -Format 'o')
            $Transaction.Failure=[PSCustomObject]@{TweakId=$Step.TweakId;Sequence=$Step.Sequence;At=(Get-Date -Format 'o');Error=$Step.Error;Warning=$null}
            Save-WinSlimTransactionOptimized -Transaction $Transaction
            return [PSCustomObject]@{Success=$false;Changed=$false;StateBefore=$null;StateAfter=$null;Verification=$null;Restart='None';Warning=$null;Error=$Step.Error}
        }
        if($null -eq $preBackup){
            $Step.Status='Failed'; $Step.Error='Backup pre-apply retornou null; Apply bloqueado para preservar rollback.'; $Step.CompletedAt=(Get-Date -Format 'o')
            $Transaction.Failure=[PSCustomObject]@{TweakId=$Step.TweakId;Sequence=$Step.Sequence;At=(Get-Date -Format 'o');Error=$Step.Error;Warning=$null}
            Save-WinSlimTransactionOptimized -Transaction $Transaction
            return [PSCustomObject]@{Success=$false;Changed=$false;StateBefore=$null;StateAfter=$null;Verification=$null;Restart='None';Warning=$null;Error=$Step.Error}
        }
    }
    if($null -ne $preBackup){ Save-WinSlimTransactionBackupOptimized -Transaction $Transaction -Step $Step -BackupData $preBackup }

    $Step.Status='Applying'; $Step.StartedAt=(Get-Date -Format 'o')
    $Transaction.Recovery.Required=$true; $Transaction.Recovery.LastKnownStep=$Step.Sequence
    Set-WinSlimTransactionStatusOptimized -Transaction $Transaction -Status 'Applying' -Detail "Aplicando $($Step.TweakId)."

    try { $result=& $ApplyHandler $Step.Tweak $Step.Level $Context }
    catch { $result=[PSCustomObject]@{Success=$false;Changed=$false;StateBefore=$null;StateAfter=$null;Verification=$null;Restart='None';Warning=$null;Error=$_.Exception.Message} }

    $Step.ApplyResult=Copy-TransactionObject -InputObject $result
    $Step.Changed=[bool]$result.Changed
    if($result.PSObject.Properties.Name -contains 'StateBefore'){ $Step.StateBefore=Copy-TransactionObject -InputObject $result.StateBefore }
    if($result.PSObject.Properties.Name -contains 'StateAfter'){ $Step.StateAfter=Copy-TransactionObject -InputObject $result.StateAfter }
    if($result.PSObject.Properties.Name -contains 'Verification'){ $Step.VerifyResult=Copy-TransactionObject -InputObject $result.Verification }
    if($result.PSObject.Properties.Name -contains 'Restart' -and $result.Restart){ $Step.Restart=[string]$result.Restart }
    if($result.PSObject.Properties.Name -contains 'Warning'){ $Step.Warning=$result.Warning }
    if($result.PSObject.Properties.Name -contains 'Error'){ $Step.Error=$result.Error }

    if($null -eq $Step.BackupData){
        $backup=$null
        if($null -ne $Step.StateBefore){ $backup=$Step.StateBefore }
        if($null -eq $backup){ $backup=Get-EngineRollbackBackup -TweakId $Step.TweakId }
        if($null -ne $backup){ Save-WinSlimTransactionBackupOptimized -Transaction $Transaction -Step $Step -BackupData $backup }
    }

    $ok=Test-TransactionApplyResult -Result $result
    if($ok){
        $Step.Status=if($Step.Changed){'Verified'}else{'NoChange'}
        $Step.CompletedAt=(Get-Date -Format 'o')
        if($Step.Changed){ $Step.RollbackStatus='Pending' }
        if($Step.Restart -and $Step.Restart -ne 'None'){ Add-WinSlimRestartScopeOptimized -Transaction $Transaction -Scope ([string]$Step.Restart) }
        Save-WinSlimTransactionOptimized -Transaction $Transaction
        return $result
    }
    $Step.Status='Failed'; $Step.CompletedAt=(Get-Date -Format 'o')
    $Transaction.Failure=[PSCustomObject]@{TweakId=$Step.TweakId;Sequence=$Step.Sequence;At=(Get-Date -Format 'o');Error=$Step.Error;Warning=$Step.Warning}
    Save-WinSlimTransactionOptimized -Transaction $Transaction
    return $result
}

function Get-WinSlimRollbackCandidatesOptimized {
    param([Parameter(Mandatory)]$Transaction)
    $steps=@($Transaction.Steps)
    $list=New-Object System.Collections.ArrayList
    $ordered=$true
    for($i=1;$i -lt $steps.Count;$i++){
        if([int]$steps[$i].Sequence -lt [int]$steps[$i-1].Sequence){ $ordered=$false; break }
    }
    if($ordered){
        for($i=$steps.Count-1;$i -ge 0;$i--){
            $s=$steps[$i]
            if([bool]$s.Changed -and [string]$s.RollbackStatus -ne 'RolledBack'){ [void]$list.Add($s) }
        }
    } else {
        foreach($s in @($steps | Where-Object { $_.Changed -and $_.RollbackStatus -ne 'RolledBack' } | Sort-Object Sequence -Descending)){ [void]$list.Add($s) }
    }
    return @($list.ToArray())
}

function Save-WinSlimTransactionResultOptimized {
    param([Parameter(Mandatory)]$Transaction)
    if(-not $Transaction.Persist){ return }
    $verified=0; $noChange=0; $failed=0; $rolledBack=0; $rollbackFailed=0
    foreach($step in @($Transaction.Steps)){
        switch([string]$step.Status){
            'Verified' {$verified++}
            'NoChange' {$noChange++}
            'Failed' {$failed++}
        }
        if([string]$step.RollbackStatus -eq 'RolledBack'){ $rolledBack++ }
        elseif([string]$step.RollbackStatus -eq 'RollbackFailed'){ $rollbackFailed++ }
    }
    $result=[PSCustomObject]@{
        TransactionId=$Transaction.Id;Status=$Transaction.Status;CreatedAt=$Transaction.CreatedAt;CompletedAt=$Transaction.CompletedAt
        RestartRequired=$Transaction.RestartRequired;RestartScopes=@($Transaction.RestartScopes);Failure=$Transaction.Failure
        Summary=[PSCustomObject]@{Total=@($Transaction.Steps).Count;Verified=$verified;NoChange=$noChange;Failed=$failed;RolledBack=$rolledBack;RollbackFailed=$rollbackFailed}
    }
    [void](Write-WinSlimTransactionJson65R3 -Transaction $Transaction -Name 'result.json' -Data $result -Force)
    [void](Write-WinSlimTransactionJson65R3 -Transaction $Transaction -Name 'state-before.json' -Data @(Get-TransactionStateBeforePersistenceSnapshot -Transaction $Transaction) -Force)
    [void](Write-WinSlimTransactionJson65R3 -Transaction $Transaction -Name 'state-after.json' -Data @(Get-TransactionStateAfterPersistenceSnapshot -Transaction $Transaction) -Force)
}

function Invoke-WinSlimTransactionRollbackOptimized {
    param(
        [Parameter(Mandatory)]$Transaction,
        $Context=$null,
        [scriptblock]$UndoHandler
    )
    if(-not $UndoHandler){
        $UndoHandler={
            param($Tweak,$Level,$Context,$BackupData,$Step)
            if($null -ne $BackupData){ Set-EngineRollbackBackup -TweakId $Step.TweakId -BackupData $BackupData }
            Invoke-Tweak -Tweak $Tweak -Action 'Undo' -Level $Level -Context $Context -StrictVerify
        }
    }
    Set-WinSlimTransactionStatusOptimized -Transaction $Transaction -Status 'RollingBack' -Detail 'Rollback LIFO iniciado.' -Force
    $recoveryWasRequired=[bool]$Transaction.Recovery.Required
    $candidates=@(Get-WinSlimRollbackCandidatesOptimized -Transaction $Transaction)
    if($recoveryWasRequired -and $candidates.Count -eq 0){
        $Transaction.Recovery.Required=$true
        Set-WinSlimTransactionStatusOptimized -Transaction $Transaction -Status 'RollbackFailed' -Detail 'Recovery exigia rollback, mas nenhum passo alterado valido foi reidratado.' -Force
        Save-WinSlimTransactionResultOptimized -Transaction $Transaction
        return $false
    }
    $failed=0
    foreach($step in $candidates){
        $step.RollbackStatus='RollingBack'; Save-WinSlimTransactionOptimized -Transaction $Transaction
        try {
            if($null -eq $step.BackupData){ throw "BackupData ausente para rollback do passo '$($step.TweakId)'." }
            $undo=& $UndoHandler $step.Tweak $step.Level $Context $step.BackupData $step
        } catch {
            $undo=[PSCustomObject]@{Success=$false;Changed=$false;Verification=$null;Warning=$null;Error=$_.Exception.Message}
        }
        $step.UndoResult=Copy-TransactionObject $undo
        if(Test-TransactionApplyResult -Result $undo){ $step.RollbackStatus='RolledBack';$step.Status='RolledBack' }
        else { $failed++;$step.RollbackStatus='RollbackFailed';$step.Status='RollbackFailed' }
        Save-WinSlimTransactionOptimized -Transaction $Transaction
    }
    $Transaction.Recovery.Required=($failed -gt 0)
    if($failed -eq 0){ Set-WinSlimTransactionStatusOptimized -Transaction $Transaction -Status 'RolledBack' -Detail 'Todos os passos alterados foram restaurados.' -Force }
    elseif($failed -lt $candidates.Count){ Set-WinSlimTransactionStatusOptimized -Transaction $Transaction -Status 'PartiallyRolledBack' -Detail "$failed rollback(s) falharam." -Force }
    else { Set-WinSlimTransactionStatusOptimized -Transaction $Transaction -Status 'RollbackFailed' -Detail 'Nenhum passo alterado pôde ser restaurado.' -Force }
    Save-WinSlimTransactionResultOptimized -Transaction $Transaction
    return ($failed -eq 0)
}

function Invoke-WinSlimTransactionPlanOptimized {
    param(
        [Parameter(Mandatory)]$Items,
        $Context=$null,
        [ValidateSet('RollbackTransaction','Stop','Continue')] [string]$FailurePolicy='RollbackTransaction',
        [string]$RootPath,
        [string]$BackupRootPath,
        [scriptblock]$ApplyHandler,
        [scriptblock]$BackupHandler,
        [scriptblock]$UndoHandler,
        [scriptblock]$OnProgress,
        [switch]$NoPersist
    )
    $lock=$null; $tx=$null
    try {
        if(-not $NoPersist){ $lock=Enter-WinSlimTransactionLock -RootPath $RootPath }
        $planList=New-Object System.Collections.ArrayList
        $seq=0
        foreach($item in @($Items)){
            $seq++
            $t=if($item.PSObject.Properties.Name -contains 'Tweak'){$item.Tweak}else{$item}
            $lvl=if($item.PSObject.Properties.Name -contains 'Level'){[int]$item.Level}else{-1}
            $tid=if($t.PSObject.Properties.Name -contains 'id'){[string]$t.id}else{[string]$t.Id}
            [void]$planList.Add([PSCustomObject]@{Sequence=$seq;TweakId=$tid;Level=$lvl})
        }
        $plan=@($planList.ToArray())
        $tx=New-WinSlimTransactionOptimized -Mode Apply -FailurePolicy $FailurePolicy -RootPath $RootPath -BackupRootPath $BackupRootPath -Plan $plan -NoPersist:$NoPersist
        # New-WinSlimTransactionOptimized ja persistiu o plano final. Apenas
        # transicionamos para Planned sem regravar plan.json.
        $tx.Plan=@($plan)
        Set-WinSlimTransactionStatusOptimized -Transaction $tx -Status 'Planned' -Detail "$(@($plan).Count) operacao(oes) planejada(s)."
        $total=@($Items).Count; $index=0; $hadFailure=$false
        foreach($item in @($Items)){
            $index++
            $t=if($item.PSObject.Properties.Name -contains 'Tweak'){$item.Tweak}else{$item}
            $lvl=if($item.PSObject.Properties.Name -contains 'Level'){[int]$item.Level}else{-1}
            $step=Add-WinSlimTransactionStepOptimized -Transaction $tx -Tweak $t -Level $lvl
            $r=Invoke-WinSlimTransactionStepOptimized -Transaction $tx -Step $step -Context $Context -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler
            if($OnProgress){ & $OnProgress $index $total $step $r $tx }
            if(-not(Test-TransactionApplyResult -Result $r)){
                $hadFailure=$true
                Set-WinSlimTransactionStatusOptimized -Transaction $tx -Status 'Failed' -Detail "Falha em $($step.TweakId)." -Force
                if($FailurePolicy -eq 'RollbackTransaction'){
                    [void](Invoke-WinSlimTransactionRollbackOptimized -Transaction $tx -Context $Context -UndoHandler $UndoHandler)
                    return $tx
                }
                if($FailurePolicy -eq 'Stop'){
                    $pending=$false
                    foreach($s in @($tx.Steps)){ if([bool]$s.Changed -and [string]$s.RollbackStatus -ne 'RolledBack'){ $pending=$true;break } }
                    $tx.Recovery.Required=$pending
                    Save-WinSlimTransactionOptimized -Transaction $tx
                    Save-WinSlimTransactionResultOptimized -Transaction $tx
                    return $tx
                }
            }
        }
        Set-WinSlimTransactionStatusOptimized -Transaction $tx -Status 'Applied' -Detail 'Todas as operacoes foram processadas.' -Force
        $tx.Recovery.Required=$false
        if($hadFailure -and $FailurePolicy -eq 'Continue'){
            Set-WinSlimTransactionStatusOptimized -Transaction $tx -Status 'CommittedWithErrors' -Detail 'Transacao concluida com uma ou mais falhas aceitas pela policy Continue.' -Force
        } else {
            Set-WinSlimTransactionStatusOptimized -Transaction $tx -Status 'Committed' -Detail 'Transacao confirmada.' -Force
        }
        Save-WinSlimTransactionResultOptimized -Transaction $tx
        return $tx
    } catch {
        if($tx){
            $tx.Failure=[PSCustomObject]@{TweakId=$null;Sequence=$null;At=(Get-Date -Format 'o');Error=$_.Exception.Message;Warning=$null}
            try{ Set-WinSlimTransactionStatusOptimized -Transaction $tx -Status 'Interrupted' -Detail $_.Exception.Message -Force }catch{}
            $tx.Recovery.Required=$true
            try{ Save-WinSlimTransactionOptimized -Transaction $tx; Save-WinSlimTransactionResultOptimized -Transaction $tx }catch{}
        }
        throw
    } finally {
        if($lock){ Exit-WinSlimTransactionLock }
    }
}

function Import-WinSlimTransactionOptimized {
    param([Parameter(Mandatory)][string]$Path)
    $tx=Import-WinSlimTransaction -Path $Path
    $tx.Steps=New-WinSlimArrayList65R3 @($tx.Steps)
    $tx.StatusHistory=New-WinSlimArrayList65R3 @($tx.StatusHistory)
    $tx.RestartScopes=New-WinSlimArrayList65R3 @($tx.RestartScopes)
    [void](Get-WinSlimTransactionRuntime65R3 -Transaction $tx)
    return $tx
}

function Invoke-WinSlimTransactionRecoveryOptimized {
    param(
        [Parameter(Mandatory)][string]$Path,
        $Context=$null,
        [scriptblock]$UndoHandler,
        [string]$RootPath
    )
    $lock=$null
    try{
        $lock=Enter-WinSlimTransactionLock -RootPath $RootPath
        $tx=Import-WinSlimTransactionOptimized -Path $Path
        if($tx.Status -eq 'Committed' -and -not [bool]$tx.Recovery.Required){ throw "Transacao '$($tx.Id)' ja esta committed e nao requer recovery." }
        Set-WinSlimTransactionStatusOptimized -Transaction $tx -Status 'RecoveryRequired' -Detail 'Recovery manual iniciado.' -Force
        [void](Invoke-WinSlimTransactionRollbackOptimized -Transaction $tx -Context $Context -UndoHandler $UndoHandler)
        return $tx
    } finally {
        if($lock){ Exit-WinSlimTransactionLock }
    }
}

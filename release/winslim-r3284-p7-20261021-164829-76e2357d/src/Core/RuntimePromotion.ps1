#requires -Version 5.1
<#
  Win-Slim Suite - FASE 6.5 R4
  Promotion layer: ativa PlannerOptimized + TransactionOptimized mantendo
  fallback controlado para as implementacoes canônicas R1/R13.

  Requisitos de carga (nesta ordem):
    Planner.ps1
    Transaction.ps1
    CatalogRuntime.ps1
    PlannerOptimized.ps1
    TransactionOptimized.ps1
    RuntimePromotion.ps1

  A camada não altera Windows. Ela apenas roteia APIs públicas para o runtime
  otimizado quando a promoção está habilitada.
#>

if (-not (Get-Variable -Scope Script -Name WinSlimPromotionState -ErrorAction SilentlyContinue)) {
    $script:WinSlimPromotionState = [PSCustomObject]@{
        PlannerEnabled     = $false
        TransactionEnabled = $false
        PlannerCache       = @{}
        PlannerCacheHits   = 0
        PlannerCacheMisses = 0
        ActivatedAt        = $null
    }
}

# Captura as implementacoes canônicas UMA vez. Recarregar este arquivo nao pode
# transformar o wrapper promovido em seu proprio fallback.
if (-not (Get-Variable -Scope Script -Name WinSlimLegacyNewExecutionPlan -ErrorAction SilentlyContinue)) {
    $script:WinSlimLegacyNewExecutionPlan = ${function:New-WinSlimExecutionPlan}
}
if (-not (Get-Variable -Scope Script -Name WinSlimLegacyNewTransaction -ErrorAction SilentlyContinue)) {
    $script:WinSlimLegacyNewTransaction = ${function:New-Transaction}
    $script:WinSlimLegacySaveTransaction = ${function:Save-Transaction}
    $script:WinSlimLegacySetTransactionStatus = ${function:Set-TransactionStatus}
    $script:WinSlimLegacySetTransactionPlan = ${function:Set-TransactionPlan}
    $script:WinSlimLegacyGetTransactionFirstBackup = ${function:Get-TransactionFirstBackup}
    $script:WinSlimLegacySaveTransactionBackup = ${function:Save-TransactionBackup}
    $script:WinSlimLegacyAddTransactionStep = ${function:Add-TransactionStep}
    $script:WinSlimLegacyInvokeTransactionStep = ${function:Invoke-TransactionStep}
    $script:WinSlimLegacyInvokeTransactionRollback = ${function:Invoke-TransactionRollback}
    $script:WinSlimLegacySaveTransactionResult = ${function:Save-TransactionResult}
    $script:WinSlimLegacyInvokeTransactionPlan = ${function:Invoke-TransactionPlan}
    $script:WinSlimLegacyInvokeTransactionRecovery = ${function:Invoke-WinSlimTransactionRecovery}
}

function Get-WinSlimPromotionTweakId {
    param($Tweak)
    if ($null -eq $Tweak) { return '' }
    try {
        if ($Tweak.PSObject.Properties.Name -contains 'id') { return [string]$Tweak.id }
        if ($Tweak.PSObject.Properties.Name -contains 'Id') { return [string]$Tweak.Id }
    } catch { }
    return ''
}

function Get-WinSlimPromotionCatalogSignature {
    param([Parameter(Mandatory)]$CatalogTweaks)
    $ids = New-Object System.Collections.ArrayList
    foreach ($t in @($CatalogTweaks)) { [void]$ids.Add((Get-WinSlimPromotionTweakId $t)) }
    return ('{0}|{1}' -f @($CatalogTweaks).Count, (@($ids.ToArray()) -join '|'))
}

function Get-WinSlimPromotedPlannerRuntime {
    param([Parameter(Mandatory)]$CatalogTweaks)
    $sig = Get-WinSlimPromotionCatalogSignature -CatalogTweaks $CatalogTweaks
    if ($script:WinSlimPromotionState.PlannerCache.ContainsKey($sig)) {
        $script:WinSlimPromotionState.PlannerCacheHits++
        return $script:WinSlimPromotionState.PlannerCache[$sig]
    }
    $catalogRuntime = New-WinSlimCatalogRuntime -CatalogTweaks $CatalogTweaks
    $plannerRuntime = New-WinSlimPlannerRuntime -CatalogRuntime $catalogRuntime
    $entry = [PSCustomObject]@{ Signature=$sig; CatalogRuntime=$catalogRuntime; PlannerRuntime=$plannerRuntime }
    $script:WinSlimPromotionState.PlannerCache[$sig] = $entry
    $script:WinSlimPromotionState.PlannerCacheMisses++
    return $entry
}

function Enable-WinSlimRuntimePromotion {
    [CmdletBinding()]
    param([switch]$Planner,[switch]$Transaction)
    if (-not $Planner.IsPresent -and -not $Transaction.IsPresent) { $Planner=$true; $Transaction=$true }
    if ($Planner) { $script:WinSlimPromotionState.PlannerEnabled = $true }
    if ($Transaction) { $script:WinSlimPromotionState.TransactionEnabled = $true }
    $script:WinSlimPromotionState.ActivatedAt = (Get-Date -Format 'o')
    return Get-WinSlimRuntimePromotionStatus
}

function Disable-WinSlimRuntimePromotion {
    [CmdletBinding()]
    param([switch]$Planner,[switch]$Transaction)
    if (-not $Planner.IsPresent -and -not $Transaction.IsPresent) { $Planner=$true; $Transaction=$true }
    if ($Planner) { $script:WinSlimPromotionState.PlannerEnabled = $false }
    if ($Transaction) { $script:WinSlimPromotionState.TransactionEnabled = $false }
    return Get-WinSlimRuntimePromotionStatus
}

function Get-WinSlimRuntimePromotionStatus {
    [CmdletBinding()]
    param()
    [PSCustomObject]@{
        SchemaVersion       = 1
        Planner             = $(if($script:WinSlimPromotionState.PlannerEnabled){'Optimized'}else{'Legacy'})
        Transaction         = $(if($script:WinSlimPromotionState.TransactionEnabled){'Optimized'}else{'Legacy'})
        PlannerCacheEntries = $script:WinSlimPromotionState.PlannerCache.Count
        PlannerCacheHits    = [int]$script:WinSlimPromotionState.PlannerCacheHits
        PlannerCacheMisses  = [int]$script:WinSlimPromotionState.PlannerCacheMisses
        ActivatedAt         = $script:WinSlimPromotionState.ActivatedAt
    }
}

function Invoke-WinSlimLegacyExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$CatalogTweaks,
        [string[]]$SelectedIds=@(),
        $LevelSelections=$null,
        $Context=$null,
        [string]$PresetName,
        [ValidateSet('Block','PreferFirst')][string]$ConflictPolicy='Block',
        [switch]$SkipApplicabilityChecks
    )
    $old=[bool]$script:WinSlimPromotionState.PlannerEnabled
    try {
        $script:WinSlimPromotionState.PlannerEnabled=$false
        return & $script:WinSlimLegacyNewExecutionPlan -CatalogTweaks $CatalogTweaks -SelectedIds $SelectedIds -LevelSelections $LevelSelections -Context $Context -PresetName $PresetName -ConflictPolicy $ConflictPolicy -SkipApplicabilityChecks:$SkipApplicabilityChecks
    } finally { $script:WinSlimPromotionState.PlannerEnabled=$old }
}

# API pública promovida: mesma assinatura do Planner R1.
function New-WinSlimExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$CatalogTweaks,
        [string[]]$SelectedIds=@(),
        $LevelSelections=$null,
        $Context=$null,
        [string]$PresetName,
        [ValidateSet('Block','PreferFirst')][string]$ConflictPolicy='Block',
        [switch]$SkipApplicabilityChecks
    )
    if (-not $script:WinSlimPromotionState.PlannerEnabled) {
        return & $script:WinSlimLegacyNewExecutionPlan -CatalogTweaks $CatalogTweaks -SelectedIds $SelectedIds -LevelSelections $LevelSelections -Context $Context -PresetName $PresetName -ConflictPolicy $ConflictPolicy -SkipApplicabilityChecks:$SkipApplicabilityChecks
    }
    $rt=Get-WinSlimPromotedPlannerRuntime -CatalogTweaks $CatalogTweaks
    return New-WinSlimExecutionPlanOptimized -PlannerRuntime $rt.PlannerRuntime -SelectedIds $SelectedIds -LevelSelections $LevelSelections -Context $Context -PresetName $PresetName -ConflictPolicy $ConflictPolicy -SkipApplicabilityChecks:$SkipApplicabilityChecks
}

function Invoke-WinSlimLegacyTransactionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Items,
        $Context=$null,
        [ValidateSet('RollbackTransaction','Stop','Continue')][string]$FailurePolicy='RollbackTransaction',
        [string]$RootPath,[string]$BackupRootPath,
        [scriptblock]$ApplyHandler,[scriptblock]$BackupHandler,[scriptblock]$UndoHandler,[scriptblock]$OnProgress,
        [switch]$NoPersist
    )
    $old=[bool]$script:WinSlimPromotionState.TransactionEnabled
    try {
        $script:WinSlimPromotionState.TransactionEnabled=$false
        return & $script:WinSlimLegacyInvokeTransactionPlan -Items $Items -Context $Context -FailurePolicy $FailurePolicy -RootPath $RootPath -BackupRootPath $BackupRootPath -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler -OnProgress $OnProgress -NoPersist:$NoPersist
    } finally { $script:WinSlimPromotionState.TransactionEnabled=$old }
}

function New-Transaction {
    param([ValidateSet('Apply','Undo','Recovery')][string]$Mode='Apply',[ValidateSet('RollbackTransaction','Stop','Continue')][string]$FailurePolicy='RollbackTransaction',[string]$RootPath,[string]$BackupRootPath,$Plan=@(),[switch]$NoPersist)
    if($script:WinSlimPromotionState.TransactionEnabled){return New-WinSlimTransactionOptimized -Mode $Mode -FailurePolicy $FailurePolicy -RootPath $RootPath -BackupRootPath $BackupRootPath -Plan $Plan -NoPersist:$NoPersist}
    return & $script:WinSlimLegacyNewTransaction -Mode $Mode -FailurePolicy $FailurePolicy -RootPath $RootPath -BackupRootPath $BackupRootPath -Plan $Plan -NoPersist:$NoPersist
}
function Save-Transaction { param([Parameter(Mandatory)]$Transaction) if($script:WinSlimPromotionState.TransactionEnabled){return Save-WinSlimTransactionOptimized -Transaction $Transaction};return & $script:WinSlimLegacySaveTransaction -Transaction $Transaction }
function Set-TransactionStatus { param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)][string]$Status,[string]$Detail,[switch]$Force) if($script:WinSlimPromotionState.TransactionEnabled){return Set-WinSlimTransactionStatusOptimized -Transaction $Transaction -Status $Status -Detail $Detail -Force:$Force};return & $script:WinSlimLegacySetTransactionStatus -Transaction $Transaction -Status $Status -Detail $Detail -Force:$Force }
function Set-TransactionPlan { param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)]$Plan) if($script:WinSlimPromotionState.TransactionEnabled){return Set-WinSlimTransactionPlanOptimized -Transaction $Transaction -Plan $Plan};return & $script:WinSlimLegacySetTransactionPlan -Transaction $Transaction -Plan $Plan }
function Get-TransactionFirstBackup { param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)][string]$TweakId) if($script:WinSlimPromotionState.TransactionEnabled){return Get-WinSlimTransactionFirstBackupOptimized -Transaction $Transaction -TweakId $TweakId};return & $script:WinSlimLegacyGetTransactionFirstBackup -Transaction $Transaction -TweakId $TweakId }
function Save-TransactionBackup { param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)]$Step,$BackupData) if($script:WinSlimPromotionState.TransactionEnabled){return Save-WinSlimTransactionBackupOptimized -Transaction $Transaction -Step $Step -BackupData $BackupData};return & $script:WinSlimLegacySaveTransactionBackup -Transaction $Transaction -Step $Step -BackupData $BackupData }
function Add-TransactionStep { param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)]$Tweak,[int]$Level=-1,[string]$Status='Pending') if($script:WinSlimPromotionState.TransactionEnabled){return Add-WinSlimTransactionStepOptimized -Transaction $Transaction -Tweak $Tweak -Level $Level -Status $Status};return & $script:WinSlimLegacyAddTransactionStep -Transaction $Transaction -Tweak $Tweak -Level $Level -Status $Status }
function Invoke-TransactionStep { param([Parameter(Mandatory)]$Transaction,[Parameter(Mandatory)]$Step,$Context=$null,[scriptblock]$ApplyHandler,[scriptblock]$BackupHandler) if($script:WinSlimPromotionState.TransactionEnabled){return Invoke-WinSlimTransactionStepOptimized -Transaction $Transaction -Step $Step -Context $Context -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler};return & $script:WinSlimLegacyInvokeTransactionStep -Transaction $Transaction -Step $Step -Context $Context -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler }
function Invoke-TransactionRollback { param([Parameter(Mandatory)]$Transaction,$Context=$null,[scriptblock]$UndoHandler) if($script:WinSlimPromotionState.TransactionEnabled){return Invoke-WinSlimTransactionRollbackOptimized -Transaction $Transaction -Context $Context -UndoHandler $UndoHandler};return & $script:WinSlimLegacyInvokeTransactionRollback -Transaction $Transaction -Context $Context -UndoHandler $UndoHandler }
function Save-TransactionResult { param([Parameter(Mandatory)]$Transaction) if($script:WinSlimPromotionState.TransactionEnabled){return Save-WinSlimTransactionResultOptimized -Transaction $Transaction};return & $script:WinSlimLegacySaveTransactionResult -Transaction $Transaction }
function Invoke-TransactionPlan {
    param([Parameter(Mandatory)]$Items,$Context=$null,[ValidateSet('RollbackTransaction','Stop','Continue')][string]$FailurePolicy='RollbackTransaction',[string]$RootPath,[string]$BackupRootPath,[scriptblock]$ApplyHandler,[scriptblock]$BackupHandler,[scriptblock]$UndoHandler,[scriptblock]$OnProgress,[switch]$NoPersist)
    if($script:WinSlimPromotionState.TransactionEnabled){return Invoke-WinSlimTransactionPlanOptimized -Items $Items -Context $Context -FailurePolicy $FailurePolicy -RootPath $RootPath -BackupRootPath $BackupRootPath -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler -OnProgress $OnProgress -NoPersist:$NoPersist}
    return & $script:WinSlimLegacyInvokeTransactionPlan -Items $Items -Context $Context -FailurePolicy $FailurePolicy -RootPath $RootPath -BackupRootPath $BackupRootPath -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler -OnProgress $OnProgress -NoPersist:$NoPersist
}
function Invoke-WinSlimTransactionRecovery {
    param([Parameter(Mandatory)][string]$Path,$Context=$null,[scriptblock]$UndoHandler,[string]$RootPath)
    if($script:WinSlimPromotionState.TransactionEnabled){return Invoke-WinSlimTransactionRecoveryOptimized -Path $Path -Context $Context -UndoHandler $UndoHandler -RootPath $RootPath}
    return & $script:WinSlimLegacyInvokeTransactionRecovery -Path $Path -Context $Context -UndoHandler $UndoHandler -RootPath $RootPath
}

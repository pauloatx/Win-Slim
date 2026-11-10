<#
    Win-Slim Suite - Preset Planner Validator (FASE 6 R3)

    Camada pura de validacao entre PresetPolicyEngine e Planner.
    - NAO altera Windows.
    - NAO altera Planner, Transaction Manager, Providers ou catalogos.
    - Resolve preset + overlays R2 e produz um relatorio normalizado do Planner.
    - Serve como base para o Preview transacional da FASE 6 R4.

    Compatibilidade alvo: Windows PowerShell 5.1.
#>

$script:WinSlimPresetPlannerValidatorSchemaVersion = 1

function Get-WinSlimPresetPlannerValidationProperty {
    param($InputObject, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        try { if ($InputObject.Contains($Name)) { return $InputObject[$Name] } } catch { }
        try { if ($InputObject.ContainsKey($Name)) { return $InputObject[$Name] } } catch { }
    }
    try {
        $p = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $p) { return $p.Value }
    } catch { }
    return $Default
}

function New-WinSlimSyntheticPlannerContext {
    [CmdletBinding()]
    param(
        [ValidateSet('10','11')][string]$OS = '11',
        [bool]$IsAdmin = $true,
        [int]$RAM = 16,
        [ValidateSet('SSD','HDD')][string]$Storage = 'SSD',
        [switch]$NoGpu,
        [switch]$PendingReboot
    )

    $gpu = @()
    if (-not $NoGpu.IsPresent) {
        $gpu = @('NVIDIA Synthetic GPU')
    }

    return [PSCustomObject]@{
        OS = $OS
        IsAdmin = $IsAdmin
        RAM = $RAM
        Storage = $Storage
        PendingReboot = [bool]$PendingReboot.IsPresent
        CPU = 'Synthetic CPU'
        GPU = @($gpu)
        TPM = [PSCustomObject]@{ Present = $true }
        SecureBoot = [PSCustomObject]@{ Enabled = $true }
        VBS = $false
        HVCI = $false
        HyperV = [PSCustomObject]@{ FeatureInstalled = $false }
        NetworkAdapters = @('Synthetic Ethernet')
    }
}

function Invoke-WinSlimPresetPlannerValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetCatalog,
        [Parameter(Mandatory)]$RuleCatalog,
        [Parameter(Mandatory)]$CatalogTweaks,
        [Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName,
        [string[]]$ConditionalProfiles = @(),
        [switch]$AllowHighRiskConditional,
        $Context = $null,
        [switch]$SkipApplicabilityChecks
    )

    if (-not (Get-Command Resolve-WinSlimPresetPolicySelection -ErrorAction SilentlyContinue)) {
        throw 'Resolve-WinSlimPresetPolicySelection nao esta carregado. Importe PresetResolver.ps1 e PresetPolicyEngine.ps1.'
    }
    if (-not (Get-Command New-WinSlimExecutionPlan -ErrorAction SilentlyContinue)) {
        throw 'New-WinSlimExecutionPlan nao esta carregado. Importe Planner.ps1.'
    }

    if ($null -eq $Context) {
        $Context = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true
    }

    $policy = Resolve-WinSlimPresetPolicySelection `
        -PresetCatalog $PresetCatalog `
        -RuleCatalog $RuleCatalog `
        -CatalogTweaks $CatalogTweaks `
        -PresetName $PresetName `
        -ConditionalProfiles @($ConditionalProfiles) `
        -AllowHighRiskConditional:$AllowHighRiskConditional

    if (-not [bool]$policy.CanResolve) {
        return [PSCustomObject]@{
            SchemaVersion = $script:WinSlimPresetPlannerValidatorSchemaVersion
            Stage = 'Policy'
            PresetName = $PresetName
            ConditionalProfiles = @($policy.EnabledConditionalProfiles)
            PolicyFingerprint = [string]$policy.Fingerprint
            PlannerFingerprint = $null
            Policy = $policy
            Plan = $null
            CanResolve = $false
            CanExecute = $false
            HasWork = $false
            SelectedCount = @($policy.SelectedIds).Count
            DependencyCount = 0
            ExecutableCount = 0
            SkippedCount = 0
            BlockedCount = @($policy.BlockedRequests).Count
            RiskSummary = [PSCustomObject]@{ Low=0; Medium=0; High=0; Highest='None' }
            RestartRequirements = [PSCustomObject]@{ Required=$false; RebootRequired=$false; Scopes=@(); TweakIds=@(); PendingRebootBeforePlan=$false }
        }
    }

    $plan = New-WinSlimExecutionPlan `
        -CatalogTweaks $CatalogTweaks `
        -SelectedIds @($policy.SelectedIds) `
        -LevelSelections $policy.LevelSelections `
        -Context $Context `
        -ConflictPolicy 'Block' `
        -SkipApplicabilityChecks:$SkipApplicabilityChecks

    return [PSCustomObject]@{
        SchemaVersion = $script:WinSlimPresetPlannerValidatorSchemaVersion
        Stage = 'Planner'
        PresetName = $PresetName
        ConditionalProfiles = @($policy.EnabledConditionalProfiles)
        PolicyFingerprint = [string]$policy.Fingerprint
        PlannerFingerprint = [string]$plan.Fingerprint
        Policy = $policy
        Plan = $plan
        CanResolve = $true
        CanExecute = [bool]$plan.CanExecute
        HasWork = [bool]$plan.HasWork
        SelectedCount = @($plan.SelectedTweaks).Count
        DependencyCount = @($plan.ExpandedDependencies).Count
        ExecutableCount = @($plan.ExecutionOrder).Count
        SkippedCount = @($plan.SkippedTweaks).Count
        BlockedCount = @($plan.BlockedTweaks).Count
        RiskSummary = $plan.RiskSummary
        RestartRequirements = $plan.RestartRequirements
    }
}

function Test-WinSlimExecutionOrderDependencies {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)

    $issues = @()
    $position = @{}
    $i = 0
    foreach ($item in @($Plan.ExecutionOrder)) {
        $id = [string](Get-WinSlimPresetPlannerValidationProperty $item 'TweakId' '')
        if (-not $id) { continue }
        if ($position.ContainsKey($id)) {
            $issues += [PSCustomObject]@{ Code='DuplicateExecutionId'; TweakId=$id; Dependency=$null }
        } else {
            $position[$id] = $i
        }
        $i++
    }

    foreach ($item in @($Plan.ExecutionOrder)) {
        $id = [string](Get-WinSlimPresetPlannerValidationProperty $item 'TweakId' '')
        foreach ($dep0 in @(Get-WinSlimPresetPlannerValidationProperty $item 'Dependencies' @())) {
            $dep = [string]$dep0
            if (-not $dep) { continue }
            if (-not $position.ContainsKey($dep)) {
                $issues += [PSCustomObject]@{ Code='MissingActiveDependency'; TweakId=$id; Dependency=$dep }
                continue
            }
            if ([int]$position[$dep] -ge [int]$position[$id]) {
                $issues += [PSCustomObject]@{ Code='DependencyAfterDepender'; TweakId=$id; Dependency=$dep }
            }
        }
    }

    return [PSCustomObject]@{
        Valid = (@($issues).Count -eq 0)
        Issues = @($issues)
    }
}

function Test-WinSlimPlannerRiskSummaryInvariant {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)

    $low = 0
    $medium = 0
    $high = 0
    foreach ($item in @($Plan.ExecutionOrder)) {
        switch ([string]$item.Risk) {
            'Baixo' { $low++ }
            'Médio' { $medium++ }
            'Medio' { $medium++ }
            'Alto' { $high++ }
        }
    }

    $ok = (
        [int]$Plan.RiskSummary.Low -eq $low -and
        [int]$Plan.RiskSummary.Medium -eq $medium -and
        [int]$Plan.RiskSummary.High -eq $high -and
        ($low + $medium + $high) -eq @($Plan.ExecutionOrder).Count
    )

    return [PSCustomObject]@{ Valid=$ok; Low=$low; Medium=$medium; High=$high }
}

function Test-WinSlimPlannerRestartInvariant {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)

    $expectedIds = @()
    $expectedScopes = @()
    $expectedReboot = $false

    foreach ($item in @($Plan.ExecutionOrder)) {
        $requires = [bool](Get-WinSlimPresetPlannerValidationProperty $item 'RequiresRestart' $false)
        $scope = [string](Get-WinSlimPresetPlannerValidationProperty $item 'RestartScope' 'None')
        if ($requires -or ($scope -and $scope -ne 'None')) {
            $expectedIds += [string]$item.TweakId
            if ($scope -and $scope -ne 'None' -and $expectedScopes -notcontains $scope) {
                $expectedScopes += $scope
            }
            if ($requires -or $scope -eq 'Reboot') { $expectedReboot = $true }
        }
    }

    $actualIds = @($Plan.RestartRequirements.TweakIds)
    $actualScopes = @($Plan.RestartRequirements.Scopes)
    $idsEqual = ((@($expectedIds) -join '|') -eq (@($actualIds) -join '|'))
    $scopesEqual = ((@($expectedScopes | Sort-Object) -join '|') -eq (@($actualScopes | Sort-Object) -join '|'))
    $requiredEqual = ([bool]$Plan.RestartRequirements.Required -eq ($expectedIds.Count -gt 0))
    $rebootEqual = ([bool]$Plan.RestartRequirements.RebootRequired -eq $expectedReboot)

    return [PSCustomObject]@{
        Valid = ($idsEqual -and $scopesEqual -and $requiredEqual -and $rebootEqual)
        ExpectedIds = @($expectedIds)
        ExpectedScopes = @($expectedScopes)
        ExpectedReboot = $expectedReboot
    }
}

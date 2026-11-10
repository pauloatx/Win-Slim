<#
    Win-Slim Suite - Preset Preview (FASE 6 R4)

    Camada pura entre PresetPlannerValidator e Transaction Manager.
    - NAO altera o Windows.
    - NAO executa Providers.
    - Produz um Preview deterministico e amigavel para UI/auditoria.
    - Vincula Preview e ExecutionPlan por fingerprint para evitar executar
      um plano diferente daquele que foi apresentado ao usuario.

    Compatibilidade alvo: Windows PowerShell 5.1.
#>

$script:WinSlimPresetPreviewSchemaVersion = 1

function Get-WinSlimPreviewProperty {
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

function Get-WinSlimPreviewFingerprint {
    param([string[]]$Tokens)
    $canonical = (@($Tokens) -join "`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function New-WinSlimPresetPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$ValidationReport)

    $policy = Get-WinSlimPreviewProperty $ValidationReport 'Policy' $null
    $plan = Get-WinSlimPreviewProperty $ValidationReport 'Plan' $null
    $canResolve = [bool](Get-WinSlimPreviewProperty $ValidationReport 'CanResolve' $false)
    $canExecute = [bool](Get-WinSlimPreviewProperty $ValidationReport 'CanExecute' $false)
    $hasWork = [bool](Get-WinSlimPreviewProperty $ValidationReport 'HasWork' $false)

    $items = @()
    $skipped = @()
    $blocked = @()
    $warnings = @()
    $dependencyIds = @()

    if ($null -ne $plan) {
        $dependencyIds = @(Get-WinSlimPreviewProperty $plan 'ExpandedDependencies' @())

        foreach ($entry in @(Get-WinSlimPreviewProperty $plan 'ExecutionOrder' @())) {
            $tweak = Get-WinSlimPreviewProperty $entry 'Tweak' $null
            $id = [string](Get-WinSlimPreviewProperty $entry 'TweakId' '')
            $name = [string](Get-WinSlimPreviewProperty $tweak 'plainName' '')
            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = [string](Get-WinSlimPreviewProperty $tweak 'name' $id)
            }
            $items += [PSCustomObject]@{
                Sequence = [int](Get-WinSlimPreviewProperty $entry 'Sequence' 0)
                TweakId = $id
                Name = $name
                Category = [string](Get-WinSlimPreviewProperty $tweak 'category' '')
                Risk = [string](Get-WinSlimPreviewProperty $entry 'Risk' '')
                Level = [int](Get-WinSlimPreviewProperty $entry 'Level' -1)
                SelectionSource = [string](Get-WinSlimPreviewProperty $entry 'SelectionSource' '')
                IsDependency = [bool]($dependencyIds -contains $id)
                RequiresRestart = [bool](Get-WinSlimPreviewProperty $entry 'RequiresRestart' $false)
                RestartScope = [string](Get-WinSlimPreviewProperty $entry 'RestartScope' 'None')
            }
        }

        foreach ($entry in @(Get-WinSlimPreviewProperty $plan 'SkippedTweaks' @())) {
            $skipped += [PSCustomObject]@{
                TweakId = [string](Get-WinSlimPreviewProperty $entry 'TweakId' '')
                ReasonCode = [string](Get-WinSlimPreviewProperty $entry 'ReasonCode' '')
                Reason = [string](Get-WinSlimPreviewProperty $entry 'Reason' '')
            }
        }

        foreach ($entry in @(Get-WinSlimPreviewProperty $plan 'BlockedTweaks' @())) {
            $blocked += [PSCustomObject]@{
                TweakId = [string](Get-WinSlimPreviewProperty $entry 'TweakId' '')
                ReasonCode = [string](Get-WinSlimPreviewProperty $entry 'ReasonCode' '')
                Reason = [string](Get-WinSlimPreviewProperty $entry 'Reason' '')
            }
        }

        foreach ($entry in @(Get-WinSlimPreviewProperty $plan 'Warnings' @())) {
            $warnings += [PSCustomObject]@{
                Code = [string](Get-WinSlimPreviewProperty $entry 'Code' '')
                TweakId = [string](Get-WinSlimPreviewProperty $entry 'TweakId' '')
                Message = [string](Get-WinSlimPreviewProperty $entry 'Message' '')
            }
        }
    }

    $policyFingerprint = [string](Get-WinSlimPreviewProperty $ValidationReport 'PolicyFingerprint' '')
    $plannerFingerprint = [string](Get-WinSlimPreviewProperty $ValidationReport 'PlannerFingerprint' '')
    $presetName = [string](Get-WinSlimPreviewProperty $ValidationReport 'PresetName' '')
    $profiles = @((Get-WinSlimPreviewProperty $ValidationReport 'ConditionalProfiles' @()) | Sort-Object)

    $tokens = @(
        "schema=$script:WinSlimPresetPreviewSchemaVersion",
        "preset=$presetName",
        "policy=$policyFingerprint",
        "planner=$plannerFingerprint",
        "canResolve=$canResolve",
        "canExecute=$canExecute",
        "hasWork=$hasWork"
    )
    foreach ($profile in $profiles) { $tokens += "profile=$profile" }
    foreach ($item in $items) {
        $tokens += "item=$($item.Sequence):$($item.TweakId):$($item.Level):$($item.Risk):$($item.RestartScope)"
    }
    foreach ($entry in $skipped) { $tokens += "skip=$($entry.TweakId):$($entry.ReasonCode)" }
    foreach ($entry in $blocked) { $tokens += "block=$($entry.TweakId):$($entry.ReasonCode)" }
    foreach ($entry in $warnings) { $tokens += "warn=$($entry.Code):$($entry.TweakId)" }

    $risk = Get-WinSlimPreviewProperty $ValidationReport 'RiskSummary' $null
    if ($null -eq $risk) {
        $risk = [PSCustomObject]@{ Low=0; Medium=0; High=0; Highest='None' }
    }
    $restart = Get-WinSlimPreviewProperty $ValidationReport 'RestartRequirements' $null
    if ($null -eq $restart) {
        $restart = [PSCustomObject]@{ Required=$false; RebootRequired=$false; Scopes=@(); TweakIds=@(); PendingRebootBeforePlan=$false }
    }

    $transactionReady = ($canResolve -and $canExecute -and $hasWork -and $null -ne $plan)

    return [PSCustomObject]@{
        SchemaVersion = $script:WinSlimPresetPreviewSchemaVersion
        PresetName = $presetName
        ConditionalProfiles = @($profiles)
        PolicyFingerprint = $policyFingerprint
        PlannerFingerprint = $plannerFingerprint
        PreviewFingerprint = (Get-WinSlimPreviewFingerprint -Tokens $tokens)
        CanResolve = $canResolve
        CanExecute = $canExecute
        HasWork = $hasWork
        TransactionReady = $transactionReady
        Summary = [PSCustomObject]@{
            Selected = [int](Get-WinSlimPreviewProperty $ValidationReport 'SelectedCount' 0)
            Dependencies = [int](Get-WinSlimPreviewProperty $ValidationReport 'DependencyCount' 0)
            Executable = @($items).Count
            Skipped = @($skipped).Count
            Blocked = @($blocked).Count
        }
        RiskSummary = $risk
        RestartRequirements = $restart
        Items = @($items)
        SkippedTweaks = @($skipped)
        BlockedTweaks = @($blocked)
        Warnings = @($warnings)
        Approval = [PSCustomObject]@{
            HighRiskCount = [int](Get-WinSlimPreviewProperty $risk 'High' 0)
            ContainsHighRisk = ([int](Get-WinSlimPreviewProperty $risk 'High' 0) -gt 0)
            PendingRebootBeforePlan = [bool](Get-WinSlimPreviewProperty $restart 'PendingRebootBeforePlan' $false)
        }
    }
}

function Test-WinSlimPreviewPlanBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Preview,
        [Parameter(Mandatory)]$Plan
    )

    if (-not [bool](Get-WinSlimPreviewProperty $Preview 'TransactionReady' $false)) {
        return [PSCustomObject]@{ Valid=$false; ReasonCode='PreviewNotReady'; Reason='Preview nao esta apto para transacao.' }
    }
    if (-not [bool](Get-WinSlimPreviewProperty $Plan 'CanExecute' $false)) {
        return [PSCustomObject]@{ Valid=$false; ReasonCode='PlanBlocked'; Reason='ExecutionPlan nao pode ser executado.' }
    }

    $previewFingerprint = [string](Get-WinSlimPreviewProperty $Preview 'PlannerFingerprint' '')
    $planFingerprint = [string](Get-WinSlimPreviewProperty $Plan 'Fingerprint' '')
    if ([string]::IsNullOrWhiteSpace($previewFingerprint) -or $previewFingerprint -ne $planFingerprint) {
        return [PSCustomObject]@{ Valid=$false; ReasonCode='PlannerFingerprintMismatch'; Reason='Preview e ExecutionPlan possuem fingerprints diferentes.' }
    }

    $previewItems = @(Get-WinSlimPreviewProperty $Preview 'Items' @())
    $execution = @(Get-WinSlimPreviewProperty $Plan 'ExecutionOrder' @())
    if ($previewItems.Count -ne $execution.Count) {
        return [PSCustomObject]@{ Valid=$false; ReasonCode='ExecutionCountMismatch'; Reason='Preview e ExecutionPlan possuem contagens diferentes.' }
    }

    for ($i = 0; $i -lt $execution.Count; $i++) {
        $previewId = [string](Get-WinSlimPreviewProperty $previewItems[$i] 'TweakId' '')
        $planId = [string](Get-WinSlimPreviewProperty $execution[$i] 'TweakId' '')
        $previewLevel = [int](Get-WinSlimPreviewProperty $previewItems[$i] 'Level' -1)
        $planLevel = [int](Get-WinSlimPreviewProperty $execution[$i] 'Level' -1)
        if ($previewId -ne $planId -or $previewLevel -ne $planLevel) {
            return [PSCustomObject]@{ Valid=$false; ReasonCode='ExecutionOrderMismatch'; Reason="Divergencia na posicao $i entre Preview e ExecutionPlan." }
        }
    }

    return [PSCustomObject]@{ Valid=$true; ReasonCode='Bound'; Reason=$null }
}

function Get-WinSlimPreviewTransactionItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Preview,
        [Parameter(Mandatory)]$Plan
    )

    $binding = Test-WinSlimPreviewPlanBinding -Preview $Preview -Plan $Plan
    if (-not $binding.Valid) {
        throw "Preview/Plan binding invalido [$($binding.ReasonCode)]: $($binding.Reason)"
    }

    if (Get-Command Get-WinSlimTransactionItemsFromPlan -ErrorAction SilentlyContinue) {
        return @(Get-WinSlimTransactionItemsFromPlan -Plan $Plan)
    }
    return @(Get-WinSlimPreviewProperty $Plan 'ExecutionOrder' @())
}

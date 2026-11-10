<#
    Win-Slim Suite - Preset Runtime (FASE 6.5 R1)

    Hot-path otimizado e puro para presets:
    - valida catalogos uma unica vez;
    - reutiliza CatalogRuntime indexado;
    - pre-resolve Balanceado/Gamer/Extremo;
    - reutiliza mapa de perfis condicionais;
    - preserva exatamente as regras/fingerprint da FASE 6 R2/R3/R4.

    Este modulo NAO altera Windows e NAO substitui Planner/Transaction.
#>

$script:WinSlimPresetRuntimeSchemaVersion = 1

function Get-WinSlimPresetRuntimeProperty {
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

function Test-WinSlimPresetRuntimeMapKey {
    param($Map, [string]$Key)
    if ($null -eq $Map) { return $false }
    try { return [bool]$Map.ContainsKey($Key) } catch { }
    try { return [bool]$Map.Contains($Key) } catch { }
    return $false
}

function ConvertTo-WinSlimPresetRuntimeLevelMap {
    param($InputObject)
    $map = @{}
    if ($null -eq $InputObject) { return $map }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($k in @($InputObject.Keys)) { $map[[string]$k] = [int]$InputObject[$k] }
        return $map
    }
    foreach ($p in @($InputObject.PSObject.Properties)) {
        if ($p.MemberType -eq 'NoteProperty') { $map[$p.Name] = [int]$p.Value }
    }
    return $map
}

function New-WinSlimPresetRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$CatalogTweaks,
        [Parameter(Mandatory)]$PresetCatalog,
        [Parameter(Mandatory)]$RuleCatalog
    )

    foreach ($required in @(
        'New-WinSlimCatalogRuntime',
        'Test-WinSlimPresetCatalog',
        'Test-WinSlimPresetPolicyRules',
        'Resolve-WinSlimPresetSelection',
        'Get-WinSlimConditionalProfileMap'
    )) {
        if (-not (Get-Command $required -ErrorAction SilentlyContinue)) {
            throw "Funcao obrigatoria '$required' nao esta carregada para PresetRuntime."
        }
    }

    $catalogRuntime = New-WinSlimCatalogRuntime -CatalogTweaks $CatalogTweaks
    if (-not $catalogRuntime.Valid) {
        $codes = @($catalogRuntime.Issues | ForEach-Object { [string]$_.Code })
        throw "CatalogRuntime invalido: $($codes -join ', ')"
    }

    $presetValidation = Test-WinSlimPresetCatalog -PresetCatalog $PresetCatalog -CatalogTweaks $CatalogTweaks
    if (-not $presetValidation.Valid) {
        $codes = @($presetValidation.Issues | ForEach-Object { if ($_.Severity -eq 'Error') { [string]$_.Code } } | Where-Object { $_ })
        throw "PresetCatalog invalido: $($codes -join ', ')"
    }

    $policyValidation = Test-WinSlimPresetPolicyRules -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $CatalogTweaks
    if (-not $policyValidation.Valid) {
        $codes = @($policyValidation.Issues | ForEach-Object { if ($_.Severity -eq 'Error') { [string]$_.Code } } | Where-Object { $_ })
        throw "RuleCatalog invalido: $($codes -join ', ')"
    }

    $presetSelections = @{}
    foreach ($name in @('Balanceado','Gamer','Extremo')) {
        $presetSelections[$name] = Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName $name
    }

    $profileMap = Get-WinSlimConditionalProfileMap -RuleCatalog $RuleCatalog
    $profileOrder = @()
    foreach ($name0 in @(Get-WinSlimPresetRuntimeProperty $RuleCatalog 'profileOrder' @())) {
        $name = ([string]$name0).Trim()
        if ($name) { $profileOrder += $name }
    }

    return [PSCustomObject]@{
        SchemaVersion = $script:WinSlimPresetRuntimeSchemaVersion
        CatalogRuntime = $catalogRuntime
        PresetCatalog = $PresetCatalog
        RuleCatalog = $RuleCatalog
        PresetSelections = $presetSelections
        ConditionalProfileMap = $profileMap
        ConditionalProfileOrder = @($profileOrder)
        PresetValidation = $presetValidation
        PolicyValidation = $policyValidation
        Valid = $true
    }
}

function Resolve-WinSlimPresetRuntimeSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetRuntime,
        [Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName,
        [string[]]$ConditionalProfiles = @(),
        [switch]$AllowHighRiskConditional
    )

    if (-not [bool](Get-WinSlimPresetRuntimeProperty $PresetRuntime 'Valid' $false)) {
        throw 'PresetRuntime invalido.'
    }
    if (-not (Get-Command Get-WinSlimPresetPolicyFingerprint -ErrorAction SilentlyContinue)) {
        throw 'Get-WinSlimPresetPolicyFingerprint nao esta carregado.'
    }

    $catalogRuntime = Get-WinSlimPresetRuntimeProperty $PresetRuntime 'CatalogRuntime' $null
    $catalog = Get-WinSlimPresetRuntimeProperty $catalogRuntime 'ById' $null
    $profileMap = Get-WinSlimPresetRuntimeProperty $PresetRuntime 'ConditionalProfileMap' $null
    $presetSelections = Get-WinSlimPresetRuntimeProperty $PresetRuntime 'PresetSelections' $null
    if (-not (Test-WinSlimPresetRuntimeMapKey $presetSelections $PresetName)) {
        throw "Preset '$PresetName' nao existe no PresetRuntime."
    }
    $base = $presetSelections[$PresetName]

    $selectedList = New-Object System.Collections.ArrayList
    $selectedSet = @{}
    foreach ($id0 in @($base.SelectedIds)) {
        $id = [string]$id0
        if (-not $id) { continue }
        if (-not (Test-WinSlimPresetRuntimeMapKey $selectedSet $id)) {
            $selectedSet[$id] = $true
            [void]$selectedList.Add($id)
        }
    }
    $levels = ConvertTo-WinSlimPresetRuntimeLevelMap $base.LevelSelections

    $blocked = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList
    $enabledProfiles = New-Object System.Collections.ArrayList
    $conditionalIds = New-Object System.Collections.ArrayList

    $requestedSet = @{}
    $requested = New-Object System.Collections.ArrayList
    foreach ($name0 in @($ConditionalProfiles)) {
        $name = ([string]$name0).Trim()
        if (-not $name) { continue }
        if (-not (Test-WinSlimPresetRuntimeMapKey $requestedSet $name)) {
            $requestedSet[$name] = $true
            [void]$requested.Add($name)
        }
    }

    $orderedRequested = New-Object System.Collections.ArrayList
    $orderedSet = @{}
    foreach ($name0 in @(Get-WinSlimPresetRuntimeProperty $PresetRuntime 'ConditionalProfileOrder' @())) {
        $name = [string]$name0
        if ((Test-WinSlimPresetRuntimeMapKey $requestedSet $name) -and -not (Test-WinSlimPresetRuntimeMapKey $orderedSet $name)) {
            $orderedSet[$name] = $true
            [void]$orderedRequested.Add($name)
        }
    }
    foreach ($name0 in @($requested.ToArray() | Sort-Object)) {
        $name = [string]$name0
        if (-not (Test-WinSlimPresetRuntimeMapKey $orderedSet $name)) {
            $orderedSet[$name] = $true
            [void]$orderedRequested.Add($name)
        }
    }

    foreach ($name0 in @($orderedRequested.ToArray())) {
        $name = [string]$name0
        if (-not (Test-WinSlimPresetRuntimeMapKey $profileMap $name)) {
            [void]$blocked.Add([PSCustomObject]@{ Code='UnknownConditionalProfile'; Profile=$name; TweakId=$null; Message="Perfil condicional desconhecido '$name'." })
            continue
        }
        $profile = $profileMap[$name]
        $requiresHigh = [bool](Get-WinSlimPresetRuntimeProperty $profile 'requiresHighRiskConsent' $false)
        if ($requiresHigh -and -not $AllowHighRiskConditional.IsPresent) {
            [void]$blocked.Add([PSCustomObject]@{ Code='HighRiskConsentRequired'; Profile=$name; TweakId=$null; Message="Perfil '$name' exige consentimento adicional para risco Alto." })
            continue
        }

        $profileLevels = ConvertTo-WinSlimPresetRuntimeLevelMap (Get-WinSlimPresetRuntimeProperty $profile 'levelSelections' $null)
        $profileBlocked = $false
        foreach ($id in @($profileLevels.Keys)) {
            $level = [int]$profileLevels[$id]
            if ((Test-WinSlimPresetRuntimeMapKey $levels $id) -and [int]$levels[$id] -ne $level) {
                [void]$blocked.Add([PSCustomObject]@{ Code='LevelOverrideConflict'; Profile=$name; TweakId=$id; Message="Perfil '$name' tenta alterar nivel de '$id' de $($levels[$id]) para $level." })
                $profileBlocked = $true
            }
        }
        if ($profileBlocked) { continue }

        [void]$enabledProfiles.Add($name)
        foreach ($id0 in @(Get-WinSlimPresetRuntimeProperty $profile 'selectedIds' @())) {
            $id = ([string]$id0).Trim()
            if (-not $id) { continue }
            if (-not (Test-WinSlimPresetRuntimeMapKey $selectedSet $id)) {
                $selectedSet[$id] = $true
                [void]$selectedList.Add($id)
                [void]$conditionalIds.Add($id)
            }
            if (Test-WinSlimPresetRuntimeMapKey $catalog $id) {
                $risk = [string](Get-WinSlimPresetRuntimeProperty $catalog[$id] 'risk' '')
                if ($risk -eq 'Alto') {
                    [void]$warnings.Add([PSCustomObject]@{ Code='HighRiskConditionalEnabled'; Profile=$name; TweakId=$id; Message="Tweak Alto '$id' habilitado explicitamente pelo perfil '$name'." })
                }
            }
        }
        foreach ($id in @($profileLevels.Keys)) { $levels[$id] = [int]$profileLevels[$id] }
    }

    # Conflict/mutex: mesmo contrato R2, mas usando indices precomputados.
    $pairSeen = @{}
    foreach ($id0 in @($selectedList.ToArray())) {
        $id = [string]$id0
        if (-not (Test-WinSlimPresetRuntimeMapKey $catalog $id)) { continue }
        $conflicts = @($catalogRuntime.ConflictsById[$id])
        foreach ($other0 in $conflicts) {
            $other = [string]$other0
            if (-not $other -or -not (Test-WinSlimPresetRuntimeMapKey $selectedSet $other)) { continue }
            $a = $id; $b = $other
            if ([string]::Compare($a,$b,$true) -gt 0) { $tmp=$a; $a=$b; $b=$tmp }
            $key = "$a|$b"
            if (-not (Test-WinSlimPresetRuntimeMapKey $pairSeen $key)) {
                $pairSeen[$key] = $true
                [void]$blocked.Add([PSCustomObject]@{ Code='DeclaredConflict'; Profile=$null; TweakId=$id; Message="Selecao final contem conflito declarado: $a x $b." })
            }
        }
    }

    $mutex = @{}
    foreach ($id0 in @($selectedList.ToArray())) {
        $id = [string]$id0
        if (-not (Test-WinSlimPresetRuntimeMapKey $catalog $id)) { continue }
        $group = [string](Get-WinSlimPresetRuntimeProperty $catalog[$id] 'mutexGroup' '')
        if (-not $group) { continue }
        if (-not (Test-WinSlimPresetRuntimeMapKey $mutex $group)) { $mutex[$group] = New-Object System.Collections.ArrayList }
        [void]$mutex[$group].Add($id)
    }
    foreach ($group in @($mutex.Keys)) {
        $members = @($mutex[$group].ToArray() | Sort-Object -Unique)
        if ($members.Count -gt 1) {
            [void]$blocked.Add([PSCustomObject]@{ Code='MutexCollision'; Profile=$null; TweakId=$null; Message="Selecao final contem mutex '$group': $($members -join ', ')." })
        }
    }

    $selected = [object[]]$selectedList.ToArray()
    $enabled = [object[]]$enabledProfiles.ToArray()
    $fingerprint = Get-WinSlimPresetPolicyFingerprint `
        -PresetName $PresetName `
        -SelectedIds @($selected) `
        -LevelSelections $levels `
        -ConditionalProfiles @($enabled) `
        -AllowHighRiskConditional ([bool]$AllowHighRiskConditional.IsPresent)

    return [PSCustomObject]@{
        PresetName = $PresetName
        BaseSelectedIds = @($base.SelectedIds)
        BaseCount = @($base.SelectedIds).Count
        RequestedConditionalProfiles = [object[]]$orderedRequested.ToArray()
        EnabledConditionalProfiles = @($enabled)
        ConditionalIds = [object[]]$conditionalIds.ToArray()
        SelectedIds = @($selected)
        LevelSelections = $levels
        ConflictPolicy = 'Block'
        BlockedRequests = [object[]]$blocked.ToArray()
        Warnings = [object[]]$warnings.ToArray()
        CanResolve = ($blocked.Count -eq 0)
        Fingerprint = $fingerprint
    }
}

function Invoke-WinSlimPresetRuntimePlannerValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetRuntime,
        [Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName,
        [string[]]$ConditionalProfiles = @(),
        [switch]$AllowHighRiskConditional,
        $Context = $null,
        [switch]$SkipApplicabilityChecks
    )

    if (-not (Get-Command New-WinSlimExecutionPlan -ErrorAction SilentlyContinue)) {
        throw 'New-WinSlimExecutionPlan nao esta carregado.'
    }
    if ($null -eq $Context) {
        if (Get-Command New-WinSlimSyntheticPlannerContext -ErrorAction SilentlyContinue) {
            $Context = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true
        } else {
            throw 'Context ausente e New-WinSlimSyntheticPlannerContext nao esta carregado.'
        }
    }

    $policy = Resolve-WinSlimPresetRuntimeSelection `
        -PresetRuntime $PresetRuntime `
        -PresetName $PresetName `
        -ConditionalProfiles @($ConditionalProfiles) `
        -AllowHighRiskConditional:$AllowHighRiskConditional

    if (-not [bool]$policy.CanResolve) {
        return [PSCustomObject]@{
            SchemaVersion = 1
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

    $catalogTweaks = @($PresetRuntime.CatalogRuntime.Tweaks)
    $plan = New-WinSlimExecutionPlan `
        -CatalogTweaks $catalogTweaks `
        -SelectedIds @($policy.SelectedIds) `
        -LevelSelections $policy.LevelSelections `
        -Context $Context `
        -ConflictPolicy 'Block' `
        -SkipApplicabilityChecks:$SkipApplicabilityChecks

    return [PSCustomObject]@{
        SchemaVersion = 1
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

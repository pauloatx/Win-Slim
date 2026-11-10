<#
    Win-Slim Suite - Preset Policy Engine (FASE 6 R2)

    Camada pura de politica de presets condicionais.
    - NAO altera Windows.
    - NAO altera Planner, Transaction Manager ou Providers.
    - Consome WinSlim-Presets-R1.json + WinSlim-PresetRules-R2.json.
    - Mantem presets automaticos intactos e aplica overlays condicionais apenas por opt-in.
    - Bloqueia conflitos, mutex, override multilevel ambiguo e alto risco sem consentimento adicional.

    Compatibilidade alvo: Windows PowerShell 5.1.
#>

$script:WinSlimPresetPolicySchemaVersion = 1

function Get-WinSlimPolicyProperty {
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

function Test-WinSlimPolicyMapKey {
    param($Map, [string]$Key)
    if ($null -eq $Map) { return $false }
    try { return [bool]$Map.Contains($Key) } catch { }
    try { return [bool]$Map.ContainsKey($Key) } catch { }
    return $false
}

function Import-WinSlimPresetPolicyRules {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo de regras de preset nao encontrado: $Path"
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Falha ao carregar regras de preset '$Path': $($_.Exception.Message)"
    }
    if ([string](Get-WinSlimPolicyProperty $obj 'schemaVersion' '') -ne '1.0') {
        throw 'schemaVersion de regras de preset nao suportada. Esperado 1.0.'
    }
    if ([string](Get-WinSlimPolicyProperty $obj 'conflictPolicy' '') -ne 'Block') {
        throw 'WinSlim-PresetRules-R2 deve usar conflictPolicy=Block.'
    }
    return $obj
}

function Get-WinSlimPolicyCatalogIndex {
    param([Parameter(Mandatory)]$CatalogTweaks)
    $map = @{}
    foreach ($t in @($CatalogTweaks)) {
        $id = [string](Get-WinSlimPolicyProperty $t 'id' '')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $map[$id.Trim()] = $t
    }
    return $map
}

function Get-WinSlimPolicyClassificationMap {
    param([Parameter(Mandatory)]$PresetCatalog)
    $map = @{}
    foreach ($c in @(Get-WinSlimPolicyProperty $PresetCatalog 'classifications' @())) {
        $id = [string](Get-WinSlimPolicyProperty $c 'id' '')
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $map[$id.Trim()] = $c
    }
    return $map
}

function Get-WinSlimConditionalProfileMap {
    param([Parameter(Mandatory)]$RuleCatalog)
    $map = @{}
    foreach ($p in @(Get-WinSlimPolicyProperty $RuleCatalog 'conditionalProfiles' @())) {
        $name = [string](Get-WinSlimPolicyProperty $p 'name' '')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $map[$name.Trim()] = $p
    }
    return $map
}

function Get-WinSlimPresetPolicyFingerprint {
    param(
        [Parameter(Mandatory)][string]$PresetName,
        [Parameter(Mandatory)][string[]]$SelectedIds,
        [Parameter(Mandatory)]$LevelSelections,
        [string[]]$ConditionalProfiles = @(),
        [bool]$AllowHighRiskConditional = $false
    )

    $tokens = @()
    $tokens += "Preset=$PresetName"
    $tokens += "HighRisk=$AllowHighRiskConditional"
    foreach ($p in @($ConditionalProfiles | Sort-Object)) { $tokens += "Profile=$p" }
    foreach ($id in @($SelectedIds | Sort-Object)) { $tokens += "Id=$id" }
    $levelKeys = @()
    if ($LevelSelections -is [System.Collections.IDictionary]) { $levelKeys = @($LevelSelections.Keys) }
    elseif ($null -ne $LevelSelections) { $levelKeys = @($LevelSelections.PSObject.Properties | ForEach-Object { $_.Name }) }
    foreach ($k in @($levelKeys | Sort-Object)) {
        $v = if ($LevelSelections -is [System.Collections.IDictionary]) { $LevelSelections[$k] } else { $LevelSelections.PSObject.Properties[[string]$k].Value }
        $tokens += "Level=${k}:$v"
    }
    $canonical = (@($tokens) -join "`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $sha.Dispose() }
}

function Test-WinSlimPresetPolicyRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetCatalog,
        [Parameter(Mandatory)]$RuleCatalog,
        [Parameter(Mandatory)]$CatalogTweaks
    )

    $issues = @()
    $catalog = Get-WinSlimPolicyCatalogIndex -CatalogTweaks $CatalogTweaks
    $classes = Get-WinSlimPolicyClassificationMap -PresetCatalog $PresetCatalog
    $profiles = Get-WinSlimConditionalProfileMap -RuleCatalog $RuleCatalog

    if ([string](Get-WinSlimPolicyProperty $RuleCatalog 'conflictPolicy' '') -ne 'Block') {
        $issues += [PSCustomObject]@{ Severity='Error'; Code='UnsafeConflictPolicy'; Id=$null; Message='R2 requer conflictPolicy=Block.' }
    }
    if ([string](Get-WinSlimPolicyProperty $RuleCatalog 'dependencyPolicy' '') -ne 'PlannerExpand') {
        $issues += [PSCustomObject]@{ Severity='Error'; Code='UnexpectedDependencyPolicy'; Id=$null; Message='R2 requer dependencyPolicy=PlannerExpand.' }
    }

    $requiredModes = @('Auto','ManualOnly','HardwareConditional','WorkloadConditional','Maintenance','Diagnostic')
    $modePolicies = Get-WinSlimPolicyProperty $RuleCatalog 'modePolicies' $null
    foreach ($mode in $requiredModes) {
        $exists = $false
        if ($null -ne $modePolicies) {
            if ($modePolicies -is [System.Collections.IDictionary]) { $exists = Test-WinSlimPolicyMapKey $modePolicies $mode }
            else { $exists = ($null -ne $modePolicies.PSObject.Properties[$mode]) }
        }
        if (-not $exists) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='MissingModePolicy'; Id=$mode; Message="Politica de modo '$mode' ausente." }
        }
    }

    $profileNames = @()
    $conditionalCoverage = @{}
    foreach ($p in @(Get-WinSlimPolicyProperty $RuleCatalog 'conditionalProfiles' @())) {
        $name = [string](Get-WinSlimPolicyProperty $p 'name' '')
        if ([string]::IsNullOrWhiteSpace($name)) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='ConditionalProfileMissingName'; Id=$null; Message='Perfil condicional sem nome.' }
            continue
        }
        if ($profileNames -contains $name) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='DuplicateConditionalProfile'; Id=$name; Message="Perfil condicional duplicado '$name'." }
        } else { $profileNames += $name }

        if (-not [bool](Get-WinSlimPolicyProperty $p 'requiresExplicitOptIn' $false)) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='ConditionalProfileNotOptIn'; Id=$name; Message="Perfil '$name' deve exigir opt-in explicito." }
        }

        $kind = [string](Get-WinSlimPolicyProperty $p 'kind' '')
        $expectedMode = if ($kind -eq 'Hardware') { 'HardwareConditional' } elseif ($kind -eq 'Workload') { 'WorkloadConditional' } else { '' }
        if (-not $expectedMode) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='UnknownConditionalKind'; Id=$name; Message="Perfil '$name' usa kind '$kind' nao suportado." }
        }

        $selected = @(Get-WinSlimPolicyProperty $p 'selectedIds' @())
        if ($selected.Count -eq 0) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='EmptyConditionalProfile'; Id=$name; Message="Perfil '$name' nao seleciona nenhum tweak." }
        }
        foreach ($id0 in $selected) {
            $id = ([string]$id0).Trim()
            if (-not $id) { continue }
            if (-not (Test-WinSlimPolicyMapKey $catalog $id)) {
                $issues += [PSCustomObject]@{ Severity='Error'; Code='UnknownConditionalTweak'; Id=$id; Message="Perfil '$name' aponta para '$id' inexistente." }
                continue
            }
            if (-not (Test-WinSlimPolicyMapKey $classes $id)) {
                $issues += [PSCustomObject]@{ Severity='Error'; Code='UnclassifiedConditionalTweak'; Id=$id; Message="'$id' nao possui classificacao R1." }
                continue
            }
            $mode = [string](Get-WinSlimPolicyProperty $classes[$id] 'mode' '')
            if ($expectedMode -and $mode -ne $expectedMode) {
                $issues += [PSCustomObject]@{ Severity='Error'; Code='ConditionalModeMismatch'; Id=$id; Message="Perfil '$name' e '$kind', mas '$id' foi classificado como '$mode'." }
            }
            if (Test-WinSlimPolicyMapKey $conditionalCoverage $id) {
                $issues += [PSCustomObject]@{ Severity='Error'; Code='ConditionalTweakInMultipleProfiles'; Id=$id; Message="'$id' aparece em mais de um perfil condicional." }
            } else { $conditionalCoverage[$id] = $name }

            $risk = [string](Get-WinSlimPolicyProperty $catalog[$id] 'risk' '')
            $requiresHigh = [bool](Get-WinSlimPolicyProperty $p 'requiresHighRiskConsent' $false)
            if ($risk -eq 'Alto' -and -not $requiresHigh) {
                $issues += [PSCustomObject]@{ Severity='Error'; Code='HighRiskProfileMissingConsentGate'; Id=$id; Message="'$id' e Alto e o perfil '$name' nao exige consentimento adicional." }
            }
        }

        $levels = Get-WinSlimPolicyProperty $p 'levelSelections' $null
        if ($null -ne $levels) {
            $props = @()
            if ($levels -is [System.Collections.IDictionary]) { $props = @($levels.Keys | ForEach-Object { [PSCustomObject]@{ Name=[string]$_; Value=$levels[$_] } }) }
            else { $props = @($levels.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' }) }
            foreach ($lp in $props) {
                $id = [string]$lp.Name
                if ($selected -notcontains $id) {
                    $issues += [PSCustomObject]@{ Severity='Error'; Code='LevelForUnselectedTweak'; Id=$id; Message="Perfil '$name' define nivel para '$id' sem seleciona-lo." }
                    continue
                }
                if (Test-WinSlimPolicyMapKey $catalog $id) {
                    $type = [string](Get-WinSlimPolicyProperty $catalog[$id] 'type' '')
                    $level = [int]$lp.Value
                    $count = @(Get-WinSlimPolicyProperty $catalog[$id] 'levels' @()).Count
                    if ($type -ne 'multilevel' -or $level -lt 0 -or $level -ge $count) {
                        $issues += [PSCustomObject]@{ Severity='Error'; Code='InvalidConditionalLevel'; Id=$id; Message="Perfil '$name' define nivel invalido $level para '$id'." }
                    }
                }
            }
        }
    }

    $expectedConditional = @()
    foreach ($c in @(Get-WinSlimPolicyProperty $PresetCatalog 'classifications' @())) {
        $mode = [string](Get-WinSlimPolicyProperty $c 'mode' '')
        if ($mode -eq 'HardwareConditional' -or $mode -eq 'WorkloadConditional') {
            $expectedConditional += [string](Get-WinSlimPolicyProperty $c 'id' '')
        }
    }
    foreach ($id in $expectedConditional) {
        if (-not (Test-WinSlimPolicyMapKey $conditionalCoverage $id)) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='ConditionalTweakUncovered'; Id=$id; Message="Tweak condicional '$id' nao possui perfil R2." }
        }
    }

    foreach ($c in @(Get-WinSlimPolicyProperty $PresetCatalog 'classifications' @())) {
        $id = [string](Get-WinSlimPolicyProperty $c 'id' '')
        $mode = [string](Get-WinSlimPolicyProperty $c 'mode' '')
        if (@('ManualOnly','Maintenance','Diagnostic') -contains $mode) {
            if (Test-WinSlimPolicyMapKey $conditionalCoverage $id) {
                $issues += [PSCustomObject]@{ Severity='Error'; Code='ProtectedModeInConditionalProfile'; Id=$id; Message="'$id' com modo '$mode' nao pode entrar em perfil condicional." }
            }
        }
    }

    $errors = @($issues | Where-Object { $_.Severity -eq 'Error' })
    return [PSCustomObject]@{
        Valid = ($errors.Count -eq 0)
        ConditionalProfileCount = $profiles.Count
        ConditionalCoverageCount = $conditionalCoverage.Count
        Issues = @($issues)
    }
}

function Resolve-WinSlimPresetPolicySelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetCatalog,
        [Parameter(Mandatory)]$RuleCatalog,
        [Parameter(Mandatory)]$CatalogTweaks,
        [Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName,
        [string[]]$ConditionalProfiles = @(),
        [switch]$AllowHighRiskConditional
    )

    if (-not (Get-Command Resolve-WinSlimPresetSelection -ErrorAction SilentlyContinue)) {
        throw 'Resolve-WinSlimPresetSelection nao esta carregado. Importe src/Core/PresetResolver.ps1 antes do PresetPolicyEngine.'
    }

    $validation = Test-WinSlimPresetPolicyRules -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $CatalogTweaks
    if (-not $validation.Valid) {
        $codes = @($validation.Issues | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object { $_.Code })
        throw "Regras R2 invalidas: $($codes -join ', ')"
    }

    $catalog = Get-WinSlimPolicyCatalogIndex -CatalogTweaks $CatalogTweaks
    $profileMap = Get-WinSlimConditionalProfileMap -RuleCatalog $RuleCatalog
    $base = Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName $PresetName

    $selected = @($base.SelectedIds)
    $selectedSet = @{}
    foreach ($id in $selected) { $selectedSet[[string]$id] = $true }
    $levels = @{}
    foreach ($k in @($base.LevelSelections.Keys)) { $levels[[string]$k] = [int]$base.LevelSelections[$k] }

    $blocked = @()
    $warnings = @()
    $enabledProfiles = @()
    $conditionalIds = @()

    $requested = @()
    $seenRequest = @{}
    foreach ($name0 in @($ConditionalProfiles)) {
        $name = ([string]$name0).Trim()
        if (-not $name) { continue }
        if (-not (Test-WinSlimPolicyMapKey $seenRequest $name)) {
            $seenRequest[$name] = $true
            $requested += $name
        }
    }

    $orderedRequested = @()
    foreach ($pname in @(Get-WinSlimPolicyProperty $RuleCatalog 'profileOrder' @())) {
        if ($requested -contains [string]$pname) { $orderedRequested += [string]$pname }
    }
    foreach ($name in @($requested | Sort-Object)) {
        if ($orderedRequested -notcontains $name) { $orderedRequested += $name }
    }

    foreach ($name in $orderedRequested) {
        if (-not (Test-WinSlimPolicyMapKey $profileMap $name)) {
            $blocked += [PSCustomObject]@{ Code='UnknownConditionalProfile'; Profile=$name; TweakId=$null; Message="Perfil condicional desconhecido '$name'." }
            continue
        }
        $profile = $profileMap[$name]
        $requiresHigh = [bool](Get-WinSlimPolicyProperty $profile 'requiresHighRiskConsent' $false)
        if ($requiresHigh -and -not $AllowHighRiskConditional.IsPresent) {
            $blocked += [PSCustomObject]@{ Code='HighRiskConsentRequired'; Profile=$name; TweakId=$null; Message="Perfil '$name' exige consentimento adicional para risco Alto." }
            continue
        }

        $profileBlocked = $false
        $profileLevels = Get-WinSlimPolicyProperty $profile 'levelSelections' $null
        if ($null -ne $profileLevels) {
            $props = @()
            if ($profileLevels -is [System.Collections.IDictionary]) { $props = @($profileLevels.Keys | ForEach-Object { [PSCustomObject]@{ Name=[string]$_; Value=$profileLevels[$_] } }) }
            else { $props = @($profileLevels.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' }) }
            foreach ($lp in $props) {
                $id = [string]$lp.Name
                $level = [int]$lp.Value
                if (Test-WinSlimPolicyMapKey $levels $id) {
                    if ([int]$levels[$id] -ne $level) {
                        $blocked += [PSCustomObject]@{ Code='LevelOverrideConflict'; Profile=$name; TweakId=$id; Message="Perfil '$name' tenta alterar nivel de '$id' de $($levels[$id]) para $level." }
                        $profileBlocked = $true
                    }
                }
            }
        }
        if ($profileBlocked) { continue }

        $enabledProfiles += $name
        foreach ($id0 in @(Get-WinSlimPolicyProperty $profile 'selectedIds' @())) {
            $id = ([string]$id0).Trim()
            if (-not $id) { continue }
            if (-not (Test-WinSlimPolicyMapKey $selectedSet $id)) {
                $selectedSet[$id] = $true
                $selected += $id
                $conditionalIds += $id
            }
            $risk = [string](Get-WinSlimPolicyProperty $catalog[$id] 'risk' '')
            if ($risk -eq 'Alto') {
                $warnings += [PSCustomObject]@{ Code='HighRiskConditionalEnabled'; Profile=$name; TweakId=$id; Message="Tweak Alto '$id' habilitado explicitamente pelo perfil '$name'." }
            }
        }
        if ($null -ne $profileLevels) {
            $props = @()
            if ($profileLevels -is [System.Collections.IDictionary]) { $props = @($profileLevels.Keys | ForEach-Object { [PSCustomObject]@{ Name=[string]$_; Value=$profileLevels[$_] } }) }
            else { $props = @($profileLevels.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' }) }
            foreach ($lp in $props) { $levels[[string]$lp.Name] = [int]$lp.Value }
        }
    }

    # Conflitos declarados: nenhum overlay pode substituir silenciosamente o preset base.
    $pairSeen = @{}
    foreach ($id in @($selected)) {
        if (-not (Test-WinSlimPolicyMapKey $catalog $id)) { continue }
        foreach ($other0 in @(Get-WinSlimPolicyProperty $catalog[$id] 'conflicts' @())) {
            $other = [string]$other0
            if (-not $other -or -not (Test-WinSlimPolicyMapKey $selectedSet $other)) { continue }
            $a = $id; $b = $other
            if ([string]::Compare($a,$b,$true) -gt 0) { $tmp=$a; $a=$b; $b=$tmp }
            $key = "$a|$b"
            if (-not (Test-WinSlimPolicyMapKey $pairSeen $key)) {
                $pairSeen[$key] = $true
                $blocked += [PSCustomObject]@{ Code='DeclaredConflict'; Profile=$null; TweakId=$id; Message="Selecao final contem conflito declarado: $a x $b." }
            }
        }
    }

    $mutex = @{}
    foreach ($id in @($selected)) {
        if (-not (Test-WinSlimPolicyMapKey $catalog $id)) { continue }
        $group = [string](Get-WinSlimPolicyProperty $catalog[$id] 'mutexGroup' '')
        if (-not $group) { continue }
        if (-not (Test-WinSlimPolicyMapKey $mutex $group)) { $mutex[$group] = @() }
        $mutex[$group] = @($mutex[$group]) + $id
    }
    foreach ($group in @($mutex.Keys)) {
        $members = @($mutex[$group] | Sort-Object -Unique)
        if ($members.Count -gt 1) {
            $blocked += [PSCustomObject]@{ Code='MutexCollision'; Profile=$null; TweakId=$null; Message="Selecao final contem mutex '$group': $($members -join ', ')." }
        }
    }

    $fingerprint = Get-WinSlimPresetPolicyFingerprint -PresetName $PresetName -SelectedIds @($selected) -LevelSelections $levels -ConditionalProfiles @($enabledProfiles) -AllowHighRiskConditional ([bool]$AllowHighRiskConditional.IsPresent)

    return [PSCustomObject]@{
        PresetName = $PresetName
        BaseSelectedIds = @($base.SelectedIds)
        BaseCount = @($base.SelectedIds).Count
        RequestedConditionalProfiles = @($orderedRequested)
        EnabledConditionalProfiles = @($enabledProfiles)
        ConditionalIds = @($conditionalIds)
        SelectedIds = @($selected)
        LevelSelections = $levels
        ConflictPolicy = 'Block'
        BlockedRequests = @($blocked)
        Warnings = @($warnings)
        CanResolve = (@($blocked).Count -eq 0)
        Fingerprint = $fingerprint
    }
}

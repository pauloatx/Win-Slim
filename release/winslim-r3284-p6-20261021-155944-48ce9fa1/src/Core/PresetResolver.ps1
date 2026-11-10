<#
    Win-Slim Suite - Preset Resolver (FASE 6 R1)

    Camada pura de composição de presets canônicos.
    - NÃO altera Windows.
    - NÃO altera o catálogo validado da Fase 5.
    - Resolve Balanceado/Gamer/Extremo a partir de presets/WinSlim-Presets-R1.json.
    - Entrega SelectedIds + LevelSelections ao Planner já validado.

    Compatibilidade alvo: Windows PowerShell 5.1.
#>

$script:WinSlimPresetResolverSchemaVersion = 1

function Get-WinSlimPresetProperty {
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

function Import-WinSlimPresetCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Arquivo de presets não encontrado: $Path"
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Falha ao carregar catálogo de presets '$Path': $($_.Exception.Message)"
    }
    if ([string](Get-WinSlimPresetProperty $obj 'schemaVersion' '') -ne '1.0') {
        throw "schemaVersion de preset não suportada. Esperado 1.0."
    }
    return $obj
}

function Get-WinSlimPresetDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetCatalog,
        [Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName
    )

    $presets = Get-WinSlimPresetProperty $PresetCatalog 'presets' $null
    if ($null -eq $presets) { throw 'Objeto presets ausente no catálogo canônico.' }
    $prop = $presets.PSObject.Properties[$PresetName]
    if ($null -eq $prop) { throw "Preset '$PresetName' ausente no catálogo canônico." }
    return $prop.Value
}

function ConvertTo-WinSlimPresetLevelMap {
    param($LevelSelections)
    $map = @{}
    if ($null -eq $LevelSelections) { return $map }
    if ($LevelSelections -is [System.Collections.IDictionary]) {
        foreach ($k in @($LevelSelections.Keys)) { $map[[string]$k] = [int]$LevelSelections[$k] }
        return $map
    }
    foreach ($p in @($LevelSelections.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })) {
        $map[$p.Name] = [int]$p.Value
    }
    return $map
}

function Resolve-WinSlimPresetSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetCatalog,
        [Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName
    )

    $def = Get-WinSlimPresetDefinition -PresetCatalog $PresetCatalog -PresetName $PresetName
    $ids = @()
    $seen = @{}
    foreach ($id0 in @(Get-WinSlimPresetProperty $def 'selectedIds' @())) {
        $id = ([string]$id0).Trim()
        if (-not $id) { continue }
        if (-not $seen.ContainsKey($id)) {
            $seen[$id] = $true
            $ids += $id
        }
    }
    $levels = ConvertTo-WinSlimPresetLevelMap (Get-WinSlimPresetProperty $def 'levelSelections' $null)

    return [PSCustomObject]@{
        PresetName       = $PresetName
        SelectedIds      = @($ids)
        LevelSelections  = $levels
        ConflictPolicy   = [string](Get-WinSlimPresetProperty $def 'conflictPolicy' 'Block')
        Description      = [string](Get-WinSlimPresetProperty $def 'description' '')
        ExpectedCount    = [int](Get-WinSlimPresetProperty $def 'expectedSelectedCount' $ids.Count)
    }
}

function Test-WinSlimPresetCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetCatalog,
        [Parameter(Mandatory)]$CatalogTweaks
    )

    $issues = @()
    $catalogIds = @{}
    $riskById = @{}
    foreach ($t in @($CatalogTweaks)) {
        $id = [string](Get-WinSlimPresetProperty $t 'id' '')
        if (-not $id) { continue }
        $catalogIds[$id] = $true
        $riskById[$id] = [string](Get-WinSlimPresetProperty $t 'risk' '')
    }

    $classes = @(Get-WinSlimPresetProperty $PresetCatalog 'classifications' @())
    $classById = @{}
    foreach ($c in $classes) {
        $id = [string](Get-WinSlimPresetProperty $c 'id' '')
        if (-not $id) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='ClassificationMissingId'; TweakId=$null; Message='Classificação sem id.' }
            continue
        }
        if ($classById.ContainsKey($id)) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='DuplicateClassification'; TweakId=$id; Message="Classificação duplicada para '$id'." }
            continue
        }
        $classById[$id] = $c
        if (-not $catalogIds.ContainsKey($id)) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='UnknownClassificationId'; TweakId=$id; Message="Classificação aponta para id inexistente '$id'." }
        }
    }

    foreach ($id in @($catalogIds.Keys)) {
        if (-not $classById.ContainsKey($id)) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='UnclassifiedTweak'; TweakId=$id; Message="Tweak '$id' não foi classificado." }
        }
    }

    foreach ($presetName in @('Balanceado','Gamer','Extremo')) {
        $resolved = Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName $presetName
        if ($resolved.ConflictPolicy -ne 'Block') {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='UnsafeConflictPolicy'; TweakId=$null; Message="Preset '$presetName' deve usar ConflictPolicy=Block." }
        }
        if ($resolved.SelectedIds.Count -ne $resolved.ExpectedCount) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='PresetCountMismatch'; TweakId=$null; Message="Preset '$presetName' esperava $($resolved.ExpectedCount), obteve $($resolved.SelectedIds.Count)." }
        }
        foreach ($id in @($resolved.SelectedIds)) {
            if (-not $catalogIds.ContainsKey($id)) {
                $issues += [PSCustomObject]@{ Severity='Error'; Code='UnknownPresetId'; TweakId=$id; Message="Preset '$presetName' aponta para '$id' inexistente." }
                continue
            }
            if ($riskById[$id] -eq 'Alto') {
                $issues += [PSCustomObject]@{ Severity='Error'; Code='HighRiskInAutomaticPreset'; TweakId=$id; Message="Tweak Alto '$id' não pode entrar em preset automático." }
            }
            if ($classById.ContainsKey($id)) {
                $mode = [string](Get-WinSlimPresetProperty $classById[$id] 'mode' '')
                $declaredPresets = @(Get-WinSlimPresetProperty $classById[$id] 'presets' @())
                if ($mode -ne 'Auto' -or $declaredPresets -notcontains $presetName) {
                    $issues += [PSCustomObject]@{ Severity='Error'; Code='ClassificationPresetDrift'; TweakId=$id; Message="'$id' está no preset '$presetName' mas sua classificação não corresponde." }
                }
            }
        }
    }

    foreach ($id in @($classById.Keys)) {
        $c = $classById[$id]
        $mode = [string](Get-WinSlimPresetProperty $c 'mode' '')
        $declared = @(Get-WinSlimPresetProperty $c 'presets' @())
        if ($mode -ne 'Auto' -and $declared.Count -gt 0) {
            $issues += [PSCustomObject]@{ Severity='Error'; Code='ConditionalHasAutomaticPreset'; TweakId=$id; Message="'$id' tem mode '$mode' mas declara preset automático." }
        }
        if ($mode -eq 'Auto') {
            foreach ($presetName in $declared) {
                $resolved = Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName ([string]$presetName)
                if ($resolved.SelectedIds -notcontains $id) {
                    $issues += [PSCustomObject]@{ Severity='Error'; Code='ClassificationSelectionDrift'; TweakId=$id; Message="Classificação de '$id' declara '$presetName', mas o preset não o seleciona." }
                }
            }
        }
    }

    $errors = @($issues | Where-Object { $_.Severity -eq 'Error' })
    return [PSCustomObject]@{
        Valid               = ($errors.Count -eq 0)
        CatalogCount        = $catalogIds.Count
        ClassificationCount = $classById.Count
        Issues              = @($issues)
    }
}

function New-WinSlimPresetExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetCatalog,
        [Parameter(Mandatory)]$CatalogTweaks,
        [Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName,
        $Context = $null,
        [switch]$SkipApplicabilityChecks
    )

    if (-not (Get-Command New-WinSlimExecutionPlan -ErrorAction SilentlyContinue)) {
        throw 'New-WinSlimExecutionPlan não está carregado. Importe src/Core/Planner.ps1 antes do PresetResolver.'
    }

    $resolved = Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName $PresetName
    if ($resolved.ConflictPolicy -ne 'Block') {
        throw "Preset '$PresetName' usa política de conflito não permitida: $($resolved.ConflictPolicy)"
    }

    # Não passamos PresetName ao Planner nesta fase: o catálogo legado ainda contém
    # memberships antigos. A seleção canônica entra explicitamente por SelectedIds.
    $plan = New-WinSlimExecutionPlan `
        -CatalogTweaks $CatalogTweaks `
        -SelectedIds $resolved.SelectedIds `
        -LevelSelections $resolved.LevelSelections `
        -Context $Context `
        -ConflictPolicy 'Block' `
        -SkipApplicabilityChecks:$SkipApplicabilityChecks

    Add-Member -InputObject $plan -MemberType NoteProperty -Name CanonicalPresetName -Value $PresetName -Force
    Add-Member -InputObject $plan -MemberType NoteProperty -Name PresetResolverSchema -Value $script:WinSlimPresetResolverSchemaVersion -Force
    Add-Member -InputObject $plan -MemberType NoteProperty -Name PresetSelectionCount -Value $resolved.SelectedIds.Count -Force
    return $plan
}

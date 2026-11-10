#requires -Version 5.1
<#!
 Win-Slim Suite - FASE 7 R3
 View-model read-only para perfis condicionais de Presets.

 Este arquivo nao aplica tweaks, nao chama providers e nao altera o Windows.
 Ele apenas traduz metadados ja aprovados do PresetRuntime para a UI e calcula
 elegibilidade visual baseada no snapshot de hardware da R2.
#>

function Get-WinSlimUiObjectProperty {
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

function Get-WinSlimUiConditionalProfileDescriptors {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$PresetRuntime)

    $labels = @{
        'HW-HAGS-ON'='HAGS — agendamento de GPU'
        'HW-MSI-GPU'='MSI Mode — GPU'
        'HW-CORE-PARKING-100'='Core Parking — CPMINCORES 100%'
        'HW-CS2-P-CORES'='CS2 — afinidade P-cores'
        'HW-GPU-IRQ-AFFINITY'='GPU IRQ affinity'
        'WL-VALORANT'='VALORANT'
        'WL-CS2'='Counter-Strike 2'
        'WL-APEX'='Apex Legends'
        'WL-FORTNITE'='Fortnite'
        'WL-GTAV'='GTA V'
        'WL-FSO-OFF'='Fullscreen Optimizations OFF'
        'WL-DEFENDER-DEV-EXCLUSIONS'='Defender — exclusoes de desenvolvimento'
        'WL-STREAMING'='Streaming'
        'WL-VIDEO-EDITING'='Edicao de video'
        'WL-DESIGN'='Design'
        'WL-PROGRAMMING'='Programacao'
    }

    $map = Get-WinSlimUiObjectProperty $PresetRuntime 'ConditionalProfileMap' $null
    $order = @(Get-WinSlimUiObjectProperty $PresetRuntime 'ConditionalProfileOrder' @())
    $result = New-Object System.Collections.ArrayList
    foreach ($name0 in $order) {
        $name = [string]$name0
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $profile = $null
        try { $profile = $map[$name] } catch { }
        if ($null -eq $profile) { continue }
        $label = if ($labels.ContainsKey($name)) { [string]$labels[$name] } else { $name }
        [void]$result.Add([pscustomobject]@{
            Name = $name
            Label = $label
            Kind = [string](Get-WinSlimUiObjectProperty $profile 'kind' '')
            Description = [string](Get-WinSlimUiObjectProperty $profile 'description' '')
            RequiresExplicitOptIn = [bool](Get-WinSlimUiObjectProperty $profile 'requiresExplicitOptIn' $false)
            RequiresHighRiskConsent = [bool](Get-WinSlimUiObjectProperty $profile 'requiresHighRiskConsent' $false)
            EligibilityHints = Get-WinSlimUiObjectProperty $profile 'eligibilityHints' $null
            SelectedIds = @(Get-WinSlimUiObjectProperty $profile 'selectedIds' @())
        })
    }
    return @($result.ToArray())
}

function Test-WinSlimUiConditionalProfileEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Profile,
        $SystemSnapshot = $null
    )

    $eligible = $true
    $reasons = New-Object System.Collections.ArrayList
    $hints = Get-WinSlimUiObjectProperty $Profile 'EligibilityHints' $null

    $requiresGpu = [bool](Get-WinSlimUiObjectProperty $hints 'requiresGPU' $false)
    if ($requiresGpu) {
        $gpuName = [string](Get-WinSlimUiObjectProperty $SystemSnapshot 'GPUName' '')
        if ([string]::IsNullOrWhiteSpace($gpuName) -or $gpuName -match '^(?i)Nao identificado|Indisponivel') {
            $eligible = $false
            [void]$reasons.Add('GPU compativel nao detectada no snapshot atual.')
        }
    }

    $minLogical = 0
    try { $minLogical = [int](Get-WinSlimUiObjectProperty $hints 'minLogicalProcessors' 0) } catch { $minLogical = 0 }
    if ($minLogical -gt 0) {
        $threads = 0
        try { $threads = [int](Get-WinSlimUiObjectProperty $SystemSnapshot 'CPUThreads' 0) } catch { $threads = 0 }
        if ($threads -lt $minLogical) {
            $eligible = $false
            [void]$reasons.Add("Exige ao menos $minLogical processadores logicos; detectados: $threads.")
        }
    }

    $workload = [string](Get-WinSlimUiObjectProperty $hints 'workload' '')
    if (-not [string]::IsNullOrWhiteSpace($workload)) {
        [void]$reasons.Add("Workload: $workload — selecao manual; a R3 nao presume software instalado.")
    }

    if ([bool](Get-WinSlimUiObjectProperty $hints 'providerMaySkipOnUnsupportedTopology' $false)) {
        [void]$reasons.Add('O Provider podera ignorar topologias nao suportadas na etapa de execucao.')
    }

    return [pscustomobject]@{
        ProfileName = [string](Get-WinSlimUiObjectProperty $Profile 'Name' '')
        Eligible = [bool]$eligible
        Reason = (@($reasons.ToArray()) -join ' ')
    }
}

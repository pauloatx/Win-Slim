#requires -Version 5.1
<#!
 Win-Slim Suite - FASE 7 R3.2.24
 Persistent read-only bridge between the native C# WPF UI and the approved PowerShell backend.

 Contract for this subgate:
 - load the approved 230-tweak backend once;
 - expose handshake, snapshot, performance, overlay metadata and preset resolution;
 - Planner/Preview build read-only reports; Transaction/Providers are never invoked;
 - never change Windows state.
#>
[CmdletBinding()]
param(
    [switch]$Server,
    [string]$Action = 'Handshake',
    [string]$RootPath,
    [ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName = 'Balanceado',
    [string]$ProfilesJson = '[]',
    [switch]$AllowHighRisk
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

function ConvertFrom-WinSlimProfilesArgument {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    # First prefer valid JSON. PowerShell 5.1 / native argv can strip the
    # inner quotes of a single-element JSON array, so a tolerant fallback
    # is required for one-shot diagnostics. Server mode always receives
    # canonical JSON over stdin and does not use this fallback.
    try {
        $parsed = $Text | ConvertFrom-Json -ErrorAction Stop
        return @($parsed | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    } catch {
        $normalized = ([string]$Text).Trim()
        if ($normalized.StartsWith('[') -and $normalized.EndsWith(']') -and $normalized.Length -ge 2) {
            $normalized = $normalized.Substring(1, $normalized.Length - 2)
        }
        if ([string]::IsNullOrWhiteSpace($normalized)) { return @() }

        $items = New-Object System.Collections.ArrayList
        foreach ($part0 in @($normalized -split ',')) {
            $part = ([string]$part0).Trim().Trim('"').Trim("'")
            if ($part) { [void]$items.Add($part) }
        }
        return @($items.ToArray())
    }
}

function Get-WinSlimBridgeRoot {
    param([string]$ExplicitRoot)
    if (-not [string]::IsNullOrWhiteSpace($ExplicitRoot)) {
        return (Resolve-Path -LiteralPath $ExplicitRoot -ErrorAction Stop).Path
    }
    $nativeDir = Split-Path -Parent $PSCommandPath
    return (Resolve-Path -LiteralPath (Join-Path $nativeDir '..\..\..\..') -ErrorAction Stop).Path
}

$script:WinSlimBridgeRoot = Get-WinSlimBridgeRoot -ExplicitRoot $RootPath

# Load the approved runtime in the same canonical order used by the FASE 6.5 R4.1 / FASE 7 launchers.
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\Planner.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\Transaction.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\CatalogRuntime.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\PresetResolver.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\PresetPolicyEngine.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\PresetRuntime.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\PresetPlannerValidator.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\PresetPreview.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\PlannerOptimized.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\TransactionOptimized.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\RuntimePromotion.ps1')
Enable-WinSlimRuntimePromotion -Planner -Transaction | Out-Null

. (Join-Path $script:WinSlimBridgeRoot 'src\UI\Fase7\SystemContextView.R2.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\UI\Fase7\PresetOverlayView.R3.ps1')

$catalogFiles = @(
    'catalog.json',
    'catalogs\Game-Workload.json',
    'catalogs\validated\Advanced-Catalog.json',
    'catalogs\validated\Expansion-R4.json',
    'catalogs\validated\Expansion-R4.1.json',
    'catalogs\validated\Expansion-R4.2.json'
)
$allTweaks = New-Object System.Collections.ArrayList
foreach ($relative in $catalogFiles) {
    $path = Join-Path $script:WinSlimBridgeRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Catalogo obrigatorio ausente: $relative" }
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = if ($json.PSObject.Properties.Name -contains 'tweaks') { @($json.tweaks) } else { @($json) }
    foreach ($item in $items) { [void]$allTweaks.Add($item) }
}
$script:AllTweaks = @($allTweaks.ToArray())
if ($script:AllTweaks.Count -ne 230) { throw "Backend inesperado: $($script:AllTweaks.Count) tweaks; esperado: 230." }
if (@($script:AllTweaks.id | Select-Object -Unique).Count -ne 230) { throw 'Backend invalido: IDs duplicados detectados.' }

$presetCatalog = Get-Content -LiteralPath (Join-Path $script:WinSlimBridgeRoot 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ruleCatalog = Get-Content -LiteralPath (Join-Path $script:WinSlimBridgeRoot 'presets\WinSlim-PresetRules-R2.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$script:PresetRuntime = New-WinSlimPresetRuntime -CatalogTweaks $script:AllTweaks -PresetCatalog $presetCatalog -RuleCatalog $ruleCatalog
$script:PromotionStatus = Get-WinSlimRuntimePromotionStatus
$script:SystemSnapshot = $null

function Get-WinSlimBridgeSnapshot {
    if ($null -eq $script:SystemSnapshot) {
        try { $script:SystemSnapshot = Get-WinSlimUiSystemSnapshot } catch { $script:SystemSnapshot = [pscustomobject]@{} }
    }
    return $script:SystemSnapshot
}

function Get-WinSlimBridgeOverlayMetadata {
    $snapshot = Get-WinSlimBridgeSnapshot
    $descriptors = @(Get-WinSlimUiConditionalProfileDescriptors -PresetRuntime $script:PresetRuntime)
    $out = New-Object System.Collections.ArrayList
    foreach ($profile in $descriptors) {
        $eligibility = Test-WinSlimUiConditionalProfileEligibility -Profile $profile -SystemSnapshot $snapshot
        [void]$out.Add([pscustomobject]@{
            name = [string]$profile.Name
            label = [string]$profile.Label
            kind = [string]$profile.Kind
            description = [string]$profile.Description
            requiresHighRiskConsent = [bool]$profile.RequiresHighRiskConsent
            eligible = [bool]$eligibility.Eligible
            eligibilityReason = [string]$eligibility.Reason
            selectedIdsCount = @($profile.SelectedIds).Count
        })
    }
    return @($out.ToArray())
}

function ConvertTo-WinSlimBridgeResolvedView {
    param([Parameter(Mandatory)]$Resolved)
    return [pscustomobject]@{
        presetName = [string]$Resolved.PresetName
        baseCount = [int]$Resolved.BaseCount
        requestedConditionalProfiles = @($Resolved.RequestedConditionalProfiles)
        enabledConditionalProfiles = @($Resolved.EnabledConditionalProfiles)
        enabledOverlayCount = @($Resolved.EnabledConditionalProfiles).Count
        selectedCount = @($Resolved.SelectedIds).Count
        selectedTweaks = @($script:AllTweaks | Where-Object { $Resolved.SelectedIds -contains $_.id } | ForEach-Object {
            [pscustomobject]@{
                id=$_.id; name=$_.name; risk=$_.risk; type=$_.type
                windowsVersion=$_.windowsVersion; registry=$_.registry
                commands=$_.InvokeScript; undoCommands=$_.UndoScript
                provider=$_.rollbackClass; hardwareRules=$_.hardwareRules
                dependencies=$_.dependencies; conflicts=$_.conflicts
            }
        })
        blockedCount = @($Resolved.BlockedRequests).Count
        warningCount = @($Resolved.Warnings).Count
        canResolve = [bool]$Resolved.CanResolve
        fingerprint = [string]$Resolved.Fingerprint
        blockedRequests = @($Resolved.BlockedRequests | ForEach-Object {
            [pscustomobject]@{ code=[string]$_.Code; profile=[string]$_.Profile; tweakId=[string]$_.TweakId; message=[string]$_.Message }
        })
        warnings = @($Resolved.Warnings | ForEach-Object {
            [pscustomobject]@{ code=[string]$_.Code; profile=[string]$_.Profile; tweakId=[string]$_.TweakId; message=[string]$_.Message }
        })
    }
}

function Get-WinSlimPreviewContext {
    $s = Get-WinSlimBridgeSnapshot
    $gpu = @(); if ($s.GPUName -and $s.GPUName -ne 'Nao identificado') { $gpu = @([string]$s.GPUName) }
    $network = @(); try { $network = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Select-Object -ExpandProperty Name) } catch { }
    $vbs = $null; if ($s.VBS -eq 'Ativo') { $vbs=$true } elseif ($s.VBS -eq 'Desativado') { $vbs=$false }
    $hvci = $null; if ($s.HVCI -eq 'Ativo') { $hvci=$true } elseif ($s.HVCI -eq 'Desativado') { $hvci=$false }
    $hyperV = $null; try { $f=Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction Stop; $hyperV=[pscustomobject]@{ FeatureInstalled=($f.State.ToString() -eq 'Enabled') } } catch { }
    $major = $null; if ($s.Build) { $major = if ([int]$s.Build -ge 22000) { '11' } else { '10' } }
    [pscustomobject]@{ OS=$major; Build=$s.Build; IsAdmin=[bool]$s.IsAdmin; CPU=$s.CPUName; GPU=@($gpu); RAM=$s.RamGB; Storage=$s.StorageType; PendingReboot=[bool]$s.PendingReboot; TPM=[pscustomobject]@{ Present=([string]$s.TPM -like 'Presente*') }; SecureBoot=[pscustomobject]@{ Enabled=($s.SecureBoot -eq 'Ativo') }; VBS=$vbs; HVCI=$hvci; HyperV=$hyperV; NetworkAdapters=@($network) }
}
function Get-WinSlimPreviewRiskRank {
    param([string]$Risk)
    switch -Regex ($Risk) { '^(High|Alto)$' { return 3 }; '^(Medium|Medio|Médio)$' { return 2 }; '^(Low|Baixo)$' { return 1 }; default { return 0 } }
}
function Get-WinSlimBridgePreview {
    param($Request)
    $context = Get-WinSlimPreviewContext
    $report = Invoke-WinSlimPresetRuntimePlannerValidation -PresetRuntime $script:PresetRuntime -PresetName ([string]$Request.presetName) -ConditionalProfiles @($Request.conditionalProfiles) -AllowHighRiskConditional:([bool]$Request.allowHighRisk) -Context $context
    $preview = New-WinSlimPresetPreview -ValidationReport $report
    $categories = @($preview.Items | Group-Object Category | Sort-Object Name | ForEach-Object {
        $rank=0; foreach($item in $_.Group){$r=Get-WinSlimPreviewRiskRank ([string]$item.Risk);if($r -gt $rank){$rank=$r}}
        $risk=switch($rank){3{'Alto'}2{'Médio'}1{'Baixo'}default{'Não informado'}}
        [pscustomobject]@{ name=$(if($_.Name){$_.Name}else{'Outros'}); count=$_.Count; risk=$risk; restartCount=@($_.Group | Where-Object {$_.RequiresRestart}).Count }
    })
    [pscustomobject]@{ preview=$preview; categories=@($categories); restartCount=@($preview.Items | Where-Object {$_.RequiresRestart}).Count; policyBlocked=@($report.Policy.BlockedRequests); readOnly=$true }
}

function Invoke-WinSlimBridgeAction {
    param(
        [Parameter(Mandatory)][string]$Name,
        $Request = $null
    )

    switch ($Name.ToLowerInvariant()) {
        'handshake' {
            return [pscustomobject]@{
                bridgeVersion = '7.3.2.24'
                backendCount = [int]$script:AllTweaks.Count
                uniqueIds = [int]@($script:AllTweaks.id | Select-Object -Unique).Count
                presets = [pscustomobject]@{
                    Balanceado = [int]@($script:PresetRuntime.PresetSelections['Balanceado'].SelectedIds).Count
                    Gamer = [int]@($script:PresetRuntime.PresetSelections['Gamer'].SelectedIds).Count
                    Extremo = [int]@($script:PresetRuntime.PresetSelections['Extremo'].SelectedIds).Count
                }
                plannerPromoted = ([string]$script:PromotionStatus.Planner -eq 'Optimized')
                transactionPromoted = ([string]$script:PromotionStatus.Transaction -eq 'Optimized')
                processId = $PID
                readOnly = $true
            }
        }
        'snapshot' {
            return Get-WinSlimBridgeSnapshot
        }
        'performance' {
            return Get-WinSlimUiPerformanceSnapshot
        }
        'overlays' {
            return Get-WinSlimBridgeOverlayMetadata
        }
        'preview' { return Get-WinSlimBridgePreview -Request $Request }
        'resolvepreset' {
            $preset = [string]$Request.presetName
            if ([string]::IsNullOrWhiteSpace($preset)) { $preset = 'Balanceado' }
            $profiles = @($Request.conditionalProfiles | ForEach-Object { [string]$_ })
            $allowHigh = [bool]$Request.allowHighRisk
            $resolved = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $script:PresetRuntime -PresetName $preset -ConditionalProfiles $profiles -AllowHighRiskConditional:$allowHigh
            return ConvertTo-WinSlimBridgeResolvedView -Resolved $resolved
        }
        default { throw "Acao de bridge desconhecida: $Name" }
    }
}

function New-WinSlimBridgeEnvelope {
    param([string]$Id, [bool]$Ok, $Data, [string]$ErrorMessage)
    [pscustomobject]@{
        id = $Id
        ok = $Ok
        data = $Data
        error = $ErrorMessage
    }
}

if ($Server) {
    while ($true) {
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $id = ''
        try {
            $request = $line | ConvertFrom-Json -ErrorAction Stop
            $id = [string]$request.id
            $data = Invoke-WinSlimBridgeAction -Name ([string]$request.action) -Request $request
            $envelope = New-WinSlimBridgeEnvelope -Id $id -Ok $true -Data $data -ErrorMessage $null
        } catch {
            $envelope = New-WinSlimBridgeEnvelope -Id $id -Ok $false -Data $null -ErrorMessage $_.Exception.Message
        }
        [Console]::Out.WriteLine(($envelope | ConvertTo-Json -Depth 24 -Compress))
        [Console]::Out.Flush()
    }
    exit 0
}

# One-shot mode is intentionally kept for diagnostics/tests.
try {
    $request = [pscustomobject]@{
        presetName = $PresetName
        conditionalProfiles = @(ConvertFrom-WinSlimProfilesArgument -Text $ProfilesJson)
        allowHighRisk = [bool]$AllowHighRisk.IsPresent
    }
    $payload = Invoke-WinSlimBridgeAction -Name $Action -Request $request
    [Console]::Out.WriteLine(($payload | ConvertTo-Json -Depth 24 -Compress))
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}

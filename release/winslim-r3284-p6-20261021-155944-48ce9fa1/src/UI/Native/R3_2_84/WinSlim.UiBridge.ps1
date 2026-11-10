#requires -Version 5.1
<#!
 Win-Slim Suite - FASE 7 R3.2.84
 Persistent bridge with explicit backup creation between the native C# WPF UI and the approved PowerShell backend.

 Contract for this subgate:
 - load the approved 230-tweak backend once;
 - expose handshake, snapshot, performance, overlay metadata and preset resolution;
 - Planner/Preview build read-only reports; Transaction/Providers are never invoked;
 - GPU service actions are explicit, allowlisted and require a verified backup.
#>
[CmdletBinding()]
param(
    [switch]$Server,
    [switch]$LibraryOnly,
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
. (Join-Path $PSScriptRoot 'WinSlimLivePreview.ps1')
. (Join-Path $PSScriptRoot 'WinSlimBackup.ps1')
. (Join-Path $PSScriptRoot 'WinSlimRegistryApply.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\PlannerOptimized.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\TransactionOptimized.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Core\RuntimePromotion.ps1')
Enable-WinSlimRuntimePromotion -Planner -Transaction | Out-Null

. (Join-Path $script:WinSlimBridgeRoot 'src\UI\Fase7\SystemContextView.R2.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\UI\Native\R3_2_84\WinSlimPerformance.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\UI\Fase7\PresetOverlayView.R3.ps1')

. (Join-Path $PSScriptRoot 'WinSlimGpu.ps1')
. (Join-Path $PSScriptRoot 'WinSlimGpuTransaction.ps1')
. (Join-Path $script:WinSlimBridgeRoot 'src\Providers\CpuAffinityProvider.ps1')
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
. (Join-Path $PSScriptRoot 'WinSlimReviewedCatalog.ps1')
Set-WinSlimReviewedCatalog -Tweaks $script:AllTweaks
Set-WinSlimGpuCatalogContracts -Tweaks $script:AllTweaks
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
    Initialize-WinSlimHardwarePolicy
    $snapshot = Get-WinSlimBridgeSnapshot
    $descriptors = @(Get-WinSlimUiConditionalProfileDescriptors -PresetRuntime $script:PresetRuntime)
    $out = New-Object System.Collections.ArrayList
    foreach ($profile in $descriptors) {
        $eligibility = Test-WinSlimUiConditionalProfileEligibility -Profile $profile -SystemSnapshot $snapshot
        foreach($id in @($profile.SelectedIds)) {
            if($script:HardwareEligibility.ContainsKey($id)) {
                $e=$script:HardwareEligibility[$id]
                if(-not $e.Eligible){$eligibility=[pscustomobject]@{Eligible=$false;Reason=$e.Reason};break}
            }
        }
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
        levelSelections = $Resolved.LevelSelections
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
    Initialize-WinSlimHardwarePolicy
    $gpu = @($script:GpuInventory.Adapters | Where-Object {$_.Available} | ForEach-Object {$_.Vendor+' '+$_.Name})
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
function Get-WinSlimCustomValidationReport {
    param($Request)
    $ids = @($Request.selectedIds)
    if ($ids.Count -eq 0 -or $ids.Count -gt 230) { throw 'Selecione entre 1 e 230 ajustes para a pre-visualizacao.' }
    $seen = @{}
    foreach ($id in $ids) {
        if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id) -or $seen.ContainsKey($id) -or -not $script:PresetRuntime.CatalogRuntime.ById.ContainsKey($id)) {
            throw "ID de ajuste desconhecido, repetido ou invalido: $id"
        }
        $seen[$id] = $true
    }
    Test-WinSlimHardwareSelection -Ids $ids
    $name = [string]$Request.customName
    if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 80 -or $name -match '[\x00-\x1F]') { throw 'Nome de preset personalizado invalido.' }
    $levels = @{}
    if ($null -ne $Request.levelSelections) {
        foreach ($property in $Request.levelSelections.PSObject.Properties) {
            $id = [string]$property.Name
            $value = $property.Value
            $tweak = $script:PresetRuntime.CatalogRuntime.ById[$id]
            if (-not $seen.ContainsKey($id) -or $null -eq $tweak -or ($value -isnot [int] -and $value -isnot [long]) -or $value -lt 0 -or $value -ge @($tweak.levels).Count) { throw "Nivel de ajuste invalido: $id" }
            $levels[$id] = $value
        }
    }
    foreach ($id in $ids) {
        $tweak = $script:PresetRuntime.CatalogRuntime.ById[$id]
        if ([string]$tweak.type -eq 'multilevel' -and -not $levels.ContainsKey($id)) { $levels[$id]=0 }
    }
    $context = Get-WinSlimPreviewContext
    $plan = New-WinSlimExecutionPlan -CatalogTweaks @($script:PresetRuntime.CatalogRuntime.Tweaks) -SelectedIds @($ids) -LevelSelections $levels -Context $context -ConflictPolicy 'Block'
    Test-WinSlimHardwareSelection -Ids @($plan.ExecutionOrder | ForEach-Object {$_.TweakId}) 
    [pscustomobject]@{
        SchemaVersion = 1; Stage = 'Planner'; PresetName = $name; ConditionalProfiles = @()
        PolicyFingerprint = [string]$plan.Fingerprint; PlannerFingerprint = [string]$plan.Fingerprint
        Policy = [pscustomobject]@{ SelectedIds=@($ids); BlockedRequests=@(); CanResolve=$true }
        Plan = $plan; CanResolve=$true; CanExecute=[bool]$plan.CanExecute; HasWork=[bool]$plan.HasWork
        SelectedCount=$ids.Count; DependencyCount=@($plan.ExpandedDependencies).Count
        ExecutableCount=@($plan.ExecutionOrder).Count; SkippedCount=@($plan.SkippedTweaks).Count; BlockedCount=@($plan.BlockedTweaks).Count
        RiskSummary=$plan.RiskSummary; RestartRequirements=$plan.RestartRequirements
    }
}

function Get-WinSlimPreviewCategories {
 param([object[]]$Items)
    @($Items | Group-Object { $name=[string]$_.Category; if(($name -replace '\s','') -ieq 'UI/QoL'){'UI / QoL'}elseif([string]::IsNullOrWhiteSpace($name)){'Outros'}else{$name} } | Sort-Object Name | ForEach-Object {
        $rank=0; foreach($item in $_.Group){$r=Get-WinSlimPreviewRiskRank ([string]$item.Risk);if($r -gt $rank){$rank=$r}}
        $risk=switch($rank){3{'Alto'}2{'Médio'}1{'Baixo'}default{'Não informado'}}
        [pscustomobject]@{ name=$(if($_.Name){$_.Name}else{'Outros'}); count=$_.Count; risk=$risk; restartCount=@($_.Group | Where-Object {$_.RequiresRestart}).Count }
    })
}

function Get-WinSlimBridgePreview {
    param($Request, $CustomReport = $null)
    $script:BackupPreviewSession = $null
    $report = $CustomReport
    if ($null -eq $report) {
        $context = Get-WinSlimPreviewContext
        $report = Get-WinSlimHardwarePresetReport -Request $Request
    }
    $preview = New-WinSlimPresetPreview -ValidationReport $report
    $categories = @(Get-WinSlimPreviewCategories $preview.Items)
    $script:RegistryApplyAuthorization=$null
    $script:RegistryPreviewSession=$null
    $registryCount=0;$registryToken=''
    if($null -ne $report.Plan -and $report.Plan.CanExecute){
        $scope=Get-WinSlimRegistryApplyScope $report.Plan
        $registryCount=$scope.Targets.Count
        if($registryCount -gt 0){
            $registryToken=[Guid]::NewGuid().ToString('N')
            $script:RegistryPreviewSession=[pscustomobject]@{Token=$registryToken;CreatedUtc=[DateTime]::UtcNow;Request=($Request | ConvertTo-Json -Depth 24 | ConvertFrom-Json);Fingerprint=[string]$report.Plan.Fingerprint}
        }
    }
    $liveState = Get-WinSlimLivePreview -Plan $report.Plan
    $canBackup=$null -ne $report.Plan -and [bool]$report.Plan.CanExecute -and @($report.Plan.ExecutionOrder | Where-Object {$_.Tweak.type -in @('registry','service')}).Count -gt 0
    $token=''
    if($canBackup){
        $token=[Guid]::NewGuid().ToString('N')
        $script:BackupPreviewSession=[pscustomobject]@{Token=$token;CreatedUtc=[DateTime]::UtcNow;Request=($Request | ConvertTo-Json -Depth 24 | ConvertFrom-Json);Fingerprint=[string]$report.Plan.Fingerprint;Profile=[string]$report.PresetName}
    }
    [pscustomobject]@{ registryApplyCount=$registryCount; registryPreviewToken=$registryToken; backupToken=$token; canCreateBackup=$canBackup; liveState=$liveState; preview=$preview; categories=@($categories); restartCount=@($preview.Items | Where-Object {$_.RequiresRestart}).Count; policyBlocked=@($report.Policy.BlockedRequests); readOnly=$true }
}

function Get-WinSlimBridgeTweakDetail {
    param($Request)
    $id = [string]$Request.tweakId
    $tweak = Get-WinSlimRuntimeTweak -CatalogRuntime $script:PresetRuntime.CatalogRuntime -TweakId $id
    if ($null -eq $tweak) { throw "Ajuste nao encontrado: $id" }
    $context = Get-WinSlimPreviewContext
    $app = Test-WinSlimTweakApplicability -Tweak $tweak -Context $context
    $dependencyNames = @($tweak.dependencies | ForEach-Object { $t=$script:PresetRuntime.CatalogRuntime.ById[[string]$_]; if($null -ne $t){[string]$t.name}else{[string]$_} })
    $conflictNames = @($tweak.conflicts | ForEach-Object { $t=$script:PresetRuntime.CatalogRuntime.ById[[string]$_]; if($null -ne $t){[string]$t.name}else{[string]$_} })
    $hardware = if($app.Hardware.Applicable -eq $true){'Hardware compativel'}elseif($app.Hardware.Reason){[string]$app.Hardware.Reason}else{'Compatibilidade de hardware nao confirmada'}
    $rollback = if(@($tweak.rollbackClass).Count -gt 0){'Previsto no catalogo'}else{'Nao informado'}
    $warning = [string]$tweak.activationNote
    if ([string]::IsNullOrWhiteSpace($warning)) {
        $warning = switch([string]$tweak.risk) {
            'Alto' {'Ajuste avancado: pode afetar recursos e a estabilidade. Confira o plano e o backup antes de uma aplicacao real.'}
            'Médio' {'Este ajuste pode alterar o comportamento do sistema. Confira se ele atende ao seu uso antes de continuar.'}
            default {'Confira a descricao e a compatibilidade antes de continuar.'}
        }
    }
    if($app.Decision -ne 'Apply' -and $app.Reason){$warning += "`n" + [string]$app.Reason}
    if($tweak.rollbackNote){$warning += "`nRollback: " + [string]$tweak.rollbackNote}
    if($script:HardwareEligibility.ContainsKey($id) -and -not $script:HardwareEligibility[$id].Eligible){
        $app.Decision='Block';$hardware=$script:HardwareEligibility[$id].Reason;$warning=$hardware
    }
    return [pscustomobject]@{
        readOnly=$true
        tweak=($tweak | Select-Object id,name,plainName,@{Name='description';Expression={if($_.id -eq 'PILOT-003'){'Ativa o Modo de Jogo do Windows para o usuário atual. O resultado varia conforme o jogo e o sistema; não garante aumento de FPS. Feche e reabra o jogo após aplicar.'}else{$_.description}}},category,risk,requiresRestart,restartScope,windowsVersion,experimental)
        applicability=$app; hardwareText=$hardware; rollbackText=$rollback; warning=$warning
        dependencyNames=@($dependencyNames); conflictNames=@($conflictNames)
    }
}

function Invoke-WinSlimBridgeAction {
    param(
        [Parameter(Mandatory)][string]$Name,
        $Request = $null
    )

    switch ($Name.ToLowerInvariant()) {
        'handshake' {
            return [pscustomobject]@{
                bridgeVersion = '7.3.2.84'
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
                readOnly = $false
                systemReadOnly = $false
                gpuServiceActions = $true
                backupCreation = $true
                backupRestoration = $true
                registryApplication = $true
                registryApplicationIds = @('PERF-001','UI-007','UI-008','UI-009','UI-014','UI-015','UI-016','PILOT-001','PRIV-017','PILOT-003','EDGE-001','EDGE-002','UI-006','UI-004','UI-001','UI-010','UI-017','UI-021','UI-023','UI-024','QOL-003','QOL-008','QOL-012','EDGE-003','EDGE-004','EDGE-005','EDGE-006','EDGE-008','EDGE-011','EDGE-012','EDGE-016','EDGE-019','EDGE-020','EDGE-024','EDGE-025')
            }
        }
        'gpu' { return Get-WinSlimGpuView }
        'gpuaction' { return Invoke-WinSlimGpuAction -Request $Request }
        'catalog' {
            Initialize-WinSlimHardwarePolicy
            return [pscustomobject]@{
                readOnly = $true
                tweaks = @($script:PresetRuntime.CatalogRuntime.Tweaks | Select-Object id,name,plainName,@{Name='description';Expression={if($_.id -eq 'PILOT-003'){'Ativa o Modo de Jogo do Windows para o usuário atual. O resultado varia conforme o jogo e o sistema; não garante aumento de FPS. Feche e reabra o jogo após aplicar.'}else{$_.description}}},@{Name='category';Expression={if($script:HardwareEligibility.ContainsKey([string]$_.id) -and $script:HardwareEligibility[[string]$_.id].Group -ne 'CPU'){'Performance / GPU'}else{$_.category}}},risk,requiresRestart,windowsVersion,@{Name='eligible';Expression={if($script:HardwareEligibility.ContainsKey([string]$_.id)){$script:HardwareEligibility[[string]$_.id].Eligible}else{$true}}},@{Name='eligibilityReason';Expression={if($script:HardwareEligibility.ContainsKey([string]$_.id)){$script:HardwareEligibility[[string]$_.id].Reason}else{''}}},@{Name="levelCount";Expression={if($null -eq $_.levels){0}else{@($_.levels).Count}}})
            }
        }
        'snapshot' {
            return Get-WinSlimBridgeSnapshot
        }
        'performance' {
            return Get-WinSlimUiPerformanceSnapshot -OnMetric {
                param($metric,$value)
                if ($Server -and -not [string]::IsNullOrWhiteSpace($script:RegistryRequestId)) {
                    $sample=@{metric=$metric}; $sample[$metric]=$value
                    $frame=@{id=$script:RegistryRequestId;event='performanceProgress';data=$sample}
                    [Console]::Out.WriteLine(($frame | ConvertTo-Json -Depth 6 -Compress))
                    [Console]::Out.Flush()
                }
            }
        }
        'overlays' {
            return Get-WinSlimBridgeOverlayMetadata
        }
        'registryapplypreview' { return New-WinSlimRegistryApplyPreview -Request $Request }
        'registryapply' { return Invoke-WinSlimRegistryApply -Request $Request }
        'restorepreview' { return New-WinSlimRestorePreview -Request $Request }
        'restorebackup' { return Invoke-WinSlimBackupRestore -Request $Request }
        'createbackup' { return New-WinSlimBridgeBackup -Request $Request }
        'backupinventory' { return Get-WinSlimBackupInventory -Root (Join-Path $script:WinSlimBridgeRoot 'Backups\UI') }
        'backupdetails' {
            $backupId=[string]$Request.backupId
            if($backupId -notmatch '\A[a-f0-9]{32}\z'){throw 'ID de backup invalido.'}
            return Read-WinSlimVerifiedBackup -Directory (Join-Path (Join-Path $script:WinSlimBridgeRoot 'Backups\UI') $backupId)
        }
        'preview' { return Get-WinSlimBridgePreview -Request $Request }
        'tweakdetails' { return Get-WinSlimBridgeTweakDetail -Request $Request }
        'custompreview' {
            $report = Get-WinSlimCustomValidationReport -Request $Request
            return Get-WinSlimBridgePreview -Request $Request -CustomReport $report
        }
        'resolvepreset' {
            $preset = [string]$Request.presetName
            if ([string]::IsNullOrWhiteSpace($preset)) { $preset = 'Balanceado' }
            $profiles = @($Request.conditionalProfiles | ForEach-Object { [string]$_ })
            $allowHigh = [bool]$Request.allowHighRisk
            $resolved = Resolve-WinSlimHardwarePreset -Preset $preset -Profiles $profiles -AllowHigh $allowHigh
            return ConvertTo-WinSlimBridgeResolvedView -Resolved $resolved
        }
        default { throw "Acao de bridge desconhecida: $Name" }
    }
}

function New-WinSlimBridgeBackup {
    param($Request)
    $session=$script:BackupPreviewSession
    if($null -eq $session -or [string]::IsNullOrWhiteSpace([string]$Request.backupToken) -or [string]$Request.backupToken -cne [string]$session.Token){throw 'Pre-visualizacao expirada. Abra o plano novamente.'}
    $script:BackupPreviewSession=$null
    if(([DateTime]::UtcNow-$session.CreatedUtc).TotalMinutes -gt 10){throw 'Pre-visualizacao expirada. Abra o plano novamente.'}
    $source=$session.Request
    if($source.PSObject.Properties.Name -contains 'selectedIds'){
        $report=Get-WinSlimCustomValidationReport -Request $source
    }else{
        $context=Get-WinSlimPreviewContext
        $report=Get-WinSlimHardwarePresetReport -Request $source
    }
    if($null -eq $report.Plan -or -not $report.Plan.CanExecute -or [string]$report.Plan.Fingerprint -cne [string]$session.Fingerprint){throw 'O plano mudou. Revise a pre-visualizacao antes de criar o backup.'}
    $snapshot=New-WinSlimBackupSnapshot -Plan $report.Plan -Profile $session.Profile
    Save-WinSlimBackupSnapshot -Root (Join-Path $script:WinSlimBridgeRoot 'Backups\UI') -Snapshot $snapshot
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

if ($LibraryOnly) { return }

if ($Server) {
    while ($true) {
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { break }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $id = ''
        try {
            $request = $line | ConvertFrom-Json -ErrorAction Stop
            $id = [string]$request.id
            $script:RegistryRequestId=$id
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

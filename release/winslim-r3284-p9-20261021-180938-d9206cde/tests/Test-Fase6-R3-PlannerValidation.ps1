$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.ArrayList

function Assert-Fase6R3 {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  [OK] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        [void]$script:Failures.Add($Message)
    }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-BackendCatalog {
    $paths = @(
        'catalog.json',
        'catalogs\Game-Workload.json',
        'catalogs\validated\Advanced-Catalog.json',
        'catalogs\validated\Expansion-R4.json',
        'catalogs\validated\Expansion-R4.1.json',
        'catalogs\validated\Expansion-R4.2.json'
    )
    $items = @()
    foreach ($rel in $paths) {
        $doc = Read-JsonFile (Join-Path $Root $rel)
        $items += @($doc.tweaks)
    }
    return @($items)
}

function Get-ExpectedPresetCount {
    param($ScenarioSpec, [string]$PresetName)
    $p = $ScenarioSpec.basePresets.PSObject.Properties[$PresetName]
    if ($null -eq $p) { return -1 }
    return [int]$p.Value.expectedSelectedCount
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Win-Slim Suite - FASE 6 R3 / Planner Deep Validation' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'R3: matriz Win10/11 + 16 overlays + invariantes Planner sem mutação do Windows' -ForegroundColor DarkGray

. (Join-Path $Root 'src\Core\Planner.ps1')
. (Join-Path $Root 'src\Core\PresetResolver.ps1')
. (Join-Path $Root 'src\Core\PresetPolicyEngine.ps1')
. (Join-Path $Root 'src\Core\PresetPlannerValidator.ps1')

$PresetCatalog = Import-WinSlimPresetCatalog -Path (Join-Path $Root 'presets\WinSlim-Presets-R1.json')
$RuleCatalog = Import-WinSlimPresetPolicyRules -Path (Join-Path $Root 'presets\WinSlim-PresetRules-R2.json')
$ScenarioSpec = Read-JsonFile (Join-Path $Root 'specs\FASE6-R3-scenarios.json')
$AllTweaks = @(Get-BackendCatalog)

Write-Host "`n=== TEST 00: baseline Fase 6 R2 congelada + schema R3 ===" -ForegroundColor Yellow
$baseline = Read-JsonFile (Join-Path $Root 'specs\FASE6-R3-baseline.json')
foreach ($prop in @($baseline.files.PSObject.Properties)) {
    $rel = [string]$prop.Name
    $expected = ([string]$prop.Value).ToLowerInvariant()
    $target = Join-Path $Root $rel
    $ok = $false
    if (Test-Path -LiteralPath $target) {
        $actual = ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash).ToLowerInvariant()
        $ok = ($actual -eq $expected)
    }
    Assert-Fase6R3 $ok "baseline R2 congelada: $rel"
}
Assert-Fase6R3 ([string]$ScenarioSpec.schemaVersion -eq '1.0') 'scenario spec R3 usa schemaVersion 1.0'
Assert-Fase6R3 ($AllTweaks.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert-Fase6R3 ((@($AllTweaks.id | Sort-Object -Unique)).Count -eq 230) '230 IDs permanecem únicos'
Assert-Fase6R3 (@($ScenarioSpec.conditionalProfiles).Count -eq 16) 'scenario spec cobre os 16 perfis condicionais R2'

Write-Host "`n=== TEST 01: camada PresetPlannerValidator pura + shape normalizado ===" -ForegroundColor Yellow
$validatorText = Get-Content -LiteralPath (Join-Path $Root 'src\Core\PresetPlannerValidator.ps1') -Raw -Encoding UTF8
$mutationTokens = @('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Set-Service','Register-ScheduledTask','Unregister-ScheduledTask','bcdedit.exe','powercfg.exe','Invoke-NativeCommand')
$foundMutation = @()
foreach ($token in $mutationTokens) {
    if ($validatorText -match [regex]::Escape($token)) { $foundMutation += $token }
}
Assert-Fase6R3 ($foundMutation.Count -eq 0) 'PresetPlannerValidator não contém primitivos de mutação do Windows'

$ctx11 = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true
$shape = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -Context $ctx11
Assert-Fase6R3 ($shape.Stage -eq 'Planner' -and $shape.CanResolve -and $shape.CanExecute) 'validator resolve Policy -> Planner com sucesso'
Assert-Fase6R3 ($null -ne $shape.Policy -and $null -ne $shape.Plan) 'validator preserva Policy e Plan para preview/auditoria'
Assert-Fase6R3 ([string]::IsNullOrWhiteSpace($shape.PolicyFingerprint) -eq $false) 'validator expõe PolicyFingerprint'
Assert-Fase6R3 ([string]::IsNullOrWhiteSpace($shape.PlannerFingerprint) -eq $false) 'validator expõe PlannerFingerprint'
Assert-Fase6R3 ($shape.SelectedCount -eq 105) 'validator preserva contagem Balanceado=105'

Write-Host "`n=== TEST 02: matriz base Balanceado/Gamer/Extremo em Windows 10 e 11 ===" -ForegroundColor Yellow
$baseReports = @{}
foreach ($os in @('10','11')) {
    $ctx = New-WinSlimSyntheticPlannerContext -OS $os -IsAdmin $true
    foreach ($name in @('Balanceado','Gamer','Extremo')) {
        $key = "$name-Win$os"
        $r1 = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName $name -Context $ctx
        $r2 = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName $name -Context $ctx
        $baseReports[$key] = $r1
        $expected = Get-ExpectedPresetCount -ScenarioSpec $ScenarioSpec -PresetName $name

        Assert-Fase6R3 ($r1.CanResolve -and $r1.CanExecute) "$name / Windows $os chega ao Planner sem Block"
        Assert-Fase6R3 ($r1.SelectedCount -eq $expected) "$name / Windows $os preserva seleção canônica $expected"
        Assert-Fase6R3 ($r1.Plan.Conflicts.Count -eq 0 -and $r1.Plan.MutexDecisions.Count -eq 0) "$name / Windows $os não produz conflict/mutex pendente"
        Assert-Fase6R3 ($r1.RiskSummary.High -eq 0) "$name / Windows $os mantém risco Alto automático em zero"
        Assert-Fase6R3 ($r1.PlannerFingerprint -eq $r2.PlannerFingerprint) "$name / Windows $os tem fingerprint Planner determinístico"
        Assert-Fase6R3 ($r1.PolicyFingerprint -eq $r2.PolicyFingerprint) "$name / Windows $os tem fingerprint Policy determinístico"
    }
}
foreach ($name in @('Balanceado','Gamer','Extremo')) {
    $w10 = $baseReports["$name-Win10"]
    $w11 = $baseReports["$name-Win11"]
    Assert-Fase6R3 ($w10.PolicyFingerprint -eq $w11.PolicyFingerprint) "$name mantém PolicyFingerprint independente do OS"
    Assert-Fase6R3 ($w10.PlannerFingerprint -ne $w11.PlannerFingerprint) "$name muda PlannerFingerprint entre Windows 10 e 11"
}

Write-Host "`n=== TEST 03: dependências/topologia + stack de 14 overlays não-Alto ===" -ForegroundColor Yellow
$mediumProfiles = @($ScenarioSpec.mediumStack.profiles | ForEach-Object { [string]$_ })
$mediumA = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles $mediumProfiles -Context $ctx11
$mediumB = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @($mediumProfiles | Sort-Object -Descending) -Context $ctx11
Assert-Fase6R3 ($mediumProfiles.Count -eq 14) 'stack R3 contém exatamente 14 overlays não-Alto'
Assert-Fase6R3 ($mediumA.CanResolve -and $mediumA.CanExecute) 'Gamer + 14 overlays não-Alto chega ao Planner sem Block'
Assert-Fase6R3 ($mediumA.SelectedCount -eq [int]$ScenarioSpec.mediumStack.expectedSelectedCount) 'Gamer + 14 overlays resulta em 143 seleções'
Assert-Fase6R3 ($mediumA.RiskSummary.High -eq 0) 'stack não-Alto mantém RiskSummary.High=0'
Assert-Fase6R3 ($mediumA.PolicyFingerprint -eq $mediumB.PolicyFingerprint) 'ordem dos 14 overlays não altera PolicyFingerprint'
Assert-Fase6R3 ($mediumA.PlannerFingerprint -eq $mediumB.PlannerFingerprint) 'ordem dos 14 overlays não altera PlannerFingerprint'

$topology = Test-WinSlimExecutionOrderDependencies -Plan $mediumA.Plan
Assert-Fase6R3 $topology.Valid 'ExecutionOrder mantém toda dependência ativa antes do depender'
Assert-Fase6R3 ((@($mediumA.Plan.ExecutionOrder.TweakId | Sort-Object -Unique)).Count -eq @($mediumA.Plan.ExecutionOrder).Count) 'ExecutionOrder não contém TweakId duplicado'
Assert-Fase6R3 ((@($mediumA.Plan.ExpandedDependencies | Sort-Object -Unique)).Count -eq @($mediumA.Plan.ExpandedDependencies).Count) 'ExpandedDependencies não contém duplicatas'

Write-Host "`n=== TEST 04: os 16 perfis condicionais atravessam Policy -> Planner individualmente ===" -ForegroundColor Yellow
$profilePass = 0
foreach ($profile in @($ScenarioSpec.conditionalProfiles)) {
    $name = [string]$profile.name
    $requiresHigh = [bool]$profile.requiresHighRiskConsent
    $report = Invoke-WinSlimPresetPlannerValidation `
        -PresetCatalog $PresetCatalog `
        -RuleCatalog $RuleCatalog `
        -CatalogTweaks $AllTweaks `
        -PresetName 'Gamer' `
        -ConditionalProfiles @($name) `
        -AllowHighRiskConditional:$requiresHigh `
        -Context $ctx11

    $selectedOk = $true
    foreach ($id0 in @($profile.selectedIds)) {
        $id = [string]$id0
        if ($report.Policy.SelectedIds -notcontains $id) { $selectedOk = $false }
    }
    $riskOk = if ($requiresHigh) { [int]$report.RiskSummary.High -eq 1 } else { [int]$report.RiskSummary.High -eq 0 }
    $ok = ($report.CanResolve -and $report.CanExecute -and $selectedOk -and $riskOk)
    if ($ok) { $profilePass++ }
    Assert-Fase6R3 $ok "perfil $name atravessa Policy -> Planner com risco esperado"
}
Assert-Fase6R3 ($profilePass -eq 16) 'todos os 16 perfis condicionais passam individualmente no Planner'

Write-Host "`n=== TEST 05: aplicabilidade real - admin, OS e GPU ===" -ForegroundColor Yellow
$noGpuCtx = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true -NoGpu
$noGpu = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @('HW-MSI-GPU') -Context $noGpuCtx
Assert-Fase6R3 ($noGpu.CanResolve -and $noGpu.CanExecute) 'GPU ausente gera Skip aplicável, não Block estrutural'
Assert-Fase6R3 ((@($noGpu.Plan.SkippedTweaks | Where-Object { $_.TweakId -eq 'PERF-018' -and $_.ReasonCode -eq 'GpuRequired' })).Count -eq 1) 'HW-MSI-GPU sem GPU resulta em GpuRequired/Skip'

$noGpuHigh = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @('HW-GPU-IRQ-AFFINITY') -AllowHighRiskConditional -Context $noGpuCtx
Assert-Fase6R3 ($noGpuHigh.CanResolve -and $noGpuHigh.CanExecute) 'GPU IRQ consentido sem GPU também não cria Block estrutural'
Assert-Fase6R3 ((@($noGpuHigh.Plan.SkippedTweaks | Where-Object { $_.TweakId -eq 'WS-ADV-003' -and $_.ReasonCode -eq 'GpuRequired' })).Count -eq 1) 'GPU IRQ sem GPU resulta em GpuRequired/Skip'

$nonAdminCtx = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $false
$nonAdmin = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -Context $nonAdminCtx
Assert-Fase6R3 (-not $nonAdmin.CanExecute) 'contexto não-admin bloqueia preset com operações administrativas'
$nonAdminReasons = @($nonAdmin.Plan.BlockedTweaks | Where-Object { $_.ReasonCode -eq 'RequiresAdmin' })
Assert-Fase6R3 ($nonAdminReasons.Count -gt 0) 'bloqueio não-admin usa ReasonCode RequiresAdmin'

$missingOsContext = [PSCustomObject]@{
    IsAdmin=$true; RAM=16; Storage='SSD'; PendingReboot=$false; CPU='Synthetic CPU'; GPU=@('NVIDIA Synthetic GPU')
}
$missingOs = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -Context $missingOsContext
Assert-Fase6R3 (-not $missingOs.CanExecute) 'Context.OS ausente bloqueia em vez de assumir uma versão do Windows'
Assert-Fase6R3 ((@($missingOs.Plan.BlockedTweaks | Where-Object { $_.ReasonCode -eq 'MissingContextOS' })).Count -gt 0) 'OS ausente usa ReasonCode MissingContextOS'

Write-Host "`n=== TEST 06: RiskSummary e RestartRequirements batem exatamente com ExecutionOrder ===" -ForegroundColor Yellow
$invariantReports = @(
    $baseReports['Balanceado-Win11'],
    $baseReports['Gamer-Win11'],
    $baseReports['Extremo-Win11'],
    $mediumA
)
foreach ($r in $invariantReports) {
    $riskInvariant = Test-WinSlimPlannerRiskSummaryInvariant -Plan $r.Plan
    $restartInvariant = Test-WinSlimPlannerRestartInvariant -Plan $r.Plan
    Assert-Fase6R3 $riskInvariant.Valid "$($r.PresetName): RiskSummary corresponde exatamente aos itens executáveis"
    Assert-Fase6R3 $restartInvariant.Valid "$($r.PresetName): RestartRequirements corresponde exatamente aos itens executáveis"
}

Write-Host "`n=== TEST 07: fingerprint - determinismo e sensibilidade controlada ===" -ForegroundColor Yellow
$threeA = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -ConditionalProfiles @('WL-CS2','HW-HAGS-ON','HW-MSI-GPU') -Context $ctx11
$threeB = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -ConditionalProfiles @('HW-MSI-GPU','WL-CS2','HW-HAGS-ON') -Context $ctx11
$baseBalanced = $baseReports['Balanceado-Win11']
Assert-Fase6R3 ($threeA.PolicyFingerprint -eq $threeB.PolicyFingerprint) 'permutação de overlays preserva PolicyFingerprint'
Assert-Fase6R3 ($threeA.PlannerFingerprint -eq $threeB.PlannerFingerprint) 'permutação de overlays preserva PlannerFingerprint'
Assert-Fase6R3 ($threeA.PolicyFingerprint -ne $baseBalanced.PolicyFingerprint) 'adicionar overlays altera PolicyFingerprint'
Assert-Fase6R3 ($threeA.PlannerFingerprint -ne $baseBalanced.PlannerFingerprint) 'adicionar overlays altera PlannerFingerprint'

$pendingCtx = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true -PendingReboot
$pending = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -Context $pendingCtx
Assert-Fase6R3 ((@($pending.Plan.Warnings | Where-Object { $_.Code -eq 'PendingReboot' })).Count -eq 1) 'PendingReboot gera warning estruturado no Planner'
Assert-Fase6R3 ([bool]$pending.Plan.RestartRequirements.PendingRebootBeforePlan) 'RestartRequirements registra reboot pendente anterior ao plano'

Write-Host "`n=== TEST 08: shape Planner -> Transaction sem mutação ===" -ForegroundColor Yellow
$txItems = @(Get-WinSlimTransactionItemsFromPlan -Plan $mediumA.Plan)
Assert-Fase6R3 ($txItems.Count -eq @($mediumA.Plan.ExecutionOrder).Count) 'plano válido converte 1:1 para itens de Transaction'
Assert-Fase6R3 ((@($txItems.TweakId) -join '|') -eq (@($mediumA.Plan.ExecutionOrder.TweakId) -join '|')) 'conversão para Transaction preserva ordem de execução'
Assert-Fase6R3 ((@($txItems | Where-Object { $null -eq $_.Tweak -or [string]::IsNullOrWhiteSpace([string]$_.TweakId) })).Count -eq 0) 'itens de Transaction preservam Tweak e TweakId'

$blockedThrow = $false
try {
    [void](Get-WinSlimTransactionItemsFromPlan -Plan $nonAdmin.Plan)
} catch {
    $blockedThrow = $true
}
Assert-Fase6R3 $blockedThrow 'plano bloqueado não pode virar itens transacionais'

Write-Host "`n=== TEST 09: proteção do backend/UI legado + fechamento R3 ===" -ForegroundColor Yellow
$baseDoc = Read-JsonFile (Join-Path $Root 'catalog.json')
$workloadDoc = Read-JsonFile (Join-Path $Root 'catalogs\Game-Workload.json')
Assert-Fase6R3 ($baseDoc.tweaks.Count -eq 177 -and $workloadDoc.tweaks.Count -eq 10) 'UI/autoload legado permanece em 187 entradas'
Assert-Fase6R3 ($AllTweaks.Count -eq 230) 'backend validado permanece em 230 entradas'
Assert-Fase6R3 ((Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Balanceado').SelectedIds.Count -eq 105) 'Balanceado permanece 105'
Assert-Fase6R3 ((Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Gamer').SelectedIds.Count -eq 129) 'Gamer permanece 129'
Assert-Fase6R3 ((Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Extremo').SelectedIds.Count -eq 168) 'Extremo permanece 168'

Write-Host "`n=== RESUMO FASE 6 R3 ===" -ForegroundColor Cyan
if ($Failures.Count -eq 0) {
    Write-Host 'FASE 6 R3 APROVADA - presets e 16 overlays validados profundamente no Planner; dependências, risco, restart, fingerprints e shape transacional preservados.' -ForegroundColor Green
    Write-Host 'Próximo subgate: FASE 6 R4 - Preview + integração Transaction Manager sem aplicar mudanças reais no harness.' -ForegroundColor Cyan
    exit 0
}

Write-Host "FASE 6 R3 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $Failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1

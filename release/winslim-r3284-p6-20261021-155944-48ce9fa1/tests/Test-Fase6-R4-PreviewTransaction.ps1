$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.ArrayList

function Assert-Fase6R4 {
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

function Get-Fase6R4TweakId {
    param($Tweak)
    if ($null -eq $Tweak) { return '' }
    if ($Tweak.PSObject.Properties.Name -contains 'id') { return [string]$Tweak.id }
    if ($Tweak.PSObject.Properties.Name -contains 'Id') { return [string]$Tweak.Id }
    return ''
}

function Invoke-Fase6R4SyntheticBackup {
    param($Tweak, $Level, $Context, $Step)
    $id = Get-Fase6R4TweakId $Tweak
    return [PSCustomObject]@{
        Marker = 'Before'
        TweakId = $id
        Level = [int]$Level
    }
}

function Invoke-Fase6R4SyntheticApply {
    param($Tweak, $Level, $Context)
    $id = Get-Fase6R4TweakId $Tweak
    $failId = ''
    if ($null -ne $Context -and $Context.PSObject.Properties.Name -contains 'FailureTweakId') {
        $failId = [string]$Context.FailureTweakId
    }
    if ($failId -and $id -eq $failId) {
        return [PSCustomObject]@{
            Id = $id
            Action = 'Apply'
            Success = $false
            Changed = $false
            StateBefore = $null
            StateAfter = $null
            Verification = [PSCustomObject]@{ Applicable=$true; Success=$false; Detail='SyntheticFailure' }
            Restart = 'None'
            Warning = $null
            Error = 'Falha sintética R4 solicitada pelo harness.'
        }
    }

    $restart = 'None'
    if ($Tweak.PSObject.Properties.Name -contains 'restartScope') {
        $candidate = [string]$Tweak.restartScope
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $restart = $candidate }
    }
    return [PSCustomObject]@{
        Id = $id
        Action = 'Apply'
        Success = $true
        Changed = $true
        StateBefore = [PSCustomObject]@{ Marker='Before'; TweakId=$id; Level=[int]$Level }
        StateAfter = [PSCustomObject]@{ Marker='After'; TweakId=$id; Level=[int]$Level }
        Verification = [PSCustomObject]@{ Applicable=$true; Success=$true; Detail='SyntheticVerified' }
        Restart = $restart
        Warning = $null
        Error = $null
    }
}

function Invoke-Fase6R4SyntheticUndo {
    param($Tweak, $Level, $Context, $BackupData, $Step)
    $id = Get-Fase6R4TweakId $Tweak
    $script:R4UndoOrder += $id
    $backupOk = ($null -ne $BackupData -and [string]$BackupData.TweakId -eq $id)
    return [PSCustomObject]@{
        Id = $id
        Action = 'Undo'
        Success = [bool]$backupOk
        Changed = [bool]$backupOk
        StateBefore = $null
        StateAfter = $BackupData
        Verification = [PSCustomObject]@{ Applicable=$true; Success=[bool]$backupOk; Detail='SyntheticUndoVerified' }
        Restart = 'None'
        Warning = $null
        Error = $(if ($backupOk) { $null } else { 'Backup sintético não corresponde ao TweakId.' })
    }
}

$SyntheticApplyHandler = {
    param($Tweak, $Level, $Context)
    Invoke-Fase6R4SyntheticApply -Tweak $Tweak -Level $Level -Context $Context
}
$SyntheticBackupHandler = {
    param($Tweak, $Level, $Context, $Step)
    Invoke-Fase6R4SyntheticBackup -Tweak $Tweak -Level $Level -Context $Context -Step $Step
}
$SyntheticUndoHandler = {
    param($Tweak, $Level, $Context, $BackupData, $Step)
    Invoke-Fase6R4SyntheticUndo -Tweak $Tweak -Level $Level -Context $Context -BackupData $BackupData -Step $Step
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Win-Slim Suite - FASE 6 R4 / Preview + Transaction Handoff' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'R4: Preview determinístico + binding por fingerprint + Transaction Manager sintético sem mutação do Windows' -ForegroundColor DarkGray

. (Join-Path $Root 'src\Core\Planner.ps1')
. (Join-Path $Root 'src\Core\PresetResolver.ps1')
. (Join-Path $Root 'src\Core\PresetPolicyEngine.ps1')
. (Join-Path $Root 'src\Core\PresetPlannerValidator.ps1')
. (Join-Path $Root 'src\Core\PresetPreview.ps1')
. (Join-Path $Root 'src\Core\Transaction.ps1')

$PresetCatalog = Import-WinSlimPresetCatalog -Path (Join-Path $Root 'presets\WinSlim-Presets-R1.json')
$RuleCatalog = Import-WinSlimPresetPolicyRules -Path (Join-Path $Root 'presets\WinSlim-PresetRules-R2.json')
$ScenarioSpec = Read-JsonFile (Join-Path $Root 'specs\FASE6-R4-scenarios.json')
$AllTweaks = @(Get-BackendCatalog)
$ctx11 = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true

Write-Host "`n=== TEST 00: baseline Fase 6 R3 congelada + schema R4 ===" -ForegroundColor Yellow
$baseline = Read-JsonFile (Join-Path $Root 'specs\FASE6-R4-baseline.json')
foreach ($prop in @($baseline.files.PSObject.Properties)) {
    $rel = [string]$prop.Name
    $expected = ([string]$prop.Value).ToLowerInvariant()
    $target = Join-Path $Root $rel
    $ok = $false
    if (Test-Path -LiteralPath $target) {
        $actual = ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash).ToLowerInvariant()
        $ok = ($actual -eq $expected)
    }
    Assert-Fase6R4 $ok "baseline R3 congelada: $rel"
}
Assert-Fase6R4 ([string]$ScenarioSpec.schemaVersion -eq '1.0') 'scenario spec R4 usa schemaVersion 1.0'
Assert-Fase6R4 ($AllTweaks.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert-Fase6R4 ((@($AllTweaks.id | Sort-Object -Unique)).Count -eq 230) '230 IDs permanecem únicos'

Write-Host "`n=== TEST 01: PresetPreview puro + shape UI/auditoria ===" -ForegroundColor Yellow
$previewPath = Join-Path $Root 'src\Core\PresetPreview.ps1'
$previewText = Get-Content -LiteralPath $previewPath -Raw -Encoding UTF8
$mutationTokens = @('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Set-Service','Register-ScheduledTask','Unregister-ScheduledTask','bcdedit.exe','powercfg.exe','Invoke-NativeCommand')
$foundMutation = @()
foreach ($token in $mutationTokens) {
    if ($previewText -match [regex]::Escape($token)) { $foundMutation += $token }
}
Assert-Fase6R4 ($foundMutation.Count -eq 0) 'PresetPreview não contém primitivos de mutação do Windows'

$balancedReport = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -Context $ctx11
$balancedPreview = New-WinSlimPresetPreview -ValidationReport $balancedReport
Assert-Fase6R4 ($balancedPreview.SchemaVersion -eq 1) 'Preview expõe schemaVersion 1'
Assert-Fase6R4 ($balancedPreview.PresetName -eq 'Balanceado') 'Preview preserva nome do preset'
Assert-Fase6R4 ($balancedPreview.TransactionReady) 'Balanceado válido fica TransactionReady'
Assert-Fase6R4 ($balancedPreview.Summary.Selected -eq 105) 'Preview preserva seleção Balanceado=105'
Assert-Fase6R4 ($balancedPreview.Summary.Executable -eq @($balancedReport.Plan.ExecutionOrder).Count) 'Preview executável corresponde exatamente ao Planner'
Assert-Fase6R4 ($balancedPreview.Items.Count -eq $balancedPreview.Summary.Executable) 'Preview Items corresponde ao total executável'
Assert-Fase6R4 (-not [string]::IsNullOrWhiteSpace([string]$balancedPreview.PreviewFingerprint)) 'Preview possui fingerprint próprio'

Write-Host "`n=== TEST 02: Preview dos três presets e determinismo ===" -ForegroundColor Yellow
$expectedCounts = @{'Balanceado'=105; 'Gamer'=129; 'Extremo'=168}
foreach ($name in @('Balanceado','Gamer','Extremo')) {
    $r1 = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName $name -Context $ctx11
    $r2 = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName $name -Context $ctx11
    $p1 = New-WinSlimPresetPreview -ValidationReport $r1
    $p2 = New-WinSlimPresetPreview -ValidationReport $r2
    Assert-Fase6R4 ($p1.TransactionReady) "$name gera Preview pronto para Transaction"
    Assert-Fase6R4 ($p1.Summary.Selected -eq [int]$expectedCounts[$name]) "$name preserva contagem canônica no Preview"
    Assert-Fase6R4 ($p1.PreviewFingerprint -eq $p2.PreviewFingerprint) "$name mantém PreviewFingerprint determinístico"
    Assert-Fase6R4 ($p1.PlannerFingerprint -eq $r1.Plan.Fingerprint) "$name vincula Preview ao PlannerFingerprint correto"
    Assert-Fase6R4 ($p1.RiskSummary.High -eq 0) "$name continua sem risco Alto automático"
}

Write-Host "`n=== TEST 03: overlays, skips, warning e risco Alto visíveis no Preview ===" -ForegroundColor Yellow
$stackProfiles = @($ScenarioSpec.previewStack.profiles | ForEach-Object { [string]$_ })
$stackReport = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles $stackProfiles -Context $ctx11
$stackPreview = New-WinSlimPresetPreview -ValidationReport $stackReport
Assert-Fase6R4 ($stackPreview.Summary.Selected -eq [int]$ScenarioSpec.previewStack.expectedSelectedCount) 'Gamer + 3 overlays preserva 132 seleções no Preview'
Assert-Fase6R4 ((@($stackPreview.ConditionalProfiles) -join '|') -eq (@($stackProfiles | Sort-Object) -join '|')) 'Preview normaliza perfis condicionais em ordem canônica'
Assert-Fase6R4 ($stackPreview.RiskSummary.High -eq 0) 'stack padrão continua sem risco Alto'

$highReport = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @('HW-CS2-P-CORES') -AllowHighRiskConditional -Context $ctx11
$highPreview = New-WinSlimPresetPreview -ValidationReport $highReport
Assert-Fase6R4 ($highPreview.Approval.ContainsHighRisk -and $highPreview.Approval.HighRiskCount -eq 1) 'Preview sinaliza explicitamente overlay de risco Alto consentido'

$noGpuCtx = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true -NoGpu
$skipReport = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @('HW-MSI-GPU') -Context $noGpuCtx
$skipPreview = New-WinSlimPresetPreview -ValidationReport $skipReport
Assert-Fase6R4 ((@($skipPreview.SkippedTweaks | Where-Object { $_.TweakId -eq 'PERF-018' -and $_.ReasonCode -eq 'GpuRequired' })).Count -eq 1) 'Preview expõe Skip GpuRequired sem esconder decisão do Planner'

$pendingCtx = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true -PendingReboot
$pendingReport = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -Context $pendingCtx
$pendingPreview = New-WinSlimPresetPreview -ValidationReport $pendingReport
Assert-Fase6R4 ($pendingPreview.Approval.PendingRebootBeforePlan) 'Preview sinaliza reboot pendente anterior ao plano'
Assert-Fase6R4 ((@($pendingPreview.Warnings | Where-Object { $_.Code -eq 'PendingReboot' })).Count -eq 1) 'Preview preserva warning estruturado PendingReboot'

Write-Host "`n=== TEST 04: binding Preview -> Plan impede TOCTOU ===" -ForegroundColor Yellow
$binding = Test-WinSlimPreviewPlanBinding -Preview $stackPreview -Plan $stackReport.Plan
Assert-Fase6R4 ($binding.Valid -and $binding.ReasonCode -eq 'Bound') 'Preview válido liga ao mesmo ExecutionPlan por fingerprint e ordem'
$txItems = @(Get-WinSlimPreviewTransactionItems -Preview $stackPreview -Plan $stackReport.Plan)
Assert-Fase6R4 ($txItems.Count -eq @($stackReport.Plan.ExecutionOrder).Count) 'handoff Preview -> Transaction preserva contagem 1:1'
Assert-Fase6R4 ((@($txItems.TweakId) -join '|') -eq (@($stackPreview.Items.TweakId) -join '|')) 'handoff Preview -> Transaction preserva ordem exibida ao usuário'

$tamperedPlan = Copy-WinSlimPlannerObject -InputObject $stackReport.Plan
$tamperedPlan.Fingerprint = 'tampered-r4'
$tamperedBinding = Test-WinSlimPreviewPlanBinding -Preview $stackPreview -Plan $tamperedPlan
Assert-Fase6R4 (-not $tamperedBinding.Valid -and $tamperedBinding.ReasonCode -eq 'PlannerFingerprintMismatch') 'fingerprint diferente bloqueia execução de plano não-previewado'

$blockedCtx = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $false
$blockedReport = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -Context $blockedCtx
$blockedPreview = New-WinSlimPresetPreview -ValidationReport $blockedReport
Assert-Fase6R4 (-not $blockedPreview.TransactionReady -and $blockedPreview.Summary.Blocked -gt 0) 'plano bloqueado aparece no Preview e nunca fica TransactionReady'
$blockedThrow = $false
try {
    [void](Get-WinSlimPreviewTransactionItems -Preview $blockedPreview -Plan $blockedReport.Plan)
} catch {
    $blockedThrow = $true
}
Assert-Fase6R4 $blockedThrow 'plano bloqueado não atravessa o handoff transacional'

Write-Host "`n=== TEST 05: Transaction Manager - commit sintético sem mutação/persistência ===" -ForegroundColor Yellow
$commitCount = [int]$ScenarioSpec.syntheticTransaction.commitSampleSize
$commitItems = @($txItems | Select-Object -First $commitCount)
$commitContext = [PSCustomObject]@{ FailureTweakId=''; Mode='SyntheticR4' }
$commitTx = Invoke-TransactionPlan `
    -Items $commitItems `
    -Context $commitContext `
    -FailurePolicy 'RollbackTransaction' `
    -ApplyHandler $SyntheticApplyHandler `
    -BackupHandler $SyntheticBackupHandler `
    -UndoHandler $SyntheticUndoHandler `
    -NoPersist
Assert-Fase6R4 ($commitTx.Status -eq 'Committed') 'amostra Preview -> Transaction conclui Commit sintético'
Assert-Fase6R4 ($commitTx.Persist -eq $false) 'transação sintética usa NoPersist'
Assert-Fase6R4 ($commitTx.Steps.Count -eq $commitCount) 'Transaction processa exatamente a amostra prevista'
Assert-Fase6R4 ((@($commitTx.Steps.TweakId) -join '|') -eq (@($commitItems.TweakId) -join '|')) 'Transaction preserva ordem recebida do Preview'
Assert-Fase6R4 ((@($commitTx.Steps | Where-Object { -not $_.Changed -or $_.Status -ne 'Verified' })).Count -eq 0) 'todos os passos sintéticos commitados ficam Changed=true + Verified'
Assert-Fase6R4 ((@($commitTx.Steps | Where-Object { $null -eq $_.BackupData })).Count -eq 0) 'todos os passos sintéticos recebem backup pre-apply em memória'

Write-Host "`n=== TEST 06: falha sintética posterior -> rollback LIFO ===" -ForegroundColor Yellow
$rollbackCount = [int]$ScenarioSpec.syntheticTransaction.rollbackSampleSize
$rollbackItems = @($txItems | Select-Object -First $rollbackCount)
$failureId = [string]$rollbackItems[$rollbackCount - 1].TweakId
$script:R4UndoOrder = @()
$rollbackContext = [PSCustomObject]@{ FailureTweakId=$failureId; Mode='SyntheticR4Rollback' }
$rollbackTx = Invoke-TransactionPlan `
    -Items $rollbackItems `
    -Context $rollbackContext `
    -FailurePolicy 'RollbackTransaction' `
    -ApplyHandler $SyntheticApplyHandler `
    -BackupHandler $SyntheticBackupHandler `
    -UndoHandler $SyntheticUndoHandler `
    -NoPersist
$expectedUndo = @($rollbackItems[0..($rollbackCount - 2)].TweakId)
[Array]::Reverse($expectedUndo)
Assert-Fase6R4 ($rollbackTx.Status -eq 'RolledBack') 'falha posterior dispara rollback transacional completo'
Assert-Fase6R4 ((@($script:R4UndoOrder) -join '|') -eq (@($expectedUndo) -join '|')) 'rollback sintético ocorre estritamente em LIFO'
Assert-Fase6R4 ((@($rollbackTx.Steps | Where-Object { $_.TweakId -ne $failureId -and $_.RollbackStatus -eq 'RolledBack' })).Count -eq ($rollbackCount - 1)) 'passos alterados anteriores ficam RolledBack'
Assert-Fase6R4 ((@($rollbackTx.Steps | Where-Object { $_.TweakId -eq $failureId -and $_.Status -eq 'Failed' -and -not $_.Changed })).Count -eq 1) 'passo sintético de falha não é marcado como alterado'

Write-Host "`n=== TEST 07: backend/UI legada e fechamento da Fase 6 ===" -ForegroundColor Yellow
$baseDoc = Read-JsonFile (Join-Path $Root 'catalog.json')
$workloadDoc = Read-JsonFile (Join-Path $Root 'catalogs\Game-Workload.json')
Assert-Fase6R4 ($baseDoc.tweaks.Count -eq 177 -and $workloadDoc.tweaks.Count -eq 10) 'UI/autoload legado permanece em 187 entradas'
Assert-Fase6R4 ($AllTweaks.Count -eq 230) 'backend validado permanece em 230 entradas'
Assert-Fase6R4 ((Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Balanceado').SelectedIds.Count -eq 105) 'Balanceado permanece 105'
Assert-Fase6R4 ((Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Gamer').SelectedIds.Count -eq 129) 'Gamer permanece 129'
Assert-Fase6R4 ((Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Extremo').SelectedIds.Count -eq 168) 'Extremo permanece 168'

Write-Host "`n=== RESUMO FASE 6 R4 ===" -ForegroundColor Cyan
if ($Failures.Count -eq 0) {
    Write-Host 'FASE 6 R4 APROVADA - Preview determinístico, binding Preview/Plan e integração Transaction Manager sintética validados sem mutação do Windows.' -ForegroundColor Green
    Write-Host 'FASE 6 CONCLUÍDA. Próximo gate: FASE 6.5 - cleanup, refactor estrutural, otimização pesada e benchmarks antes/depois.' -ForegroundColor Cyan
    exit 0
}

Write-Host "FASE 6 R4 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $Failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1

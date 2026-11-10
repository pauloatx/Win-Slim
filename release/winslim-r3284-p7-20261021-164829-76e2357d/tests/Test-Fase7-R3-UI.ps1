#requires -Version 5.1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$Root = Split-Path -Parent $PSScriptRoot

$Failures = New-Object System.Collections.ArrayList
function Ok7R3([string]$Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Fail7R3([string]$Message) { Write-Host "  [FAIL] $Message" -ForegroundColor Red; [void]$Failures.Add($Message) }
function Assert7R3([bool]$Condition,[string]$Message) { if ($Condition) { Ok7R3 $Message } else { Fail7R3 $Message } }

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 7 R3 / Presets + Conditional Overlays'
Write-Host '============================================================'
Write-Host 'R3: selecao funcional de presets/overlays; sem Apply; R2/R1/backend protegidos'

Write-Host "`n=== TEST 00: baseline FASE 6.5 R4.1 preservada ===" -ForegroundColor Yellow
$baseline = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R4-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($p in $baseline.files.PSObject.Properties) {
    $path = Join-Path $Root ([string]$p.Name)
    $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
    Assert7R3 $ok "baseline R4.1 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01: FASE 7 R1 e R2 permanecem congeladas ===" -ForegroundColor Yellow
$r1spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R1-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($p in $r1spec.r1Files.PSObject.Properties) {
    $path = Join-Path $Root ([string]$p.Name)
    $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
    Assert7R3 $ok "R1 congelada: $($p.Name)"
}
$r2spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R2-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($p in $r2spec.r2Files.PSObject.Properties) {
    $path = Join-Path $Root ([string]$p.Name)
    $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
    Assert7R3 $ok "R2 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 02: backend 230 + presets 105/129/168 ===" -ForegroundColor Yellow
$catalogFiles = @(
    'catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json',
    'catalogs\validated\Expansion-R4.json','catalogs\validated\Expansion-R4.1.json','catalogs\validated\Expansion-R4.2.json'
)
$all = New-Object System.Collections.ArrayList
foreach ($rel in $catalogFiles) {
    $j = Get-Content -LiteralPath (Join-Path $Root $rel) -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = if ($j.PSObject.Properties.Name -contains 'tweaks') { @($j.tweaks) } else { @($j) }
    foreach ($x in $items) { [void]$all.Add($x) }
}
$all = @($all.ToArray())
Assert7R3 ($all.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert7R3 ((@($all.id | Select-Object -Unique).Count) -eq 230) '230 IDs permanecem unicos'
$presets = Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert7R3 ([int]$presets.presets.Balanceado.expectedSelectedCount -eq 105) 'preset Balanceado permanece 105'
Assert7R3 ([int]$presets.presets.Gamer.expectedSelectedCount -eq 129) 'preset Gamer permanece 129'
Assert7R3 ([int]$presets.presets.Extremo.expectedSelectedCount -eq 168) 'preset Extremo permanece 168'

Write-Host "`n=== TEST 03: contrato aprovado dos overlays condicionais ===" -ForegroundColor Yellow
$rules = Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-PresetRules-R2.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$profiles = @($rules.conditionalProfiles)
Assert7R3 ($profiles.Count -eq 16) 'catalogo permanece com 16 perfis condicionais'
Assert7R3 (@($rules.profileOrder).Count -eq 16) 'profileOrder permanece com 16 entradas'
Assert7R3 (@($profiles | Where-Object { -not [bool]$_.requiresExplicitOptIn }).Count -eq 0) 'todos os overlays continuam opt-in explicito'
$highRisk = @($profiles | Where-Object { [bool]$_.requiresHighRiskConsent } | Select-Object -ExpandProperty name)
Assert7R3 ($highRisk.Count -eq 2) 'exatamente dois overlays exigem consentimento Alto'
Assert7R3 ($highRisk -contains 'HW-CS2-P-CORES') 'HW-CS2-P-CORES continua Alto'
Assert7R3 ($highRisk -contains 'HW-GPU-IRQ-AFFINITY') 'HW-GPU-IRQ-AFFINITY continua Alto'

Write-Host "`n=== TEST 04: PresetRuntime resolve base/overlay/consentimento sem mutacao ===" -ForegroundColor Yellow
. (Join-Path $Root 'src\Core\CatalogRuntime.ps1')
. (Join-Path $Root 'src\Core\PresetResolver.ps1')
. (Join-Path $Root 'src\Core\PresetPolicyEngine.ps1')
. (Join-Path $Root 'src\Core\PresetRuntime.ps1')
$presetCatalog = Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ruleCatalog = Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-PresetRules-R2.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = New-WinSlimPresetRuntime -CatalogTweaks $all -PresetCatalog $presetCatalog -RuleCatalog $ruleCatalog
foreach ($pair in @(@('Balanceado',105),@('Gamer',129),@('Extremo',168))) {
    $r = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $runtime -PresetName $pair[0]
    Assert7R3 ($r.CanResolve -and @($r.SelectedIds).Count -eq [int]$pair[1]) "resolucao base $($pair[0]) preserva $($pair[1])"
}
$low = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $runtime -PresetName 'Gamer' -ConditionalProfiles @('HW-HAGS-ON')
Assert7R3 ($low.CanResolve -and @($low.SelectedIds).Count -eq 130) 'overlay HAGS adiciona exatamente 1 tweak ao Gamer'
Assert7R3 (@($low.EnabledConditionalProfiles) -contains 'HW-HAGS-ON') 'overlay HAGS aparece como habilitado'
$blocked = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $runtime -PresetName 'Gamer' -ConditionalProfiles @('HW-GPU-IRQ-AFFINITY')
Assert7R3 (-not $blocked.CanResolve) 'overlay Alto sem consentimento e bloqueado pelo runtime'
Assert7R3 (@($blocked.BlockedRequests | Where-Object { $_.Code -eq 'HighRiskConsentRequired' }).Count -eq 1) 'bloqueio Alto usa HighRiskConsentRequired'
$allowed = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $runtime -PresetName 'Gamer' -ConditionalProfiles @('HW-GPU-IRQ-AFFINITY') -AllowHighRiskConditional
Assert7R3 ($allowed.CanResolve -and @($allowed.SelectedIds).Count -eq 130) 'overlay Alto com consentimento resolve sem alterar base'
Assert7R3 (@($allowed.Warnings | Where-Object { $_.Code -eq 'HighRiskConditionalEnabled' }).Count -eq 1) 'overlay Alto resolvido gera warning canonico'

Write-Host "`n=== TEST 05: view-model R3 e somente leitura + elegibilidade ===" -ForegroundColor Yellow
$overlayViewPath = Join-Path $Root 'src\UI\Fase7\PresetOverlayView.R3.ps1'
Assert7R3 (Test-Path -LiteralPath $overlayViewPath) 'PresetOverlayView.R3.ps1 existe'
$overlayRaw = Get-Content -LiteralPath $overlayViewPath -Raw -Encoding UTF8
foreach ($fn in @('Get-WinSlimUiConditionalProfileDescriptors','Test-WinSlimUiConditionalProfileEligibility')) {
    Assert7R3 ($overlayRaw -match ('function\s+' + [regex]::Escape($fn))) "view-model implementa $fn"
}
$forbidden = @(
    'Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg.exe','bcdedit','powercfg','sc.exe',
    'Set-Service','Stop-Service','Disable-ScheduledTask','Remove-AppxPackage','dism.exe','netsh',
    'Invoke-TransactionPlan','Invoke-WinSlimProvider','ApplyHandler','UndoHandler'
)
foreach ($token in $forbidden) { Assert7R3 ($overlayRaw -notmatch [regex]::Escape($token)) "view-model nao executa: $token" }
. $overlayViewPath
$descriptors = @(Get-WinSlimUiConditionalProfileDescriptors -PresetRuntime $runtime)
Assert7R3 ($descriptors.Count -eq 16) 'view-model expoe os 16 overlays do runtime'
$irq = $descriptors | Where-Object { $_.Name -eq 'HW-GPU-IRQ-AFFINITY' } | Select-Object -First 1
$eligible = Test-WinSlimUiConditionalProfileEligibility -Profile $irq -SystemSnapshot ([pscustomobject]@{ GPUName='GPU teste'; CPUThreads=16 })
Assert7R3 ([bool]$eligible.Eligible) 'GPU IRQ fica elegivel com GPU + 16 threads'
$ineligible = Test-WinSlimUiConditionalProfileEligibility -Profile $irq -SystemSnapshot ([pscustomobject]@{ GPUName=''; CPUThreads=4 })
Assert7R3 (-not [bool]$ineligible.Eligible) 'GPU IRQ fica inelegivel sem GPU/threads minimos'

Write-Host "`n=== TEST 06: XAML R3 valido + presets/overlays conectaveis ===" -ForegroundColor Yellow
$xamlPath = Join-Path $Root 'src\UI\Fase7\WinSlimShell.R3.xaml'
Assert7R3 (Test-Path -LiteralPath $xamlPath) 'WinSlimShell.R3.xaml existe'
$xamlRaw = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$xmlOk = $true; try { [xml]$null = $xamlRaw } catch { $xmlOk = $false }
Assert7R3 $xmlOk 'XAML R3 e XML bem-formado'
foreach ($control in @(
    'CardPresetBalanced','CardPresetGamer','CardPresetExtreme','BtnPresetBalanced','BtnPresetGamer','BtnPresetExtreme',
    'PanelOverlays','ChkOverlayHags','ChkOverlayMsiGpu','ChkOverlayCoreParking','ChkOverlayCs2PCores','ChkOverlayGpuIrq',
    'ChkOverlayValorant','ChkOverlayCs2','ChkOverlayApex','ChkOverlayFortnite','ChkOverlayGtav','ChkOverlayFso',
    'ChkOverlayDefenderDev','ChkOverlayStreaming','ChkOverlayVideo','ChkOverlayDesign','ChkOverlayProgramming',
    'ChkAllowHighRiskConditional','TxtPresetSelectionStatus','TxtPresetSelectionDetail','TxtPresetSelectionFingerprint',
    'BtnClearOverlays','BtnPresetNext'
)) { Assert7R3 ($xamlRaw -match ('x:Name="' + [regex]::Escape($control) + '"')) "controle R3 presente: $control" }
Assert7R3 ($xamlRaw -match 'Todos são opt-in explícito') 'UI explica opt-in explicito dos overlays'
Assert7R3 ($xamlRaw -match 'nenhuma alteração é aplicada') 'UI explicita que R3 nao aplica alteracoes'

Write-Host "`n=== TEST 07: shell R3 usa somente resolver puro de presets ===" -ForegroundColor Yellow
$shellPath = Join-Path $Root 'src\UI\Fase7\WinSlimShell.R3.ps1'
Assert7R3 (Test-Path -LiteralPath $shellPath) 'WinSlimShell.R3.ps1 existe'
$shellRaw = Get-Content -LiteralPath $shellPath -Raw -Encoding UTF8
Assert7R3 ($shellRaw -match 'Resolve-WinSlimPresetRuntimeSelection') 'shell R3 usa resolver canonico do PresetRuntime'
Assert7R3 ($shellRaw -match 'Get-WinSlimUiConditionalProfileDescriptors') 'shell R3 consome metadados condicionais'
Assert7R3 ($shellRaw -match 'Test-WinSlimUiConditionalProfileEligibility') 'shell R3 usa elegibilidade do snapshot'
foreach ($token in $forbidden) { Assert7R3 ($shellRaw -notmatch [regex]::Escape($token)) "shell R3 nao executa: $token" }
foreach ($token in @('Invoke-WinSlimPresetRuntimePlannerValidation','New-WinSlimPresetPreview','Invoke-WinSlimTransactionOptimized')) {
    Assert7R3 ($shellRaw -notmatch [regex]::Escape($token)) "R3 ainda nao chama etapa futura: $token"
}

Write-Host "`n=== TEST 08: launcher/entrypoint R3 preservam arquitetura ===" -ForegroundColor Yellow
$launcherPath = Join-Path $Root 'WinSlimSuite.Fase7R3.ps1'
Assert7R3 (Test-Path -LiteralPath $launcherPath) 'WinSlimSuite.Fase7R3.ps1 existe'
$launcher = Get-Content -LiteralPath $launcherPath -Raw -Encoding UTF8
Assert7R3 ($launcher -match 'Enable-WinSlimRuntimePromotion\s+-Planner\s+-Transaction') 'launcher R3 mantem runtime promovido'
Assert7R3 ($launcher -match 'SystemContextView\.R2\.ps1') 'launcher R3 reutiliza coletor R2 aprovado'
Assert7R3 ($launcher -match 'PresetOverlayView\.R3\.ps1') 'launcher R3 carrega view-model de overlays'
Assert7R3 ($launcher -match 'WinSlimShell\.R3\.ps1') 'launcher R3 carrega shell R3'
$r3bat = Get-Content -LiteralPath (Join-Path $Root 'Executar-WinSlim-R3.bat') -Raw
Assert7R3 ($r3bat -match 'WinSlimSuite\.Fase7R3\.ps1') 'entrypoint R3 abre launcher R3'

Write-Host "`n=== TEST 09: arquivos R3 registrados ===" -ForegroundColor Yellow
$r3specPath = Join-Path $Root 'specs\FASE7-R3-baseline.json'
Assert7R3 (Test-Path -LiteralPath $r3specPath) 'spec FASE7-R3-baseline.json existe'
if (Test-Path -LiteralPath $r3specPath) {
    $r3spec = Get-Content -LiteralPath $r3specPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $r3spec.r3Files.PSObject.Properties) {
        $path = Join-Path $Root ([string]$p.Name)
        $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
        Assert7R3 $ok "R3 registrado: $($p.Name)"
    }
}

Write-Host "`n=== RESUMO FASE 7 R3 ===" -ForegroundColor Yellow
if ($Failures.Count -eq 0) {
    Write-Host 'FASE 7 R3 APROVADA - Presets e overlays condicionais usam o PresetRuntime canonico; consentimento Alto e elegibilidade visual preservados; nenhuma alteracao e aplicada.' -ForegroundColor Green
    Write-Host 'Proximo subgate: FASE 7 R4 - Catalogo Personalizado.' -ForegroundColor Cyan
    exit 0
}
Write-Host "FASE 7 R3 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $Failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1

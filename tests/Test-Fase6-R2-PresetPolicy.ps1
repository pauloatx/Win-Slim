$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.ArrayList

function Assert-Fase6R2 {
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

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Win-Slim Suite - FASE 6 R2 / Preset Policy & Conditionals' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'R2: inclusão/exclusão formal, conflict/mutex Block e 16 perfis condicionais opt-in' -ForegroundColor DarkGray

. (Join-Path $Root 'src\Core\Planner.ps1')
. (Join-Path $Root 'src\Core\PresetResolver.ps1')
. (Join-Path $Root 'src\Core\PresetPolicyEngine.ps1')

$PresetCatalog = Import-WinSlimPresetCatalog -Path (Join-Path $Root 'presets\WinSlim-Presets-R1.json')
$RuleCatalog = Import-WinSlimPresetPolicyRules -Path (Join-Path $Root 'presets\WinSlim-PresetRules-R2.json')
$AllTweaks = @(Get-BackendCatalog)
$ById = @{}
foreach ($t in $AllTweaks) { $ById[[string]$t.id] = $t }
$ClassById = @{}
foreach ($c in @($PresetCatalog.classifications)) { $ClassById[[string]$c.id] = $c }

Write-Host "`n=== TEST 00: baseline Fase 6 R1 congelada ===" -ForegroundColor Yellow
$baseline = Read-JsonFile (Join-Path $Root 'specs\FASE6-R2-baseline.json')
foreach ($p in @($baseline.files.PSObject.Properties)) {
    $rel = [string]$p.Name
    $expected = ([string]$p.Value).ToLowerInvariant()
    $target = Join-Path $Root $rel
    $ok = $false
    if (Test-Path -LiteralPath $target) {
        $actual = ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash).ToLowerInvariant()
        $ok = ($actual -eq $expected)
    }
    Assert-Fase6R2 $ok "baseline R1 congelada: $rel"
}
Assert-Fase6R2 ($AllTweaks.Count -eq 230) 'backend permanece em 230 tweaks'
Assert-Fase6R2 ((@($AllTweaks.id | Sort-Object -Unique)).Count -eq 230) '230 IDs permanecem únicos'

Write-Host "`n=== TEST 01: schema R2 + cobertura dos 16 condicionais ===" -ForegroundColor Yellow
$validation = Test-WinSlimPresetPolicyRules -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks
Assert-Fase6R2 $validation.Valid 'PresetPolicyEngine valida as regras R2 sem erro'
Assert-Fase6R2 ($validation.ConditionalProfileCount -eq 16) 'R2 declara exatamente 16 perfis condicionais'
Assert-Fase6R2 ($validation.ConditionalCoverageCount -eq 16) 'os 16 tweaks condicionais têm cobertura exata'
Assert-Fase6R2 ([string]$RuleCatalog.conflictPolicy -eq 'Block') 'ConflictPolicy R2 permanece Block'
Assert-Fase6R2 ([string]$RuleCatalog.dependencyPolicy -eq 'PlannerExpand') 'dependências continuam responsabilidade do Planner'

$hardwareProfiles = @($RuleCatalog.conditionalProfiles | Where-Object { $_.kind -eq 'Hardware' })
$workloadProfiles = @($RuleCatalog.conditionalProfiles | Where-Object { $_.kind -eq 'Workload' })
Assert-Fase6R2 ($hardwareProfiles.Count -eq 5) '5 HardwareConditional viram perfis opt-in explícitos'
Assert-Fase6R2 ($workloadProfiles.Count -eq 11) '11 WorkloadConditional viram perfis opt-in explícitos'
Assert-Fase6R2 ((@($RuleCatalog.conditionalProfiles | Where-Object { -not $_.requiresExplicitOptIn })).Count -eq 0) 'nenhum perfil condicional pode ativar sem opt-in'

Write-Host "`n=== TEST 02: inclusão/exclusão formal por modo ===" -ForegroundColor Yellow
foreach ($name in @('Balanceado','Gamer','Extremo')) {
    $base = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName $name
    $badModes = @()
    foreach ($id in @($base.SelectedIds)) {
        if ([string]$ClassById[$id].mode -ne 'Auto') { $badModes += $id }
    }
    Assert-Fase6R2 ($badModes.Count -eq 0) "$name automático contém somente mode=Auto"
    Assert-Fase6R2 ($base.ConditionalIds.Count -eq 0 -and $base.EnabledConditionalProfiles.Count -eq 0) "$name não injeta condicionais sem opt-in"
    Assert-Fase6R2 $base.CanResolve "$name base resolve sem bloqueio R2"
}

$profileIds = @()
foreach ($p in @($RuleCatalog.conditionalProfiles)) { $profileIds += @($p.selectedIds) }
$protectedLeak = @()
foreach ($id in @($profileIds)) {
    if (@('ManualOnly','Maintenance','Diagnostic') -contains [string]$ClassById[$id].mode) { $protectedLeak += $id }
}
Assert-Fase6R2 ($protectedLeak.Count -eq 0) 'ManualOnly/Maintenance/Diagnostic nunca entram em perfis condicionais'

Write-Host "`n=== TEST 03: opt-in padrão + HAGS multilevel nível 0 ===" -ForegroundColor Yellow
$cs2 = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -ConditionalProfiles @('WL-CS2')
Assert-Fase6R2 ($cs2.CanResolve -and $cs2.SelectedIds.Count -eq 106) 'WL-CS2 adiciona exatamente um tweak ao Balanceado'
Assert-Fase6R2 (($cs2.SelectedIds -contains 'GAME-002') -and ($cs2.ConditionalIds -contains 'GAME-002')) 'WL-CS2 inclui GAME-002 somente por opt-in'
Assert-Fase6R2 ($cs2.Warnings.Count -eq 0) 'perfil condicional Médio não gera aviso de risco Alto'

$hags = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -ConditionalProfiles @('HW-HAGS-ON')
Assert-Fase6R2 ($hags.CanResolve -and $hags.SelectedIds -contains 'MLV-004') 'HW-HAGS-ON inclui MLV-004 explicitamente'
Assert-Fase6R2 ($hags.LevelSelections.ContainsKey('MLV-004') -and [int]$hags.LevelSelections['MLV-004'] -eq 0) 'HAGS ON preserva corretamente o nível multilevel 0'
Assert-Fase6R2 ($hags.LevelSelections.ContainsKey('MLV-002') -and [int]$hags.LevelSelections['MLV-002'] -eq 1) 'overlay HAGS não altera PUA Protection do preset base'

Write-Host "`n=== TEST 04: gate adicional para risco Alto condicional ===" -ForegroundColor Yellow
$highBlocked = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @('HW-CS2-P-CORES')
Assert-Fase6R2 (-not $highBlocked.CanResolve) 'HW-CS2-P-CORES bloqueia sem consentimento Alto adicional'
Assert-Fase6R2 ($highBlocked.SelectedIds -notcontains 'WS-ADV-002') 'tweak Alto não é injetado quando o gate bloqueia'
Assert-Fase6R2 ((@($highBlocked.BlockedRequests | Where-Object { $_.Code -eq 'HighRiskConsentRequired' })).Count -eq 1) 'bloqueio Alto usa ReasonCode formal HighRiskConsentRequired'

$highAllowed = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @('HW-CS2-P-CORES') -AllowHighRiskConditional
Assert-Fase6R2 ($highAllowed.CanResolve -and $highAllowed.SelectedIds -contains 'WS-ADV-002') 'consentimento explícito libera WS-ADV-002'
Assert-Fase6R2 ((@($highAllowed.Warnings | Where-Object { $_.Code -eq 'HighRiskConditionalEnabled' -and $_.TweakId -eq 'WS-ADV-002' })).Count -eq 1) 'ativação Alto gera warning estruturado'

$irqBlocked = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @('HW-GPU-IRQ-AFFINITY')
Assert-Fase6R2 (-not $irqBlocked.CanResolve -and $irqBlocked.SelectedIds -notcontains 'WS-ADV-003') 'GPU IRQ Alto também exige consentimento adicional'

Write-Host "`n=== TEST 05: merge determinístico de overlays ===" -ForegroundColor Yellow
$overlayA = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -ConditionalProfiles @('WL-CS2','HW-HAGS-ON','HW-MSI-GPU')
$overlayB = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -ConditionalProfiles @('HW-MSI-GPU','WL-CS2','HW-HAGS-ON')
Assert-Fase6R2 ($overlayA.CanResolve -and $overlayB.CanResolve) 'três overlays Médios resolvem sem bloqueios'
Assert-Fase6R2 ($overlayA.SelectedIds.Count -eq 108) 'Balanceado + 3 overlays resulta em 108 seleções'
Assert-Fase6R2 ($overlayA.Fingerprint -eq $overlayB.Fingerprint) 'ordem do pedido de overlays não altera fingerprint'
Assert-Fase6R2 ((@($overlayA.EnabledConditionalProfiles) -join '|') -eq (@($overlayB.EnabledConditionalProfiles) -join '|')) 'ordem canônica de perfis habilitados é determinística'
Assert-Fase6R2 ($overlayA.LevelSelections.ContainsKey('MLV-004') -and [int]$overlayA.LevelSelections['MLV-004'] -eq 0) 'merge mantém nível HAGS=0'
Assert-Fase6R2 ($overlayA.LevelSelections.ContainsKey('MLV-002') -and [int]$overlayA.LevelSelections['MLV-002'] -eq 1) 'merge preserva níveis do preset base'

Write-Host "`n=== TEST 06: conflitos/mutex são Block, nunca auto-resolvidos ===" -ForegroundColor Yellow
$oldConflicts = @($ById['GAME-002'].conflicts)
$ById['GAME-002'].conflicts = @('RESP-006')
$syntheticConflict = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -ConditionalProfiles @('WL-CS2')
$ById['GAME-002'].conflicts = @($oldConflicts)
Assert-Fase6R2 (-not $syntheticConflict.CanResolve) 'conflito sintético overlay x preset bloqueia resolução'
Assert-Fase6R2 ((@($syntheticConflict.BlockedRequests | Where-Object { $_.Code -eq 'DeclaredConflict' })).Count -ge 1) 'conflito usa ReasonCode formal DeclaredConflict'

$oldMutex = $ById['GAME-002'].mutexGroup
$ById['GAME-002'].mutexGroup = 'HIBERNATION_DEPENDENT'
$syntheticMutex = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -ConditionalProfiles @('WL-CS2')
$ById['GAME-002'].mutexGroup = $oldMutex
Assert-Fase6R2 (-not $syntheticMutex.CanResolve) 'colisão mutex sintética bloqueia resolução'
Assert-Fase6R2 ((@($syntheticMutex.BlockedRequests | Where-Object { $_.Code -eq 'MutexCollision' })).Count -ge 1) 'mutex usa ReasonCode formal MutexCollision'

$unknown = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Balanceado' -ConditionalProfiles @('PROFILE-NAO-EXISTE')
Assert-Fase6R2 (-not $unknown.CanResolve) 'perfil condicional desconhecido bloqueia em vez de ser ignorado'
Assert-Fase6R2 ((@($unknown.BlockedRequests | Where-Object { $_.Code -eq 'UnknownConditionalProfile' })).Count -eq 1) 'perfil desconhecido possui ReasonCode estruturado'

Write-Host "`n=== TEST 07: smoke Planner após resolução R2 ===" -ForegroundColor Yellow
$ctx = [PSCustomObject]@{
    OS='11'; IsAdmin=$true; RAM=16; Storage='SSD'; PendingReboot=$false
    CPU=[PSCustomObject]@{ Vendor='Generic'; LogicalProcessors=16 }
    GPU=@([PSCustomObject]@{ Vendor='NVIDIA'; Name='Synthetic GPU' })
}
$plan = New-WinSlimExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds $overlayA.SelectedIds -LevelSelections $overlayA.LevelSelections -Context $ctx -ConflictPolicy 'Block' -SkipApplicabilityChecks
Assert-Fase6R2 $plan.CanExecute 'seleção R2 Média chega ao Planner sem Block'
Assert-Fase6R2 ($plan.Conflicts.Count -eq 0 -and $plan.MutexDecisions.Count -eq 0) 'Planner confirma overlay R2 sem conflict/mutex pendente'
Assert-Fase6R2 ($plan.RiskSummary.High -eq 0) 'overlay padrão mantém RiskSummary.High=0'

$highPlan = New-WinSlimExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds $highAllowed.SelectedIds -LevelSelections $highAllowed.LevelSelections -Context $ctx -ConflictPolicy 'Block' -SkipApplicabilityChecks
Assert-Fase6R2 $highPlan.CanExecute 'overlay Alto consentido chega ao Planner explicitamente'
Assert-Fase6R2 ($highPlan.RiskSummary.High -eq 1) 'Planner contabiliza exatamente um Alto no teste consentido'

Write-Host "`n=== TEST 08: pureza da camada R2 + proteção da UI legada ===" -ForegroundColor Yellow
$engineText = Get-Content -LiteralPath (Join-Path $Root 'src\Core\PresetPolicyEngine.ps1') -Raw -Encoding UTF8
$mutationTokens = @('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Set-Service','Register-ScheduledTask','Unregister-ScheduledTask','bcdedit.exe','powercfg.exe','Invoke-NativeCommand')
$foundMutation = @()
foreach ($token in $mutationTokens) { if ($engineText -match [regex]::Escape($token)) { $foundMutation += $token } }
Assert-Fase6R2 ($foundMutation.Count -eq 0) 'PresetPolicyEngine é puro e não contém primitivos de mutação do Windows'

$baseDoc = Read-JsonFile (Join-Path $Root 'catalog.json')
$workloadDoc = Read-JsonFile (Join-Path $Root 'catalogs\Game-Workload.json')
Assert-Fase6R2 ($baseDoc.tweaks.Count -eq 177 -and $workloadDoc.tweaks.Count -eq 10) 'UI/autoload legado permanece em 187 entradas'
Assert-Fase6R2 ((Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Balanceado').SelectedIds.Count -eq 105) 'R2 não altera a composição R1 do Balanceado'
Assert-Fase6R2 ((Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Gamer').SelectedIds.Count -eq 129) 'R2 não altera a composição R1 do Gamer'
Assert-Fase6R2 ((Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Extremo').SelectedIds.Count -eq 168) 'R2 não altera a composição R1 do Extremo'

Write-Host "`n=== RESUMO FASE 6 R2 ===" -ForegroundColor Cyan
if ($Failures.Count -eq 0) {
    Write-Host 'FASE 6 R2 APROVADA - regras formais de inclusão/exclusão, conflict/mutex Block e 16 perfis condicionais validados.' -ForegroundColor Green
    Write-Host 'Próximo subgate: FASE 6 R3 - validação aprofundada Planner dos presets + overlays condicionais.' -ForegroundColor Cyan
    exit 0
}

Write-Host "FASE 6 R2 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $Failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1

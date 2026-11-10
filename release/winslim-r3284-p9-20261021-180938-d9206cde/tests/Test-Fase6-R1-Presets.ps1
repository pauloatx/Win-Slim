$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.ArrayList

function Assert-Fase6R1 {
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
Write-Host ' Win-Slim Suite - FASE 6 R1 / Canonical Preset Composition' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'R1: classificação dos 230 tweaks + presets canônicos sem alterar o backend validado' -ForegroundColor DarkGray

. (Join-Path $Root 'src\Core\Planner.ps1')
. (Join-Path $Root 'src\Core\PresetResolver.ps1')

$PresetPath = Join-Path $Root 'presets\WinSlim-Presets-R1.json'
$PresetCatalog = Import-WinSlimPresetCatalog -Path $PresetPath
$AllTweaks = @(Get-BackendCatalog)
$ById = @{}
foreach ($t in $AllTweaks) { $ById[[string]$t.id] = $t }

Write-Host "`n=== TEST 00: baseline Fase 5 R4.2.1 congelada ===" -ForegroundColor Yellow
$baseline = Read-JsonFile (Join-Path $Root 'specs\FASE6-R1-baseline.json')
foreach ($p in @($baseline.files.PSObject.Properties)) {
    $rel = [string]$p.Name
    $expected = ([string]$p.Value).ToLowerInvariant()
    $target = Join-Path $Root $rel
    $ok = $false
    if (Test-Path -LiteralPath $target) {
        $actual = ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash).ToLowerInvariant()
        $ok = ($actual -eq $expected)
    }
    Assert-Fase6R1 $ok "baseline congelada: $rel"
}
Assert-Fase6R1 ($AllTweaks.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert-Fase6R1 ((@($AllTweaks.id | Sort-Object -Unique)).Count -eq 230) '230 IDs permanecem únicos'

Write-Host "`n=== TEST 01: schema/cobertura integral dos presets ===" -ForegroundColor Yellow
$validation = Test-WinSlimPresetCatalog -PresetCatalog $PresetCatalog -CatalogTweaks $AllTweaks
Assert-Fase6R1 $validation.Valid 'PresetResolver valida o catálogo canônico sem erro'
Assert-Fase6R1 ($validation.CatalogCount -eq 230) 'validação enxerga 230 tweaks no backend'
Assert-Fase6R1 ($validation.ClassificationCount -eq 230) 'todos os 230 tweaks possuem classificação explícita'
Assert-Fase6R1 ((@($PresetCatalog.classifications.id | Sort-Object -Unique)).Count -eq 230) 'classificações não possuem IDs duplicados'

$bal = Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Balanceado'
$gam = Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Gamer'
$ext = Resolve-WinSlimPresetSelection -PresetCatalog $PresetCatalog -PresetName 'Extremo'
Assert-Fase6R1 ($bal.SelectedIds.Count -eq 105) 'Balanceado seleciona exatamente 105 tweaks'
Assert-Fase6R1 ($gam.SelectedIds.Count -eq 129) 'Gamer seleciona exatamente 129 tweaks'
Assert-Fase6R1 ($ext.SelectedIds.Count -eq 168) 'Extremo seleciona exatamente 168 tweaks'
Assert-Fase6R1 ($bal.ConflictPolicy -eq 'Block' -and $gam.ConflictPolicy -eq 'Block' -and $ext.ConflictPolicy -eq 'Block') 'todos os presets usam ConflictPolicy=Block'

Write-Host "`n=== TEST 02: política de risco e modos de classificação ===" -ForegroundColor Yellow
$modeCounts = @{}
foreach ($c in @($PresetCatalog.classifications)) {
    $m = [string]$c.mode
    if (-not $modeCounts.ContainsKey($m)) { $modeCounts[$m] = 0 }
    $modeCounts[$m] = [int]$modeCounts[$m] + 1
}
Assert-Fase6R1 ($modeCounts['Auto'] -eq 171) '171 tweaks são elegíveis a pelo menos um preset automático'
Assert-Fase6R1 ($modeCounts['ManualOnly'] -eq 35) '35 tweaks permanecem ManualOnly'
Assert-Fase6R1 ($modeCounts['HardwareConditional'] -eq 5) '5 tweaks permanecem HardwareConditional'
Assert-Fase6R1 ($modeCounts['WorkloadConditional'] -eq 11) '11 tweaks permanecem WorkloadConditional'
Assert-Fase6R1 ($modeCounts['Maintenance'] -eq 6) '6 ações ficam na classe Maintenance'
Assert-Fase6R1 ($modeCounts['Diagnostic'] -eq 2) '2 itens ficam na classe Diagnostic'

$allAutoIds = @($bal.SelectedIds + $gam.SelectedIds + $ext.SelectedIds | Sort-Object -Unique)
$highRiskAuto = @()
foreach ($id in $allAutoIds) { if ([string]$ById[$id].risk -eq 'Alto') { $highRiskAuto += $id } }
Assert-Fase6R1 ($highRiskAuto.Count -eq 0) 'nenhum tweak de risco Alto entra em preset automático'

$highRiskIds = @($AllTweaks | Where-Object { $_.risk -eq 'Alto' } | ForEach-Object { [string]$_.id })
$allHighOutsideAuto = $true
foreach ($id in $highRiskIds) { if ($allAutoIds -contains $id) { $allHighOutsideAuto = $false } }
Assert-Fase6R1 ($allHighOutsideAuto -and $highRiskIds.Count -eq 9) 'os 9 tweaks Alto permanecem fora dos presets automáticos'

Write-Host "`n=== TEST 03: resolução explícita de conflicts/mutex ===" -ForegroundColor Yellow
$pairSeen = @{}
$conflictPairs = @()
foreach ($t in $AllTweaks) {
    foreach ($c0 in @($t.conflicts)) {
        $a = [string]$t.id; $b = [string]$c0
        if (-not $b) { continue }
        if ([string]::Compare($a,$b,$true) -gt 0) { $tmp=$a; $a=$b; $b=$tmp }
        $key = "$a|$b"
        if (-not $pairSeen.ContainsKey($key)) {
            $pairSeen[$key] = $true
            $conflictPairs += ,@($a,$b)
        }
    }
}
foreach ($entry in @(@('Balanceado',$bal),@('Gamer',$gam),@('Extremo',$ext))) {
    $name = [string]$entry[0]; $sel = $entry[1]
    $bad = @()
    foreach ($pair in $conflictPairs) {
        if (($sel.SelectedIds -contains $pair[0]) -and ($sel.SelectedIds -contains $pair[1])) { $bad += "$($pair[0])/$($pair[1])" }
    }
    Assert-Fase6R1 ($bad.Count -eq 0) "$name não contém par de conflicts simultâneo"
}
Assert-Fase6R1 (($bal.SelectedIds -contains 'RESP-006') -and ($gam.SelectedIds -contains 'RESP-006') -and ($ext.SelectedIds -contains 'RESP-005') -and ($ext.SelectedIds -notcontains 'RESP-006')) 'HIBERNATION_DEPENDENT: Balanceado/Gamer=RESP-006; Extremo=RESP-005'
Assert-Fase6R1 (($gam.SelectedIds -contains 'PERF-012') -and ($gam.SelectedIds -notcontains 'EXTRA-005') -and ($ext.SelectedIds -contains 'EXTRA-005') -and ($ext.SelectedIds -notcontains 'PERF-012')) 'SYSTEM_RESPONSIVENESS: Gamer=10; Extremo=0'
Assert-Fase6R1 (($bal.SelectedIds -contains 'UI-004') -and ($gam.SelectedIds -contains 'UI-004') -and ($ext.SelectedIds -contains 'UI-021') -and ($ext.SelectedIds -notcontains 'UI-004')) 'TASKBAR_SEARCH_MODE: Balanceado/Gamer=ícone; Extremo=oculto'
Assert-Fase6R1 (($ext.SelectedIds -contains 'APP-032') -and ($allAutoIds -notcontains 'APP-032X')) 'ONEDRIVE_REMOVAL: somente variante reversível entra no Extremo'
Assert-Fase6R1 (($bal.SelectedIds -contains 'UPD-002') -and ($gam.SelectedIds -contains 'UPD-002') -and ($ext.SelectedIds -contains 'UPD-002') -and ($allAutoIds -notcontains 'UPD-003')) 'WINDOWS_UPDATE_CONTROL: UPD-002 em todos; UPD-003 manual-only'
Assert-Fase6R1 (($allAutoIds -notcontains 'PERF-011') -and ($allAutoIds -notcontains 'SEC-006')) 'HVCI/VBS: nenhum redutor de segurança entra automaticamente'

Write-Host "`n=== TEST 04: dependências e níveis multilevel canônicos ===" -ForegroundColor Yellow
foreach ($entry in @(@('Balanceado',$bal),@('Gamer',$gam),@('Extremo',$ext))) {
    $name = [string]$entry[0]; $sel = $entry[1]
    $missing = @()
    foreach ($id in @($sel.SelectedIds)) {
        foreach ($dep in @($ById[$id].dependencies)) {
            if ($dep -and $sel.SelectedIds -notcontains [string]$dep) { $missing += "$id->$dep" }
        }
    }
    Assert-Fase6R1 ($missing.Count -eq 0) "$name já inclui as dependências diretas de seus tweaks"
}
Assert-Fase6R1 ($bal.LevelSelections['MLV-002'] -eq 1 -and -not $bal.LevelSelections.ContainsKey('MLV-001')) 'Balanceado mantém plano de energia e ativa PUA Protection'
Assert-Fase6R1 ($gam.LevelSelections['MLV-001'] -eq 1 -and $gam.LevelSelections['MLV-002'] -eq 1) 'Gamer usa Alto Desempenho + PUA Protection'
Assert-Fase6R1 ($ext.LevelSelections['MLV-001'] -eq 2 -and $ext.LevelSelections['MLV-002'] -eq 1) 'Extremo usa Ultimate Performance + PUA Protection'
Assert-Fase6R1 (($allAutoIds -notcontains 'MLV-004') -and ($allAutoIds -notcontains 'MLV-005')) 'HAGS e limpeza recorrente de standby não são automáticos'

Write-Host "`n=== TEST 05: Planner aceita os três presets canônicos ===" -ForegroundColor Yellow
$ctx = [PSCustomObject]@{
    OS='11'; IsAdmin=$true; RAM=16; Storage='SSD'; PendingReboot=$false
    CPU=[PSCustomObject]@{ Vendor='Generic'; LogicalProcessors=16 }
    GPU=@([PSCustomObject]@{ Vendor='NVIDIA'; Name='Synthetic GPU' })
}
foreach ($name in @('Balanceado','Gamer','Extremo')) {
    $p1 = New-WinSlimPresetExecutionPlan -PresetCatalog $PresetCatalog -CatalogTweaks $AllTweaks -PresetName $name -Context $ctx -SkipApplicabilityChecks
    $p2 = New-WinSlimPresetExecutionPlan -PresetCatalog $PresetCatalog -CatalogTweaks $AllTweaks -PresetName $name -Context $ctx -SkipApplicabilityChecks
    Assert-Fase6R1 $p1.CanExecute "$name chega ao Planner sem bloqueios"
    Assert-Fase6R1 ($p1.BlockedTweaks.Count -eq 0 -and $p1.Conflicts.Count -eq 0 -and $p1.MutexDecisions.Count -eq 0) "$name chega ao Planner sem conflict/mutex pendente"
    Assert-Fase6R1 ($p1.RiskSummary.High -eq 0) "$name tem RiskSummary.High=0"
    Assert-Fase6R1 ($p1.Fingerprint -eq $p2.Fingerprint) "$name mantém fingerprint determinístico"
    Assert-Fase6R1 ($p1.CanonicalPresetName -eq $name -and $p1.PresetSelectionCount -gt 0) "$name é identificado pelo resolver canônico"
}

$realPlan = New-WinSlimPresetExecutionPlan -PresetCatalog $PresetCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -Context $ctx
Assert-Fase6R1 ($realPlan.BlockedTweaks.Count -eq 0) 'Gamer também passa pelas verificações reais de aplicabilidade sem Block'

Write-Host "`n=== TEST 06: grupos manuais/condicionais protegidos ===" -ForegroundColor Yellow
$special = $PresetCatalog.specialGroups
Assert-Fase6R1 ((@($special.HardwareConditional) -contains 'MLV-004') -and (@($special.HardwareConditional) -contains 'PERF-018') -and (@($special.HardwareConditional) -contains 'WS-ADV-003')) 'HAGS/MSI/GPU IRQ permanecem HardwareConditional'
Assert-Fase6R1 ((@($special.WorkloadConditional) -contains 'GAME-002') -and (@($special.WorkloadConditional) -contains 'WORK-004') -and (@($special.WorkloadConditional) -contains 'SEC-011')) 'jogos/workloads/exclusões dev permanecem WorkloadConditional'
Assert-Fase6R1 ((@($special.Maintenance) -contains 'EXT-001') -and (@($special.Maintenance) -contains 'EXTRA-006')) 'ações de manutenção não são disparadas por preset'
Assert-Fase6R1 ((@($special.ManualOnly) -contains 'APP-003') -and (@($special.ManualOnly) -contains 'APP-054') -and (@($special.ManualOnly) -contains 'EDGE-010')) 'App Installer/remoção Edge/browser sign-in ficam ManualOnly'

Write-Host "`n=== TEST 07: pureza do resolver + proteção da UI legada ===" -ForegroundColor Yellow
$resolverText = Get-Content -LiteralPath (Join-Path $Root 'src\Core\PresetResolver.ps1') -Raw -Encoding UTF8
$mutationTokens = @('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Set-Service','Register-ScheduledTask','Unregister-ScheduledTask','bcdedit.exe','powercfg.exe','Invoke-NativeCommand')
$foundMutation = @()
foreach ($token in $mutationTokens) { if ($resolverText -match [regex]::Escape($token)) { $foundMutation += $token } }
Assert-Fase6R1 ($foundMutation.Count -eq 0) 'PresetResolver é camada pura e não contém primitivos de mutação do Windows'

$baseDoc = Read-JsonFile (Join-Path $Root 'catalog.json')
$workloadDoc = Read-JsonFile (Join-Path $Root 'catalogs\Game-Workload.json')
Assert-Fase6R1 ($baseDoc.tweaks.Count -eq 177 -and $workloadDoc.tweaks.Count -eq 10) 'loader/UI legado continua enxergando 177+10=187 entradas no layout atual'
Assert-Fase6R1 (Test-Path -LiteralPath (Join-Path $Root 'catalogs\validated\Expansion-R4.2.json')) 'catálogos validados continuam separados do autoload legado'

Write-Host "`n=== RESUMO FASE 6 R1 ===" -ForegroundColor Cyan
if ($Failures.Count -eq 0) {
    Write-Host 'FASE 6 R1 APROVADA - 230 tweaks classificados; Balanceado=105, Gamer=129, Extremo=168; nenhum conflito ou risco Alto automático.' -ForegroundColor Green
    Write-Host 'Próximo subgate: FASE 6 R2 - regras formais de inclusão/exclusão, conflict/mutex e perfis condicionais.' -ForegroundColor Cyan
    exit 0
}

Write-Host "FASE 6 R1 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $Failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1

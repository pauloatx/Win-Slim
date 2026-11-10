$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.ArrayList
$Warnings = New-Object System.Collections.ArrayList

function Assert-Fase65R1 {
    param([bool]$Condition, [string]$Message)
    if ($Condition) {
        Write-Host "  [OK] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        [void]$script:Failures.Add($Message)
    }
}

function Warn-Fase65R1 {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor DarkYellow
    [void]$script:Warnings.Add($Message)
}

function Read-JsonFile65 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-BackendCatalog65 {
    $paths = @(
        'catalog.json',
        'catalogs\Game-Workload.json',
        'catalogs\validated\Advanced-Catalog.json',
        'catalogs\validated\Expansion-R4.json',
        'catalogs\validated\Expansion-R4.1.json',
        'catalogs\validated\Expansion-R4.2.json'
    )
    $items = New-Object System.Collections.ArrayList
    foreach ($rel in $paths) {
        $doc = Read-JsonFile65 (Join-Path $Root $rel)
        foreach ($t in @($doc.tweaks)) { [void]$items.Add($t) }
    }
    return [object[]]$items.ToArray()
}

function Get-LevelMapString65 {
    param($Map)
    if ($null -eq $Map) { return '' }
    $keys = @()
    if ($Map -is [System.Collections.IDictionary]) { $keys = @($Map.Keys) }
    else { $keys = @($Map.PSObject.Properties | ForEach-Object { $_.Name }) }
    $parts = @()
    foreach ($k0 in @($keys | Sort-Object)) {
        $k = [string]$k0
        $v = if ($Map -is [System.Collections.IDictionary]) { $Map[$k] } else { $Map.PSObject.Properties[$k].Value }
        $parts += "${k}:$v"
    }
    return ($parts -join '|')
}

function Get-IdsString65 {
    param($Values)
    return (@($Values | ForEach-Object { [string]$_ }) -join '|')
}

function Measure-ActionMs65 {
    param([Parameter(Mandatory)][scriptblock]$Action)
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    [GC]::Collect()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $Action
    $sw.Stop()
    return [math]::Round($sw.Elapsed.TotalMilliseconds, 3)
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Win-Slim Suite - FASE 6.5 R1 / Runtime Index & Hot Paths' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'R1: baseline de performance + CatalogRuntime + PresetRuntime sem alterar Planner/Transaction' -ForegroundColor DarkGray

. (Join-Path $Root 'src\Core\Planner.ps1')
. (Join-Path $Root 'src\Core\PresetResolver.ps1')
. (Join-Path $Root 'src\Core\PresetPolicyEngine.ps1')
. (Join-Path $Root 'src\Core\PresetPlannerValidator.ps1')
. (Join-Path $Root 'src\Core\PresetPreview.ps1')
. (Join-Path $Root 'src\Core\CatalogRuntime.ps1')
. (Join-Path $Root 'src\Core\PresetRuntime.ps1')

$PresetCatalog = Import-WinSlimPresetCatalog -Path (Join-Path $Root 'presets\WinSlim-Presets-R1.json')
$RuleCatalog = Import-WinSlimPresetPolicyRules -Path (Join-Path $Root 'presets\WinSlim-PresetRules-R2.json')
$ScenarioSpec = Read-JsonFile65 (Join-Path $Root 'specs\FASE6-R3-scenarios.json')
$BenchSpec = Read-JsonFile65 (Join-Path $Root 'specs\FASE6.5-R1-benchmark.json')
$AllTweaks = @(Get-BackendCatalog65)
$ctx11 = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true

Write-Host "`n=== TEST 00: baseline Fase 6 R4 congelada ===" -ForegroundColor Yellow
$baseline = Read-JsonFile65 (Join-Path $Root 'specs\FASE6.5-R1-baseline.json')
foreach ($prop in @($baseline.files.PSObject.Properties)) {
    $rel = [string]$prop.Name
    $expected = ([string]$prop.Value).ToLowerInvariant()
    $target = Join-Path $Root $rel
    $ok = $false
    if (Test-Path -LiteralPath $target) {
        $actual = ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash).ToLowerInvariant()
        $ok = ($actual -eq $expected)
    }
    Assert-Fase65R1 $ok "baseline R4 congelada: $rel"
}
Assert-Fase65R1 ($AllTweaks.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert-Fase65R1 ((@($AllTweaks.id | Sort-Object -Unique)).Count -eq 230) '230 IDs permanecem únicos'

Write-Host "`n=== TEST 01: novas camadas são puras e PS5.1-safe ===" -ForegroundColor Yellow
$mutationTokens = @('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Set-Service','Register-ScheduledTask','Unregister-ScheduledTask','bcdedit.exe','powercfg.exe','Invoke-NativeCommand','Remove-AppxPackage')
foreach ($rel in @('src\Core\CatalogRuntime.ps1','src\Core\PresetRuntime.ps1')) {
    $txt = Get-Content -LiteralPath (Join-Path $Root $rel) -Raw -Encoding UTF8
    $found = @()
    foreach ($token in $mutationTokens) { if ($txt -match [regex]::Escape($token)) { $found += $token } }
    Assert-Fase65R1 ($found.Count -eq 0) "$rel não contém primitivos de mutação do Windows"
    Assert-Fase65R1 ($txt -notmatch 'Generic\.List\[object\]') "$rel evita Generic.List[object] problemático no Windows PowerShell 5.1"
}

Write-Host "`n=== TEST 02: CatalogRuntime indexa exatamente o backend 230 ===" -ForegroundColor Yellow
$runtime = New-WinSlimCatalogRuntime -CatalogTweaks $AllTweaks
Assert-Fase65R1 $runtime.Valid 'CatalogRuntime valida sem erro estrutural'
Assert-Fase65R1 ($runtime.Count -eq 230) 'CatalogRuntime contém 230 tweaks'
Assert-Fase65R1 ($runtime.ById.Count -eq 230) 'ById contém 230 chaves O(1)'
Assert-Fase65R1 ((Get-IdsString65 $runtime.Ids) -eq (Get-IdsString65 $AllTweaks.id)) 'CatalogRuntime preserva ordem canônica do catálogo'

$mapEquivalent = $true
foreach ($t in $AllTweaks) {
    $id = [string]$t.id
    if (-not $runtime.ById.ContainsKey($id)) { $mapEquivalent = $false; break }
    if ([string]$runtime.ById[$id].id -ne $id) { $mapEquivalent = $false; break }
    $depsOld = @($t.dependencies | ForEach-Object { [string]$_ })
    $depsNew = @($runtime.DependenciesById[$id] | ForEach-Object { [string]$_ })
    if ((Get-IdsString65 $depsOld) -ne (Get-IdsString65 $depsNew)) { $mapEquivalent = $false; break }
    $confOld = @($t.conflicts | ForEach-Object { [string]$_ })
    $confNew = @($runtime.ConflictsById[$id] | ForEach-Object { [string]$_ })
    if ((Get-IdsString65 $confOld) -ne (Get-IdsString65 $confNew)) { $mapEquivalent = $false; break }
}
Assert-Fase65R1 $mapEquivalent 'ById/dependencies/conflicts equivalem exatamente ao catálogo original'
Assert-Fase65R1 (-not [string]::IsNullOrWhiteSpace([string]$runtime.Fingerprint)) 'CatalogRuntime possui fingerprint determinístico'
$runtime2 = New-WinSlimCatalogRuntime -CatalogTweaks $AllTweaks
Assert-Fase65R1 ($runtime.Fingerprint -eq $runtime2.Fingerprint) 'CatalogRuntime mantém fingerprint determinístico'

Write-Host "`n=== TEST 03: PresetRuntime valida uma vez e preserva política R2 ===" -ForegroundColor Yellow
$presetRuntime = New-WinSlimPresetRuntime -CatalogTweaks $AllTweaks -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog
Assert-Fase65R1 $presetRuntime.Valid 'PresetRuntime inicializa sobre backend validado'
Assert-Fase65R1 ($presetRuntime.CatalogRuntime.Count -eq 230) 'PresetRuntime reutiliza CatalogRuntime 230'
Assert-Fase65R1 ($presetRuntime.PresetSelections['Balanceado'].SelectedIds.Count -eq 105) 'PresetRuntime pré-resolve Balanceado=105'
Assert-Fase65R1 ($presetRuntime.PresetSelections['Gamer'].SelectedIds.Count -eq 129) 'PresetRuntime pré-resolve Gamer=129'
Assert-Fase65R1 ($presetRuntime.PresetSelections['Extremo'].SelectedIds.Count -eq 168) 'PresetRuntime pré-resolve Extremo=168'

$policyCases = @(
    [PSCustomObject]@{ Name='Balanceado base'; Preset='Balanceado'; Profiles=@(); High=$false },
    [PSCustomObject]@{ Name='Gamer overlays'; Preset='Gamer'; Profiles=@('HW-HAGS-ON','WL-CS2','WL-PROGRAMMING'); High=$false },
    [PSCustomObject]@{ Name='Extremo base'; Preset='Extremo'; Profiles=@(); High=$false },
    [PSCustomObject]@{ Name='HAGS level zero'; Preset='Gamer'; Profiles=@('HW-HAGS-ON'); High=$false },
    [PSCustomObject]@{ Name='High consent'; Preset='Gamer'; Profiles=@('HW-CS2-P-CORES'); High=$true },
    [PSCustomObject]@{ Name='High blocked'; Preset='Gamer'; Profiles=@('HW-CS2-P-CORES'); High=$false },
    [PSCustomObject]@{ Name='Unknown blocked'; Preset='Balanceado'; Profiles=@('PROFILE-DOES-NOT-EXIST'); High=$false }
)
foreach ($case in $policyCases) {
    $allowHigh = [bool]$case.High
    $legacy = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName $case.Preset -ConditionalProfiles @($case.Profiles) -AllowHighRiskConditional:$allowHigh
    $fast = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $presetRuntime -PresetName $case.Preset -ConditionalProfiles @($case.Profiles) -AllowHighRiskConditional:$allowHigh
    $ok = ($legacy.Fingerprint -eq $fast.Fingerprint) -and
          ($legacy.CanResolve -eq $fast.CanResolve) -and
          ((Get-IdsString65 $legacy.SelectedIds) -eq (Get-IdsString65 $fast.SelectedIds)) -and
          ((Get-LevelMapString65 $legacy.LevelSelections) -eq (Get-LevelMapString65 $fast.LevelSelections)) -and
          ((Get-IdsString65 $legacy.EnabledConditionalProfiles) -eq (Get-IdsString65 $fast.EnabledConditionalProfiles)) -and
          (@($legacy.BlockedRequests).Count -eq @($fast.BlockedRequests).Count) -and
          (@($legacy.Warnings).Count -eq @($fast.Warnings).Count)
    Assert-Fase65R1 $ok "$($case.Name): Runtime preserva exatamente seleção/fingerprint/bloqueios R2"
}

Write-Host "`n=== TEST 04: Runtime -> Planner preserva fingerprints e invariantes ===" -ForegroundColor Yellow
$plannerCases = New-Object System.Collections.ArrayList
foreach ($name in @('Balanceado','Gamer','Extremo')) {
    [void]$plannerCases.Add([PSCustomObject]@{ Name=$name; Preset=$name; Profiles=@(); High=$false })
}
$mediumProfiles = @($ScenarioSpec.mediumStack.profiles | ForEach-Object { [string]$_ })
[void]$plannerCases.Add([PSCustomObject]@{ Name='Gamer + 14 overlays'; Preset='Gamer'; Profiles=$mediumProfiles; High=$false })
[void]$plannerCases.Add([PSCustomObject]@{ Name='Gamer + P-core Alto'; Preset='Gamer'; Profiles=@('HW-CS2-P-CORES'); High=$true })

foreach ($case in @($plannerCases.ToArray())) {
    $allowHigh = [bool]$case.High
    $legacy = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName $case.Preset -ConditionalProfiles @($case.Profiles) -AllowHighRiskConditional:$allowHigh -Context $ctx11
    $fast = Invoke-WinSlimPresetRuntimePlannerValidation -PresetRuntime $presetRuntime -PresetName $case.Preset -ConditionalProfiles @($case.Profiles) -AllowHighRiskConditional:$allowHigh -Context $ctx11
    $ok = ($legacy.PolicyFingerprint -eq $fast.PolicyFingerprint) -and
          ($legacy.PlannerFingerprint -eq $fast.PlannerFingerprint) -and
          ($legacy.SelectedCount -eq $fast.SelectedCount) -and
          ($legacy.DependencyCount -eq $fast.DependencyCount) -and
          ($legacy.ExecutableCount -eq $fast.ExecutableCount) -and
          ($legacy.SkippedCount -eq $fast.SkippedCount) -and
          ($legacy.BlockedCount -eq $fast.BlockedCount) -and
          ($legacy.RiskSummary.High -eq $fast.RiskSummary.High) -and
          ($legacy.RestartRequirements.RebootRequired -eq $fast.RestartRequirements.RebootRequired)
    Assert-Fase65R1 $ok "$($case.Name): Runtime -> Planner é fingerprint-equivalente ao caminho legado"
}

Write-Host "`n=== TEST 05: Runtime preserva Preview e binding da Fase 6 R4 ===" -ForegroundColor Yellow
foreach ($name in @('Balanceado','Gamer','Extremo')) {
    $legacyReport = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName $name -Context $ctx11
    $fastReport = Invoke-WinSlimPresetRuntimePlannerValidation -PresetRuntime $presetRuntime -PresetName $name -Context $ctx11
    $legacyPreview = New-WinSlimPresetPreview -ValidationReport $legacyReport
    $fastPreview = New-WinSlimPresetPreview -ValidationReport $fastReport
    Assert-Fase65R1 ($legacyPreview.PreviewFingerprint -eq $fastPreview.PreviewFingerprint) "$name mantém PreviewFingerprint idêntico"
    Assert-Fase65R1 ($fastPreview.TransactionReady -and (Test-WinSlimPreviewPlanBinding -Preview $fastPreview -Plan $fastReport.Plan)) "$name continua TransactionReady com binding Preview/Plan"
}

Write-Host "`n=== TEST 06: benchmarks antes/depois (diagnóstico, não gate por tempo) ===" -ForegroundColor Yellow
$lookupOuter = [int]$BenchSpec.lookupOuterIterations
$policyIterations = [int]$BenchSpec.policyIterations
$pipelineIterations = [int]$BenchSpec.pipelineIterations

# Warm-up JIT / PowerShell command cache.
$null = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @('HW-HAGS-ON','WL-CS2')
$null = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $presetRuntime -PresetName 'Gamer' -ConditionalProfiles @('HW-HAGS-ON','WL-CS2')
$null = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -Context $ctx11
$null = Invoke-WinSlimPresetRuntimePlannerValidation -PresetRuntime $presetRuntime -PresetName 'Gamer' -Context $ctx11

$ids = @($runtime.Ids)
$legacyLookupMs = Measure-ActionMs65 {
    for ($outer=0; $outer -lt $lookupOuter; $outer++) {
        foreach ($id in $ids) {
            $match = $AllTweaks | Where-Object { [string]$_.id -eq [string]$id } | Select-Object -First 1
            if ($null -eq $match) { throw "Lookup legado perdeu $id" }
        }
    }
}
$runtimeLookupMs = Measure-ActionMs65 {
    for ($outer=0; $outer -lt $lookupOuter; $outer++) {
        foreach ($id in $ids) {
            $match = $runtime.ById[[string]$id]
            if ($null -eq $match) { throw "Runtime lookup perdeu $id" }
        }
    }
}

$legacyPolicyMs = Measure-ActionMs65 {
    for ($i=0; $i -lt $policyIterations; $i++) {
        $null = Resolve-WinSlimPresetPolicySelection -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName 'Gamer' -ConditionalProfiles @('HW-HAGS-ON','WL-CS2','WL-PROGRAMMING')
    }
}
$runtimePolicyMs = Measure-ActionMs65 {
    for ($i=0; $i -lt $policyIterations; $i++) {
        $null = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $presetRuntime -PresetName 'Gamer' -ConditionalProfiles @('HW-HAGS-ON','WL-CS2','WL-PROGRAMMING')
    }
}

$legacyPipelineMs = Measure-ActionMs65 {
    for ($i=0; $i -lt $pipelineIterations; $i++) {
        foreach ($name in @('Balanceado','Gamer','Extremo')) {
            $null = Invoke-WinSlimPresetPlannerValidation -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog -CatalogTweaks $AllTweaks -PresetName $name -Context $ctx11
        }
    }
}
$runtimePipelineMs = Measure-ActionMs65 {
    for ($i=0; $i -lt $pipelineIterations; $i++) {
        foreach ($name in @('Balanceado','Gamer','Extremo')) {
            $null = Invoke-WinSlimPresetRuntimePlannerValidation -PresetRuntime $presetRuntime -PresetName $name -Context $ctx11
        }
    }
}

function Get-Speedup65 {
    param([double]$Before, [double]$After)
    if ($After -le 0) { return 0 }
    return [math]::Round(($Before / $After), 2)
}
$lookupSpeedup = Get-Speedup65 $legacyLookupMs $runtimeLookupMs
$policySpeedup = Get-Speedup65 $legacyPolicyMs $runtimePolicyMs
$pipelineSpeedup = Get-Speedup65 $legacyPipelineMs $runtimePipelineMs

Write-Host ("  Lookup:   legado={0} ms | runtime={1} ms | speedup={2}x" -f $legacyLookupMs,$runtimeLookupMs,$lookupSpeedup) -ForegroundColor Cyan
Write-Host ("  Policy:   legado={0} ms | runtime={1} ms | speedup={2}x" -f $legacyPolicyMs,$runtimePolicyMs,$policySpeedup) -ForegroundColor Cyan
Write-Host ("  Pipeline: legado={0} ms | runtime={1} ms | speedup={2}x" -f $legacyPipelineMs,$runtimePipelineMs,$pipelineSpeedup) -ForegroundColor Cyan
Assert-Fase65R1 ($legacyLookupMs -gt 0 -and $runtimeLookupMs -gt 0 -and $legacyPolicyMs -gt 0 -and $runtimePolicyMs -gt 0) 'benchmarks produziram medições válidas'
if ($lookupSpeedup -lt 1.0) { Warn-Fase65R1 "lookup indexado não foi mais rápido nesta execução ($lookupSpeedup`x); repetir benchmark após fechar apps." }
if ($policySpeedup -lt 1.0) { Warn-Fase65R1 "PresetRuntime não foi mais rápido no policy hot-path nesta execução ($policySpeedup`x); revisar na R2." }
if ($pipelineSpeedup -lt 1.0) { Warn-Fase65R1 "pipeline total ainda não melhorou ($pipelineSpeedup`x); Planner continua legado e será alvo da R2." }

$benchReport = [PSCustomObject]@{
    schemaVersion = '1.0'
    phase = 'FASE6.5-R1'
    timestamp = (Get-Date).ToString('o')
    powershell = $PSVersionTable.PSVersion.ToString()
    catalogCount = $runtime.Count
    iterations = [PSCustomObject]@{ lookupOuter=$lookupOuter; policy=$policyIterations; pipeline=$pipelineIterations }
    lookup = [PSCustomObject]@{ legacyMs=$legacyLookupMs; runtimeMs=$runtimeLookupMs; speedup=$lookupSpeedup }
    policy = [PSCustomObject]@{ legacyMs=$legacyPolicyMs; runtimeMs=$runtimePolicyMs; speedup=$policySpeedup }
    pipeline = [PSCustomObject]@{ legacyMs=$legacyPipelineMs; runtimeMs=$runtimePipelineMs; speedup=$pipelineSpeedup }
    warnings = @($Warnings)
}
$benchDir = Join-Path $Root 'benchmarks'
if (-not (Test-Path -LiteralPath $benchDir)) { New-Item -ItemType Directory -Path $benchDir -Force | Out-Null }
$benchPath = Join-Path $benchDir 'FASE6.5-R1-last-run.json'
$benchReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $benchPath -Encoding UTF8
Assert-Fase65R1 (Test-Path -LiteralPath $benchPath) 'relatório de benchmark foi salvo em benchmarks\FASE6.5-R1-last-run.json'

Write-Host "`n=== TEST 07: fechamento R1 e proteção da arquitetura ===" -ForegroundColor Yellow
Assert-Fase65R1 ($AllTweaks.Count -eq 230) 'backend validado permanece 230'
Assert-Fase65R1 ($presetRuntime.PresetSelections['Balanceado'].SelectedIds.Count -eq 105) 'Balanceado permanece 105'
Assert-Fase65R1 ($presetRuntime.PresetSelections['Gamer'].SelectedIds.Count -eq 129) 'Gamer permanece 129'
Assert-Fase65R1 ($presetRuntime.PresetSelections['Extremo'].SelectedIds.Count -eq 168) 'Extremo permanece 168'
Assert-Fase65R1 ((Get-FileHash -LiteralPath (Join-Path $Root 'src\Core\Planner.ps1') -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$baseline.files.PSObject.Properties['src/Core/Planner.ps1'].Value).ToLowerInvariant()) 'Planner R1 permanece byte-a-byte congelado nesta R1'
Assert-Fase65R1 ((Get-FileHash -LiteralPath (Join-Path $Root 'src\Core\Transaction.ps1') -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$baseline.files.PSObject.Properties['src/Core/Transaction.ps1'].Value).ToLowerInvariant()) 'Transaction Manager R13 permanece byte-a-byte congelado nesta R1'

Write-Host "`n=== RESUMO FASE 6.5 R1 ===" -ForegroundColor Yellow
if ($Failures.Count -eq 0) {
    Write-Host 'FASE 6.5 R1 APROVADA - Runtime indexado e hot-path de presets validados com equivalência funcional; benchmarks antes/depois registrados.' -ForegroundColor Green
    Write-Host 'Próximo subgate: FASE 6.5 R2 - refactor/otimização interna do Planner com equivalência de fingerprints e regressão completa.' -ForegroundColor Cyan
    exit 0
}

Write-Host "FASE 6.5 R1 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $Failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.ArrayList
$Warnings = New-Object System.Collections.ArrayList

function Assert-Fase65R2 {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Write-Host "  [OK] $Message" -ForegroundColor Green }
    else { Write-Host "  [FAIL] $Message" -ForegroundColor Red; [void]$script:Failures.Add($Message) }
}

function Warn-Fase65R2 {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor DarkYellow
    [void]$script:Warnings.Add($Message)
}

function Read-JsonFile65R2 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-BackendCatalog65R2 {
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
        $doc = Read-JsonFile65R2 (Join-Path $Root $rel)
        foreach ($t in @($doc.tweaks)) { [void]$items.Add($t) }
    }
    return [object[]]$items.ToArray()
}

function Get-StringList65R2 {
    param($Values)
    return (@($Values | ForEach-Object { [string]$_ }) -join '|')
}

function Get-LevelMapString65R2 {
    param($Map)
    if ($null -eq $Map) { return '' }
    $keys = @()
    if ($Map -is [System.Collections.IDictionary]) { $keys=@($Map.Keys) }
    else { $keys=@($Map.PSObject.Properties | ForEach-Object { $_.Name }) }
    $parts = New-Object System.Collections.ArrayList
    foreach ($k0 in @($keys | Sort-Object)) {
        $k=[string]$k0
        $v=if ($Map -is [System.Collections.IDictionary]) { $Map[$k] } else { $Map.PSObject.Properties[$k].Value }
        [void]$parts.Add("${k}:$v")
    }
    return (@($parts.ToArray()) -join '|')
}

function Get-PlanSignature65R2 {
    param([Parameter(Mandatory)]$Plan)
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add("fp=$($Plan.Fingerprint)")
    [void]$parts.Add("can=$($Plan.CanExecute)")
    [void]$parts.Add("work=$($Plan.HasWork)")
    [void]$parts.Add("selected=$(Get-StringList65R2 $Plan.SelectedTweaks)")
    [void]$parts.Add("deps=$(Get-StringList65R2 $Plan.ExpandedDependencies)")
    foreach ($e in @($Plan.ExecutionOrder)) {
        [void]$parts.Add("exec=$($e.Sequence):$($e.TweakId):$($e.Level):$($e.SelectionSource):$($e.Risk):$($e.RequiresRestart):$($e.RestartScope):$(@($e.Dependencies)-join ',')")
    }
    foreach ($b in @($Plan.BlockedTweaks)) { [void]$parts.Add("blocked=$($b.TweakId):$($b.ReasonCode)") }
    foreach ($s in @($Plan.SkippedTweaks)) { [void]$parts.Add("skipped=$($s.TweakId):$($s.ReasonCode)") }
    foreach ($c in @($Plan.Conflicts)) { [void]$parts.Add("conf=$($c.A):$($c.B):$($c.Policy):$($c.Decision):$($c.Winner):$($c.Loser)") }
    foreach ($m in @($Plan.MutexDecisions)) { [void]$parts.Add("mutex=$($m.Group):$($m.Policy):$($m.Decision):$($m.Winner):$(@($m.Candidates)-join ','):$(@($m.Losers)-join ',')") }
    foreach ($c in @($Plan.DependencyCycles)) { [void]$parts.Add("cycle=$($c.Path)") }
    foreach ($w in @($Plan.Warnings)) { [void]$parts.Add("warn=$($w.Code):$($w.TweakId)") }
    [void]$parts.Add("risk=$($Plan.RiskSummary.Low):$($Plan.RiskSummary.Medium):$($Plan.RiskSummary.High):$($Plan.RiskSummary.Highest)")
    [void]$parts.Add("restart=$($Plan.RestartRequirements.Required):$($Plan.RestartRequirements.RebootRequired):$(@($Plan.RestartRequirements.Scopes)-join ','):$(@($Plan.RestartRequirements.TweakIds)-join ','):$($Plan.RestartRequirements.PendingRebootBeforePlan)")
    return (@($parts.ToArray()) -join "`n")
}

function Measure-ActionMs65R2 {
    param([Parameter(Mandatory)][scriptblock]$Action)
    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()
    $sw=[System.Diagnostics.Stopwatch]::StartNew()
    & $Action
    $sw.Stop()
    return [math]::Round($sw.Elapsed.TotalMilliseconds,3)
}

function Get-Speedup65R2 {
    param([double]$Before,[double]$After)
    if ($After -le 0) { return 0 }
    return [math]::Round(($Before/$After),2)
}

function New-SyntheticTweak65R2 {
    param(
        [string]$Id,
        [string[]]$Dependencies=@(),
        [string[]]$Conflicts=@(),
        [string]$MutexGroup='',
        [bool]$RequiresAdmin=$false
    )
    return [PSCustomObject]@{
        id=$Id
        name=$Id
        category='Synthetic'
        risk='Baixo'
        type='registry'
        windowsVersion=@('10','11')
        hardwareRules=$null
        dependencies=@($Dependencies)
        conflicts=@($Conflicts)
        mutexGroup=$MutexGroup
        requiresAdmin=$RequiresAdmin
        requiresRestart=$false
        restartScope='None'
        presets=@()
    }
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Win-Slim Suite - FASE 6.5 R2.1 / Planner Structural Refactor' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host 'R2.1: correção do gate Preview/Plan; Planner shadow/catálogo/backend preservados' -ForegroundColor DarkGray

. (Join-Path $Root 'src\Core\Planner.ps1')
. (Join-Path $Root 'src\Core\PresetResolver.ps1')
. (Join-Path $Root 'src\Core\PresetPolicyEngine.ps1')
. (Join-Path $Root 'src\Core\PresetPlannerValidator.ps1')
. (Join-Path $Root 'src\Core\PresetPreview.ps1')
. (Join-Path $Root 'src\Core\CatalogRuntime.ps1')
. (Join-Path $Root 'src\Core\PresetRuntime.ps1')
. (Join-Path $Root 'src\Core\PlannerOptimized.ps1')

$PresetCatalog = Import-WinSlimPresetCatalog -Path (Join-Path $Root 'presets\WinSlim-Presets-R1.json')
$RuleCatalog = Import-WinSlimPresetPolicyRules -Path (Join-Path $Root 'presets\WinSlim-PresetRules-R2.json')
$ScenarioSpec = Read-JsonFile65R2 (Join-Path $Root 'specs\FASE6-R3-scenarios.json')
$BenchSpec = Read-JsonFile65R2 (Join-Path $Root 'specs\FASE6.5-R2-benchmark.json')
$AllTweaks = @(Get-BackendCatalog65R2)
$ctx10 = New-WinSlimSyntheticPlannerContext -OS '10' -IsAdmin $true
$ctx11 = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true
$ctxNoGpu = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true -NoGpu
$ctxNoAdmin = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $false

Write-Host "`n=== TEST 00: baseline Fase 6.5 R1 congelada ===" -ForegroundColor Yellow
$baseline = Read-JsonFile65R2 (Join-Path $Root 'specs\FASE6.5-R2-baseline.json')
foreach ($prop in @($baseline.files.PSObject.Properties)) {
    $rel=[string]$prop.Name
    $expected=([string]$prop.Value).ToLowerInvariant()
    $target=Join-Path $Root $rel
    $ok=$false
    if (Test-Path -LiteralPath $target) {
        $actual=((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash).ToLowerInvariant()
        $ok=($actual -eq $expected)
    }
    Assert-Fase65R2 $ok "baseline R1 congelada: $rel"
}
Assert-Fase65R2 ($AllTweaks.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert-Fase65R2 ((@($AllTweaks.id | Sort-Object -Unique)).Count -eq 230) '230 IDs permanecem únicos'

Write-Host "`n=== TEST 01: PlannerOptimized puro, PS5.1-safe e hot-path limpo ===" -ForegroundColor Yellow
$plannerOptPath=Join-Path $Root 'src\Core\PlannerOptimized.ps1'
$plannerOptText=Get-Content -LiteralPath $plannerOptPath -Raw -Encoding UTF8
$mutationTokens=@('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Set-Service','Register-ScheduledTask','Unregister-ScheduledTask','bcdedit.exe','powercfg.exe','Invoke-NativeCommand','Remove-AppxPackage')
$found=@()
foreach ($token in $mutationTokens) { if ($plannerOptText -match [regex]::Escape($token)) { $found += $token } }
Assert-Fase65R2 ($found.Count -eq 0) 'PlannerOptimized não contém primitivos de mutação do Windows'
Assert-Fase65R2 ($plannerOptText -notmatch 'Generic\.List\[object\]') 'PlannerOptimized evita Generic.List[object] no PowerShell 5.1'
Assert-Fase65R2 ($plannerOptText -notmatch '\$candidateOrdered\s*\|\s*Where-Object') 'topologia otimizada elimina scan Where-Object de candidateOrdered'
Assert-Fase65R2 ($plannerOptText -notmatch '\$orderedIds\s*-notcontains') 'topologia otimizada elimina -notcontains sobre orderedIds'
Assert-Fase65R2 ($plannerOptText -match 'System\.Collections\.SortedList') 'ordenação topológica usa fila estável indexada por posição'

Write-Host "`n=== TEST 02: PlannerRuntime materializa metadados uma vez ===" -ForegroundColor Yellow
$catalogRuntime = New-WinSlimCatalogRuntime -CatalogTweaks $AllTweaks
$presetRuntime = New-WinSlimPresetRuntime -CatalogTweaks $AllTweaks -PresetCatalog $PresetCatalog -RuleCatalog $RuleCatalog
$plannerRuntime = New-WinSlimPlannerRuntime -CatalogRuntime $presetRuntime.CatalogRuntime
Assert-Fase65R2 $catalogRuntime.Valid 'CatalogRuntime permanece válido'
Assert-Fase65R2 ($plannerRuntime.Count -eq 230) 'PlannerRuntime contém 230 entradas'
Assert-Fase65R2 ($plannerRuntime.CatalogFingerprint -eq $presetRuntime.CatalogRuntime.Fingerprint) 'PlannerRuntime está vinculado ao mesmo CatalogRuntime do PresetRuntime'
Assert-Fase65R2 ($plannerRuntime.TypeById.Count -eq 230) 'TypeById indexa 230 tweaks'
Assert-Fase65R2 ($plannerRuntime.RequiresRestartById.Count -eq 230) 'RequiresRestartById indexa 230 tweaks'
Assert-Fase65R2 ($plannerRuntime.RestartScopeById.Count -eq 230) 'RestartScopeById indexa 230 tweaks'

Write-Host "`n=== TEST 03: equivalência Planner R1 x PlannerOptimized em presets/OS/overlays ===" -ForegroundColor Yellow
$cases=New-Object System.Collections.ArrayList
foreach ($os in @('10','11')) {
    $caseContext = if ($os -eq '10') { $ctx10 } else { $ctx11 }
    foreach ($name in @('Balanceado','Gamer','Extremo')) {
        [void]$cases.Add([PSCustomObject]@{ Name="$name / Windows $os"; Preset=$name; Profiles=@(); High=$false; Context=$caseContext })
    }
}
$mediumProfiles=@($ScenarioSpec.mediumStack.profiles | ForEach-Object { [string]$_ })
[void]$cases.Add([PSCustomObject]@{ Name='Gamer + 14 overlays'; Preset='Gamer'; Profiles=$mediumProfiles; High=$false; Context=$ctx11 })
[void]$cases.Add([PSCustomObject]@{ Name='Gamer + HAGS/CS2/Programming'; Preset='Gamer'; Profiles=@('HW-HAGS-ON','WL-CS2','WL-PROGRAMMING'); High=$false; Context=$ctx11 })
[void]$cases.Add([PSCustomObject]@{ Name='Gamer + P-core Alto'; Preset='Gamer'; Profiles=@('HW-CS2-P-CORES'); High=$true; Context=$ctx11 })
[void]$cases.Add([PSCustomObject]@{ Name='Gamer + MSI sem GPU'; Preset='Gamer'; Profiles=@('HW-MSI-GPU'); High=$false; Context=$ctxNoGpu })

foreach ($case in @($cases.ToArray())) {
    $allowHigh=[bool]$case.High
    $legacy=Invoke-WinSlimPresetRuntimePlannerValidation -PresetRuntime $presetRuntime -PresetName $case.Preset -ConditionalProfiles @($case.Profiles) -AllowHighRiskConditional:$allowHigh -Context $case.Context
    $fast=Invoke-WinSlimPresetRuntimePlannerValidationR2 -PresetRuntime $presetRuntime -PlannerRuntime $plannerRuntime -PresetName $case.Preset -ConditionalProfiles @($case.Profiles) -AllowHighRiskConditional:$allowHigh -Context $case.Context
    $ok=($legacy.PolicyFingerprint -eq $fast.PolicyFingerprint) -and
        ($legacy.PlannerFingerprint -eq $fast.PlannerFingerprint) -and
        ($legacy.CanResolve -eq $fast.CanResolve) -and
        ($legacy.CanExecute -eq $fast.CanExecute) -and
        ($legacy.SelectedCount -eq $fast.SelectedCount) -and
        ($legacy.DependencyCount -eq $fast.DependencyCount) -and
        ($legacy.ExecutableCount -eq $fast.ExecutableCount) -and
        ($legacy.SkippedCount -eq $fast.SkippedCount) -and
        ($legacy.BlockedCount -eq $fast.BlockedCount) -and
        ((Get-PlanSignature65R2 $legacy.Plan) -eq (Get-PlanSignature65R2 $fast.Plan))
    Assert-Fase65R2 $ok "$($case.Name): PlannerOptimized é semanticamente/fingerprint-equivalente"
}

Write-Host "`n=== TEST 04: equivalência em cenários estruturais sintéticos ===" -ForegroundColor Yellow
$syntheticCases=New-Object System.Collections.ArrayList
[void]$syntheticCases.Add([PSCustomObject]@{ Name='dependência transitiva'; Tweaks=@(
    (New-SyntheticTweak65R2 -Id 'A' -Dependencies @('B')),
    (New-SyntheticTweak65R2 -Id 'B' -Dependencies @('C')),
    (New-SyntheticTweak65R2 -Id 'C')
); Selected=@('A'); Policy='Block'; Context=$ctx11 })
[void]$syntheticCases.Add([PSCustomObject]@{ Name='dependência ausente'; Tweaks=@(
    (New-SyntheticTweak65R2 -Id 'A' -Dependencies @('MISSING'))
); Selected=@('A'); Policy='Block'; Context=$ctx11 })
[void]$syntheticCases.Add([PSCustomObject]@{ Name='ciclo A-B'; Tweaks=@(
    (New-SyntheticTweak65R2 -Id 'A' -Dependencies @('B')),
    (New-SyntheticTweak65R2 -Id 'B' -Dependencies @('A'))
); Selected=@('A'); Policy='Block'; Context=$ctx11 })
[void]$syntheticCases.Add([PSCustomObject]@{ Name='conflict Block'; Tweaks=@(
    (New-SyntheticTweak65R2 -Id 'A' -Conflicts @('B')),
    (New-SyntheticTweak65R2 -Id 'B')
); Selected=@('A','B'); Policy='Block'; Context=$ctx11 })
[void]$syntheticCases.Add([PSCustomObject]@{ Name='conflict PreferFirst'; Tweaks=@(
    (New-SyntheticTweak65R2 -Id 'A' -Conflicts @('B')),
    (New-SyntheticTweak65R2 -Id 'B')
); Selected=@('A','B'); Policy='PreferFirst'; Context=$ctx11 })
[void]$syntheticCases.Add([PSCustomObject]@{ Name='mutex Block'; Tweaks=@(
    (New-SyntheticTweak65R2 -Id 'A' -MutexGroup 'G1'),
    (New-SyntheticTweak65R2 -Id 'B' -MutexGroup 'G1')
); Selected=@('A','B'); Policy='Block'; Context=$ctx11 })
[void]$syntheticCases.Add([PSCustomObject]@{ Name='unknown selection'; Tweaks=@(
    (New-SyntheticTweak65R2 -Id 'A')
); Selected=@('A','UNKNOWN'); Policy='Block'; Context=$ctx11 })
[void]$syntheticCases.Add([PSCustomObject]@{ Name='requires admin'; Tweaks=@(
    (New-SyntheticTweak65R2 -Id 'A' -RequiresAdmin $true)
); Selected=@('A'); Policy='Block'; Context=$ctxNoAdmin })

foreach ($case in @($syntheticCases.ToArray())) {
    $legacy=New-WinSlimExecutionPlan -CatalogTweaks $case.Tweaks -SelectedIds @($case.Selected) -Context $case.Context -ConflictPolicy $case.Policy
    $rt=New-WinSlimCatalogRuntime -CatalogTweaks $case.Tweaks
    $prt=New-WinSlimPlannerRuntime -CatalogRuntime $rt
    $fast=New-WinSlimExecutionPlanOptimized -PlannerRuntime $prt -SelectedIds @($case.Selected) -Context $case.Context -ConflictPolicy $case.Policy
    Assert-Fase65R2 ((Get-PlanSignature65R2 $legacy) -eq (Get-PlanSignature65R2 $fast)) "$($case.Name): decisão/ordem/fingerprint equivalentes"
}

Write-Host "`n=== TEST 05: Preview/binding permanecem idênticos ===" -ForegroundColor Yellow
foreach ($name in @('Balanceado','Gamer','Extremo')) {
    $legacy=Invoke-WinSlimPresetRuntimePlannerValidation -PresetRuntime $presetRuntime -PresetName $name -Context $ctx11
    $fast=Invoke-WinSlimPresetRuntimePlannerValidationR2 -PresetRuntime $presetRuntime -PlannerRuntime $plannerRuntime -PresetName $name -Context $ctx11
    $previewLegacy=New-WinSlimPresetPreview -ValidationReport $legacy
    $previewFast=New-WinSlimPresetPreview -ValidationReport $fast
    Assert-Fase65R2 ($previewLegacy.PreviewFingerprint -eq $previewFast.PreviewFingerprint) "$name preserva PreviewFingerprint"
    $bindingFast = Test-WinSlimPreviewPlanBinding -Preview $previewFast -Plan $fast.Plan
    Assert-Fase65R2 ([bool]$bindingFast.Valid -and [string]$bindingFast.ReasonCode -eq 'Bound') "$name mantém binding Preview -> Plan"
}

Write-Host "`n=== TEST 06: benchmarks Planner/pipeline antes-depois ===" -ForegroundColor Yellow
$plannerIterations=[int]$BenchSpec.plannerIterations
$pipelineIterations=[int]$BenchSpec.pipelineIterations
$policy=Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $presetRuntime -PresetName 'Extremo'

# Warm-up.
$null=New-WinSlimExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($policy.SelectedIds) -LevelSelections $policy.LevelSelections -Context $ctx11 -ConflictPolicy 'Block'
$null=New-WinSlimExecutionPlanOptimized -PlannerRuntime $plannerRuntime -SelectedIds @($policy.SelectedIds) -LevelSelections $policy.LevelSelections -Context $ctx11 -ConflictPolicy 'Block'
$null=Invoke-WinSlimPresetRuntimePlannerValidation -PresetRuntime $presetRuntime -PresetName 'Gamer' -Context $ctx11
$null=Invoke-WinSlimPresetRuntimePlannerValidationR2 -PresetRuntime $presetRuntime -PlannerRuntime $plannerRuntime -PresetName 'Gamer' -Context $ctx11

$legacyPlannerMs=Measure-ActionMs65R2 {
    for($i=0;$i -lt $plannerIterations;$i++) {
        $null=New-WinSlimExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($policy.SelectedIds) -LevelSelections $policy.LevelSelections -Context $ctx11 -ConflictPolicy 'Block'
    }
}
$optimizedPlannerMs=Measure-ActionMs65R2 {
    for($i=0;$i -lt $plannerIterations;$i++) {
        $null=New-WinSlimExecutionPlanOptimized -PlannerRuntime $plannerRuntime -SelectedIds @($policy.SelectedIds) -LevelSelections $policy.LevelSelections -Context $ctx11 -ConflictPolicy 'Block'
    }
}
$legacyPipelineMs=Measure-ActionMs65R2 {
    for($i=0;$i -lt $pipelineIterations;$i++) {
        foreach($name in @('Balanceado','Gamer','Extremo')) {
            $null=Invoke-WinSlimPresetRuntimePlannerValidation -PresetRuntime $presetRuntime -PresetName $name -Context $ctx11
        }
    }
}
$optimizedPipelineMs=Measure-ActionMs65R2 {
    for($i=0;$i -lt $pipelineIterations;$i++) {
        foreach($name in @('Balanceado','Gamer','Extremo')) {
            $null=Invoke-WinSlimPresetRuntimePlannerValidationR2 -PresetRuntime $presetRuntime -PlannerRuntime $plannerRuntime -PresetName $name -Context $ctx11
        }
    }
}
$plannerSpeedup=Get-Speedup65R2 $legacyPlannerMs $optimizedPlannerMs
$pipelineSpeedup=Get-Speedup65R2 $legacyPipelineMs $optimizedPipelineMs
Write-Host ("  Planner:  legado={0} ms | otimizado={1} ms | speedup={2}x" -f $legacyPlannerMs,$optimizedPlannerMs,$plannerSpeedup) -ForegroundColor Cyan
Write-Host ("  Pipeline: legado={0} ms | otimizado={1} ms | speedup={2}x" -f $legacyPipelineMs,$optimizedPipelineMs,$pipelineSpeedup) -ForegroundColor Cyan
Assert-Fase65R2 ($legacyPlannerMs -gt 0 -and $optimizedPlannerMs -gt 0 -and $legacyPipelineMs -gt 0 -and $optimizedPipelineMs -gt 0) 'benchmarks Planner/pipeline produziram medições válidas'
if($plannerSpeedup -lt 1.0){ Warn-Fase65R2 "PlannerOptimized não foi mais rápido nesta execução ($plannerSpeedup`x)." }
if($pipelineSpeedup -lt 1.0){ Warn-Fase65R2 "pipeline otimizado não foi mais rápido nesta execução ($pipelineSpeedup`x)." }

$benchReport=[PSCustomObject]@{
    schemaVersion='1.0'; phase='FASE6.5-R2'; timestamp=(Get-Date).ToString('o'); powershell=$PSVersionTable.PSVersion.ToString(); catalogCount=230
    iterations=[PSCustomObject]@{ planner=$plannerIterations; pipeline=$pipelineIterations }
    planner=[PSCustomObject]@{ legacyMs=$legacyPlannerMs; optimizedMs=$optimizedPlannerMs; speedup=$plannerSpeedup }
    pipeline=[PSCustomObject]@{ legacyMs=$legacyPipelineMs; optimizedMs=$optimizedPipelineMs; speedup=$pipelineSpeedup }
    warnings=@($Warnings)
}
$benchDir=Join-Path $Root 'benchmarks'
if(-not(Test-Path -LiteralPath $benchDir)){ New-Item -ItemType Directory -Path $benchDir -Force | Out-Null }
$benchPath=Join-Path $benchDir 'FASE6.5-R2-last-run.json'
$benchReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $benchPath -Encoding UTF8
Assert-Fase65R2 (Test-Path -LiteralPath $benchPath) 'relatório salvo em benchmarks\FASE6.5-R2-last-run.json'

Write-Host "`n=== TEST 07: arquitetura protegida / fechamento R2 ===" -ForegroundColor Yellow
Assert-Fase65R2 ($AllTweaks.Count -eq 230) 'backend permanece 230'
Assert-Fase65R2 ($presetRuntime.PresetSelections['Balanceado'].SelectedIds.Count -eq 105) 'Balanceado permanece 105'
Assert-Fase65R2 ($presetRuntime.PresetSelections['Gamer'].SelectedIds.Count -eq 129) 'Gamer permanece 129'
Assert-Fase65R2 ($presetRuntime.PresetSelections['Extremo'].SelectedIds.Count -eq 168) 'Extremo permanece 168'
Assert-Fase65R2 ((Get-FileHash -LiteralPath (Join-Path $Root 'src\Core\Planner.ps1') -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$baseline.files.PSObject.Properties['src/Core/Planner.ps1'].Value).ToLowerInvariant()) 'Planner R1 canônico ainda congelado durante shadow validation R2'
Assert-Fase65R2 ((Get-FileHash -LiteralPath (Join-Path $Root 'src\Core\Transaction.ps1') -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$baseline.files.PSObject.Properties['src/Core/Transaction.ps1'].Value).ToLowerInvariant()) 'Transaction Manager R13 permanece congelado'

Write-Host "`n=== RESUMO FASE 6.5 R2.1 ===" -ForegroundColor Yellow
if($Failures.Count -eq 0){
    Write-Host 'FASE 6.5 R2.1 APROVADA - Planner shadow otimizado preserva fingerprints/decisões, binding Preview/Plan e benchmarks antes/depois.' -ForegroundColor Green
    Write-Host 'Próximo subgate: FASE 6.5 R3 - cleanup/otimização do Transaction Manager e persistência, mantendo rollback/recovery R13.' -ForegroundColor Cyan
    exit 0
}
Write-Host "FASE 6.5 R2 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $Failures){ Write-Host " - $f" -ForegroundColor Red }
exit 1

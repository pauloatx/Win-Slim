#requires -Version 5.1
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$OutputEncoding=[Console]::OutputEncoding
$Root=Split-Path -Parent $PSScriptRoot

. (Join-Path $Root 'src\Core\Planner.ps1')
. (Join-Path $Root 'src\Core\Transaction.ps1')
. (Join-Path $Root 'src\Core\CatalogRuntime.ps1')
. (Join-Path $Root 'src\Core\PresetResolver.ps1')
. (Join-Path $Root 'src\Core\PresetPolicyEngine.ps1')
. (Join-Path $Root 'src\Core\PresetRuntime.ps1')
. (Join-Path $Root 'src\Core\PresetPlannerValidator.ps1')
. (Join-Path $Root 'src\Core\PresetPreview.ps1')
. (Join-Path $Root 'src\Core\PlannerOptimized.ps1')
. (Join-Path $Root 'src\Core\TransactionOptimized.ps1')
. (Join-Path $Root 'src\Core\RuntimePromotion.ps1')

$Failures=New-Object System.Collections.ArrayList
$Warnings=New-Object System.Collections.ArrayList
function Ok65R4([string]$m){Write-Host "  [OK] $m" -ForegroundColor Green}
function Fail65R4([string]$m){Write-Host "  [FAIL] $m" -ForegroundColor Red;[void]$Failures.Add($m)}
function Warn65R4([string]$m){Write-Host "  [WARN] $m" -ForegroundColor Yellow;[void]$Warnings.Add($m)}
function Assert65R4([bool]$Condition,[string]$Message){if($Condition){Ok65R4 $Message}else{Fail65R4 $Message}}
function Measure65R4([scriptblock]$Action){$sw=[Diagnostics.Stopwatch]::StartNew();& $Action;$sw.Stop();[Math]::Round($sw.Elapsed.TotalMilliseconds,3)}
function Speed65R4([double]$Legacy,[double]$Fast){if($Fast -le 0){return 0};[Math]::Round($Legacy/$Fast,2)}

function Get-AllTweaks65R4 {
    $out=New-Object System.Collections.ArrayList
    foreach($f in @('catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json','catalogs\validated\Expansion-R4.json','catalogs\validated\Expansion-R4.1.json','catalogs\validated\Expansion-R4.2.json')){
        $j=Get-Content -LiteralPath (Join-Path $Root $f) -Raw -Encoding UTF8|ConvertFrom-Json
        $items=if($j.PSObject.Properties.Name -contains 'tweaks'){@($j.tweaks)}else{@($j)}
        foreach($x in $items){[void]$out.Add($x)}
    }
    @($out.ToArray())
}
function PlanSig65R4($p){
    $ord=@($p.ExecutionOrder|ForEach-Object{"$($_.Sequence):$($_.TweakId):$($_.Level):$($_.SelectionSource)"}) -join '|'
    "$($p.Fingerprint);$($p.CanExecute);$($p.HasWork);$ord;$(@($p.BlockedTweaks).Count);$(@($p.SkippedTweaks).Count)"
}
function New-Validation65R4($PresetRuntime,[string]$PresetName,$Context,[string[]]$Profiles=@(),[switch]$AllowHigh){
    $policy=Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $PresetRuntime -PresetName $PresetName -ConditionalProfiles $Profiles -AllowHighRiskConditional:$AllowHigh
    if(-not [bool]$policy.CanResolve){throw "Policy bloqueada em cenário R4: $PresetName"}
    $plan=New-WinSlimExecutionPlan -CatalogTweaks $PresetRuntime.CatalogRuntime.Tweaks -SelectedIds @($policy.SelectedIds) -LevelSelections $policy.LevelSelections -Context $Context -ConflictPolicy Block
    [PSCustomObject]@{SchemaVersion=1;Stage='Planner';PresetName=$PresetName;ConditionalProfiles=@($policy.EnabledConditionalProfiles);PolicyFingerprint=[string]$policy.Fingerprint;PlannerFingerprint=[string]$plan.Fingerprint;Policy=$policy;Plan=$plan;CanResolve=$true;CanExecute=[bool]$plan.CanExecute;HasWork=[bool]$plan.HasWork;SelectedCount=@($plan.SelectedTweaks).Count;DependencyCount=@($plan.ExpandedDependencies).Count;ExecutableCount=@($plan.ExecutionOrder).Count;SkippedCount=@($plan.SkippedTweaks).Count;BlockedCount=@($plan.BlockedTweaks).Count;RiskSummary=$plan.RiskSummary;RestartRequirements=$plan.RestartRequirements}
}

function New-TxContext65R4{$state=@{};[PSCustomObject]@{State=$state;UndoOrder=(New-Object System.Collections.ArrayList)}}
$Backup65R4={param($Tweak,$Level,$Context,$Step)$id=[string]$Tweak.id;$e=$Context.State.ContainsKey($id);[PSCustomObject]@{Exists=$e;Value=$(if($e){$Context.State[$id]}else{$null})}}
$Apply65R4={param($Tweak,$Level,$Context)$id=[string]$Tweak.id;$e=$Context.State.ContainsKey($id);$before=[PSCustomObject]@{Exists=$e;Value=$(if($e){$Context.State[$id]}else{$null})};if($id -eq 'SYN-FAIL'){return [PSCustomObject]@{Id=$id;Success=$false;Changed=$false;StateBefore=$before;StateAfter=$before;Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@()};Restart='None';Warning=$null;Error='Falha sintética'}};$v="APPLIED:$id";$changed=(-not $e)-or([string]$Context.State[$id] -ne $v);if($changed){$Context.State[$id]=$v};[PSCustomObject]@{Id=$id;Success=$true;Changed=$changed;StateBefore=$before;StateAfter=[PSCustomObject]@{Exists=$true;Value=$v};Verification=[PSCustomObject]@{Applicable=$true;Success=$true;Checks=@()};Restart='None';Warning=$null;Error=$null}}
$Undo65R4={param($Tweak,$Level,$Context,$BackupData,$Step)[void]$Context.UndoOrder.Add([string]$Step.TweakId);$id=[string]$Tweak.id;if($BackupData.Exists){$Context.State[$id]=$BackupData.Value}else{[void]$Context.State.Remove($id)};[PSCustomObject]@{Id=$id;Success=$true;Changed=$true;Verification=[PSCustomObject]@{Applicable=$true;Success=$true;Checks=@()};Restart='None';Warning=$null;Error=$null}}
function New-SyntheticItems65R4([int]$Count){$a=New-Object System.Collections.ArrayList;for($i=1;$i -le $Count;$i++){[void]$a.Add([PSCustomObject]@{Tweak=[PSCustomObject]@{id="TX-$i"};Level=-1})};@($a.ToArray())}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 6.5 R4.1 / Promotion & Full Regression'
Write-Host '============================================================'
Write-Host 'R4.1: correção de parser PS5.1 no harness; promoção/runtime R4 preservados'

$baseline=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R4-baseline.json') -Raw -Encoding UTF8|ConvertFrom-Json
$bench=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R4-benchmark.json') -Raw -Encoding UTF8|ConvertFrom-Json
$AllTweaks=@(Get-AllTweaks65R4)
$presetCatalog=Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8|ConvertFrom-Json
$ruleCatalog=Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-PresetRules-R2.json') -Raw -Encoding UTF8|ConvertFrom-Json
$PresetRuntime=New-WinSlimPresetRuntime -CatalogTweaks $AllTweaks -PresetCatalog $presetCatalog -RuleCatalog $ruleCatalog
$Context=New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true

Write-Host "`n=== TEST 00: baseline R3 congelada + backend 230 ===" -ForegroundColor Yellow
foreach($p in $baseline.files.PSObject.Properties){$path=Join-Path $Root ([string]$p.Name);$ok=(Test-Path -LiteralPath $path)-and((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()-eq([string]$p.Value).ToLowerInvariant());Assert65R4 $ok "baseline R3 congelada: $($p.Name)"}
Assert65R4 ($AllTweaks.Count -eq 230) 'backend permanece em 230 tweaks'
Assert65R4 ((@($AllTweaks.id|Select-Object -Unique).Count)-eq 230) '230 IDs permanecem únicos'

Write-Host "`n=== TEST 01: Promotion layer pura, controlável e PS5.1-safe ===" -ForegroundColor Yellow
$raw=Get-Content -LiteralPath (Join-Path $Root 'src\Core\RuntimePromotion.ps1') -Raw -Encoding UTF8
Assert65R4 ($raw -notmatch 'Generic\.List\[object\]') 'RuntimePromotion evita Generic.List[object]'
Assert65R4 ($raw -match 'Enable-WinSlimRuntimePromotion' -and $raw -match 'Disable-WinSlimRuntimePromotion') 'promoção possui Enable/Disable explícitos'
Assert65R4 ($raw -match 'PlannerCache') 'promoção mantém cache de PlannerRuntime por catálogo'
$status0=Get-WinSlimRuntimePromotionStatus
Assert65R4 ($status0.Planner -eq 'Legacy' -and $status0.Transaction -eq 'Legacy') 'promotion inicia em fallback Legacy'
Enable-WinSlimRuntimePromotion -Planner -Transaction|Out-Null
$status1=Get-WinSlimRuntimePromotionStatus
Assert65R4 ($status1.Planner -eq 'Optimized' -and $status1.Transaction -eq 'Optimized') 'Enable promove Planner e Transaction'

Write-Host "`n=== TEST 02: Planner promovido preserva presets/fingerprint ===" -ForegroundColor Yellow
foreach($name in @('Balanceado','Gamer','Extremo')){
    $policy=Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $PresetRuntime -PresetName $name
    $legacy=Invoke-WinSlimLegacyExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($policy.SelectedIds) -LevelSelections $policy.LevelSelections -Context $Context -ConflictPolicy Block
    $fast=New-WinSlimExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($policy.SelectedIds) -LevelSelections $policy.LevelSelections -Context $Context -ConflictPolicy Block
    Assert65R4 ((PlanSig65R4 $legacy)-eq(PlanSig65R4 $fast)) "${name}: API promovida é fingerprint/ordem-equivalente"
}
$policyStack=Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $PresetRuntime -PresetName Gamer -ConditionalProfiles @('HW-HAGS-ON','WL-CS2','WL-PROGRAMMING')
$legacyStack=Invoke-WinSlimLegacyExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($policyStack.SelectedIds) -LevelSelections $policyStack.LevelSelections -Context $Context -ConflictPolicy Block
$fastStack=New-WinSlimExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($policyStack.SelectedIds) -LevelSelections $policyStack.LevelSelections -Context $Context -ConflictPolicy Block
Assert65R4 ((PlanSig65R4 $legacyStack)-eq(PlanSig65R4 $fastStack)) 'Gamer + overlays mantém equivalência completa'
$statusCache=Get-WinSlimRuntimePromotionStatus
Assert65R4 ($statusCache.PlannerCacheEntries -ge 1 -and $statusCache.PlannerCacheHits -ge 1) 'cache do Planner promovido é reutilizado'

Write-Host "`n=== TEST 03: Preview/binding sobre API promovida ===" -ForegroundColor Yellow
foreach($name in @('Balanceado','Gamer','Extremo')){
    $v=New-Validation65R4 -PresetRuntime $PresetRuntime -PresetName $name -Context $Context
    $preview=New-WinSlimPresetPreview -ValidationReport $v
    $binding=Test-WinSlimPreviewPlanBinding -Preview $preview -Plan $v.Plan
    Assert65R4 ($preview.TransactionReady -and [bool]$binding.Valid -and [string]$binding.ReasonCode -eq 'Bound') "$name mantém Preview -> Plan binding promovido"
}

Write-Host "`n=== TEST 04: Transaction promovido preserva commit e rollback LIFO ===" -ForegroundColor Yellow
$items=New-SyntheticItems65R4 6
$lc=New-TxContext65R4;$fc=New-TxContext65R4
$legacyTx=Invoke-WinSlimLegacyTransactionPlan -Items $items -Context $lc -ApplyHandler $Apply65R4 -BackupHandler $Backup65R4 -UndoHandler $Undo65R4 -NoPersist
$fastTx=Invoke-TransactionPlan -Items $items -Context $fc -ApplyHandler $Apply65R4 -BackupHandler $Backup65R4 -UndoHandler $Undo65R4 -NoPersist
Assert65R4 ($legacyTx.Status -eq 'Committed' -and $fastTx.Status -eq 'Committed') 'commit sintético conclui nos dois engines'
Assert65R4 ((@($legacyTx.Steps|ForEach-Object{"$($_.TweakId):$($_.Status):$($_.Changed)"})-join '|') -eq (@($fastTx.Steps|ForEach-Object{"$($_.TweakId):$($_.Status):$($_.Changed)"})-join '|')) 'commit promovido preserva steps/status'
$failItems=@($items[0],$items[1],[PSCustomObject]@{Tweak=[PSCustomObject]@{id='SYN-FAIL'};Level=-1})
$rb=New-TxContext65R4
$rbTx=Invoke-TransactionPlan -Items $failItems -Context $rb -FailurePolicy RollbackTransaction -ApplyHandler $Apply65R4 -BackupHandler $Backup65R4 -UndoHandler $Undo65R4 -NoPersist
Assert65R4 ($rbTx.Status -eq 'RolledBack') 'falha posterior dispara rollback promovido'
Assert65R4 ((@($rb.UndoOrder)-join ',') -eq 'TX-2,TX-1') 'rollback promovido permanece estritamente LIFO'

Write-Host "`n=== TEST 05: end-to-end Policy -> Planner -> Preview -> Transaction promovidos ===" -ForegroundColor Yellow
$v=New-Validation65R4 -PresetRuntime $PresetRuntime -PresetName Gamer -Context $Context -Profiles @('HW-HAGS-ON','WL-CS2','WL-PROGRAMMING')
$preview=New-WinSlimPresetPreview -ValidationReport $v
$txItems=@(Get-WinSlimPreviewTransactionItems -Preview $preview -Plan $v.Plan | Select-Object -First 12)
$e2eCtx=New-TxContext65R4
$e2e=Invoke-TransactionPlan -Items $txItems -Context $e2eCtx -ApplyHandler $Apply65R4 -BackupHandler $Backup65R4 -UndoHandler $Undo65R4 -NoPersist
Assert65R4 ($preview.TransactionReady -and $e2e.Status -eq 'Committed') 'pipeline promovido completa Preview -> Transaction'
Assert65R4 ($e2e.Steps.Count -eq $txItems.Count) 'handoff promovido preserva contagem 1:1'
Assert65R4 ((@($e2e.Steps.TweakId)-join '|') -eq (@($txItems.TweakId)-join '|')) 'handoff promovido preserva ordem exibida no Preview'

Write-Host "`n=== TEST 06: fallback controlado não muda semântica ===" -ForegroundColor Yellow
Disable-WinSlimRuntimePromotion -Planner -Transaction|Out-Null
$stLegacy=Get-WinSlimRuntimePromotionStatus
Assert65R4 ($stLegacy.Planner -eq 'Legacy' -and $stLegacy.Transaction -eq 'Legacy') 'Disable retorna APIs ao fallback Legacy'
$p=Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $PresetRuntime -PresetName Balanceado
$fallback=New-WinSlimExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($p.SelectedIds) -LevelSelections $p.LevelSelections -Context $Context -ConflictPolicy Block
$direct=Invoke-WinSlimLegacyExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($p.SelectedIds) -LevelSelections $p.LevelSelections -Context $Context -ConflictPolicy Block
Assert65R4 ((PlanSig65R4 $fallback)-eq(PlanSig65R4 $direct)) 'fallback Planner usa semântica canônica R1'
Enable-WinSlimRuntimePromotion -Planner -Transaction|Out-Null

Write-Host "`n=== TEST 07: benchmark final antes/depois ===" -ForegroundColor Yellow
$g=Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $PresetRuntime -PresetName Gamer -ConditionalProfiles @('HW-HAGS-ON','WL-CS2','WL-PROGRAMMING')
$legacyPlanner=Measure65R4 {for($i=0;$i -lt [int]$bench.plannerIterations;$i++){$null=Invoke-WinSlimLegacyExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($g.SelectedIds) -LevelSelections $g.LevelSelections -Context $Context -ConflictPolicy Block}}
$fastPlanner=Measure65R4 {for($i=0;$i -lt [int]$bench.plannerIterations;$i++){$null=New-WinSlimExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($g.SelectedIds) -LevelSelections $g.LevelSelections -Context $Context -ConflictPolicy Block}}
$plannerSpeed=Speed65R4 $legacyPlanner $fastPlanner
$benchItems=New-SyntheticItems65R4 ([int]$bench.transactionItems)
$legacyTxMs=Measure65R4 {for($i=0;$i -lt [int]$bench.transactionIterations;$i++){$c=New-TxContext65R4;$null=Invoke-WinSlimLegacyTransactionPlan -Items $benchItems -Context $c -ApplyHandler $Apply65R4 -BackupHandler $Backup65R4 -UndoHandler $Undo65R4 -NoPersist}}
$fastTxMs=Measure65R4 {for($i=0;$i -lt [int]$bench.transactionIterations;$i++){$c=New-TxContext65R4;$null=Invoke-TransactionPlan -Items $benchItems -Context $c -ApplyHandler $Apply65R4 -BackupHandler $Backup65R4 -UndoHandler $Undo65R4 -NoPersist}}
$txSpeed=Speed65R4 $legacyTxMs $fastTxMs
$legacyE2E=Measure65R4 {for($i=0;$i -lt [int]$bench.endToEndIterations;$i++){$pol=Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $PresetRuntime -PresetName Gamer -ConditionalProfiles @('HW-HAGS-ON','WL-CS2','WL-PROGRAMMING');$pl=Invoke-WinSlimLegacyExecutionPlan -CatalogTweaks $AllTweaks -SelectedIds @($pol.SelectedIds) -LevelSelections $pol.LevelSelections -Context $Context -ConflictPolicy Block;$vr=[PSCustomObject]@{PresetName='Gamer';ConditionalProfiles=@($pol.EnabledConditionalProfiles);PolicyFingerprint=$pol.Fingerprint;PlannerFingerprint=$pl.Fingerprint;Policy=$pol;Plan=$pl;CanResolve=$true;CanExecute=$pl.CanExecute;HasWork=$pl.HasWork;SelectedCount=@($pl.SelectedTweaks).Count;DependencyCount=@($pl.ExpandedDependencies).Count;RiskSummary=$pl.RiskSummary;RestartRequirements=$pl.RestartRequirements};$pv=New-WinSlimPresetPreview -ValidationReport $vr;$its=@(Get-WinSlimPreviewTransactionItems -Preview $pv -Plan $pl|Select-Object -First 12);$c=New-TxContext65R4;$null=Invoke-WinSlimLegacyTransactionPlan -Items $its -Context $c -ApplyHandler $Apply65R4 -BackupHandler $Backup65R4 -UndoHandler $Undo65R4 -NoPersist}}
$fastE2E=Measure65R4 {for($i=0;$i -lt [int]$bench.endToEndIterations;$i++){$vr=New-Validation65R4 -PresetRuntime $PresetRuntime -PresetName Gamer -Context $Context -Profiles @('HW-HAGS-ON','WL-CS2','WL-PROGRAMMING');$pv=New-WinSlimPresetPreview -ValidationReport $vr;$its=@(Get-WinSlimPreviewTransactionItems -Preview $pv -Plan $vr.Plan|Select-Object -First 12);$c=New-TxContext65R4;$null=Invoke-TransactionPlan -Items $its -Context $c -ApplyHandler $Apply65R4 -BackupHandler $Backup65R4 -UndoHandler $Undo65R4 -NoPersist}}
$e2eSpeed=Speed65R4 $legacyE2E $fastE2E
Write-Host ("  Planner:     legado={0} ms | promovido={1} ms | speedup={2}x" -f $legacyPlanner,$fastPlanner,$plannerSpeed) -ForegroundColor Cyan
Write-Host ("  Transaction: legado={0} ms | promovido={1} ms | speedup={2}x" -f $legacyTxMs,$fastTxMs,$txSpeed) -ForegroundColor Cyan
Write-Host ("  End-to-end:  legado={0} ms | promovido={1} ms | speedup={2}x" -f $legacyE2E,$fastE2E,$e2eSpeed) -ForegroundColor Cyan
Assert65R4 ($legacyPlanner -gt 0 -and $fastPlanner -gt 0 -and $legacyTxMs -gt 0 -and $fastTxMs -gt 0 -and $legacyE2E -gt 0 -and $fastE2E -gt 0) 'benchmark final produziu medições válidas'
if($plannerSpeed -lt 1){Warn65R4 "Planner promovido não foi mais rápido nesta execução ($plannerSpeed`x)."}
if($txSpeed -lt 1){Warn65R4 "Transaction promovido não foi mais rápido nesta execução ($txSpeed`x)."}
if($e2eSpeed -lt 1){Warn65R4 "End-to-end promovido não foi mais rápido nesta execução ($e2eSpeed`x)."}
$report=[PSCustomObject]@{schemaVersion='1.0';phase='FASE6.5-R4';timestamp=(Get-Date).ToString('o');powershell=$PSVersionTable.PSVersion.ToString();planner=[PSCustomObject]@{legacyMs=$legacyPlanner;promotedMs=$fastPlanner;speedup=$plannerSpeed};transaction=[PSCustomObject]@{legacyMs=$legacyTxMs;promotedMs=$fastTxMs;speedup=$txSpeed};endToEnd=[PSCustomObject]@{legacyMs=$legacyE2E;promotedMs=$fastE2E;speedup=$e2eSpeed};warnings=@($Warnings)}
$benchDir=Join-Path $Root 'benchmarks';if(-not(Test-Path -LiteralPath $benchDir)){New-Item -ItemType Directory -Path $benchDir -Force|Out-Null};$benchPath=Join-Path $benchDir 'FASE6.5-R4-last-run.json';$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $benchPath -Encoding UTF8
Assert65R4 (Test-Path -LiteralPath $benchPath) 'relatório final salvo em benchmarks\FASE6.5-R4-last-run.json'

Write-Host "`n=== TEST 08: promoção integrada ao launcher de desenvolvimento ===" -ForegroundColor Yellow
$devRaw=Get-Content -LiteralPath (Join-Path $Root 'WinSlimSuite.dev.ps1') -Raw -Encoding UTF8
Assert65R4 ($devRaw -match 'RuntimePromotion\.ps1') 'WinSlimSuite.dev carrega RuntimePromotion'
Assert65R4 ($devRaw -match 'Enable-WinSlimRuntimePromotion\s+-Planner\s+-Transaction') 'WinSlimSuite.dev habilita promoção controlada'
Assert65R4 ($AllTweaks.Count -eq 230) 'backend final permanece 230'

Write-Host "`n=== RESUMO FASE 6.5 R4.1 ===" -ForegroundColor Yellow
if($Failures.Count -eq 0){Write-Host 'FASE 6.5 R4.1 APROVADA - Planner/Transaction otimizados promovidos com fallback controlado; regressão e benchmark end-to-end preservados.' -ForegroundColor Green;Write-Host 'FASE 6.5 CONCLUÍDA. Próximo gate: FASE 7 - nova UI sobre backend/runtime promovidos.' -ForegroundColor Cyan;exit 0}
Write-Host "FASE 6.5 R4.1 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $Failures){Write-Host " - $f" -ForegroundColor Red}
exit 1

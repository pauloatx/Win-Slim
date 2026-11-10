$ErrorActionPreference = 'Stop'

$TestsRoot = Split-Path -Parent $PSScriptRoot
$ProviderContract = Join-Path $TestsRoot 'src\Core\ProviderContract.ps1'
$RegistryProvider = Join-Path $TestsRoot 'src\Providers\RegistryProvider.ps1'
$PlannerPath = Join-Path $TestsRoot 'src\Core\Planner.ps1'
$TransactionPath = Join-Path $TestsRoot 'src\Core\Transaction.ps1'

. $ProviderContract
. $RegistryProvider
. $PlannerPath
. $TransactionPath

$script:failures = @()
function Assert-Fase5R4 {
    param([bool]$Condition,[string]$Message,[string]$Detail=$null)
    if($Condition){ Write-Host "  [OK] $Message" -ForegroundColor Green }
    else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        if($Detail){ Write-Host "         $Detail" -ForegroundColor DarkYellow }
        $script:failures += $(if($Detail){"$Message :: $Detail"}else{$Message})
    }
}
function Get-Sha256 { param([string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-Json { param([string]$Path) Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Get-AllValidatedTweaks {
    $out=@()
    foreach($f in @('catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json','catalogs\validated\Expansion-R4.json')){
        $d=Get-Json (Join-Path $TestsRoot $f)
        $out += @($d.tweaks)
    }
    return @($out)
}
function Get-RegistryTargetKey {
    param($Operation)
    return (([string]$Operation.Path).ToLowerInvariant() + '|' + ([string]$Operation.Name).ToLowerInvariant())
}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 5 R4 / Curated Catalog Expansion'
Write-Host '============================================================'
Write-Host 'R4: +12 políticas documentadas Microsoft; backend validado 202; UI legada protegida'

Write-Host "`n=== TEST 00: baseline R3.3 congelada + JSON novo válido ==="
$expected=@{
    'src\Core\Transaction.ps1'='ecee3451af44cef809215d4a9045c2a81d7596e57062273e2860c00171f43619'
    'src\Core\Planner.ps1'='a27ab444744f3011d9ff7c539967c1d75bdcfdbf2a8a81ee2f03d56c48c81ce4'
    'src\Core\AdvancedProviderBridge.ps1'='d28f6bba2d20e95deff5868f7d6f2787cb0c0ebb2cd79672b736cc9284b666a3'
    'src\Providers\RegistryProvider.ps1'='b01680f038d0eaa075680041ef76a48938bce412991d530fd8cabadf0186a90e'
    'src\Providers\CoreParkingProvider.ps1'='8b40540706ce36ec9cd7b282b60919ad015859f422b4a1ac286951ee7b3866c9'
    'src\Providers\CpuAffinityProvider.ps1'='02b9b38ab406ae07980346c5e32e041c7de3f6c36dff4dc32755e444efd7a424'
    'src\Providers\GpuInterruptAffinityProvider.ps1'='f496ee289c213cbafb8f28ebb769e6b23dc97ce31e4d55cc3f00d4e19187f41f'
    'catalog.json'='0e71c1fba2fb9fefba09d3b8b82007c5b972c30ae2d0c69734a30b93857cc1ba'
    'catalogs\Game-Workload.json'='19e5d57eb6ac7501ef5fc782445a44bc1bc5aaf6a59100ae45639aea7e25079d'
    'catalogs\validated\Advanced-Catalog.json'='48b03f6627c7ee9943e9c1094c93036f961fa30a6b9a61bff6b5e34f9b718389'
}
foreach($rel in $expected.Keys){
    $actual=Get-Sha256 (Join-Path $TestsRoot $rel)
    Assert-Fase5R4 ($actual -eq $expected[$rel]) "baseline R3.3 congelada: $rel" "expected=$($expected[$rel]); actual=$actual"
}
$expansion=$null
try { $expansion=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Expansion-R4.json') } catch { }
Assert-Fase5R4 ($null -ne $expansion -and @($expansion.tweaks).Count -eq 12 -and [int]$expansion.count -eq 12) 'Expansion-R4.json parseia e declara exatamente 12 tweaks'
$sourceMap=$null
try { $sourceMap=Get-Json (Join-Path $TestsRoot 'specs\FASE5-R4-source-map.json') } catch { }
Assert-Fase5R4 ($null -ne $sourceMap -and @($sourceMap.entries).Count -eq 12) 'source-map R4 contém referência oficial para os 12 itens'
if($script:failures.Count -gt 0){ Write-Host 'PRE-FLIGHT R4 FALHOU.' -ForegroundColor Red; exit 1 }

Write-Host "`n=== TEST 01: 190 + 12 = 202 sem IDs ou alvos Registry duplicados ==="
$base=Get-Json (Join-Path $TestsRoot 'catalog.json')
$tl=Get-Json (Join-Path $TestsRoot 'catalogs\Game-Workload.json')
$adv=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Advanced-Catalog.json')
$all=Get-AllValidatedTweaks
Assert-Fase5R4 (@($base.tweaks).Count -eq 177) 'base permanece em 177 entradas'
Assert-Fase5R4 (@($tl.tweaks).Count -eq 10) 'Game-Workload Game/Workload permanece em 10 entradas'
Assert-Fase5R4 (@($adv.tweaks).Count -eq 3) 'Advanced permanece em 3 entradas'
Assert-Fase5R4 (@($expansion.tweaks).Count -eq 12) 'R4 adiciona exatamente 12 entradas'
Assert-Fase5R4 (@($all).Count -eq 202) 'backend validado chega a 202 entradas'
$dups=@($all | Group-Object id | Where-Object{$_.Count -gt 1})
Assert-Fase5R4 ($dups.Count -eq 0) 'nenhum ID duplicado em 202 entradas'
$priorTargets=@{}
$priorTweaks=@($base.tweaks)+@($tl.tweaks)+@($adv.tweaks)
foreach($t in @($priorTweaks)){
    foreach($op in @($t.registry)){
        if($null -ne $op){ $priorTargets[(Get-RegistryTargetKey $op)] = [string]$t.id }
    }
}
$collisions=@()
foreach($t in @($expansion.tweaks)){
    foreach($op in @($t.registry)){
        $k=Get-RegistryTargetKey $op
        if($priorTargets.ContainsKey($k)){ $collisions += "$($t.id)<->$($priorTargets[$k])@$k" }
    }
}
Assert-Fase5R4 ($collisions.Count -eq 0) 'nenhum novo alvo Path/Name duplica tweak anterior' $(if($collisions.Count){$collisions -join '; '}else{$null})
$catalogIssues=@((Test-WinSlimPlannerCatalog -CatalogTweaks $all) | Where-Object{$_.Severity -eq 'Error'})
Assert-Fase5R4 ($catalogIssues.Count -eq 0) 'Planner valida catálogo de 202 sem referências estruturais ausentes' $(if($catalogIssues.Count){($catalogIssues|ForEach-Object{"$($_.Code):$($_.TweakId)->$($_.Reference)"}) -join '; '}else{$null})

Write-Host "`n=== TEST 02: políticas Windows R4 exatas ==="
$expectedWindows=@{
 'PRIV-016'=@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo','DisabledByGroupPolicy',1)
 'PRIV-017'=@('HKCU:\Software\Policies\Microsoft\Windows\CloudContent','DisableTailoredExperiencesWithDiagnosticData',1)
 'PRIV-018'=@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search','AllowSearchToUseLocation',0)
 'UI-023'=@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search','EnableDynamicContentInWSB',0)
 'UI-024'=@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer','HideRecommendedPersonalizedSites',1)
}
foreach($id in $expectedWindows.Keys){
    $t=@($expansion.tweaks|Where-Object{$_.id -eq $id})[0]
    $op=@($t.registry)[0];$e=$expectedWindows[$id]
    Assert-Fase5R4 ($t -and $t.type -eq 'registry' -and $op.Path -eq $e[0] -and $op.Name -eq $e[1] -and [int]$op.Value -eq [int]$e[2] -and $op.Type -eq 'DWord') "$id registra política Windows exata"
}
$ui24=@($expansion.tweaks|Where-Object{$_.id -eq 'UI-024'})[0]
Assert-Fase5R4 (@($ui24.windowsVersion).Count -eq 1 -and [string]$ui24.windowsVersion[0] -eq '11') 'UI-024 fica restrito ao Windows 11'

Write-Host "`n=== TEST 03: políticas Microsoft Edge R4 exatas ==="
$expectedEdge=@{
 'EDGE-001'=@('StartupBoostEnabled',0)
 'EDGE-002'=@('BackgroundModeEnabled',0)
 'EDGE-003'=@('EdgeShoppingAssistantEnabled',0)
 'EDGE-004'=@('NewTabPageContentEnabled',0)
 'EDGE-005'=@('PersonalizationReportingEnabled',0)
 'EDGE-006'=@('SleepingTabsEnabled',1)
 'EDGE-007'=@('AutoDiscardSleepingTabsEnabled',1)
}
foreach($id in $expectedEdge.Keys){
    $t=@($expansion.tweaks|Where-Object{$_.id -eq $id})[0]
    $op=@($t.registry)[0];$e=$expectedEdge[$id]
    Assert-Fase5R4 ($t -and $op.Path -eq 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -and $op.Name -eq $e[0] -and [int]$op.Value -eq [int]$e[1] -and $op.Type -eq 'DWord') "$id registra política Edge exata"
}
$edge7=@($expansion.tweaks|Where-Object{$_.id -eq 'EDGE-007'})[0]
Assert-Fase5R4 (@($edge7.dependencies).Count -eq 1 -and [string]$edge7.dependencies[0] -eq 'EDGE-006') 'EDGE-007 depende explicitamente de EDGE-006'

Write-Host "`n=== TEST 04: curadoria, rollback e isolamento de presets/UI ==="
Assert-Fase5R4 (@($expansion.tweaks|Where-Object{$_.type -ne 'registry'}).Count -eq 0) 'R4 usa apenas RegistryProvider já conformado'
Assert-Fase5R4 (@($expansion.tweaks|Where-Object{@($_.rollbackClass) -notcontains 'Registry'}).Count -eq 0) 'todos os R4 declaram rollback Registry'
Assert-Fase5R4 (@($expansion.tweaks|Where-Object{@($_.presets).Count -gt 0}).Count -eq 0) 'nenhum R4 entra em preset antes da Fase 6'
Assert-Fase5R4 (@($expansion.tweaks|Where-Object{$_.uiAvailability -ne 'Phase7'}).Count -eq 0) 'todos os R4 aguardam integração UI da Fase 7'
Assert-Fase5R4 (@($expansion.tweaks|Where-Object{[string]$_.source -ne 'MS+WS'}).Count -eq 0) 'lote R4 marcado como Microsoft docs + Win-Slim'

Write-Host "`n=== TEST 05: Planner - aplicabilidade, dependência e determinismo ==="
$ctx11=[PSCustomObject]@{OS='11';IsAdmin=$true;GPU=@('NVIDIA');RAM=16;Storage='SSD';NetworkAdapters=@('Ethernet');CPU='Synthetic'}
$newIds=@($expansion.tweaks|ForEach-Object{[string]$_.id})
$planAll=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds $newIds -Context $ctx11
Assert-Fase5R4 ($planAll.CanExecute -and @($planAll.ExecutionOrder).Count -eq 12 -and @($planAll.BlockedTweaks).Count -eq 0 -and @($planAll.SkippedTweaks).Count -eq 0) 'Planner executa os 12 R4 no contexto Windows 11/admin'
$planAll2=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds $newIds -Context $ctx11
Assert-Fase5R4 ($planAll.Fingerprint -eq $planAll2.Fingerprint -and ((@($planAll.ExecutionOrder|ForEach-Object{$_.TweakId}) -join ',') -eq (@($planAll2.ExecutionOrder|ForEach-Object{$_.TweakId}) -join ','))) 'Planner mantém fingerprint e ordem determinísticos no lote R4'
$planDep=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('EDGE-007') -Context $ctx11
$depOrder=@($planDep.ExecutionOrder|ForEach-Object{$_.TweakId})
Assert-Fase5R4 ($planDep.CanExecute -and $depOrder.Count -eq 2 -and $depOrder[0] -eq 'EDGE-006' -and $depOrder[1] -eq 'EDGE-007') 'Planner expande EDGE-006 antes de EDGE-007'
$ctx10=[PSCustomObject]@{OS='10';IsAdmin=$true;GPU=@();RAM=8;Storage='SSD';NetworkAdapters=@();CPU='Synthetic'}
$planWin10=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('UI-024') -Context $ctx10
Assert-Fase5R4 (@($planWin10.SkippedTweaks|Where-Object{$_.TweakId -eq 'UI-024'}).Count -eq 1) 'Planner faz SKIP de UI-024 no Windows 10'
$ctxNoAdmin=[PSCustomObject]@{OS='11';IsAdmin=$false;GPU=@();RAM=8;Storage='SSD';NetworkAdapters=@();CPU='Synthetic'}
$planNoAdmin=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('PRIV-016') -Context $ctxNoAdmin
Assert-Fase5R4 (@($planNoAdmin.BlockedTweaks|Where-Object{$_.TweakId -eq 'PRIV-016'}).Count -eq 1) 'Planner bloqueia política HKLM R4 sem elevação'

Write-Host "`n=== TEST 06: RegistryProvider Apply/Undo exato dos 12 em HKCU temporário ==="
$testRoot='HKCU:\Software\WinSlimSuite\Tests\Fase5R4'
Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
$regPass=$true;$regDetails=@();$idx=0
foreach($t in @($expansion.tweaks)){
    $idx++
    $originalOp=@($t.registry)[0]
    $safeId=([string]$t.id -replace '[^A-Za-z0-9_.-]','_')
    $path="$testRoot\$safeId"
    $op=[PSCustomObject]@{Path=$path;Name=[string]$originalOp.Name;Value=$originalOp.Value;Type='DWord'}
    # Metade nasce ausente; metade nasce com valor sentinela para validar os dois caminhos de Undo.
    $seeded=($idx % 2 -eq 0)
    if($seeded){
        New-Item -Path $path -Force | Out-Null
        $seedValue=if([int]$op.Value -eq 0){1}else{0}
        New-ItemProperty -Path $path -Name $op.Name -Value $seedValue -PropertyType DWord -Force | Out-Null
    }
    $apply=Invoke-RegistryProvider -Id ([string]$t.id) -RegistryOps @($op) -Action Apply
    $undo=Invoke-RegistryProvider -Id ([string]$t.id) -RegistryOps @($op) -Action Undo -BackupData $apply.StateBefore
    $after=Get-RegistryState -Path $path -Name $op.Name
    $ok=$apply.Success -and $undo.Success
    if($seeded){ $ok=$ok -and $after.Exists -and [int]$after.Value -eq [int]$seedValue }
    else { $ok=$ok -and (-not $after.Exists) }
    if(-not $ok){ $regPass=$false;$regDetails += "$($t.id): apply=$($apply.Success) undo=$($undo.Success) exists=$($after.Exists) value=$($after.Value)" }
}
Assert-Fase5R4 $regPass 'RegistryProvider aplica/verifica/desfaz os 12 R4 exatamente em sandbox HKCU' $(if($regDetails.Count){$regDetails -join '; '}else{$null})
Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== TEST 07: Planner -> Transaction Manager -> RegistryProvider com rollback LIFO ==="
$txRoot='HKCU:\Software\WinSlimSuite\Tests\Fase5R4Tx'
Remove-Item -Path $txRoot -Recurse -Force -ErrorAction SilentlyContinue
$tPriv=@($expansion.tweaks|Where-Object{$_.id -eq 'PRIV-016'})[0]
$tEdge=@($expansion.tweaks|Where-Object{$_.id -eq 'EDGE-001'})[0]
$planTx=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('PRIV-016','EDGE-001') -Context $ctx11
$opsMap=@{}
$opsMap['PRIV-016']=@([PSCustomObject]@{Path="$txRoot\PRIV-016";Name='DisabledByGroupPolicy';Value=1;Type='DWord'})
$opsMap['EDGE-001']=@([PSCustomObject]@{Path="$txRoot\EDGE-001";Name='StartupBoostEnabled';Value=0;Type='DWord'})
New-Item -Path "$txRoot\PRIV-016" -Force | Out-Null
New-ItemProperty -Path "$txRoot\PRIV-016" -Name 'DisabledByGroupPolicy' -Value 7 -PropertyType DWord -Force | Out-Null
New-Item -Path "$txRoot\EDGE-001" -Force | Out-Null
New-ItemProperty -Path "$txRoot\EDGE-001" -Name 'StartupBoostEnabled' -Value 9 -PropertyType DWord -Force | Out-Null
$txContext=[PSCustomObject]@{RegistryOpsMap=$opsMap}
$backupHandler={
    param($Tweak,$Level,$Context,$Step)
    $key=[string]$Tweak.id
    $ops=@($Context.RegistryOpsMap[$key]);$b=@()
    foreach($o in $ops){$b += (Backup-RegistryValue -Path $o.Path -Name $o.Name)}
    return @($b)
}
$applyHandler={
    param($Tweak,$Level,$Context)
    if([string]$Tweak.id -eq 'F5R4-FAIL'){
        return [PSCustomObject]@{Id='F5R4-FAIL';Action='Apply';Success=$false;Changed=$false;StateBefore=$null;StateAfter=$null;Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@([PSCustomObject]@{Pass=$false})};Restart='None';Warning=$null;Error='falha sintetica esperada'}
    }
    $key=[string]$Tweak.id
    Invoke-RegistryProvider -Id $key -RegistryOps @($Context.RegistryOpsMap[$key]) -Action Apply
}
$undoHandler={
    param($Tweak,$Level,$Context,$BackupData,$Step)
    $key=[string]$Tweak.id
    Invoke-RegistryProvider -Id $key -RegistryOps @($Context.RegistryOpsMap[$key]) -Action Undo -BackupData $BackupData
}
$fail=[PSCustomObject]@{id='F5R4-FAIL';type='synthetic';name='falha sintetica';restartScope='None'}
$items=@($planTx.ExecutionOrder)+@($fail)
$tx=Invoke-TransactionPlan -Items $items -Context $txContext -FailurePolicy RollbackTransaction -NoPersist -ApplyHandler $applyHandler -BackupHandler $backupHandler -UndoHandler $undoHandler
$sPriv=Get-RegistryState -Path "$txRoot\PRIV-016" -Name 'DisabledByGroupPolicy'
$sEdge=Get-RegistryState -Path "$txRoot\EDGE-001" -Name 'StartupBoostEnabled'
$stepPriv=@($tx.Steps|Where-Object{$_.TweakId -eq 'PRIV-016'}|Select-Object -Last 1)
$stepEdge=@($tx.Steps|Where-Object{$_.TweakId -eq 'EDGE-001'}|Select-Object -Last 1)
Assert-Fase5R4 ($tx.Status -eq 'RolledBack' -and $tx.Failure -and [string]$tx.Failure.TweakId -eq 'F5R4-FAIL') 'falha posterior dispara rollback transacional do lote R4'
Assert-Fase5R4 ($sPriv.Exists -and [int]$sPriv.Value -eq 7 -and $sEdge.Exists -and [int]$sEdge.Value -eq 9) 'Transaction Manager restaura valores Registry originais do lote R4'
Assert-Fase5R4 ($stepPriv.Count -eq 1 -and $stepEdge.Count -eq 1 -and $stepPriv[0].Changed -and $stepEdge[0].Changed -and $stepPriv[0].RollbackStatus -eq 'RolledBack' -and $stepEdge[0].RollbackStatus -eq 'RolledBack') 'steps R4 ficam Changed=true + RolledBack após rollback LIFO'
Remove-Item -Path $txRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== TEST 08: UI legada protegida; backend validado em 202 ==="
$loader=Get-Content -LiteralPath (Join-Path $TestsRoot 'WinSlimSuite.dev.ps1') -Raw -Encoding UTF8
$recursiveLoader=($loader -match 'Get-ChildItem[^\r\n]+-Recurse')
Assert-Fase5R4 (-not $recursiveLoader) 'loader legado de catalogs continua não-recursivo'
$topLevelModules=@(Get-ChildItem -LiteralPath (Join-Path $TestsRoot 'catalogs') -File -Filter '*.json')
$legacyCount=@($base.tweaks).Count
foreach($f in $topLevelModules){$legacyCount += @((Get-Json $f.FullName).tweaks).Count}
Assert-Fase5R4 ($legacyCount -eq 187) 'UI/autoload legado permanece em 187 entradas'
Assert-Fase5R4 (@($all).Count -eq 202) 'catálogo backend validado chega a 202 sem exposição prematura'

Write-Host "`n=== RESUMO FASE 5 R4 ==="
if($script:failures.Count -eq 0){
    Write-Host 'FASE 5 R4 APROVADA - expansão curada validada: backend 202 entradas, rollback e Planner preservados.' -ForegroundColor Green
    Write-Host 'UI legada permanece em 187 entradas até a Fase 7.'
    Write-Host 'Proximo subgate: FASE 5 R4.1 - segunda expansão curada rumo a 215-220 entradas.'
    exit 0
}
Write-Host "FASE 5 R4 REPROVADA - $($script:failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $script:failures){Write-Host " - $f" -ForegroundColor Red}
exit 1

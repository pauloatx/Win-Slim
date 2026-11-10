$ErrorActionPreference = 'Stop'

$TestsRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $TestsRoot 'src\Core\ProviderContract.ps1')
. (Join-Path $TestsRoot 'src\Providers\RegistryProvider.ps1')
. (Join-Path $TestsRoot 'src\Core\Planner.ps1')
. (Join-Path $TestsRoot 'src\Core\Transaction.ps1')

$script:failures = @()
function Assert-Fase5R42 {
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
function Get-RegistryTargetKey { param($Operation) (([string]$Operation.Path).ToLowerInvariant() + '|' + ([string]$Operation.Name).ToLowerInvariant()) }
function Get-AllValidatedTweaks {
    $out=@()
    foreach($f in @(
        'catalog.json',
        'catalogs\Game-Workload.json',
        'catalogs\validated\Advanced-Catalog.json',
        'catalogs\validated\Expansion-R4.json',
        'catalogs\validated\Expansion-R4.1.json',
        'catalogs\validated\Expansion-R4.2.json'
    )){
        $d=Get-Json (Join-Path $TestsRoot $f)
        $out += @($d.tweaks)
    }
    return @($out)
}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 5 R4.2.1 / Curated Catalog Expansion III'
Write-Host '============================================================'
Write-Host 'R4.2.1: correção de parser EDGE-031; catálogo R4.2 preservado em 230 entradas'

Write-Host "`n=== TEST 00: baseline R4.1.1 congelada + JSON/source-map R4.2 válidos ==="
$expected=@{
    'src\Core\Transaction.ps1'='ecee3451af44cef809215d4a9045c2a81d7596e57062273e2860c00171f43619'
    'src\Core\Planner.ps1'='a27ab444744f3011d9ff7c539967c1d75bdcfdbf2a8a81ee2f03d56c48c81ce4'
    'src\Providers\RegistryProvider.ps1'='b01680f038d0eaa075680041ef76a48938bce412991d530fd8cabadf0186a90e'
    'catalog.json'='0e71c1fba2fb9fefba09d3b8b82007c5b972c30ae2d0c69734a30b93857cc1ba'
    'catalogs\Game-Workload.json'='19e5d57eb6ac7501ef5fc782445a44bc1bc5aaf6a59100ae45639aea7e25079d'
    'catalogs\validated\Advanced-Catalog.json'='48b03f6627c7ee9943e9c1094c93036f961fa30a6b9a61bff6b5e34f9b718389'
    'catalogs\validated\Expansion-R4.json'='303e411d4cafdd1f52eb1af126a6b5551adf77ae45c83eae3f1ecbbe0f1216ee'
    'catalogs\validated\Expansion-R4.1.json'='5ccba3d18ae2bf8c2144c40d5cfe06fbab825c7b5c1f6708dec2bbeb6beb3973'
    'tests\Test-Fase5-R4.1-CatalogExpansion.ps1'='8710fdeadb3f305dac899b75902223b40a5e29f1b0b004072ea2231c03c8b914'
    'specs\FASE5-R4.1-source-map.json'='cb92322e0b21d0a7e46ddcd972c57f713052d3714fd5569b3940a8a384895ba8'
}
foreach($rel in $expected.Keys){
    $actual=Get-Sha256 (Join-Path $TestsRoot $rel)
    Assert-Fase5R42 ($actual -eq $expected[$rel]) "baseline R4.1.1 congelada: $rel" "expected=$($expected[$rel]); actual=$actual"
}
$exp=$null
try{$exp=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Expansion-R4.2.json')}catch{}
Assert-Fase5R42 ($null -ne $exp -and @($exp.tweaks).Count -eq 13 -and [int]$exp.count -eq 13) 'Expansion-R4.2.json parseia e declara exatamente 13 tweaks'
$srcMap=$null
try{$srcMap=Get-Json (Join-Path $TestsRoot 'specs\FASE5-R4.2-source-map.json')}catch{}
Assert-Fase5R42 ($null -ne $srcMap -and @($srcMap.entries).Count -eq 13) 'source-map R4.2 contém 13 referências oficiais'
if($script:failures.Count -gt 0){Write-Host 'PRE-FLIGHT R4.2 FALHOU.' -ForegroundColor Red; exit 1}

Write-Host "`n=== TEST 01: 217 + 13 = 230 sem IDs/alvos Registry duplicados ==="
$base=Get-Json (Join-Path $TestsRoot 'catalog.json')
$tl=Get-Json (Join-Path $TestsRoot 'catalogs\Game-Workload.json')
$adv=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Advanced-Catalog.json')
$r4=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Expansion-R4.json')
$r41=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Expansion-R4.1.json')
$all=Get-AllValidatedTweaks
Assert-Fase5R42 (@($base.tweaks).Count -eq 177) 'base permanece em 177 entradas'
Assert-Fase5R42 (@($tl.tweaks).Count -eq 10) 'Game-Workload permanece em 10 entradas'
Assert-Fase5R42 (@($adv.tweaks).Count -eq 3) 'Advanced permanece em 3 entradas'
Assert-Fase5R42 (@($r4.tweaks).Count -eq 12) 'R4 permanece em 12 entradas'
Assert-Fase5R42 (@($r41.tweaks).Count -eq 15) 'R4.1 permanece em 15 entradas'
Assert-Fase5R42 (@($exp.tweaks).Count -eq 13) 'R4.2 adiciona exatamente 13 entradas'
Assert-Fase5R42 (@($all).Count -eq 230) 'backend validado chega a 230 entradas'
$dups=@($all|Group-Object id|Where-Object{$_.Count -gt 1})
Assert-Fase5R42 ($dups.Count -eq 0) 'nenhum ID duplicado em 230 entradas'
$priorTargets=@{}
foreach($t in @($base.tweaks)+@($tl.tweaks)+@($adv.tweaks)+@($r4.tweaks)+@($r41.tweaks)){
    foreach($op in @($t.registry)){
        if($null -ne $op){$priorTargets[(Get-RegistryTargetKey $op)]=[string]$t.id}
    }
}
$collisions=@()
foreach($t in @($exp.tweaks)){
    foreach($op in @($t.registry)){
        $k=Get-RegistryTargetKey $op
        if($priorTargets.ContainsKey($k)){$collisions += "$($t.id)<->$($priorTargets[$k])@$k"}
    }
}
Assert-Fase5R42 ($collisions.Count -eq 0) 'nenhum alvo Path/Name R4.2 duplica tweak anterior' $(if($collisions.Count){$collisions -join '; '}else{$null})
$issues=@((Test-WinSlimPlannerCatalog -CatalogTweaks $all)|Where-Object{$_.Severity -eq 'Error'})
Assert-Fase5R42 ($issues.Count -eq 0) 'Planner valida catálogo 230 sem referência estrutural ausente' $(if($issues.Count){($issues|ForEach-Object{"$($_.Code):$($_.TweakId)->$($_.Reference)"})-join '; '}else{$null})

Write-Host "`n=== TEST 02: três políticas Windows R4.2 exatas ==="
$expectedWin=@{
 'PRIV-019'=@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','AllowDeviceNameInDiagnosticData',0)
 'PRIV-020'=@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','AllowClipboardHistory',0)
 'SEARCH-001'=@('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search','DisableRemovableDriveIndexing',1)
}
foreach($id in $expectedWin.Keys){
 $t=@($exp.tweaks|Where-Object{$_.id -eq $id})[0]
 $op=@($t.registry)[0]
 $e=$expectedWin[$id]
 Assert-Fase5R42 ($t -and $op.Path -eq $e[0] -and $op.Name -eq $e[1] -and [int]$op.Value -eq [int]$e[2] -and $op.Type -eq 'DWord' -and [bool]$t.requiresAdmin) "$id registra política Windows exata"
}
Assert-Fase5R42 (@($exp.tweaks|Where-Object{$_.id -notlike 'EDGE-*'}).Count -eq 3) 'R4.2 contém exatamente 3 políticas Windows + 10 Edge'

Write-Host "`n=== TEST 03: dez políticas Microsoft Edge R4.2 exatas ==="
$expectedEdge=@{
 'EDGE-022'=@('NetworkPredictionOptions',2)
 'EDGE-023'=@('NewTabPagePrerenderEnabled',0)
 'EDGE-024'=@('AlternateErrorPagesEnabled',0)
 'EDGE-025'=@('SearchSuggestEnabled',0)
 'EDGE-026'=@('TextPredictionEnabled',0)
 'EDGE-027'=@('VisualSearchEnabled',0)
 'EDGE-028'=@('AutofillMembershipsEnabled',0)
 'EDGE-029'=@('MicrosoftEditorProofingEnabled',0)
 'EDGE-030'=@('PaymentMethodQueryEnabled',0)
 'EDGE-031'=@('DiagnosticData',1)
}
foreach($id in $expectedEdge.Keys){
 $t=@($exp.tweaks|Where-Object{$_.id -eq $id})[0]
 $op=@($t.registry)[0]
 $e=$expectedEdge[$id]
 Assert-Fase5R42 ($t -and $op.Path -eq 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -and $op.Name -eq $e[0] -and [int]$op.Value -eq [int]$e[1] -and $op.Type -eq 'DWord') "$id registra política Edge exata"
}
Assert-Fase5R42 (@($exp.tweaks|Where-Object{$_.id -like 'EDGE-*'}).Count -eq 10) 'R4.2 contém exatamente 10 políticas Edge'
$edge031 = @($exp.tweaks | Where-Object { $_.id -eq 'EDGE-031' })[0]
Assert-Fase5R42 ($null -ne $edge031 -and [int]$edge031.registry[0].Value -eq 1) 'EDGE-031 limita diagnóstico a RequiredData=1 em vez de Off=0'

Write-Host "`n=== TEST 04: curadoria, risco, rollback, presets e políticas não-obsoletas ==="
Assert-Fase5R42 (@($exp.tweaks|Where-Object{$_.type -ne 'registry'}).Count -eq 0) 'R4.2 usa apenas RegistryProvider conformado'
Assert-Fase5R42 (@($exp.tweaks|Where-Object{@($_.rollbackClass) -notcontains 'Registry'}).Count -eq 0) 'todos R4.2 declaram rollback Registry'
Assert-Fase5R42 (@($exp.tweaks|Where-Object{@($_.presets).Count -gt 0}).Count -eq 0) 'nenhum R4.2 entra em preset antes da Fase 6'
Assert-Fase5R42 (@($exp.tweaks|Where-Object{$_.uiAvailability -ne 'Phase7'}).Count -eq 0) 'todos R4.2 aguardam UI da Fase 7'
Assert-Fase5R42 (@($exp.tweaks|Where-Object{[string]$_.source -ne 'MS+WS'}).Count -eq 0) 'lote R4.2 marcado Microsoft docs + Win-Slim'
$mediumIds=@('PRIV-020','EDGE-028','EDGE-029')
$mediumBad=@($exp.tweaks|Where-Object{($mediumIds -contains [string]$_.id) -and $_.risk -ne 'Médio'})
Assert-Fase5R42 ($mediumBad.Count -eq 0) 'itens com perda funcional relevante ficam risco Médio'
$obsoleteNames=@('EdgeEnhanceImagesEnabled','EdgeCollectionsEnabled','WebWidgetAllowed','CryptoWalletEnabled','AutomaticHttpsDefault','NewTabPageSetFeedType')
$obsoleteUsed=@()
foreach($t in @($exp.tweaks)){foreach($op in @($t.registry)){if($obsoleteNames -contains [string]$op.Name){$obsoleteUsed += [string]$op.Name}}}
Assert-Fase5R42 ($obsoleteUsed.Count -eq 0) 'R4.2 exclui políticas Edge obsoletas/depreciadas conhecidas' $(if($obsoleteUsed.Count){$obsoleteUsed -join ','}else{$null})

Write-Host "`n=== TEST 05: Planner - admin, determinismo e aplicabilidade ==="
$ctx11=[PSCustomObject]@{OS='11';IsAdmin=$true;GPU=@('NVIDIA');RAM=16;Storage='SSD';NetworkAdapters=@('Ethernet');CPU='Synthetic'}
$ids=@($exp.tweaks|ForEach-Object{[string]$_.id})
$p1=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds $ids -Context $ctx11
$p2=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds $ids -Context $ctx11
Assert-Fase5R42 ($p1.CanExecute -and @($p1.ExecutionOrder).Count -eq 13 -and @($p1.BlockedTweaks).Count -eq 0 -and @($p1.SkippedTweaks).Count -eq 0) 'Planner executa os 13 R4.2 em Windows 11/admin'
Assert-Fase5R42 ($p1.Fingerprint -eq $p2.Fingerprint -and ((@($p1.ExecutionOrder|ForEach-Object{$_.TweakId})-join ',') -eq (@($p2.ExecutionOrder|ForEach-Object{$_.TweakId})-join ','))) 'Planner mantém fingerprint e ordem determinísticos no R4.2'
$ctxNoAdmin=[PSCustomObject]@{OS='11';IsAdmin=$false;GPU=@();RAM=8;Storage='SSD';NetworkAdapters=@();CPU='Synthetic'}
$pNoAdmin=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('PRIV-019','EDGE-022') -Context $ctxNoAdmin
Assert-Fase5R42 (@($pNoAdmin.BlockedTweaks|Where-Object{$_.TweakId -eq 'PRIV-019'}).Count -eq 1) 'Planner bloqueia política Windows HKLM sem elevação'
Assert-Fase5R42 (@($pNoAdmin.BlockedTweaks|Where-Object{$_.TweakId -eq 'EDGE-022'}).Count -eq 1) 'Planner bloqueia política Edge HKLM sem elevação'

Write-Host "`n=== TEST 06: RegistryProvider Apply/Undo exato dos 13 em HKCU temporário ==="
$testRoot='HKCU:\Software\WinSlimSuite\Tests\Fase5R42'
Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
$pass=$true
$details=@()
$i=0
foreach($t in @($exp.tweaks)){
 $i++
 $orig=@($t.registry)[0]
 $sid=([string]$t.id -replace '[^A-Za-z0-9_.-]','_')
 $path="$testRoot\$sid"
 $op=[PSCustomObject]@{Path=$path;Name=[string]$orig.Name;Value=$orig.Value;Type='DWord'}
 $seeded=($i%2 -eq 0)
 if($seeded){
   New-Item -Path $path -Force|Out-Null
   $seed=if([int]$op.Value -eq 0){7}else{0}
   New-ItemProperty -Path $path -Name $op.Name -Value $seed -PropertyType DWord -Force|Out-Null
 }
 $a=Invoke-RegistryProvider -Id ([string]$t.id) -RegistryOps @($op) -Action Apply
 $u=Invoke-RegistryProvider -Id ([string]$t.id) -RegistryOps @($op) -Action Undo -BackupData $a.StateBefore
 $after=Get-RegistryState -Path $path -Name $op.Name
 $ok=$a.Success -and $u.Success
 if($seeded){$ok=$ok -and $after.Exists -and [int]$after.Value -eq [int]$seed}else{$ok=$ok -and (-not $after.Exists)}
 if(-not $ok){$pass=$false;$details += "$($t.id): apply=$($a.Success) undo=$($u.Success) exists=$($after.Exists) value=$($after.Value)"}
}
Assert-Fase5R42 $pass 'RegistryProvider aplica/verifica/desfaz os 13 R4.2 em sandbox HKCU' $(if($details.Count){$details -join '; '}else{$null})
Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== TEST 07: Planner -> Transaction -> RegistryProvider rollback LIFO ==="
$txRoot='HKCU:\Software\WinSlimSuite\Tests\Fase5R42Tx'
Remove-Item -Path $txRoot -Recurse -Force -ErrorAction SilentlyContinue
$planTx=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('PRIV-019','EDGE-022') -Context $ctx11
$opsMap=@{
 'PRIV-019'=@([PSCustomObject]@{Path="$txRoot\PRIV-019";Name='AllowDeviceNameInDiagnosticData';Value=0;Type='DWord'})
 'EDGE-022'=@([PSCustomObject]@{Path="$txRoot\EDGE-022";Name='NetworkPredictionOptions';Value=2;Type='DWord'})
}
New-Item -Path "$txRoot\PRIV-019" -Force|Out-Null
New-ItemProperty -Path "$txRoot\PRIV-019" -Name 'AllowDeviceNameInDiagnosticData' -Value 7 -PropertyType DWord -Force|Out-Null
New-Item -Path "$txRoot\EDGE-022" -Force|Out-Null
New-ItemProperty -Path "$txRoot\EDGE-022" -Name 'NetworkPredictionOptions' -Value 9 -PropertyType DWord -Force|Out-Null
$txCtx=[PSCustomObject]@{RegistryOpsMap=$opsMap}
$backup={param($Tweak,$Level,$Context,$Step)$k=[string]$Tweak.id;$b=@();foreach($o in @($Context.RegistryOpsMap[$k])){$b+=(Backup-RegistryValue -Path $o.Path -Name $o.Name)};return @($b)}
$apply={
 param($Tweak,$Level,$Context)
 if([string]$Tweak.id -eq 'F5R42-FAIL'){
   return [PSCustomObject]@{Id='F5R42-FAIL';Action='Apply';Success=$false;Changed=$false;StateBefore=$null;StateAfter=$null;Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@([PSCustomObject]@{Pass=$false})};Restart='None';Warning=$null;Error='falha sintetica esperada'}
 }
 $k=[string]$Tweak.id
 Invoke-RegistryProvider -Id $k -RegistryOps @($Context.RegistryOpsMap[$k]) -Action Apply
}
$undo={param($Tweak,$Level,$Context,$BackupData,$Step)$k=[string]$Tweak.id;Invoke-RegistryProvider -Id $k -RegistryOps @($Context.RegistryOpsMap[$k]) -Action Undo -BackupData $BackupData}
$fail=[PSCustomObject]@{id='F5R42-FAIL';type='synthetic';name='falha sintetica';restartScope='None'}
$tx=Invoke-TransactionPlan -Items (@($planTx.ExecutionOrder)+@($fail)) -Context $txCtx -FailurePolicy RollbackTransaction -NoPersist -ApplyHandler $apply -BackupHandler $backup -UndoHandler $undo
$s1=Get-RegistryState -Path "$txRoot\PRIV-019" -Name 'AllowDeviceNameInDiagnosticData'
$s2=Get-RegistryState -Path "$txRoot\EDGE-022" -Name 'NetworkPredictionOptions'
$st1=@($tx.Steps|Where-Object{$_.TweakId -eq 'PRIV-019'}|Select-Object -Last 1)
$st2=@($tx.Steps|Where-Object{$_.TweakId -eq 'EDGE-022'}|Select-Object -Last 1)
Assert-Fase5R42 ($tx.Status -eq 'RolledBack' -and $tx.Failure -and [string]$tx.Failure.TweakId -eq 'F5R42-FAIL') 'falha posterior dispara rollback transacional do lote R4.2'
Assert-Fase5R42 ($s1.Exists -and [int]$s1.Value -eq 7 -and $s2.Exists -and [int]$s2.Value -eq 9) 'Transaction Manager restaura valores originais R4.2'
Assert-Fase5R42 ($st1.Count -eq 1 -and $st2.Count -eq 1 -and $st1[0].Changed -and $st2[0].Changed -and $st1[0].RollbackStatus -eq 'RolledBack' -and $st2[0].RollbackStatus -eq 'RolledBack') 'steps R4.2 ficam Changed=true + RolledBack em LIFO'
Remove-Item -Path $txRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== TEST 08: source-map/UI legada/backend 230 ==="
$mapped=@($srcMap.entries|ForEach-Object{[string]$_.id}|Sort-Object)
$declared=@($exp.tweaks|ForEach-Object{[string]$_.id}|Sort-Object)
Assert-Fase5R42 (($mapped -join ',') -eq ($declared -join ',')) 'source-map cobre exatamente todos os IDs R4.2'
$loader=Get-Content -LiteralPath (Join-Path $TestsRoot 'WinSlimSuite.dev.ps1') -Raw -Encoding UTF8
Assert-Fase5R42 (-not ($loader -match 'Get-ChildItem[^\r\n]+-Recurse')) 'loader legado de catalogs continua não-recursivo'
$top=@(Get-ChildItem -LiteralPath (Join-Path $TestsRoot 'catalogs') -File -Filter '*.json')
$legacy=@($base.tweaks).Count
foreach($f in $top){$legacy += @((Get-Json $f.FullName).tweaks).Count}
Assert-Fase5R42 ($legacy -eq 187) 'UI/autoload legado permanece em 187 entradas'
Assert-Fase5R42 (@($all).Count -eq 230) 'backend validado chega a 230 sem exposição prematura'

Write-Host "`n=== RESUMO FASE 5 R4.2.1 ==="
if($script:failures.Count -eq 0){
 Write-Host 'FASE 5 R4.2.1 APROVADA - expansão final validada: backend 230 entradas, rollback e Planner preservados.' -ForegroundColor Green
 Write-Host 'UI legada permanece em 187 entradas até a Fase 7.'
 Write-Host 'FASE 5 pronta para fechamento; próximo gate: FASE 6 - Presets.'
 exit 0
}
Write-Host "FASE 5 R4.2.1 REPROVADA - $($script:failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $script:failures){Write-Host " - $f" -ForegroundColor Red}
exit 1

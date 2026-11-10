$ErrorActionPreference = 'Stop'

$TestsRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $TestsRoot 'src\Core\ProviderContract.ps1')
. (Join-Path $TestsRoot 'src\Providers\RegistryProvider.ps1')
. (Join-Path $TestsRoot 'src\Core\Planner.ps1')
. (Join-Path $TestsRoot 'src\Core\Transaction.ps1')

$script:failures = @()
function Assert-Fase5R41 {
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
    foreach($f in @('catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json','catalogs\validated\Expansion-R4.json','catalogs\validated\Expansion-R4.1.json')){
        $d=Get-Json (Join-Path $TestsRoot $f); $out += @($d.tweaks)
    }
    return @($out)
}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 5 R4.1.1 / Curated Catalog Expansion II'
Write-Host '============================================================'
Write-Host 'R4.1.1: correção do harness QOL-015 + rollback transacional; catálogo R4.1 preservado em 217'

Write-Host "`n=== TEST 00: baseline R4 congelada + JSON/source-map novos válidos ==="
$expected=@{
    'src\Core\Transaction.ps1'='ecee3451af44cef809215d4a9045c2a81d7596e57062273e2860c00171f43619'
    'src\Core\Planner.ps1'='a27ab444744f3011d9ff7c539967c1d75bdcfdbf2a8a81ee2f03d56c48c81ce4'
    'src\Providers\RegistryProvider.ps1'='b01680f038d0eaa075680041ef76a48938bce412991d530fd8cabadf0186a90e'
    'catalog.json'='0e71c1fba2fb9fefba09d3b8b82007c5b972c30ae2d0c69734a30b93857cc1ba'
    'catalogs\Game-Workload.json'='19e5d57eb6ac7501ef5fc782445a44bc1bc5aaf6a59100ae45639aea7e25079d'
    'catalogs\validated\Advanced-Catalog.json'='48b03f6627c7ee9943e9c1094c93036f961fa30a6b9a61bff6b5e34f9b718389'
    'catalogs\validated\Expansion-R4.json'='303e411d4cafdd1f52eb1af126a6b5551adf77ae45c83eae3f1ecbbe0f1216ee'
    'tests\Test-Fase5-R4-CatalogExpansion.ps1'='29ce3333150e81b081909de8b6589f125f6a523468fc9e2f6753b4436483edad'
}
foreach($rel in $expected.Keys){
    $actual=Get-Sha256 (Join-Path $TestsRoot $rel)
    Assert-Fase5R41 ($actual -eq $expected[$rel]) "baseline R4 congelada: $rel" "expected=$($expected[$rel]); actual=$actual"
}
$exp=$null; try{$exp=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Expansion-R4.1.json')}catch{}
Assert-Fase5R41 ($null -ne $exp -and @($exp.tweaks).Count -eq 15 -and [int]$exp.count -eq 15) 'Expansion-R4.1.json parseia e declara exatamente 15 tweaks'
$srcMap=$null; try{$srcMap=Get-Json (Join-Path $TestsRoot 'specs\FASE5-R4.1-source-map.json')}catch{}
Assert-Fase5R41 ($null -ne $srcMap -and @($srcMap.entries).Count -eq 15) 'source-map R4.1 contém 15 referências oficiais'
if($script:failures.Count -gt 0){Write-Host 'PRE-FLIGHT R4.1 FALHOU.' -ForegroundColor Red; exit 1}

Write-Host "`n=== TEST 01: 202 + 15 = 217 sem IDs/alvos Registry duplicados ==="
$base=Get-Json (Join-Path $TestsRoot 'catalog.json')
$tl=Get-Json (Join-Path $TestsRoot 'catalogs\Game-Workload.json')
$adv=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Advanced-Catalog.json')
$r4=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Expansion-R4.json')
$all=Get-AllValidatedTweaks
Assert-Fase5R41 (@($base.tweaks).Count -eq 177) 'base permanece em 177 entradas'
Assert-Fase5R41 (@($tl.tweaks).Count -eq 10) 'Game-Workload permanece em 10 entradas'
Assert-Fase5R41 (@($adv.tweaks).Count -eq 3) 'Advanced permanece em 3 entradas'
Assert-Fase5R41 (@($r4.tweaks).Count -eq 12) 'R4 permanece em 12 entradas'
Assert-Fase5R41 (@($exp.tweaks).Count -eq 15) 'R4.1 adiciona exatamente 15 entradas'
Assert-Fase5R41 (@($all).Count -eq 217) 'backend validado chega a 217 entradas'
$dups=@($all|Group-Object id|Where-Object{$_.Count -gt 1})
Assert-Fase5R41 ($dups.Count -eq 0) 'nenhum ID duplicado em 217 entradas'
$priorTargets=@{}
foreach($t in @($base.tweaks)+@($tl.tweaks)+@($adv.tweaks)+@($r4.tweaks)){foreach($op in @($t.registry)){if($null -ne $op){$priorTargets[(Get-RegistryTargetKey $op)]=[string]$t.id}}}
$collisions=@()
foreach($t in @($exp.tweaks)){foreach($op in @($t.registry)){$k=Get-RegistryTargetKey $op;if($priorTargets.ContainsKey($k)){$collisions += "$($t.id)<->$($priorTargets[$k])@$k"}}}
Assert-Fase5R41 ($collisions.Count -eq 0) 'nenhum alvo Path/Name R4.1 duplica tweak anterior' $(if($collisions.Count){$collisions -join '; '}else{$null})
$issues=@((Test-WinSlimPlannerCatalog -CatalogTweaks $all)|Where-Object{$_.Severity -eq 'Error'})
Assert-Fase5R41 ($issues.Count -eq 0) 'Planner valida catálogo 217 sem referência estrutural ausente' $(if($issues.Count){($issues|ForEach-Object{"$($_.Code):$($_.TweakId)->$($_.Reference)"})-join '; '}else{$null})

Write-Host "`n=== TEST 02: política Windows/Explorer R4.1 exata ==="
$expectedWin=@{
 'QOL-015'=@('HKCU:\Software\Policies\Microsoft\Windows\Explorer','NoSearchInternetTryHarderButton',1,$false)
}
foreach($id in $expectedWin.Keys){
 $t=@($exp.tweaks|Where-Object{$_.id -eq $id})[0];$op=@($t.registry)[0];$e=$expectedWin[$id]
 Assert-Fase5R41 ($t -and $op.Path -eq $e[0] -and $op.Name -eq $e[1] -and [int]$op.Value -eq [int]$e[2] -and $op.Type -eq 'DWord' -and [bool]$t.requiresAdmin -eq [bool]$e[3]) "$id registra política Windows/Explorer exata"
}
Assert-Fase5R41 (@($exp.tweaks|Where-Object{$_.id -like 'EDGE-*'}).Count -eq 14) 'R4.1 contém exatamente 1 política Windows/Explorer + 14 políticas Edge'

Write-Host "`n=== TEST 03: quatorze políticas Microsoft Edge R4.1 exatas ==="
$expectedEdge=@{
 'EDGE-008'=@('HideFirstRunExperience',1)
 'EDGE-009'=@('SyncDisabled',1)
 'EDGE-010'=@('BrowserSignin',0)
 'EDGE-011'=@('SearchInSidebarEnabled',2)
 'EDGE-012'=@('ShowRecommendationsEnabled',0)
 'EDGE-013'=@('ShowMicrosoftRewards',0)
 'EDGE-014'=@('AutofillAddressEnabled',0)
 'EDGE-015'=@('AutofillCreditCardEnabled',0)
 'EDGE-016'=@('NewTabPageQuickLinksEnabled',0)
 'EDGE-017'=@('WebToBrowserSignInEnabled',0)
 'EDGE-018'=@('UrlDiagnosticDataEnabled',0)
 'EDGE-019'=@('UserFeedbackAllowed',0)
 'EDGE-020'=@('MicrosoftEdgeInsiderPromotionEnabled',0)
 'EDGE-021'=@('Microsoft365CopilotChatIconEnabled',0)
}
foreach($id in $expectedEdge.Keys){
 $t=@($exp.tweaks|Where-Object{$_.id -eq $id})[0];$op=@($t.registry)[0];$e=$expectedEdge[$id]
 Assert-Fase5R41 ($t -and $op.Path -eq 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -and $op.Name -eq $e[0] -and [int]$op.Value -eq [int]$e[1] -and $op.Type -eq 'DWord') "$id registra política Edge exata"
}
Assert-Fase5R41 (@($exp.tweaks|Where-Object{$_.id -in @('EDGE-009','EDGE-010','EDGE-014','EDGE-015') -and $_.risk -ne 'Médio'}).Count -eq 0) 'itens Edge com impacto funcional maior ficam risco Médio'

Write-Host "`n=== TEST 04: curadoria/rollback/presets/UI ==="
Assert-Fase5R41 (@($exp.tweaks|Where-Object{$_.type -ne 'registry'}).Count -eq 0) 'R4.1 usa apenas RegistryProvider conformado'
Assert-Fase5R41 (@($exp.tweaks|Where-Object{@($_.rollbackClass) -notcontains 'Registry'}).Count -eq 0) 'todos R4.1 declaram rollback Registry'
Assert-Fase5R41 (@($exp.tweaks|Where-Object{@($_.presets).Count -gt 0}).Count -eq 0) 'nenhum R4.1 entra em preset antes da Fase 6'
Assert-Fase5R41 (@($exp.tweaks|Where-Object{$_.uiAvailability -ne 'Phase7'}).Count -eq 0) 'todos R4.1 aguardam UI da Fase 7'
Assert-Fase5R41 (@($exp.tweaks|Where-Object{[string]$_.source -ne 'MS+WS'}).Count -eq 0) 'lote R4.1 marcado Microsoft docs + Win-Slim'

Write-Host "`n=== TEST 05: Planner - aplicabilidade/admin/determinismo ==="
$ctx11=[PSCustomObject]@{OS='11';IsAdmin=$true;GPU=@('NVIDIA');RAM=16;Storage='SSD';NetworkAdapters=@('Ethernet');CPU='Synthetic'}
$ids=@($exp.tweaks|ForEach-Object{[string]$_.id})
$p1=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds $ids -Context $ctx11
$p2=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds $ids -Context $ctx11
Assert-Fase5R41 ($p1.CanExecute -and @($p1.ExecutionOrder).Count -eq 15 -and @($p1.BlockedTweaks).Count -eq 0 -and @($p1.SkippedTweaks).Count -eq 0) 'Planner executa os 15 R4.1 em Windows 11/admin'
Assert-Fase5R41 ($p1.Fingerprint -eq $p2.Fingerprint -and ((@($p1.ExecutionOrder|ForEach-Object{$_.TweakId})-join ',') -eq (@($p2.ExecutionOrder|ForEach-Object{$_.TweakId})-join ','))) 'Planner mantém fingerprint e ordem determinísticos no R4.1'
$ctxNoAdmin=[PSCustomObject]@{OS='11';IsAdmin=$false;GPU=@();RAM=8;Storage='SSD';NetworkAdapters=@();CPU='Synthetic'}
$pNoAdmin=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('EDGE-008','QOL-015') -Context $ctxNoAdmin
Assert-Fase5R41 (@($pNoAdmin.BlockedTweaks|Where-Object{$_.TweakId -eq 'EDGE-008'}).Count -eq 1) 'Planner bloqueia política HKLM Edge sem elevação'
Assert-Fase5R41 (@($pNoAdmin.ExecutionOrder|Where-Object{$_.TweakId -eq 'QOL-015'}).Count -eq 1) 'Planner mantém QOL-015 HKCU executável sem admin'

Write-Host "`n=== TEST 06: RegistryProvider Apply/Undo exato dos 15 em HKCU temporário ==="
$testRoot='HKCU:\Software\WinSlimSuite\Tests\Fase5R41'
Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue
$pass=$true;$details=@();$i=0
foreach($t in @($exp.tweaks)){
 $i++;$orig=@($t.registry)[0];$sid=([string]$t.id -replace '[^A-Za-z0-9_.-]','_');$path="$testRoot\$sid"
 $op=[PSCustomObject]@{Path=$path;Name=[string]$orig.Name;Value=$orig.Value;Type='DWord'};$seeded=($i%2 -eq 0)
 if($seeded){New-Item -Path $path -Force|Out-Null;$seed=if([int]$op.Value -eq 0){1}else{0};New-ItemProperty -Path $path -Name $op.Name -Value $seed -PropertyType DWord -Force|Out-Null}
 $a=Invoke-RegistryProvider -Id ([string]$t.id) -RegistryOps @($op) -Action Apply
 $u=Invoke-RegistryProvider -Id ([string]$t.id) -RegistryOps @($op) -Action Undo -BackupData $a.StateBefore
 $after=Get-RegistryState -Path $path -Name $op.Name;$ok=$a.Success -and $u.Success
 if($seeded){$ok=$ok -and $after.Exists -and [int]$after.Value -eq [int]$seed}else{$ok=$ok -and (-not $after.Exists)}
 if(-not $ok){$pass=$false;$details += "$($t.id): apply=$($a.Success) undo=$($u.Success) exists=$($after.Exists) value=$($after.Value)"}
}
Assert-Fase5R41 $pass 'RegistryProvider aplica/verifica/desfaz os 15 R4.1 em sandbox HKCU' $(if($details.Count){$details -join '; '}else{$null})
Remove-Item -Path $testRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== TEST 07: Planner -> Transaction -> RegistryProvider rollback LIFO ==="
$txRoot='HKCU:\Software\WinSlimSuite\Tests\Fase5R41Tx';Remove-Item -Path $txRoot -Recurse -Force -ErrorAction SilentlyContinue
$planTx=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('QOL-015','EDGE-008') -Context $ctx11
$opsMap=@{
 'QOL-015'=@([PSCustomObject]@{Path="$txRoot\QOL-015";Name='NoSearchInternetTryHarderButton';Value=1;Type='DWord'})
 'EDGE-008'=@([PSCustomObject]@{Path="$txRoot\EDGE-008";Name='HideFirstRunExperience';Value=1;Type='DWord'})
}
New-Item -Path "$txRoot\QOL-015" -Force|Out-Null;New-ItemProperty -Path "$txRoot\QOL-015" -Name 'NoSearchInternetTryHarderButton' -Value 7 -PropertyType DWord -Force|Out-Null
New-Item -Path "$txRoot\EDGE-008" -Force|Out-Null;New-ItemProperty -Path "$txRoot\EDGE-008" -Name 'HideFirstRunExperience' -Value 9 -PropertyType DWord -Force|Out-Null
$txCtx=[PSCustomObject]@{RegistryOpsMap=$opsMap}
$backup={param($Tweak,$Level,$Context,$Step)$k=[string]$Tweak.id;$b=@();foreach($o in @($Context.RegistryOpsMap[$k])){$b+=(Backup-RegistryValue -Path $o.Path -Name $o.Name)};return @($b)}
$apply={param($Tweak,$Level,$Context)if([string]$Tweak.id -eq 'F5R41-FAIL'){return [PSCustomObject]@{Id='F5R41-FAIL';Action='Apply';Success=$false;Changed=$false;StateBefore=$null;StateAfter=$null;Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@([PSCustomObject]@{Pass=$false})};Restart='None';Warning=$null;Error='falha sintetica esperada'}};$k=[string]$Tweak.id;Invoke-RegistryProvider -Id $k -RegistryOps @($Context.RegistryOpsMap[$k]) -Action Apply}
$undo={param($Tweak,$Level,$Context,$BackupData,$Step)$k=[string]$Tweak.id;Invoke-RegistryProvider -Id $k -RegistryOps @($Context.RegistryOpsMap[$k]) -Action Undo -BackupData $BackupData}
$fail=[PSCustomObject]@{id='F5R41-FAIL';type='synthetic';name='falha sintetica';restartScope='None'}
$tx=Invoke-TransactionPlan -Items (@($planTx.ExecutionOrder)+@($fail)) -Context $txCtx -FailurePolicy RollbackTransaction -NoPersist -ApplyHandler $apply -BackupHandler $backup -UndoHandler $undo
$s1=Get-RegistryState -Path "$txRoot\QOL-015" -Name 'NoSearchInternetTryHarderButton';$s2=Get-RegistryState -Path "$txRoot\EDGE-008" -Name 'HideFirstRunExperience'
$st1=@($tx.Steps|Where-Object{$_.TweakId -eq 'QOL-015'}|Select-Object -Last 1);$st2=@($tx.Steps|Where-Object{$_.TweakId -eq 'EDGE-008'}|Select-Object -Last 1)
Assert-Fase5R41 ($tx.Status -eq 'RolledBack' -and $tx.Failure -and [string]$tx.Failure.TweakId -eq 'F5R41-FAIL') 'falha posterior dispara rollback transacional do lote R4.1'
Assert-Fase5R41 ($s1.Exists -and [int]$s1.Value -eq 7 -and $s2.Exists -and [int]$s2.Value -eq 9) 'Transaction Manager restaura valores originais R4.1'
Assert-Fase5R41 ($st1.Count -eq 1 -and $st2.Count -eq 1 -and $st1[0].Changed -and $st2[0].Changed -and $st1[0].RollbackStatus -eq 'RolledBack' -and $st2[0].RollbackStatus -eq 'RolledBack') 'steps R4.1 ficam Changed=true + RolledBack em LIFO'
Remove-Item -Path $txRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== TEST 08: source-map/UI legada/backend 217 ==="
$mapped=@($srcMap.entries|ForEach-Object{[string]$_.id}|Sort-Object);$declared=@($exp.tweaks|ForEach-Object{[string]$_.id}|Sort-Object)
Assert-Fase5R41 (($mapped -join ',') -eq ($declared -join ',')) 'source-map cobre exatamente todos os IDs R4.1'
$loader=Get-Content -LiteralPath (Join-Path $TestsRoot 'WinSlimSuite.dev.ps1') -Raw -Encoding UTF8
Assert-Fase5R41 (-not ($loader -match 'Get-ChildItem[^
]+-Recurse')) 'loader legado de catalogs continua não-recursivo'
$top=@(Get-ChildItem -LiteralPath (Join-Path $TestsRoot 'catalogs') -File -Filter '*.json');$legacy=@($base.tweaks).Count
foreach($f in $top){$legacy += @((Get-Json $f.FullName).tweaks).Count}
Assert-Fase5R41 ($legacy -eq 187) 'UI/autoload legado permanece em 187 entradas'
Assert-Fase5R41 (@($all).Count -eq 217) 'backend validado chega a 217 sem exposição prematura'

Write-Host "`n=== RESUMO FASE 5 R4.1.1 ==="
if($script:failures.Count -eq 0){
 Write-Host 'FASE 5 R4.1.1 APROVADA - segunda expansão curada validada: backend 217 entradas, rollback e Planner preservados.' -ForegroundColor Green
 Write-Host 'UI legada permanece em 187 entradas até a Fase 7.'
 Write-Host 'Proximo subgate: FASE 5 R4.2 - expansão final da Fase 5 rumo a 225-235 entradas.'
 exit 0
}
Write-Host "FASE 5 R4.1.1 REPROVADA - $($script:failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $script:failures){Write-Host " - $f" -ForegroundColor Red}
exit 1

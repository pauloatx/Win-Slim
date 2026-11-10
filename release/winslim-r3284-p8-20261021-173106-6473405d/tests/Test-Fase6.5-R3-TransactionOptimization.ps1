#requires -Version 5.1
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$OutputEncoding=[Console]::OutputEncoding

$Root=Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'src\Core\Transaction.ps1')
. (Join-Path $Root 'src\Core\TransactionOptimized.ps1')

$Failures=New-Object System.Collections.ArrayList
$Warnings=New-Object System.Collections.ArrayList
function Ok65R3([string]$m){ Write-Host "  [OK] $m" -ForegroundColor Green }
function Fail65R3([string]$m){ Write-Host "  [FAIL] $m" -ForegroundColor Red;[void]$Failures.Add($m) }
function Warn65R3([string]$m){ Write-Host "  [WARN] $m" -ForegroundColor Yellow;[void]$Warnings.Add($m) }
function Assert65R3([bool]$Condition,[string]$Message){ if($Condition){Ok65R3 $Message}else{Fail65R3 $Message} }
function Measure65R3([scriptblock]$Action){ $sw=[Diagnostics.Stopwatch]::StartNew();& $Action;$sw.Stop();return [Math]::Round($sw.Elapsed.TotalMilliseconds,3) }
function Speedup65R3([double]$Legacy,[double]$Fast){ if($Fast -le 0){return 0};return [Math]::Round($Legacy/$Fast,2) }

function Get-AllTweaks65R3 {
    $out=New-Object System.Collections.ArrayList
    foreach($f in @('catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json','catalogs\validated\Expansion-R4.json','catalogs\validated\Expansion-R4.1.json','catalogs\validated\Expansion-R4.2.json')){
        $j=Get-Content -LiteralPath (Join-Path $Root $f) -Raw -Encoding UTF8 | ConvertFrom-Json
        $items=if($j.PSObject.Properties.Name -contains 'tweaks'){@($j.tweaks)}else{@($j)}
        foreach($x in $items){[void]$out.Add($x)}
    }
    return @($out.ToArray())
}

function New-Tweak65R3 {
    param([string]$Id,[string]$Value,[switch]$FailApply,[switch]$FailVerify,[switch]$FailUndo,[string]$Restart='None')
    [PSCustomObject]@{id=$Id;Value=$Value;FailApply=[bool]$FailApply;FailVerify=[bool]$FailVerify;FailUndo=[bool]$FailUndo;restartScope=$Restart}
}
function New-Context65R3 {
    param([hashtable]$Initial=@{})
    $state=@{}
    foreach($k in @($Initial.Keys)){$state[[string]$k]=$Initial[$k]}
    [PSCustomObject]@{State=$state;UndoOrder=(New-Object System.Collections.ArrayList)}
}
$BackupHandler65R3={
    param($Tweak,$Level,$Context,$Step)
    $exists=$Context.State.ContainsKey([string]$Tweak.id)
    [PSCustomObject]@{Exists=[bool]$exists;Value=$(if($exists){$Context.State[[string]$Tweak.id]}else{$null})}
}
$ApplyHandler65R3={
    param($Tweak,$Level,$Context)
    $id=[string]$Tweak.id
    $exists=$Context.State.ContainsKey($id)
    $before=[PSCustomObject]@{Exists=[bool]$exists;Value=$(if($exists){$Context.State[$id]}else{$null})}
    if([bool]$Tweak.FailApply){
        return [PSCustomObject]@{Id=$id;Success=$false;Changed=$false;StateBefore=$before;StateAfter=$before;Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@()};Restart='None';Warning=$null;Error='Apply injetado'}
    }
    $changed=(-not $exists)-or([string]$Context.State[$id] -ne [string]$Tweak.Value)
    if($changed){$Context.State[$id]=[string]$Tweak.Value}
    $actual=$(if($Context.State.ContainsKey($id)){$Context.State[$id]}else{$null})
    $pass=([string]$actual -eq [string]$Tweak.Value)-and(-not [bool]$Tweak.FailVerify)
    [PSCustomObject]@{Id=$id;Success=$true;Changed=[bool]$changed;StateBefore=$before;StateAfter=[PSCustomObject]@{Exists=$true;Value=$actual};Verification=[PSCustomObject]@{Applicable=$true;Success=[bool]$pass;Checks=@([PSCustomObject]@{Target=$id;Expected=$Tweak.Value;Actual=$actual;Pass=[bool]$pass})};Restart=[string]$Tweak.restartScope;Warning=$(if($pass){$null}else{'Verify injetado'});Error=$null}
}
$UndoHandler65R3={
    param($Tweak,$Level,$Context,$BackupData,$Step)
    [void]$Context.UndoOrder.Add([string]$Step.TweakId)
    if([bool]$Tweak.FailUndo){return [PSCustomObject]@{Id=$Tweak.id;Success=$false;Changed=$false;Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@()};Restart='None';Warning=$null;Error='Undo injetado'}}
    if([bool]$BackupData.Exists){$Context.State[[string]$Tweak.id]=$BackupData.Value}else{[void]$Context.State.Remove([string]$Tweak.id)}
    $exists=$Context.State.ContainsKey([string]$Tweak.id)
    $pass=$(if([bool]$BackupData.Exists){$exists -and [string]$Context.State[[string]$Tweak.id] -eq [string]$BackupData.Value}else{-not $exists})
    [PSCustomObject]@{Id=$Tweak.id;Success=[bool]$pass;Changed=$true;Verification=[PSCustomObject]@{Applicable=$true;Success=[bool]$pass;Checks=@()};Restart='None';Warning=$null;Error=$(if($pass){$null}else{'Undo divergente'})}
}
function New-Items65R3 { param($Tweaks) $a=New-Object System.Collections.ArrayList;foreach($t in @($Tweaks)){[void]$a.Add([PSCustomObject]@{Tweak=$t;Level=-1})};return @($a.ToArray()) }
function TxSignature65R3($Tx){
    $steps=@($Tx.Steps | ForEach-Object{"$($_.Sequence):$($_.TweakId):$($_.Status):$($_.Changed):$($_.RollbackStatus):$($_.Restart)"}) -join '|'
    $history=@($Tx.StatusHistory | ForEach-Object{[string]$_.Status}) -join ','
    "$($Tx.Status);$($Tx.Recovery.Required);$($Tx.RestartRequired);$(@($Tx.RestartScopes)-join ',');$history;$steps"
}
function StateSignature65R3($Context){
    (@($Context.State.Keys|Sort-Object|ForEach-Object{"$_=$($Context.State[$_])"}) -join ';')
}
function Run-Case65R3 {
    param([string]$Engine,$Items,[hashtable]$Initial=@{},[string]$FailurePolicy='RollbackTransaction')
    $ctx=New-Context65R3 -Initial $Initial
    if($Engine -eq 'Legacy'){
        $tx=Invoke-TransactionPlan -Items $Items -Context $ctx -FailurePolicy $FailurePolicy -ApplyHandler $ApplyHandler65R3 -BackupHandler $BackupHandler65R3 -UndoHandler $UndoHandler65R3 -NoPersist
    }else{
        $tx=Invoke-WinSlimTransactionPlanOptimized -Items $Items -Context $ctx -FailurePolicy $FailurePolicy -ApplyHandler $ApplyHandler65R3 -BackupHandler $BackupHandler65R3 -UndoHandler $UndoHandler65R3 -NoPersist
    }
    [PSCustomObject]@{Tx=$tx;Context=$ctx;TxSig=(TxSignature65R3 $tx);StateSig=(StateSignature65R3 $ctx);Undo=(@($ctx.UndoOrder)-join ',')}
}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 6.5 R3 / Transaction Optimization'
Write-Host '============================================================'
Write-Host 'R3: shadow Transaction otimizado + journaling deduplicado + rollback/recovery equivalentes'

$baseline=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R3-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$benchSpec=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R3-benchmark.json') -Raw -Encoding UTF8 | ConvertFrom-Json

Write-Host "`n=== TEST 00: baseline Fase 6.5 R2.1 congelada ===" -ForegroundColor Yellow
foreach($p in $baseline.files.PSObject.Properties){
    $path=Join-Path $Root ([string]$p.Name)
    $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
    Assert65R3 $ok "baseline R2.1 congelada: $($p.Name)"
}
$AllTweaks=@(Get-AllTweaks65R3)
Assert65R3 ($AllTweaks.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert65R3 ((@($AllTweaks.id|Select-Object -Unique).Count) -eq 230) '230 IDs permanecem únicos'

Write-Host "`n=== TEST 01: TransactionOptimized PS5.1-safe + hot paths limpos ===" -ForegroundColor Yellow
$optPath=Join-Path $Root 'src\Core\TransactionOptimized.ps1'
$raw=Get-Content -LiteralPath $optPath -Raw -Encoding UTF8
$mutators=@('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Set-Service','Stop-Service','Start-Service','bcdedit','powercfg','Register-ScheduledTask','Disable-NetAdapter','Enable-NetAdapter')
$hasMutator=$false;foreach($m in $mutators){if($raw -match [regex]::Escape($m)){$hasMutator=$true;break}}
Assert65R3 (-not $hasMutator) 'TransactionOptimized não contém primitivas de mutação do Windows'
Assert65R3 ($raw -notmatch 'Generic\.List\[object\]') 'TransactionOptimized evita Generic.List[object] no PowerShell 5.1'
Assert65R3 ($raw -match 'FirstBackupByTweakId') 'primeiro backup usa índice O(1) por TweakId'
Assert65R3 ($raw -match 'JsonWriteCountByName') 'journaling mantém telemetria de writes por sidecar'
Assert65R3 ($raw -match 'System\.Collections\.ArrayList') 'Steps/StatusHistory usam ArrayList nos hot paths'
Assert65R3 ($raw -match 'Get-WinSlimRollbackCandidatesOptimized') 'rollback possui caminho reverso sem Sort-Object no caso canônico'

Write-Host "`n=== TEST 02: equivalência transacional NoPersist em cenários R13 ===" -ForegroundColor Yellow
$cases=New-Object System.Collections.ArrayList
[void]$cases.Add([PSCustomObject]@{Name='commit';Items=(New-Items65R3 @((New-Tweak65R3 A 1),(New-Tweak65R3 B 2),(New-Tweak65R3 C 3)));Initial=@{};Expected='Committed'})
[void]$cases.Add([PSCustomObject]@{Name='apply fail + LIFO';Items=(New-Items65R3 @((New-Tweak65R3 L1 N1),(New-Tweak65R3 L2 N2),(New-Tweak65R3 L3 N3 -FailApply)));Initial=@{L1='O1';L2='O2'};Expected='RolledBack'})
[void]$cases.Add([PSCustomObject]@{Name='verify fail + rollback';Items=(New-Items65R3 @((New-Tweak65R3 V1 N1),(New-Tweak65R3 V2 N2 -FailVerify)));Initial=@{V1='O1';V2='O2'};Expected='RolledBack'})
[void]$cases.Add([PSCustomObject]@{Name='partial undo';Items=(New-Items65R3 @((New-Tweak65R3 U1 N1 -FailUndo),(New-Tweak65R3 U2 N2),(New-Tweak65R3 U3 N3 -FailApply)));Initial=@{U1='O1';U2='O2'};Expected='PartiallyRolledBack'})
[void]$cases.Add([PSCustomObject]@{Name='idempotent';Items=(New-Items65R3 @((New-Tweak65R3 I1 SAME)));Initial=@{I1='SAME'};Expected='Committed'})
foreach($case in @($cases.ToArray())){
    $legacy=Run-Case65R3 -Engine Legacy -Items $case.Items -Initial $case.Initial
    $fast=Run-Case65R3 -Engine Fast -Items $case.Items -Initial $case.Initial
    Assert65R3 ($legacy.Tx.Status -eq $case.Expected -and $fast.Tx.Status -eq $case.Expected) "$($case.Name): status esperado em ambos"
    Assert65R3 ($legacy.TxSig -eq $fast.TxSig) "$($case.Name): status/steps/rollback equivalentes"
    Assert65R3 ($legacy.StateSig -eq $fast.StateSig) "$($case.Name): estado final equivalente"
    Assert65R3 ($legacy.Undo -eq $fast.Undo) "$($case.Name): ordem de Undo equivalente"
}

Write-Host "`n=== TEST 03: primeiro backup imutável + restart set indexado ===" -ForegroundColor Yellow
$immItems=New-Items65R3 @((New-Tweak65R3 IMM FIRST),(New-Tweak65R3 IMM SECOND),(New-Tweak65R3 FAIL X -FailApply))
$legacyImm=Run-Case65R3 -Engine Legacy -Items $immItems -Initial @{IMM='ORIGINAL'}
$fastImm=Run-Case65R3 -Engine Fast -Items $immItems -Initial @{IMM='ORIGINAL'}
$li=@($legacyImm.Tx.Steps|Where-Object{$_.TweakId -eq 'IMM'}|Sort-Object Sequence)
$fi=@($fastImm.Tx.Steps|Where-Object{$_.TweakId -eq 'IMM'}|Sort-Object Sequence)
Assert65R3 ($li.Count -eq 2 -and $fi.Count -eq 2 -and $li[0].BackupData.Value -eq 'ORIGINAL' -and $li[1].BackupData.Value -eq 'ORIGINAL' -and $fi[0].BackupData.Value -eq 'ORIGINAL' -and $fi[1].BackupData.Value -eq 'ORIGINAL') 'primeiro backup permanece imutável para TweakId repetido'
Assert65R3 ($fastImm.StateSig -match 'IMM=ORIGINAL') 'rollback otimizado retorna ao estado pré-transação'
$restartItems=New-Items65R3 @((New-Tweak65R3 RST1 A -Restart 'Explorer'),(New-Tweak65R3 RST2 B -Restart 'Explorer'),(New-Tweak65R3 RST3 C -Restart 'Reboot'))
$legacyRestart=Run-Case65R3 -Engine Legacy -Items $restartItems
$fastRestart=Run-Case65R3 -Engine Fast -Items $restartItems
Assert65R3 ((@($legacyRestart.Tx.RestartScopes)-join ',') -eq (@($fastRestart.Tx.RestartScopes)-join ',')) 'RestartScopes preserva ordem/deduplicação canônica'
Assert65R3 ($fastRestart.Tx.RestartRequired) 'restart otimizado sinaliza RestartRequired'

Write-Host "`n=== TEST 04: persistência compacta + compatibilidade de import ===" -ForegroundColor Yellow
$runId=Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$sandbox=Join-Path $Root ("tests\_fase65r3-$runId")
$txRoot=Join-Path $sandbox 'Transactions';$backupRoot=Join-Path $sandbox 'Backups'
New-Item -ItemType Directory -Path $txRoot,$backupRoot -Force | Out-Null
$ctxPersist=New-Context65R3
$pItems=New-Items65R3 @((New-Tweak65R3 P1 A),(New-Tweak65R3 P2 B),(New-Tweak65R3 P3 C))
$ptx=Invoke-WinSlimTransactionPlanOptimized -Items $pItems -Context $ctxPersist -RootPath $txRoot -BackupRootPath $backupRoot -ApplyHandler $ApplyHandler65R3 -BackupHandler $BackupHandler65R3 -UndoHandler $UndoHandler65R3
Assert65R3 ($ptx.Status -eq 'Committed') 'transação persistida otimizada conclui Commit'
foreach($name in @('transaction.json','plan.json','operations.json','rollback.json','result.json','state-before.json','state-after.json')){Assert65R3 (Test-Path -LiteralPath (Join-Path $ptx.TransactionPath $name)) "artefato persistido: $name"}
$opsRaw=(Get-Content -LiteralPath (Join-Path $ptx.TransactionPath 'operations.json') -Raw -Encoding UTF8).Trim([char]0xFEFF).Trim()
Assert65R3 ($opsRaw.StartsWith('[')) 'operations.json permanece array JSON top-level real'
$canonicalImport=Import-WinSlimTransaction -Path $ptx.TransactionPath
Assert65R3 ($canonicalImport.Status -eq 'Committed' -and @($canonicalImport.Steps).Count -eq 3) 'Transaction R13 canônico importa journal produzido pelo otimizado'
$rtp=Get-WinSlimTransactionRuntime65R3 -Transaction $ptx
Assert65R3 ([int]$rtp.JsonWriteCountByName['plan.json'] -eq 1) 'plan.json imutável é gravado exatamente uma vez no caminho otimizado'
Assert65R3 ([int]$rtp.JsonSkips -gt 0) 'journaling deduplica sidecars JSON sem mudança'

Write-Host "`n=== TEST 05: recovery cross-process do journal otimizado ===" -ForegroundColor Yellow
$stateRoot=Join-Path $sandbox 'State';New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
$r1=Join-Path $stateRoot 'r1.txt';$r2=Join-Path $stateRoot 'r2.txt';[IO.File]::WriteAllText($r1,'ORIGINAL')
$fileBackup={param($Tweak,$Level,$Context,$Step)$exists=Test-Path -LiteralPath $Tweak.Path;[PSCustomObject]@{Path=$Tweak.Path;Exists=$exists;Content=$(if($exists){Get-Content -LiteralPath $Tweak.Path -Raw -Encoding UTF8}else{$null})}}
$fileApply={param($Tweak,$Level,$Context)$exists=Test-Path -LiteralPath $Tweak.Path;$before=[PSCustomObject]@{Path=$Tweak.Path;Exists=$exists;Content=$(if($exists){Get-Content -LiteralPath $Tweak.Path -Raw -Encoding UTF8}else{$null})};if($Tweak.FailApply){return [PSCustomObject]@{Success=$false;Changed=$false;StateBefore=$before;StateAfter=$before;Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@()};Restart='None';Warning=$null;Error='fail'}};[IO.File]::WriteAllText($Tweak.Path,[string]$Tweak.Value);[PSCustomObject]@{Success=$true;Changed=$true;StateBefore=$before;StateAfter=[PSCustomObject]@{Path=$Tweak.Path;Exists=$true;Content=$Tweak.Value};Verification=[PSCustomObject]@{Applicable=$true;Success=$true;Checks=@()};Restart='None';Warning=$null;Error=$null}}
$fileUndo={param($Tweak,$Level,$Context,$BackupData,$Step)if($BackupData.Exists){[IO.File]::WriteAllText([string]$BackupData.Path,[string]$BackupData.Content)}else{Remove-Item -LiteralPath ([string]$BackupData.Path) -Force -ErrorAction SilentlyContinue};[PSCustomObject]@{Success=$true;Changed=$true;Verification=[PSCustomObject]@{Applicable=$true;Success=$true;Checks=@()};Restart='None';Warning=$null;Error=$null}}
$rItems=@([PSCustomObject]@{Tweak=[PSCustomObject]@{id='REC1';Path=$r1;Value='NEW';FailApply=$false};Level=-1},[PSCustomObject]@{Tweak=[PSCustomObject]@{id='REC2';Path=$r2;Value='X';FailApply=$true};Level=-1})
$rtx=Invoke-WinSlimTransactionPlanOptimized -Items $rItems -FailurePolicy Stop -RootPath $txRoot -BackupRootPath $backupRoot -ApplyHandler $fileApply -BackupHandler $fileBackup -UndoHandler $fileUndo
Assert65R3 ($rtx.Status -eq 'Failed' -and [bool]$rtx.Recovery.Required) 'FailurePolicy Stop deixa recovery otimizado pendente'
$child=Join-Path $sandbox 'child-recovery-r3.ps1'
$txModule=(Join-Path $Root 'src\Core\Transaction.ps1').Replace("'","''")
$optModule=(Join-Path $Root 'src\Core\TransactionOptimized.ps1').Replace("'","''")
$txPath=([string]$rtx.TransactionPath).Replace("'","''");$txRootEsc=$txRoot.Replace("'","''")
$childText=@"
`$ErrorActionPreference='Stop'
. '$txModule'
. '$optModule'
`$undo={param(`$Tweak,`$Level,`$Context,`$BackupData,`$Step)if(`$BackupData.Exists){[IO.File]::WriteAllText([string]`$BackupData.Path,[string]`$BackupData.Content)}else{Remove-Item -LiteralPath ([string]`$BackupData.Path) -Force -ErrorAction SilentlyContinue};[PSCustomObject]@{Success=`$true;Changed=`$true;Verification=[PSCustomObject]@{Applicable=`$true;Success=`$true;Checks=@()};Restart='None';Warning=`$null;Error=`$null}}
`$tx=Invoke-WinSlimTransactionRecoveryOptimized -Path '$txPath' -RootPath '$txRootEsc' -UndoHandler `$undo
if(`$tx.Status -ne 'RolledBack'){exit 9}
"@
[IO.File]::WriteAllText($child,$childText,(New-Object System.Text.UTF8Encoding($true)))
$psExe=(Get-Process -Id $PID).Path
$proc=Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$child) -PassThru -Wait
$post=Import-WinSlimTransaction -Path $rtx.TransactionPath
Assert65R3 ($proc.ExitCode -eq 0 -and $post.Status -eq 'RolledBack') 'novo processo conclui recovery otimizado e journal continua legível pelo R13'
Assert65R3 ((Get-Content -LiteralPath $r1 -Raw -Encoding UTF8) -eq 'ORIGINAL') 'recovery cross-process restaura estado original'
$rec1=@($post.Steps|Where-Object{$_.TweakId -eq 'REC1'})
Assert65R3 ($rec1.Count -eq 1 -and $rec1[0].RollbackStatus -eq 'RolledBack') 'recovery persiste passo alterado como RolledBack'

Write-Host "`n=== TEST 06: terminal state e corrupção/recovery guard preservados ===" -ForegroundColor Yellow
$termCtx=New-Context65R3
$term=Invoke-WinSlimTransactionPlanOptimized -Items (New-Items65R3 @((New-Tweak65R3 TERM A))) -Context $termCtx -ApplyHandler $ApplyHandler65R3 -BackupHandler $BackupHandler65R3 -UndoHandler $UndoHandler65R3 -NoPersist
$threw=$false;try{Set-WinSlimTransactionStatusOptimized -Transaction $term -Status Applying}catch{$threw=$true}
Assert65R3 $threw 'Committed otimizado não retorna silenciosamente para Applying'
$fake=New-WinSlimTransactionOptimized -Mode Recovery -NoPersist
$fake.Recovery.Required=$true
$fake.Status='RecoveryRequired'
$okFake=Invoke-WinSlimTransactionRollbackOptimized -Transaction $fake -Context (New-Context65R3) -UndoHandler $UndoHandler65R3
Assert65R3 (-not $okFake -and $fake.Status -eq 'RollbackFailed' -and [bool]$fake.Recovery.Required) 'recovery pendente com zero candidatos não vira falso RolledBack'

Write-Host "`n=== TEST 07: benchmarks Transaction antes/depois (diagnóstico) ===" -ForegroundColor Yellow
$npItems=New-Object System.Collections.ArrayList
for($i=0;$i -lt [int]$benchSpec.noPersistItems;$i++){ $id='B'+($i%15);[void]$npItems.Add([PSCustomObject]@{Tweak=(New-Tweak65R3 $id ("V$i"));Level=-1}) }
$npItems=@($npItems.ToArray())
$legacyNoPersist=Measure65R3 {for($n=0;$n -lt [int]$benchSpec.noPersistIterations;$n++){ $c=New-Context65R3;$null=Invoke-TransactionPlan -Items $npItems -Context $c -ApplyHandler $ApplyHandler65R3 -BackupHandler $BackupHandler65R3 -UndoHandler $UndoHandler65R3 -NoPersist }}
$fastNoPersist=Measure65R3 {for($n=0;$n -lt [int]$benchSpec.noPersistIterations;$n++){ $c=New-Context65R3;$null=Invoke-WinSlimTransactionPlanOptimized -Items $npItems -Context $c -ApplyHandler $ApplyHandler65R3 -BackupHandler $BackupHandler65R3 -UndoHandler $UndoHandler65R3 -NoPersist }}
$npSpeed=Speedup65R3 $legacyNoPersist $fastNoPersist

$persistItems=New-Object System.Collections.ArrayList
for($i=0;$i -lt [int]$benchSpec.persistItems;$i++){[void]$persistItems.Add([PSCustomObject]@{Tweak=(New-Tweak65R3 "PB$i" "V$i");Level=-1})}
$persistItems=@($persistItems.ToArray())
$legacyPersistRoot=Join-Path $sandbox 'BenchLegacyTx';$legacyPersistBackup=Join-Path $sandbox 'BenchLegacyBk'
$fastPersistRoot=Join-Path $sandbox 'BenchFastTx';$fastPersistBackup=Join-Path $sandbox 'BenchFastBk'
$legacyPersist=Measure65R3 {for($n=0;$n -lt [int]$benchSpec.persistIterations;$n++){ $c=New-Context65R3;$null=Invoke-TransactionPlan -Items $persistItems -Context $c -RootPath $legacyPersistRoot -BackupRootPath $legacyPersistBackup -ApplyHandler $ApplyHandler65R3 -BackupHandler $BackupHandler65R3 -UndoHandler $UndoHandler65R3 }}
$fastPersist=Measure65R3 {for($n=0;$n -lt [int]$benchSpec.persistIterations;$n++){ $c=New-Context65R3;$null=Invoke-WinSlimTransactionPlanOptimized -Items $persistItems -Context $c -RootPath $fastPersistRoot -BackupRootPath $fastPersistBackup -ApplyHandler $ApplyHandler65R3 -BackupHandler $BackupHandler65R3 -UndoHandler $UndoHandler65R3 }}
$pSpeed=Speedup65R3 $legacyPersist $fastPersist
Write-Host ("  NoPersist: legado={0} ms | otimizado={1} ms | speedup={2}x" -f $legacyNoPersist,$fastNoPersist,$npSpeed) -ForegroundColor Cyan
Write-Host ("  Persist:   legado={0} ms | otimizado={1} ms | speedup={2}x" -f $legacyPersist,$fastPersist,$pSpeed) -ForegroundColor Cyan
Assert65R3 ($legacyNoPersist -gt 0 -and $fastNoPersist -gt 0 -and $legacyPersist -gt 0 -and $fastPersist -gt 0) 'benchmarks Transaction produziram medições válidas'
if($npSpeed -lt 1){Warn65R3 "NoPersist otimizado não foi mais rápido nesta execução ($npSpeed`x)."}
if($pSpeed -lt 1){Warn65R3 "Persist otimizado não foi mais rápido nesta execução ($pSpeed`x)."}
$report=[PSCustomObject]@{schemaVersion='1.0';phase='FASE6.5-R3';timestamp=(Get-Date).ToString('o');powershell=$PSVersionTable.PSVersion.ToString();noPersist=[PSCustomObject]@{legacyMs=$legacyNoPersist;optimizedMs=$fastNoPersist;speedup=$npSpeed;iterations=[int]$benchSpec.noPersistIterations;items=[int]$benchSpec.noPersistItems};persist=[PSCustomObject]@{legacyMs=$legacyPersist;optimizedMs=$fastPersist;speedup=$pSpeed;iterations=[int]$benchSpec.persistIterations;items=[int]$benchSpec.persistItems};warnings=@($Warnings)}
$benchDir=Join-Path $Root 'benchmarks';if(-not(Test-Path -LiteralPath $benchDir)){New-Item -ItemType Directory -Path $benchDir -Force|Out-Null}
$benchPath=Join-Path $benchDir 'FASE6.5-R3-last-run.json';$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $benchPath -Encoding UTF8
Assert65R3 (Test-Path -LiteralPath $benchPath) 'relatório salvo em benchmarks\FASE6.5-R3-last-run.json'

Write-Host "`n=== TEST 08: arquitetura protegida / fechamento R3 ===" -ForegroundColor Yellow
Assert65R3 ((Get-FileHash -LiteralPath (Join-Path $Root 'src\Core\Transaction.ps1') -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$baseline.files.PSObject.Properties['src/Core/Transaction.ps1'].Value).ToLowerInvariant()) 'Transaction Manager R13 canônico permanece byte-a-byte congelado'
Assert65R3 ((Get-FileHash -LiteralPath (Join-Path $Root 'src\Core\PlannerOptimized.ps1') -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$baseline.files.PSObject.Properties['src/Core/PlannerOptimized.ps1'].Value).ToLowerInvariant()) 'PlannerOptimized R2.1 permanece congelado'
Assert65R3 ($AllTweaks.Count -eq 230) 'backend permanece 230'

try{Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue}catch{}

Write-Host "`n=== RESUMO FASE 6.5 R3 ===" -ForegroundColor Yellow
if($Failures.Count -eq 0){
    Write-Host 'FASE 6.5 R3 APROVADA - Transaction shadow otimizado preserva commit/rollback/recovery R13 e reduz hot paths/persistência redundante.' -ForegroundColor Green
    Write-Host 'Próximo subgate: FASE 6.5 R4 - promoção controlada + regressão completa + benchmark final end-to-end.' -ForegroundColor Cyan
    exit 0
}
Write-Host "FASE 6.5 R3 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $Failures){Write-Host " - $f" -ForegroundColor Red}
exit 1

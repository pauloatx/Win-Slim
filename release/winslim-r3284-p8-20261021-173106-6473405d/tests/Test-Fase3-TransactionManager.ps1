#requires -Version 5.1
<#
  Win-Slim Suite - FASE 3 Transaction Manager
  Harness seguro: usa somente arquivos temporarios para validar semantica
  transacional, persistencia, rollback LIFO e recovery cross-process.
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

$TestsRoot = Split-Path -Parent $PSScriptRoot
$Module = Join-Path $TestsRoot 'src\Core\Transaction.ps1'
. $Module

$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$Sandbox = Join-Path $TestsRoot ("tests\_fase3-sandbox-$runId")
$TxRoot = Join-Path $Sandbox 'Transactions'
$BackupRoot = Join-Path $Sandbox 'Backups'
$StateRoot = Join-Path $Sandbox 'State'
New-Item -Path $TxRoot,$BackupRoot,$StateRoot -ItemType Directory -Force | Out-Null

$script:failures = @()
$script:undoOrder = @()

function Ok([string]$m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function Fail([string]$m) { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:failures += $m }
function Assert-True([bool]$cond,[string]$m) { if ($cond) { Ok $m } else { Fail $m } }

function New-TestTweak {
    param([string]$Id,[string]$Path,[string]$Value,[switch]$FailApply,[switch]$FailVerify,[switch]$FailUndo)
    return [PSCustomObject]@{
        id=$Id; Path=$Path; Value=$Value
        FailApply=[bool]$FailApply; FailVerify=[bool]$FailVerify; FailUndo=[bool]$FailUndo
        restartScope='None'
    }
}

$ApplyHandler = {
    param($Tweak,$Level,$Context)
    $exists = Test-Path -LiteralPath $Tweak.Path
    $before = [PSCustomObject]@{ Path=$Tweak.Path; Exists=$exists; Content=$(if($exists){Get-Content -LiteralPath $Tweak.Path -Raw -Encoding UTF8}else{$null}) }
    if ($Tweak.FailApply) {
        return [PSCustomObject]@{ Id=$Tweak.id; Success=$false; Changed=$false; StateBefore=$before; StateAfter=$before; Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@()}; Restart='None'; Warning=$null; Error='falha Apply injetada' }
    }
    $current = if ($exists) { $before.Content } else { $null }
    $changed = (-not $exists) -or ($current -ne $Tweak.Value)
    if ($changed) { [System.IO.File]::WriteAllText($Tweak.Path,[string]$Tweak.Value,(New-Object System.Text.UTF8Encoding($true))) }
    $actual = if (Test-Path -LiteralPath $Tweak.Path) { Get-Content -LiteralPath $Tweak.Path -Raw -Encoding UTF8 } else { $null }
    $verify = ($actual -eq $Tweak.Value) -and (-not $Tweak.FailVerify)
    return [PSCustomObject]@{
        Id=$Tweak.id; Success=$true; Changed=[bool]$changed; StateBefore=$before
        StateAfter=[PSCustomObject]@{Path=$Tweak.Path;Exists=(Test-Path $Tweak.Path);Content=$actual}
        Verification=[PSCustomObject]@{Applicable=$true;Success=[bool]$verify;Checks=@([PSCustomObject]@{Target=$Tweak.Path;Expected=$Tweak.Value;Actual=$actual;Pass=[bool]$verify})}
        Restart='None'; Warning=$(if($verify){$null}else{'verify injetado'}); Error=$null
    }
}

$BackupHandler = {
    param($Tweak,$Level,$Context,$Step)
    $exists = Test-Path -LiteralPath $Tweak.Path
    [PSCustomObject]@{
        Path    = [string]$Tweak.Path
        Exists  = [bool]$exists
        Content = $(if ($exists) { Get-Content -LiteralPath $Tweak.Path -Raw -Encoding UTF8 } else { $null })
    }
}

$UndoHandler = {
    param($Tweak,$Level,$Context,$BackupData,$Step)
    $script:undoOrder += $Step.TweakId
    if ($Tweak.FailUndo) {
        return [PSCustomObject]@{Id=$Tweak.id;Success=$false;Changed=$false;Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@()};Restart='None';Warning=$null;Error='falha Undo injetada'}
    }
    if ($BackupData.Exists) {
        [System.IO.File]::WriteAllText([string]$BackupData.Path,[string]$BackupData.Content,(New-Object System.Text.UTF8Encoding($true)))
    } else {
        Remove-Item -LiteralPath ([string]$BackupData.Path) -Force -ErrorAction SilentlyContinue
    }
    $exists = Test-Path -LiteralPath ([string]$BackupData.Path)
    $actual = if ($exists) { Get-Content -LiteralPath ([string]$BackupData.Path) -Raw -Encoding UTF8 } else { $null }
    $pass = if ($BackupData.Exists) { $exists -and ($actual -eq $BackupData.Content) } else { -not $exists }
    return [PSCustomObject]@{Id=$Tweak.id;Success=[bool]$pass;Changed=$true;Verification=[PSCustomObject]@{Applicable=$true;Success=[bool]$pass;Checks=@([PSCustomObject]@{Target=$BackupData.Path;Expected=$BackupData.Content;Actual=$actual;Pass=[bool]$pass})};Restart='None';Warning=$null;Error=$(if($pass){$null}else{'restore divergente'})}
}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 3 Transaction Manager'
Write-Host '============================================================'
Write-Host "Sandbox: $Sandbox"
Write-Host "R13: harness PS5.1 array-safe + serializer JSON top-level + recovery endurecido"

Write-Host "`n=== TEST 00: persistencia de arrays vazios (PowerShell 5.1) ==="
$probePath = Join-Path $Sandbox 'empty-array-probe.json'
$emptyCopy = Copy-TransactionObject -InputObject @()
$ok00a = (($null -ne $emptyCopy) -and ($emptyCopy -is [System.Array]) -and $emptyCopy.Count -eq 0)
Assert-True $ok00a 'Copy-TransactionObject preserva @() sem acessar BaseObject nulo'

$jsonDataProbe = ConvertTo-TransactionJsonData -Data @()
$ok00b = (($null -ne $jsonDataProbe) -and ($jsonDataProbe -is [System.Array]) -and $jsonDataProbe.Count -eq 0)
Assert-True $ok00b 'ConvertTo-TransactionJsonData preserva @() atraves da pipeline'

Write-JsonAtomic -Path $probePath -Data @()
$probeRaw = (Get-Content -LiteralPath $probePath -Raw -Encoding UTF8).Trim([char]0xFEFF).Trim()
$ok00c = ($probeRaw -eq '[]')
Assert-True $ok00c "Write-JsonAtomic persiste colecao vazia como [] (actual='$probeRaw')"


# R6: provar que operations.json nao carrega o grafo detalhado do resultado.
$probeStep = [PSCustomObject]@{
    Sequence=1; TweakId='PROBE'; Level=-1; Status='Verified'; StartedAt=$null; CompletedAt=$null
    Changed=$true; Tweak=(New-TestTweak -Id 'PROBE' -Path (Join-Path $StateRoot 'probe.txt') -Value 'X')
    StateBefore=[PSCustomObject]@{A=1}; StateAfter=[PSCustomObject]@{A=2}; BackupData=[PSCustomObject]@{B=1}
    BackupFile=(Join-Path $BackupRoot 'probe.json'); ApplyResult=[PSCustomObject]@{Success=$true}; VerifyResult=[PSCustomObject]@{Success=$true}
    Restart='None'; RollbackStatus='Pending'; UndoResult=$null; Warning=$null; Error=$null
}
$probeTx = [PSCustomObject]@{ Steps=@($probeStep) }
$opProbe = @(Get-TransactionOperationsPersistenceSnapshot -Transaction $probeTx)
$ok00d = (@($opProbe).Count -eq 1 -and
          ($opProbe[0].PSObject.Properties.Name -contains 'BackupFile') -and
          ($opProbe[0].PSObject.Properties.Name -notcontains 'ApplyResult') -and
          ($opProbe[0].PSObject.Properties.Name -notcontains 'StateBefore') -and
          ($opProbe[0].PSObject.Properties.Name -notcontains 'BackupData'))
Assert-True $ok00d 'operations journal e compacto e nao reserializa ApplyResult/State/BackupData'

# R7: rollback.json nao pode carregar UndoResult inteiro.
$probeStep.UndoResult = [PSCustomObject]@{
    Id='PROBE'; Success=$true; Changed=$true; Restart='None'; Warning=$null; Error=$null
    StateBefore=[PSCustomObject]@{Deep=[PSCustomObject]@{A=1}}
    StateAfter=[PSCustomObject]@{Deep=[PSCustomObject]@{A=2}}
    Verification=[PSCustomObject]@{Applicable=$true;Success=$true;Checks=@([PSCustomObject]@{Target='x';Pass=$true})}
}
$rbProbe = @(Get-TransactionRollbackPersistenceSnapshot -Transaction $probeTx)
$ok00e = (@($rbProbe).Count -eq 1 -and
          ($rbProbe[0].PSObject.Properties.Name -contains 'Undo') -and
          ($rbProbe[0].PSObject.Properties.Name -notcontains 'UndoResult') -and
          ($rbProbe[0].Undo.PSObject.Properties.Name -notcontains 'StateBefore') -and
          ($rbProbe[0].Undo.PSObject.Properties.Name -notcontains 'StateAfter'))
Assert-True $ok00e 'rollback journal e compacto e nao reserializa UndoResult/State'

$beforeProbe = @(Get-TransactionStateBeforePersistenceSnapshot -Transaction $probeTx)
$afterProbe  = Get-TransactionStateAfterPersistenceSnapshot -Transaction $probeTx
$ok00f = (($beforeProbe[0].PSObject.Properties.Name -notcontains 'BackupData') -and
          ($afterProbe[0].PSObject.Properties.Name -notcontains 'StateAfter'))
Assert-True $ok00f 'artefatos finais usam referencias/resumos, nao grafos vivos de estado'

# R8: o snapshot de rollback usa CliXml/PSSerializer e precisa preservar tipos.
$typedBackupPath = Join-Path $Sandbox 'typed-backup-probe.clixml'
$typedBackup = [PSCustomObject]@{ Path='X'; Exists=$true; Content='ORIG1'; Bytes=[byte[]](1,2,3); Empty=@() }
Write-TransactionBackupAtomic -Path $typedBackupPath -Data $typedBackup
$typedRoundTrip = Read-TransactionBackupFile -Path $typedBackupPath
$ok00g = ((Test-Path $typedBackupPath) -and $typedRoundTrip.Exists -and $typedRoundTrip.Content -eq 'ORIG1' -and @($typedRoundTrip.Bytes).Count -eq 3 -and @($typedRoundTrip.Empty).Count -eq 0)
Assert-True $ok00g 'backup CliXml preserva snapshot existente, byte[] e array vazio'

# R9: reproduz exatamente o caso que quebrou no TEST 02 da R8. Get-Content
# devolve string com metadados ETS no Windows PowerShell 5.1. O backup deve
# persistir somente o valor da string, sem PSPath/PSDrive/PSProvider.
$etsSource = Join-Path $Sandbox 'ets-content-source.txt'
[IO.File]::WriteAllText($etsSource,'ORIG-ETS')
$etsContent = Get-Content -LiteralPath $etsSource -Raw -Encoding UTF8
$etsBackupPath = Join-Path $Sandbox 'ets-backup-probe.clixml'
$etsBackup = [PSCustomObject]@{ Path=$etsSource; Exists=$true; Content=$etsContent }
Write-TransactionBackupAtomic -Path $etsBackupPath -Data $etsBackup
$etsRoundTrip = Read-TransactionBackupFile -Path $etsBackupPath
$ok00h = ((Test-Path $etsBackupPath) -and [string]$etsRoundTrip.Content -eq 'ORIG-ETS')
Assert-True $ok00h 'backup CliXml remove metadados ETS de string retornada por Get-Content'


# R11: regressao central - arrays JSON top-level NAO podem virar {value,Count}.
$arrayProbePath = Join-Path $Sandbox 'array-shape-probe.json'
$arrayProbeData = @(
    [PSCustomObject]@{ Sequence=1; TweakId='A1'; Changed=$true },
    [PSCustomObject]@{ Sequence=2; TweakId='A2'; Changed=$false }
)
Write-JsonAtomic -Path $arrayProbePath -Data $arrayProbeData
$arrayProbeRaw = (Get-Content -LiteralPath $arrayProbePath -Raw -Encoding UTF8).Trim([char]0xFEFF).Trim()
# Windows PowerShell 5.1: ConvertFrom-Json devolve um JSON array como um
# Object[] NAO enumerado na pipeline. Envolver diretamente a chamada em @()
# cria um array externo de 1 elemento (o Object[] interno), gerando falso
# negativo no harness. Parseamos sem @() e passamos pelo mesmo normalizador
# usado pelo Import-WinSlimTransaction.
$arrayProbeParsed = ConvertFrom-Json -InputObject $arrayProbeRaw
$arrayProbeItems = @(ConvertFrom-TransactionJournalCollection -Data $arrayProbeParsed)
$ok00i = ($arrayProbeRaw.StartsWith('[') -and
          $arrayProbeRaw -notmatch '"value"\s*:' -and
          $arrayProbeRaw -notmatch '"Count"\s*:' -and
          $arrayProbeItems.Count -eq 2 -and
          $arrayProbeItems[0].TweakId -eq 'A1' -and
          $arrayProbeItems[1].TweakId -eq 'A2')
if (-not $ok00i) {
    Write-Host "  [DEBUG] array-shape-probe raw: $arrayProbeRaw" -ForegroundColor Yellow
    try {
        Write-Host "  [DEBUG] parsed type: $($arrayProbeParsed.GetType().FullName); parsed count=$($arrayProbeParsed.Count); normalized count=$($arrayProbeItems.Count)" -ForegroundColor Yellow
    } catch { }
}
Assert-True $ok00i 'Write-JsonAtomic preserva array top-level e import normaliza 2 itens no PS5.1'

if (-not ($ok00a -and $ok00b -and $ok00c -and $ok00d -and $ok00e -and $ok00f -and $ok00g -and $ok00h -and $ok00i)) {
    Write-Host "`nPRE-FLIGHT R13 FALHOU. TESTES TRANSACIONAIS NAO SERAO EXECUTADOS." -ForegroundColor Red
    Write-Host "Probe: $probePath"
    exit 2
}

Write-Host "`n=== TEST 01: commit de 3 operacoes ==="
$items=@()
1..3 | ForEach-Object { $items += [PSCustomObject]@{Tweak=(New-TestTweak -Id "C$_" -Path (Join-Path $StateRoot "commit$_.txt") -Value "V$_");Level=-1} }
$tx1=Invoke-TransactionPlan -Items $items -RootPath $TxRoot -BackupRootPath $BackupRoot -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler
Assert-True ($tx1.Status -eq 'Committed') '3 operacoes validas -> Committed'
Assert-True ((Test-Path (Join-Path $tx1.TransactionPath 'result.json'))) 'result.json persistido'
Assert-True ((Test-Path (Join-Path $tx1.TransactionPath 'state-before.json'))) 'state-before.json persistido'
Assert-True ((Test-Path (Join-Path $tx1.TransactionPath 'state-after.json'))) 'state-after.json persistido'

$tx1OpsRaw = Get-Content -LiteralPath (Join-Path $tx1.TransactionPath 'operations.json') -Raw -Encoding UTF8
$tx1OpsData = ConvertFrom-Json -InputObject $tx1OpsRaw
$tx1Ops = @(ConvertFrom-TransactionJournalCollection -Data $tx1OpsData)
$tx1Ids = (($tx1Ops | ForEach-Object { [string]$_.TweakId }) -join ',')
Assert-True ($tx1OpsRaw.Trim([char]0xFEFF).Trim().StartsWith('[') -and $tx1Ops.Count -eq 3 -and $tx1Ids -eq 'C1,C2,C3') 'operations.json persiste array real com C1,C2,C3 e reidrata 3 passos no PS5.1'

Write-Host "`n=== TEST 02: falha de Apply -> rollback LIFO ==="
$script:undoOrder=@()
$p1=Join-Path $StateRoot 'lifo1.txt'; $p2=Join-Path $StateRoot 'lifo2.txt'; $p3=Join-Path $StateRoot 'lifo3.txt'
[IO.File]::WriteAllText($p1,'ORIG1'); [IO.File]::WriteAllText($p2,'ORIG2')
$items=@(
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'L1' -Path $p1 -Value 'NEW1');Level=-1},
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'L2' -Path $p2 -Value 'NEW2');Level=-1},
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'L3' -Path $p3 -Value 'NEW3' -FailApply);Level=-1}
)
$tx2=Invoke-TransactionPlan -Items $items -RootPath $TxRoot -BackupRootPath $BackupRoot -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler
Assert-True ($tx2.Status -eq 'RolledBack') 'falha Apply dispara RolledBack'
Assert-True (($script:undoOrder -join ',') -eq 'L2,L1') 'rollback ocorreu em ordem LIFO (L2,L1)'
Assert-True ((Get-Content $p1 -Raw) -eq 'ORIG1' -and (Get-Content $p2 -Raw) -eq 'ORIG2') 'estado original restaurado'

Write-Host "`n=== TEST 03: Apply passa, Verify falha -> rollback ==="
$script:undoOrder=@()
$v1=Join-Path $StateRoot 'verify1.txt'; $v2=Join-Path $StateRoot 'verify2.txt'
[IO.File]::WriteAllText($v1,'A'); [IO.File]::WriteAllText($v2,'B')
$items=@(
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'V1' -Path $v1 -Value 'A2');Level=-1},
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'V2' -Path $v2 -Value 'B2' -FailVerify);Level=-1}
)
$tx3=Invoke-TransactionPlan -Items $items -RootPath $TxRoot -BackupRootPath $BackupRoot -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler
Assert-True ($tx3.Status -eq 'RolledBack') 'Verify=false e tratado como falha transacional'
Assert-True (($script:undoOrder -join ',') -eq 'V2,V1') 'o passo que mudou antes de falhar Verify tambem entra no rollback'
Assert-True ((Get-Content $v1 -Raw) -eq 'A' -and (Get-Content $v2 -Raw) -eq 'B') 'rollback apos falha Verify restaurou ambos'

Write-Host "`n=== TEST 04: falha parcial no Undo ==="
$script:undoOrder=@()
$u1=Join-Path $StateRoot 'undo1.txt'; $u2=Join-Path $StateRoot 'undo2.txt'; $u3=Join-Path $StateRoot 'undo3.txt'
[IO.File]::WriteAllText($u1,'U1'); [IO.File]::WriteAllText($u2,'U2')
$items=@(
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'U1' -Path $u1 -Value 'U1N' -FailUndo);Level=-1},
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'U2' -Path $u2 -Value 'U2N');Level=-1},
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'U3' -Path $u3 -Value 'X' -FailApply);Level=-1}
)
$tx4=Invoke-TransactionPlan -Items $items -RootPath $TxRoot -BackupRootPath $BackupRoot -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler
Assert-True ($tx4.Status -eq 'PartiallyRolledBack') 'Undo parcial nao e mascarado como sucesso'
Assert-True ((@($tx4.Steps|Where-Object{$_.RollbackStatus -eq 'RollbackFailed'}).Count) -eq 1) 'passo com Undo falho fica RollbackFailed'

Write-Host "`n=== TEST 05: Recovery cross-process ==="
$r1=Join-Path $StateRoot 'recovery1.txt'; $r2=Join-Path $StateRoot 'recovery2.txt'
[IO.File]::WriteAllText($r1,'R-ORIG')
$items=@(
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'R1' -Path $r1 -Value 'R-NEW');Level=-1},
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'R2' -Path $r2 -Value 'X' -FailApply);Level=-1}
)
$tx5=Invoke-TransactionPlan -Items $items -FailurePolicy Stop -RootPath $TxRoot -BackupRootPath $BackupRoot -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler
Assert-True ($tx5.Status -eq 'Failed' -and $tx5.Recovery.Required) 'FailurePolicy Stop deixa recovery pendente persistido'

$tx5Pre = Import-WinSlimTransaction -Path $tx5.TransactionPath
$r1Pre = @($tx5Pre.Steps | Where-Object { $_.TweakId -eq 'R1' })
Assert-True ($r1Pre.Count -eq 1 -and $r1Pre[0].Changed -and $null -ne $r1Pre[0].BackupData -and $r1Pre[0].BackupData.Content -eq 'R-ORIG') 'journal cross-process reidrata R1 + backup original antes do recovery'
$child=Join-Path $Sandbox 'child-recovery.ps1'
$moduleEsc=$Module.Replace("'","''"); $txPathEsc=$tx5.TransactionPath.Replace("'","''"); $txRootEsc=$TxRoot.Replace("'","''")
$childText=@"
`$ErrorActionPreference='Stop'
. '$moduleEsc'
`$undo = {
 param(`$Tweak,`$Level,`$Context,`$BackupData,`$Step)
 if (`$BackupData.Exists) { [IO.File]::WriteAllText([string]`$BackupData.Path,[string]`$BackupData.Content) } else { Remove-Item -LiteralPath ([string]`$BackupData.Path) -Force -ErrorAction SilentlyContinue }
 `$exists=Test-Path -LiteralPath ([string]`$BackupData.Path)
 `$actual=if(`$exists){Get-Content -LiteralPath ([string]`$BackupData.Path) -Raw}else{`$null}
 `$pass=if(`$BackupData.Exists){`$exists -and (`$actual -eq `$BackupData.Content)}else{-not `$exists}
 [PSCustomObject]@{Success=[bool]`$pass;Changed=`$true;Verification=[PSCustomObject]@{Applicable=`$true;Success=[bool]`$pass;Checks=@()};Restart='None';Warning=`$null;Error=`$null}
}
`$tx=Invoke-WinSlimTransactionRecovery -Path '$txPathEsc' -RootPath '$txRootEsc' -UndoHandler `$undo
if (`$tx.Status -ne 'RolledBack') { exit 9 }
"@
[IO.File]::WriteAllText($child,$childText,(New-Object System.Text.UTF8Encoding($true)))
$psExe=(Get-Process -Id $PID).Path
$proc=Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$child) -PassThru -Wait
$tx5r=Import-WinSlimTransaction -Path $tx5.TransactionPath
Assert-True ($proc.ExitCode -eq 0 -and $tx5r.Status -eq 'RolledBack') 'novo processo recuperou transacao persistida'

$r1Post = @($tx5r.Steps | Where-Object { $_.TweakId -eq 'R1' })
Assert-True ($r1Post.Count -eq 1 -and $r1Post[0].RollbackStatus -eq 'RolledBack') 'recovery persistiu R1 como RolledBack no journal'
Assert-True ((Get-Content $r1 -Raw) -eq 'R-ORIG') 'recovery cross-process restaurou estado original'

Write-Host "`n=== TEST 06: idempotencia / Changed=false ==="
$i1=Join-Path $StateRoot 'idem.txt'; [IO.File]::WriteAllText($i1,'SAME')
$tx6=Invoke-TransactionPlan -Items @([PSCustomObject]@{Tweak=(New-TestTweak -Id 'I1' -Path $i1 -Value 'SAME');Level=-1}) -RootPath $TxRoot -BackupRootPath $BackupRoot -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler
Assert-True ($tx6.Status -eq 'Committed') 'estado ja desejado ainda permite Commit'
Assert-True ($tx6.Steps[0].Status -eq 'NoChange' -and -not $tx6.Steps[0].Changed) 'idempotencia registrada como NoChange/Changed=false'

Write-Host "`n=== TEST 07: estado terminal protegido ==="
$threw=$false
try { Set-TransactionStatus -Transaction $tx6 -Status 'Applying' } catch { $threw=$true }
Assert-True $threw 'Committed nao pode voltar silenciosamente para Applying'

Write-Host "`n=== TEST 08: primeiro backup e imutavel para TweakId repetido ==="
$script:undoOrder=@()
$im=Join-Path $StateRoot 'immutable.txt'; [IO.File]::WriteAllText($im,'ORIGINAL')
$items=@(
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'IMM' -Path $im -Value 'FIRST');Level=-1},
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'IMM' -Path $im -Value 'SECOND');Level=-1},
 [PSCustomObject]@{Tweak=(New-TestTweak -Id 'IMM-FAIL' -Path (Join-Path $StateRoot 'immfail.txt') -Value 'X' -FailApply);Level=-1}
)
$tx8=Invoke-TransactionPlan -Items $items -RootPath $TxRoot -BackupRootPath $BackupRoot -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler -UndoHandler $UndoHandler
$immSteps=@($tx8.Steps|Where-Object{$_.TweakId -eq 'IMM'}|Sort-Object Sequence)
Assert-True ($immSteps.Count -eq 2 -and $immSteps[0].BackupData.Content -eq 'ORIGINAL' -and $immSteps[1].BackupData.Content -eq 'ORIGINAL') 'segundo Apply nao sobrescreveu o primeiro backup'
Assert-True ((Get-Content $im -Raw) -eq 'ORIGINAL') 'rollback final voltou ao estado anterior a transacao'

Write-Host "`n=== RESUMO FASE 3 ==="
if ($script:failures.Count -eq 0) {
    Write-Host 'FASE 3 CORE APROVADA - Transaction Manager passou em todos os cenarios do harness.' -ForegroundColor Green
    Write-Host "Artefatos de teste: $Sandbox"
    exit 0
}
Write-Host "FASE 3 CORE REPROVADA - $($script:failures.Count) falha(s):" -ForegroundColor Red
$script:failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
Write-Host "Artefatos de teste: $Sandbox"
exit 1

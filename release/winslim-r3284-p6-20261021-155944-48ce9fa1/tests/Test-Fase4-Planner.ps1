$ErrorActionPreference = 'Stop'

$TestsRoot = Split-Path -Parent $PSScriptRoot
$PlannerPath = Join-Path $TestsRoot 'src\Core\Planner.ps1'
$TransactionPath = Join-Path $TestsRoot 'src\Core\Transaction.ps1'
. $PlannerPath
. $TransactionPath

$script:failures = @()

function Assert-Phase4 {
    param([bool]$Condition, [string]$Message, [string]$Detail = $null)
    if ($Condition) {
        Write-Host "  [OK] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkYellow }
        $script:failures += $(if ($Detail) { "$Message :: $Detail" } else { $Message })
    }
}

function New-TestContext {
    param([string]$OS='11', [bool]$IsAdmin=$true, [string[]]$GPU=@('NVIDIA GeForce Test'), [int]$RAM=16, [string]$Storage='SSD')
    return [PSCustomObject]@{
        OS=$OS; Build='26100'; Architecture='AMD64'; CPU='Test CPU'; GPU=@($GPU); RAM=$RAM; Storage=$Storage
        SecureBoot=[PSCustomObject]@{ Supported=$true; Enabled=$true }
        TPM=[PSCustomObject]@{ Present=$true; Ready=$true }
        VBS=$false; HVCI=$false
        HyperV=[PSCustomObject]@{ FeatureInstalled=$false; HypervisorRunning=$false; LaunchType='Off'; WSL2Detected=$false }
        PowerPlan='test'; NetworkAdapters=@('Ethernet'); Services=@(); PendingReboot=$false; IsAdmin=$IsAdmin
    }
}

function New-TestTweak {
    param(
        [string]$Id,
        [string[]]$Dependencies=@(),
        [string[]]$Conflicts=@(),
        [string]$MutexGroup=$null,
        [string[]]$WindowsVersion=@('10','11'),
        $HardwareRules=$null,
        [bool]$RequiresAdmin=$false,
        [string]$Risk='Baixo',
        [bool]$RequiresRestart=$false,
        [string]$RestartScope='None',
        [string]$Type='registry',
        $PresetLevels=$null,
        [string[]]$Presets=@(),
        $Levels=$null
    )
    if ($null -eq $HardwareRules) { $HardwareRules=[PSCustomObject]@{} }
    if ($null -eq $Levels) { $Levels=@() }
    return [PSCustomObject]@{
        id=$Id; name="Test $Id"; plainName="Test $Id"; description='synthetic planner test'; category='Test'; risk=$Risk
        windowsVersion=@($WindowsVersion); hardwareRules=$HardwareRules; dependencies=@($Dependencies); conflicts=@($Conflicts)
        mutexGroup=$MutexGroup; presets=@($Presets); type=$Type; presetLevels=$PresetLevels; levels=@($Levels)
        requiresAdmin=$RequiresAdmin; rollbackClass=@('Registry'); requiresRestart=$RequiresRestart; restartScope=$RestartScope
        registry=@([PSCustomObject]@{ Path='HKCU:\Software\WinSlimPlannerTest'; Name=$Id; Value=1; Type='DWord'; OriginalValue=0 })
    }
}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 4 Planner'
Write-Host '============================================================'
Write-Host 'R1: planner puro + DAG/deps + conflicts/mutex + applicability + preview'

Write-Host "`n=== TEST 00: parser + pureza (nenhuma mutacao Windows) ==="
$tokens=$null; $parseErrors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($PlannerPath,[ref]$tokens,[ref]$parseErrors)
Assert-Phase4 (@($parseErrors).Count -eq 0) 'Planner.ps1 sem erros de parser' $(if (@($parseErrors).Count -gt 0) { (@($parseErrors | ForEach-Object { $_.Message }) -join '; ') } else { $null })
$dangerous=@('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Set-Service','Start-Service','Stop-Service','Remove-Service','Invoke-Expression','Remove-AppxPackage','Remove-AppxProvisionedPackage','Set-Content','Add-Content','Clear-Content','bcdedit','powercfg','fsutil','dism','schtasks','reg','netsh','Set-NetIPInterface','Set-DnsClientServerAddress')
$called=@($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] },$true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
$bad=@($called | Where-Object { $dangerous -contains $_ } | Sort-Object -Unique)
Assert-Phase4 ($bad.Count -eq 0) 'Planner nao contem comandos de mutacao do Windows' $(if ($bad.Count) { $bad -join ', ' } else { $null })

Write-Host "`n=== TEST 01: dependencias automaticas/transitivas + ordem topologica ==="
$cat=@(
    (New-TestTweak -Id 'C'),
    (New-TestTweak -Id 'B' -Dependencies @('C')),
    (New-TestTweak -Id 'A' -Dependencies @('B'))
)
$p=New-WinSlimExecutionPlan -CatalogTweaks $cat -SelectedIds @('A') -Context (New-TestContext)
$ids=@($p.ExecutionOrder | Select-Object -ExpandProperty TweakId)
Assert-Phase4 (($ids -join ',') -eq 'C,B,A') 'dependencia transitiva executa C -> B -> A' ($ids -join ',')
Assert-Phase4 (($p.ExpandedDependencies -join ',') -eq 'C,B') 'ExpandedDependencies registra C e B deterministicamente' ($p.ExpandedDependencies -join ',')
Assert-Phase4 ($p.CanExecute -and $p.BlockedTweaks.Count -eq 0) 'plano valido sem bloqueios'

Write-Host "`n=== TEST 02: determinismo ==="
$cat=@((New-TestTweak -Id 'A'),(New-TestTweak -Id 'B'),(New-TestTweak -Id 'C'))
$p1=New-WinSlimExecutionPlan -CatalogTweaks $cat -SelectedIds @('C','A','B') -Context (New-TestContext)
$p2=New-WinSlimExecutionPlan -CatalogTweaks $cat -SelectedIds @('B','C','A') -Context (New-TestContext)
$o1=@($p1.ExecutionOrder | Select-Object -ExpandProperty TweakId) -join ','
$o2=@($p2.ExecutionOrder | Select-Object -ExpandProperty TweakId) -join ','
Assert-Phase4 ($o1 -eq $o2 -and $o1 -eq 'A,B,C') 'mesmo conjunto produz mesma ordem pelo catalogo' "$o1 vs $o2"
Assert-Phase4 ($p1.Fingerprint -eq $p2.Fingerprint) 'fingerprint deterministico para o mesmo plano'

Write-Host "`n=== TEST 03: dependencia ausente + ciclo ==="
$missing=@((New-TestTweak -Id 'A' -Dependencies @('MISSING')))
$pm=New-WinSlimExecutionPlan -CatalogTweaks $missing -SelectedIds @('A') -Context (New-TestContext)
Assert-Phase4 ((@($pm.BlockedTweaks | Where-Object { $_.TweakId -eq 'A' -and $_.ReasonCode -eq 'MissingDependency' }).Count) -eq 1) 'dependencia ausente bloqueia o tweak'
$cycle=@((New-TestTweak -Id 'A' -Dependencies @('B')),(New-TestTweak -Id 'B' -Dependencies @('A')))
$pc=New-WinSlimExecutionPlan -CatalogTweaks $cycle -SelectedIds @('A') -Context (New-TestContext)
Assert-Phase4 ($pc.DependencyCycles.Count -ge 1) 'ciclo A <-> B detectado'
Assert-Phase4 ((@($pc.BlockedTweaks | Where-Object { $_.ReasonCode -eq 'DependencyCycle' }).Count) -eq 2) 'nos do ciclo ficam bloqueados'

Write-Host "`n=== TEST 04: conflicts + mutexGroup ==="
$conf=@((New-TestTweak -Id 'A' -Conflicts @('B')),(New-TestTweak -Id 'B'))
$pb=New-WinSlimExecutionPlan -CatalogTweaks $conf -SelectedIds @('A','B') -Context (New-TestContext) -ConflictPolicy Block
Assert-Phase4 (-not $pb.CanExecute -and $pb.Conflicts.Count -eq 1 -and $pb.BlockedTweaks.Count -eq 2) 'ConflictPolicy Block nao escolhe vencedor silenciosamente'
$pp=New-WinSlimExecutionPlan -CatalogTweaks $conf -SelectedIds @('B','A') -Context (New-TestContext) -ConflictPolicy PreferFirst
$ppIds=@($pp.ExecutionOrder | Select-Object -ExpandProperty TweakId)
Assert-Phase4 ($pp.CanExecute -and ($ppIds -join ',') -eq 'A') 'PreferFirst usa ordem deterministica do catalogo' ($ppIds -join ',')
$mutex=@((New-TestTweak -Id 'M1' -MutexGroup 'G'),(New-TestTweak -Id 'M2' -MutexGroup 'G'))
$px=New-WinSlimExecutionPlan -CatalogTweaks $mutex -SelectedIds @('M1','M2') -Context (New-TestContext) -ConflictPolicy Block
Assert-Phase4 ($px.MutexDecisions.Count -eq 1 -and $px.BlockedTweaks.Count -eq 2) 'mutexGroup com dois ativos exige decisao'

Write-Host "`n=== TEST 05: Windows / hardware / admin + propagacao ==="
$win=@((New-TestTweak -Id 'W11' -WindowsVersion @('11')))
$pw=New-WinSlimExecutionPlan -CatalogTweaks $win -SelectedIds @('W11') -Context (New-TestContext -OS '10')
Assert-Phase4 ((@($pw.SkippedTweaks | Where-Object { $_.ReasonCode -eq 'WindowsNotSupported' }).Count) -eq 1) 'tweak Win11 vira Skip no Windows 10'
$gpu=@((New-TestTweak -Id 'GPU' -HardwareRules ([PSCustomObject]@{ requiresGPU=$true; vendors=@('NVIDIA') })))
$pgBad=New-WinSlimExecutionPlan -CatalogTweaks $gpu -SelectedIds @('GPU') -Context (New-TestContext -GPU @('AMD Radeon Test'))
$pgGood=New-WinSlimExecutionPlan -CatalogTweaks $gpu -SelectedIds @('GPU') -Context (New-TestContext -GPU @('NVIDIA GeForce Test'))
Assert-Phase4 ($pgBad.ExecutionOrder.Count -eq 0 -and $pgBad.SkippedTweaks.Count -eq 1) 'hardwareRules rejeita fabricante de GPU incompatível'
Assert-Phase4 ($pgGood.ExecutionOrder.Count -eq 1) 'hardwareRules aceita fabricante de GPU compativel'
$admin=@((New-TestTweak -Id 'ADM' -RequiresAdmin $true))
$pa=New-WinSlimExecutionPlan -CatalogTweaks $admin -SelectedIds @('ADM') -Context (New-TestContext -IsAdmin $false)
Assert-Phase4 ((@($pa.BlockedTweaks | Where-Object { $_.ReasonCode -eq 'RequiresAdmin' }).Count) -eq 1) 'requiresAdmin bloqueia contexto nao elevado'
$depWin=@((New-TestTweak -Id 'DEP' -WindowsVersion @('11')),(New-TestTweak -Id 'ROOT' -Dependencies @('DEP')))
$pd=New-WinSlimExecutionPlan -CatalogTweaks $depWin -SelectedIds @('ROOT') -Context (New-TestContext -OS '10')
Assert-Phase4 ((@($pd.BlockedTweaks | Where-Object { $_.TweakId -eq 'ROOT' -and $_.ReasonCode -eq 'DependencyUnavailable' }).Count) -eq 1) 'dependencia Skip bloqueia o dependente'

Write-Host "`n=== TEST 06: preset + multilevel ==="
$levels=@([PSCustomObject]@{name='Base'},[PSCustomObject]@{name='Fast'},[PSCustomObject]@{name='Extreme'})
$ml=New-TestTweak -Id 'ML' -Type 'multilevel' -Levels $levels -PresetLevels ([PSCustomObject]@{ Balanceado=0; Gamer=1; Extremo=2 })
$simple=New-TestTweak -Id 'S' -Presets @('Gamer')
$pset=New-WinSlimExecutionPlan -CatalogTweaks @($ml,$simple) -PresetName 'Gamer' -Context (New-TestContext)
$mlItem=@($pset.ExecutionOrder | Where-Object { $_.TweakId -eq 'ML' })
Assert-Phase4 ($mlItem.Count -eq 1 -and [int]$mlItem[0].Level -eq 1) 'preset Gamer resolve nivel multilevel'
Assert-Phase4 ((@($pset.ExecutionOrder | Select-Object -ExpandProperty TweakId) -join ',') -eq 'ML,S') 'preset inclui multilevel + tweak simples'

Write-Host "`n=== TEST 07: risco + restart + snapshot imutavel ==="
$t1=New-TestTweak -Id 'LOW' -Risk 'Baixo'
$t2=New-TestTweak -Id 'HIGH' -Risk 'Alto' -RequiresRestart $true -RestartScope 'Reboot'
$pr=New-WinSlimExecutionPlan -CatalogTweaks @($t1,$t2) -SelectedIds @('LOW','HIGH') -Context (New-TestContext)
Assert-Phase4 ($pr.RiskSummary.Low -eq 1 -and $pr.RiskSummary.High -eq 1 -and $pr.RiskSummary.Highest -eq 'Alto') 'RiskSummary agrega Baixo/Alto'
Assert-Phase4 ($pr.RestartRequirements.Required -and $pr.RestartRequirements.RebootRequired -and ($pr.RestartRequirements.TweakIds -contains 'HIGH')) 'RestartRequirements agrega reboot'
$t1.name='MUTATED AFTER PLAN'
$planName=(@($pr.ExecutionOrder | Where-Object { $_.TweakId -eq 'LOW' })[0].Tweak.name)
Assert-Phase4 ($planName -ne 'MUTATED AFTER PLAN') 'ExecutionPlan guarda snapshot imutavel do tweak'

Write-Host "`n=== TEST 08: shape Planner -> Transaction Manager (NoPersist) ==="
$cat=@((New-TestTweak -Id 'B'),(New-TestTweak -Id 'A' -Dependencies @('B')))
$pi=New-WinSlimExecutionPlan -CatalogTweaks $cat -SelectedIds @('A') -Context (New-TestContext)
$items=@(Get-WinSlimTransactionItemsFromPlan -Plan $pi)
$apply={ param($Tweak,$Level,$Context) [PSCustomObject]@{ Success=$true; Changed=$true; StateBefore=[PSCustomObject]@{v=0}; StateAfter=[PSCustomObject]@{v=1}; Verification=[PSCustomObject]@{ Applicable=$true; Success=$true; Checks=@('synthetic') }; Restart='None'; Warning=$null; Error=$null } }
$backup={ param($Tweak,$Level,$Context,$Step) [PSCustomObject]@{ Synthetic=$true; TweakId=$Tweak.id; Value=0 } }
$tx=Invoke-TransactionPlan -Items $items -Context (New-TestContext) -NoPersist -ApplyHandler $apply -BackupHandler $backup
Assert-Phase4 ($tx.Status -eq 'Committed' -and $tx.Steps.Count -eq 2) 'ExecutionOrder e aceito diretamente por Invoke-TransactionPlan'
Assert-Phase4 ((@($tx.Steps | Select-Object -ExpandProperty TweakId) -join ',') -eq 'B,A') 'Transaction Manager recebe a ordem topologica do Planner'

Write-Host "`n=== TEST 09: catalogo real ==="
$catalogPath=Join-Path $TestsRoot 'catalog.json'
$real=(Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json).tweaks
$audit=Test-WinSlimPlannerCatalog -CatalogTweaks $real
Assert-Phase4 ($audit.Valid) 'catalog.json sem dependencias ausentes/IDs duplicados' $(if (-not $audit.Valid) { (@($audit.Issues | ForEach-Object { "$($_.Code):$($_.TweakId)->$($_.Reference)" }) -join '; ') } else { $null })
Assert-Phase4 (@($real).Count -eq 177) 'baseline R13 contem 177 entradas (174 + 3 pilotos)' "actual=$(@($real).Count)"
$realBal=New-WinSlimExecutionPlan -CatalogTweaks $real -PresetName 'Balanceado' -SkipApplicabilityChecks -ConflictPolicy Block
$realGam=New-WinSlimExecutionPlan -CatalogTweaks $real -PresetName 'Gamer' -SkipApplicabilityChecks -ConflictPolicy Block
$realExt=New-WinSlimExecutionPlan -CatalogTweaks $real -PresetName 'Extremo' -SkipApplicabilityChecks -ConflictPolicy Block
Assert-Phase4 ($realBal.CanExecute) 'preset Balanceado real nao possui conflito/mutex bloqueante no baseline'
Assert-Phase4 ($realGam.CanExecute) 'preset Gamer real nao possui conflito/mutex bloqueante no baseline'
$extPair=@($realExt.Conflicts | Where-Object { ($_.A -eq 'RESP-005' -and $_.B -eq 'RESP-006') -or ($_.A -eq 'RESP-006' -and $_.B -eq 'RESP-005') })
Assert-Phase4 (-not $realExt.CanExecute -and $extPair.Count -ge 1) 'Planner detecta conflito real RESP-005/RESP-006 no preset Extremo sem escolher silenciosamente'

Write-Host "`n=== RESUMO FASE 4 R1 ==="
if ($script:failures.Count -eq 0) {
    Write-Host 'FASE 4 R1 APROVADA - Planner passou em todos os cenarios do harness.' -ForegroundColor Green
    return
}
Write-Host "FASE 4 R1 REPROVADA - $($script:failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $script:failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1

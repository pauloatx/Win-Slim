$ErrorActionPreference = 'Stop'

$TestsRoot = Split-Path -Parent $PSScriptRoot
$ProviderContract = Join-Path $TestsRoot 'src\Core\ProviderContract.ps1'
$RegistryProvider = Join-Path $TestsRoot 'src\Providers\RegistryProvider.ps1'
$GameProvider = Join-Path $TestsRoot 'src\Providers\GamePriorityProvider.ps1'
$MmcssProvider = Join-Path $TestsRoot 'src\Providers\MmcssProvider.ps1'
$PlannerPath = Join-Path $TestsRoot 'src\Core\Planner.ps1'
$TransactionPath = Join-Path $TestsRoot 'src\Core\Transaction.ps1'

. $ProviderContract
. $RegistryProvider
. $GameProvider
. $MmcssProvider
. $PlannerPath

$script:failures = @()

function Assert-Fase5 {
    param([bool]$Condition, [string]$Message, [string]$Detail = $null)
    if ($Condition) {
        Write-Host "  [OK] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkYellow }
        $script:failures += $(if ($Detail) { "$Message :: $Detail" } else { $Message })
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function New-Fase5Context {
    return [PSCustomObject]@{
        OS='11'; Build='26100'; Architecture='AMD64'; CPU='Test CPU'; GPU=@('NVIDIA GeForce Test'); RAM=16; Storage='SSD'
        SecureBoot=[PSCustomObject]@{ Supported=$true; Enabled=$true }
        TPM=[PSCustomObject]@{ Present=$true; Ready=$true }
        VBS=$false; HVCI=$false
        HyperV=[PSCustomObject]@{ FeatureInstalled=$false; HypervisorRunning=$false; LaunchType='Off'; WSL2Detected=$false }
        PowerPlan='test'; NetworkAdapters=@('Ethernet'); Services=@(); PendingReboot=$false; IsAdmin=$true
    }
}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 5 R1 / Game-Workload Game+Workload'
Write-Host '============================================================'
Write-Host 'R1.1: correção do harness UTF-8/risco + módulo Game-Workload preservado'

Write-Host "`n=== TEST 00: baseline congelada + parser ==="
$expected = @{
    'src\Core\Transaction.ps1'='ecee3451af44cef809215d4a9045c2a81d7596e57062273e2860c00171f43619'
    'src\Core\Planner.ps1'='a27ab444744f3011d9ff7c539967c1d75bdcfdbf2a8a81ee2f03d56c48c81ce4'
    'src\Providers\RegistryProvider.ps1'='b01680f038d0eaa075680041ef76a48938bce412991d530fd8cabadf0186a90e'
}
foreach ($rel in $expected.Keys) {
    $actual = Get-Sha256 (Join-Path $TestsRoot $rel)
    Assert-Fase5 ($actual -eq $expected[$rel]) "baseline congelada: $rel" "expected=$($expected[$rel]); actual=$actual"
}
foreach ($f in @($GameProvider,$MmcssProvider)) {
    $tokens=$null; $errs=$null
    [System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errs) | Out-Null
    Assert-Fase5 (@($errs).Count -eq 0) "parser sem erros: $(Split-Path -Leaf $f)" $(if (@($errs).Count) { (@($errs | ForEach-Object { $_.Message }) -join '; ') } else { $null })
}

Write-Host "`n=== TEST 01: merge modular do catalogo ==="
$base = Get-JsonFile (Join-Path $TestsRoot 'catalog.json')
$tl = Get-JsonFile (Join-Path $TestsRoot 'catalogs\Game-Workload.json')
$combined = @($base.tweaks) + @($tl.tweaks)
Assert-Fase5 (@($base.tweaks).Count -eq 177) 'catalogo base Fase 4 preservado em 177 entradas' "actual=$(@($base.tweaks).Count)"
Assert-Fase5 (@($tl.tweaks).Count -eq 10 -and [int]$tl.count -eq 10) 'modulo Game-Workload contem 10 tweaks executaveis' "actual=$(@($tl.tweaks).Count)"
Assert-Fase5 ($combined.Count -eq 187) 'catalogo combinado chega a 187 entradas' "actual=$($combined.Count)"
$ids=@($combined | Select-Object -ExpandProperty id)
$dups=@($ids | Group-Object | Where-Object { $_.Count -gt 1 })
Assert-Fase5 ($dups.Count -eq 0) 'nenhum ID duplicado no merge base + Game-Workload' $(if ($dups.Count) { ($dups.Name -join ', ') } else { $null })
$audit=Test-WinSlimPlannerCatalog -CatalogTweaks $combined
Assert-Fase5 ($audit.Valid) 'Planner aceita catalogo combinado sem dependencias ausentes' $(if (-not $audit.Valid) { (@($audit.Issues | ForEach-Object { "$($_.Code):$($_.TweakId)->$($_.Reference)" }) -join '; ') } else { $null })

Write-Host "`n=== TEST 02: 5 perfis de jogos IFEO exatos ==="
$expectedGames = [ordered]@{
    'GAME-001'=@('VALORANT.exe','VALORANT-Win64-Shipping.exe')
    'GAME-002'=@('cs2.exe')
    'GAME-003'=@('r5apex.exe','r5apex_dx12.exe')
    'GAME-004'=@('FortniteClient-Win64-Shipping.exe','FortniteLauncher.exe')
    'GAME-005'=@('GTA5.exe','GTA5_Enhanced.exe')
}
foreach ($id in $expectedGames.Keys) {
    $t=@($tl.tweaks | Where-Object { $_.id -eq $id }) | Select-Object -First 1
    $got=@($t.registry | ForEach-Object { [regex]::Match([string]$_.Path,'Image File Execution Options\\([^\\]+)\\PerfOptions$').Groups[1].Value })
    $shapeOk = $t -and @($t.registry).Count -eq @($expectedGames[$id]).Count -and (-not (@($t.registry) | Where-Object { $_.Name -ne 'CpuPriorityClass' -or [int]$_.Value -ne 3 -or $_.Type -ne 'DWord' }))
    Assert-Fase5 ($shapeOk -and (($got -join '|') -eq (@($expectedGames[$id]) -join '|'))) "$id executaveis + CpuPriorityClass=3 exatos" "got=$($got -join ',')"
}

Write-Host "`n=== TEST 03: 4 perfis de workload IFEO exatos ==="
$expectedWork = [ordered]@{
    'WORK-001'=@('obs64.exe','obs32.exe','Streamlabs OBS.exe')
    'WORK-002'=@('Adobe Premiere Pro.exe','AfterFX.exe','Adobe Media Encoder.exe','Resolve.exe')
    'WORK-003'=@('Photoshop.exe','Illustrator.exe','Lightroom.exe','Figma.exe')
    'WORK-004'=@('Code.exe','idea64.exe','pycharm64.exe','rider64.exe','webstorm64.exe','goland64.exe')
}
foreach ($id in $expectedWork.Keys) {
    $t=@($tl.tweaks | Where-Object { $_.id -eq $id }) | Select-Object -First 1
    $got=@($t.registry | ForEach-Object { [regex]::Match([string]$_.Path,'Image File Execution Options\\([^\\]+)\\PerfOptions$').Groups[1].Value })
    $shapeOk = $t -and @($t.registry).Count -eq @($expectedWork[$id]).Count -and (-not (@($t.registry) | Where-Object { $_.Name -ne 'CpuPriorityClass' -or [int]$_.Value -ne 3 -or $_.Type -ne 'DWord' }))
    Assert-Fase5 ($shapeOk -and (($got -join '|') -eq (@($expectedWork[$id]) -join '|'))) "$id executaveis + CpuPriorityClass=3 exatos" "got=$($got -join ',')"
}

Write-Host "`n=== TEST 04: GamePriorityProvider - Apply/Undo exato em chave de teste ==="
$gpRoot='HKCU:\Software\WinSlimSuite\Tests\Fase5\IFEO'
Remove-Item 'HKCU:\Software\WinSlimSuite\Tests\Fase5' -Recurse -Force -ErrorAction SilentlyContinue
$existingPath="$gpRoot\existing.exe\PerfOptions"
New-Item -Path $existingPath -Force | Out-Null
New-ItemProperty -Path $existingPath -Name 'CpuPriorityClass' -PropertyType DWord -Value 1 -Force | Out-Null
$ga=Invoke-GamePriorityProvider -Id 'F5-GP' -Executables @('new.exe','existing.exe') -BasePath $gpRoot -Action Apply
$afterNew=(Get-ItemProperty "$gpRoot\new.exe\PerfOptions" -Name CpuPriorityClass).CpuPriorityClass
$afterExisting=(Get-ItemProperty $existingPath -Name CpuPriorityClass).CpuPriorityClass
Assert-Fase5 ($ga.Success -and $afterNew -eq 3 -and $afterExisting -eq 3) 'GamePriorityProvider aplica 3 em todos os executaveis'
$gu=Invoke-GamePriorityProvider -Id 'F5-GP' -Executables @('new.exe','existing.exe') -BasePath $gpRoot -Action Undo -BackupData $ga.StateBefore
$newExists=$false
try { $null=Get-ItemProperty "$gpRoot\new.exe\PerfOptions" -Name CpuPriorityClass -ErrorAction Stop; $newExists=$true } catch { $newExists=$false }
$existingRestored=(Get-ItemProperty $existingPath -Name CpuPriorityClass).CpuPriorityClass
Assert-Fase5 ($gu.Success -and -not $newExists -and $existingRestored -eq 1) 'GamePriorityProvider restaura ausencia + valor original exatamente' "newExists=$newExists; existing=$existingRestored"

Write-Host "`n=== TEST 05: MMCSS Provider - 8/6/High/High + Undo exato ==="
$mmPath='HKCU:\Software\WinSlimSuite\Tests\Fase5\MMCSS\Tasks\Games'
New-Item -Path $mmPath -Force | Out-Null
New-ItemProperty -Path $mmPath -Name 'Priority' -PropertyType DWord -Value 4 -Force | Out-Null
$ma=Invoke-MmcssGamesProvider -Id 'F5-MMCSS' -GamesPath $mmPath -Action Apply
$mm=Get-ItemProperty -Path $mmPath
$mmApplyOk=($mm.'GPU Priority' -eq 8 -and $mm.Priority -eq 6 -and $mm.'Scheduling Category' -eq 'High' -and $mm.'SFIO Priority' -eq 'High')
Assert-Fase5 ($ma.Success -and $mmApplyOk) 'MMCSS Provider aplica 8/6/High/High'
$mu=Invoke-MmcssGamesProvider -Id 'F5-MMCSS' -GamesPath $mmPath -Action Undo -BackupData $ma.StateBefore
$mm2=Get-ItemProperty -Path $mmPath
$gpExists=($mm2.PSObject.Properties.Name -contains 'GPU Priority')
$scExists=($mm2.PSObject.Properties.Name -contains 'Scheduling Category')
$sfExists=($mm2.PSObject.Properties.Name -contains 'SFIO Priority')
Assert-Fase5 ($mu.Success -and $mm2.Priority -eq 4 -and -not $gpExists -and -not $scExists -and -not $sfExists) 'MMCSS Provider restaura valor existente e remove valores originalmente ausentes'
Remove-Item 'HKCU:\Software\WinSlimSuite\Tests\Fase5' -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== TEST 06: deduplicacao referência técnica -> catalogo existente ==="
$perf006=@($base.tweaks | Where-Object { $_.id -eq 'PERF-006' })[0]
$perf012=@($base.tweaks | Where-Object { $_.id -eq 'PERF-012' })[0]
$extra005=@($base.tweaks | Where-Object { $_.id -eq 'EXTRA-005' })[0]
Assert-Fase5 ([int]$perf006.registry[0].Value -eq 38) 'PERF-006 ja cobre referência técnica Win32PrioritySeparation=0x26/38'
Assert-Fase5 ([int]$perf012.registry[0].Value -eq 10) 'PERF-012 ja cobre referência técnica SystemResponsiveness=10'
Assert-Fase5 ([int]$extra005.registry[0].Value -eq 0 -and @($extra005.conflicts) -contains 'PERF-012' -and $extra005.mutexGroup -eq 'SYSTEM_RESPONSIVENESS') 'EXTRA-005=0 permanece alternativa agressiva e conflitante, sem substituir perfil referência técnica=10'

Write-Host "`n=== TEST 07: MMCSS catalogo exato + manual-only ==="
$mmT=@($tl.tweaks | Where-Object { $_.id -eq 'PERF-019' })[0]
$mmMap=@{}
foreach($r in @($mmT.registry)){ $mmMap[$r.Name]=$r.Value }
Assert-Fase5 (@($mmT.registry).Count -eq 4 -and [int]$mmMap['GPU Priority'] -eq 8 -and [int]$mmMap['Priority'] -eq 6 -and $mmMap['Scheduling Category'] -eq 'High' -and $mmMap['SFIO Priority'] -eq 'High') 'PERF-019 registra MMCSS 8/6/High/High sem divergencia'
$newPresetLeaks=@($tl.tweaks | Where-Object { @($_.presets).Count -gt 0 })
Assert-Fase5 ($newPresetLeaks.Count -eq 0) 'novos Seal ficam fora dos presets ate a Fase 6' $(if ($newPresetLeaks.Count) { ($newPresetLeaks.id -join ',') } else { $null })

Write-Host "`n=== TEST 08: specs avancadas ficam fora do catalogo executavel ==="
$adv=Get-JsonFile (Join-Path $TestsRoot 'specs\Workload-advanced-pending.json')
$cp=@($adv.items | Where-Object { $_.id -eq 'WS-ADV-001' })[0]
$cs=@($adv.items | Where-Object { $_.id -eq 'WS-ADV-002' })[0]
$gpu=@($adv.items | Where-Object { $_.id -eq 'WS-ADV-003' })[0]
Assert-Fase5 ($cp.subgroupGuid -eq '54533251-82be-4824-96c1-47b60b740d00' -and $cp.settingGuid -eq '0cc5b647-c1df-4637-891a-dec35c318583' -and [int]$cp.targetAC -eq 100 -and [int]$cp.targetDC -eq 100) 'Core Parking spec preserva GUIDs + AC/DC=100'
Assert-Fase5 ($cs.topologyApi -eq 'GetLogicalProcessorInformationEx(RelationProcessorCore)' -and $cs.pCoreRule -eq 'EfficiencyClass >= 1' -and $cs.process -eq 'cs2.exe') 'CS2 P-core spec preserva API/topologia/criterio exatos'
Assert-Fase5 ([int]$gpu.precondition.minLogicalProcessors -eq 8 -and $gpu.devicePolicy.value -eq 4 -and $gpu.assignmentSetOverride.observedTlMaskHex -eq '0x14' -and (($gpu.assignmentSetOverride.observedBits -join ',') -eq '2,4')) 'GPU IRQ spec registra precondicao + DevicePolicy=4 + mascara observada 0x14'
$advIds=@($adv.items | Select-Object -ExpandProperty id)
$leaked=@($combined | Where-Object { $advIds -contains $_.id })
Assert-Fase5 ($leaked.Count -eq 0) 'afinidade/core-parking ainda nao sao expostos antes dos Providers dedicados'

Write-Host "`n=== TEST 09: Planner aceita novos tweaks e mantem decisao manual ==="
$plan=New-WinSlimExecutionPlan -CatalogTweaks $combined -SelectedIds @('GAME-002','PERF-019') -Context (New-Fase5Context) -ConflictPolicy Block
$pids=@($plan.ExecutionOrder | Select-Object -ExpandProperty TweakId)
Assert-Fase5 ($plan.CanExecute -and (($pids -join ',') -eq 'GAME-002,PERF-019')) 'Planner produz plano executavel deterministico para CS2 + MMCSS' ($pids -join ',')
$riskDetail = "Low=$($plan.RiskSummary.Low); Medium=$($plan.RiskSummary.Medium); High=$($plan.RiskSummary.High); Highest='$($plan.RiskSummary.Highest)'; HighestRank=$(Get-WinSlimPlannerRiskRank $plan.RiskSummary.Highest)"
Assert-Fase5 ($plan.RiskSummary.Medium -eq 2 -and (Get-WinSlimPlannerRiskRank $plan.RiskSummary.Highest) -eq 2) 'Planner agrega risco Médio dos dois novos tweaks' $riskDetail
Assert-Fase5 ($plan.RestartRequirements.Required -and -not $plan.RestartRequirements.RebootRequired -and $plan.RestartRequirements.Scopes -contains 'ProcessRestart') 'Planner sinaliza reinicio de processo, nao reboot do Windows'

Write-Host "`n=== TEST 10: shape para Transaction Manager (sem mutar Windows) ==="
. $TransactionPath
$items=@(Get-WinSlimTransactionItemsFromPlan -Plan $plan)
$apply={ param($Tweak,$Level,$Context) [PSCustomObject]@{ Success=$true; Changed=$true; StateBefore=[PSCustomObject]@{v=0}; StateAfter=[PSCustomObject]@{v=1}; Verification=[PSCustomObject]@{ Applicable=$true; Success=$true; Checks=@('synthetic') }; Restart=$Tweak.restartScope; Warning=$null; Error=$null } }
$backup={ param($Tweak,$Level,$Context,$Step) [PSCustomObject]@{ Synthetic=$true; TweakId=$Tweak.id; Value=0 } }
$tx=Invoke-TransactionPlan -Items $items -Context (New-Fase5Context) -NoPersist -ApplyHandler $apply -BackupHandler $backup
Assert-Fase5 ($tx.Status -eq 'Committed' -and $tx.Steps.Count -eq 2) 'Transaction Manager R13 aceita itens do modulo Game-Workload via Planner'
Assert-Fase5 ((@($tx.Steps | Select-Object -ExpandProperty TweakId) -join ',') -eq 'GAME-002,PERF-019') 'ordem Planner -> Transaction preservada'

Write-Host "`n=== RESUMO FASE 5 R1.1 ==="
if ($script:failures.Count -eq 0) {
    Write-Host 'FASE 5 R1.1 APROVADA - Seal Game+Workload passou em todos os gates do harness.' -ForegroundColor Green
    Write-Host 'Proximo subgate: FASE 5 R2 - CoreParkingProvider + CpuAffinityProvider + GpuInterruptAffinityProvider.' -ForegroundColor Cyan
    return
}
Write-Host "FASE 5 R1.1 REPROVADA - $($script:failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $script:failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1

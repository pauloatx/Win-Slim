$ErrorActionPreference = 'Stop'

$TestsRoot = Split-Path -Parent $PSScriptRoot
$ProviderContract = Join-Path $TestsRoot 'src\Core\ProviderContract.ps1'
$RegistryProvider = Join-Path $TestsRoot 'src\Providers\RegistryProvider.ps1'
$PowerCfgProvider = Join-Path $TestsRoot 'src\Providers\PowerCfgProvider.ps1'
$ScheduledTaskProvider = Join-Path $TestsRoot 'src\Providers\ScheduledTaskProvider.ps1'
$CoreParkingProvider = Join-Path $TestsRoot 'src\Providers\CoreParkingProvider.ps1'
$CpuAffinityProvider = Join-Path $TestsRoot 'src\Providers\CpuAffinityProvider.ps1'
$GpuIrqProvider = Join-Path $TestsRoot 'src\Providers\GpuInterruptAffinityProvider.ps1'
$BridgePath = Join-Path $TestsRoot 'src\Core\AdvancedProviderBridge.ps1'
$PlannerPath = Join-Path $TestsRoot 'src\Core\Planner.ps1'
$TransactionPath = Join-Path $TestsRoot 'src\Core\Transaction.ps1'

. $ProviderContract
. $RegistryProvider
. $PowerCfgProvider
. $ScheduledTaskProvider
. $PlannerPath
. $TransactionPath

$script:failures=@()
function Assert-Fase5R3 {
    param([bool]$Condition,[string]$Message,[string]$Detail=$null)
    if($Condition){ Write-Host "  [OK] $Message" -ForegroundColor Green }
    else { Write-Host "  [FAIL] $Message" -ForegroundColor Red; if($Detail){Write-Host "         $Detail" -ForegroundColor DarkYellow}; $script:failures += $(if($Detail){"$Message :: $Detail"}else{$Message}) }
}
function Get-Sha256 { param([string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-Json { param([string]$Path) Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Get-AllCatalogTweaks {
    $out=@()
    foreach($f in @('catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json')){
        $d=Get-Json (Join-Path $TestsRoot $f)
        $out += @($d.tweaks)
    }
    return @($out)
}
function New-HybridTopology {
    [PSCustomObject]@{
        Cores=@(
            [PSCustomObject]@{EfficiencyClass=8;Group=0;Mask=[UInt64]0x3},
            [PSCustomObject]@{EfficiencyClass=8;Group=0;Mask=[UInt64]0xC},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x10},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x20},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x40},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x80}
        ); Groups=@(0); EfficiencyClasses=@(0,8); LogicalProcessorCount=8; PhysicalCoreEntries=6; IsHybrid=$true; SingleProcessorGroup=$true; Api='synthetic'
    }
}
function New-SmtTopology {
    [PSCustomObject]@{
        Cores=@(
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x03},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x0C},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x30},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0xC0}
        ); Groups=@(0); EfficiencyClasses=@(0); LogicalProcessorCount=8; PhysicalCoreEntries=4; IsHybrid=$false; SingleProcessorGroup=$true; Api='synthetic'
    }
}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 5 R3.3 / Catalog Promotion'
Write-Host '============================================================'
Write-Host 'R3.3: handlers closure-free PS5.1-safe + context runtime + rollback transacional real'

Write-Host "`n=== TEST 00: baseline R2.1 congelada + parser do bridge ==="
$expected=@{
    'src\Core\Transaction.ps1'='ecee3451af44cef809215d4a9045c2a81d7596e57062273e2860c00171f43619'
    'src\Core\Planner.ps1'='a27ab444744f3011d9ff7c539967c1d75bdcfdbf2a8a81ee2f03d56c48c81ce4'
    'src\Providers\RegistryProvider.ps1'='b01680f038d0eaa075680041ef76a48938bce412991d530fd8cabadf0186a90e'
    'src\Providers\PowerCfgProvider.ps1'='75109f2e5a8fee29ebe7a28e1aeaa0f5052d849a0814c9dfefe0ce5025ab1764'
    'src\Providers\ScheduledTaskProvider.ps1'='b1866212cedbf855df9e05dc54223a2223eb9c320a97357dc43d4ad0bad7b179'
    'src\Providers\CoreParkingProvider.ps1'='8b40540706ce36ec9cd7b282b60919ad015859f422b4a1ac286951ee7b3866c9'
    'src\Providers\CpuAffinityProvider.ps1'='02b9b38ab406ae07980346c5e32e041c7de3f6c36dff4dc32755e444efd7a424'
    'src\Providers\GpuInterruptAffinityProvider.ps1'='f496ee289c213cbafb8f28ebb769e6b23dc97ce31e4d55cc3f00d4e19187f41f'
    'catalogs\Game-Workload.json'='19e5d57eb6ac7501ef5fc782445a44bc1bc5aaf6a59100ae45639aea7e25079d'
}
foreach($rel in $expected.Keys){ $actual=Get-Sha256 (Join-Path $TestsRoot $rel); Assert-Fase5R3 ($actual -eq $expected[$rel]) "baseline R2.1 congelada: $rel" "expected=$($expected[$rel]); actual=$actual" }
$tokens=$null;$errs=$null
[System.Management.Automation.Language.Parser]::ParseFile($BridgePath,[ref]$tokens,[ref]$errs)|Out-Null
Assert-Fase5R3 (@($errs).Count -eq 0) 'AdvancedProviderBridge.ps1 sem erros de parser' $(if(@($errs).Count){(@($errs|ForEach-Object{$_.Message}) -join '; ')}else{$null})
if($script:failures.Count -gt 0){ Write-Host 'PRE-FLIGHT R3 FALHOU.' -ForegroundColor Red; exit 1 }
. $CoreParkingProvider
. $CpuAffinityProvider
. $GpuIrqProvider
. $BridgePath

Write-Host "`n=== TEST 01: promoção modular 177 + 10 + 3 = 190 ==="
$base=Get-Json (Join-Path $TestsRoot 'catalog.json')
$tl=Get-Json (Join-Path $TestsRoot 'catalogs\Game-Workload.json')
$adv=Get-Json (Join-Path $TestsRoot 'catalogs\validated\Advanced-Catalog.json')
$all=Get-AllCatalogTweaks
Assert-Fase5R3 (@($base.tweaks).Count -eq 177) 'catálogo base permanece com 177 entradas'
Assert-Fase5R3 (@($tl.tweaks).Count -eq 10) 'Game-Workload R1.1 permanece com 10 entradas'
Assert-Fase5R3 (@($adv.tweaks).Count -eq 3 -and [int]$adv.count -eq 3) 'módulo Advanced promove exatamente 3 entradas'
Assert-Fase5R3 (@($all).Count -eq 190) 'catálogo backend validado chega a 190 entradas'
$dups=@($all | Group-Object id | Where-Object{$_.Count -gt 1})
Assert-Fase5R3 ($dups.Count -eq 0) 'nenhum ID duplicado em base + Game-Workload + Advanced'

Write-Host "`n=== TEST 02: metadados e roteamento exatos dos 3 avançados ==="
$a1=@($adv.tweaks|Where-Object{$_.id -eq 'WS-ADV-001'})[0]
$a2=@($adv.tweaks|Where-Object{$_.id -eq 'WS-ADV-002'})[0]
$a3=@($adv.tweaks|Where-Object{$_.id -eq 'WS-ADV-003'})[0]
Assert-Fase5R3 ($a1.provider.name -eq 'CoreParkingProvider' -and $a1.provider.entryPoint -eq 'Invoke-CoreParkingProvider' -and [int]$a1.provider.arguments.TargetAc -eq 100 -and [int]$a1.provider.arguments.TargetDc -eq 100) 'WS-ADV-001 roteia CoreParking 100/100'
Assert-Fase5R3 ($a2.provider.name -eq 'CpuAffinityProvider' -and $a2.provider.arguments.ProcessName -eq 'cs2.exe' -and $a2.provider.arguments.TaskName -eq 'WinSlimSuite-AffinityCs2') 'WS-ADV-002 roteia CS2 P-core dinamicamente'
Assert-Fase5R3 ($a3.provider.name -eq 'GpuInterruptAffinityProvider' -and [bool]$a3.hardwareRules.requiresGPU -and $a3.restartScope -eq 'Reboot') 'WS-ADV-003 roteia GPU IRQ + requiresGPU + reboot'
Assert-Fase5R3 (@($adv.tweaks|Where-Object{@($_.presets).Count -gt 0}).Count -eq 0) 'avançados continuam fora dos presets até a Fase 6'
Assert-Fase5R3 (@($adv.tweaks|Where-Object{$_.uiAvailability -ne 'Phase7'}).Count -eq 0) 'avançados ficam ocultos da UI legada até integração transacional da Fase 7'

Write-Host "`n=== TEST 03: Planner aceita os 3 avançados sem conflito estrutural ==="
$ctx=[PSCustomObject]@{OS='11';IsAdmin=$true;GPU=@('NVIDIA GeForce RTX 3080 Ti');RAM=16;Storage='SSD';NetworkAdapters=@('Ethernet');CPU='Synthetic Hybrid'}
$plan=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('WS-ADV-001','WS-ADV-002','WS-ADV-003') -Context $ctx
Assert-Fase5R3 ($plan.CanExecute -and @($plan.ExecutionOrder).Count -eq 3) 'Planner gera plano executável determinístico para os 3 avançados'
Assert-Fase5R3 (@($plan.BlockedTweaks).Count -eq 0 -and @($plan.SkippedTweaks).Count -eq 0) 'nenhum avançado é bloqueado no contexto compatível'
Assert-Fase5R3 ($plan.RestartRequirements.Required -and @($plan.RestartRequirements.Scopes) -contains 'Reboot') 'Planner agrega reboot exigido pelo GPU IRQ'
$ctxNoGpu=[PSCustomObject]@{OS='11';IsAdmin=$true;GPU=@();RAM=16;Storage='SSD';NetworkAdapters=@();CPU='Synthetic'}
$planNoGpu=New-WinSlimExecutionPlan -CatalogTweaks $all -SelectedIds @('WS-ADV-003') -Context $ctxNoGpu
Assert-Fase5R3 (@($planNoGpu.SkippedTweaks|Where-Object{$_.TweakId -eq 'WS-ADV-003'}).Count -eq 1) 'Planner faz SKIP do GPU IRQ quando nenhuma GPU é detectada'

Write-Host "`n=== TEST 04: bridge CoreParking - backup pre-apply + Apply/Undo ==="
$script:r3CpAc=25;$script:r3CpDc=50
$cpReader={param($Sub,$Set)[PSCustomObject]@{AC=$script:r3CpAc;DC=$script:r3CpDc;Queryable=$true}}
$cpWriter={param($Sub,$Set,$Ac,$Dc)$script:r3CpAc=[int]$Ac;$script:r3CpDc=[int]$Dc}
$cpArgs=@{StateReader=$cpReader;StateWriter=$cpWriter}
$cpBackup=Get-WinSlimAdvancedProviderBackup -Tweak $a1 -AdditionalArguments $cpArgs
$cpApply=Invoke-WinSlimAdvancedProvider -Tweak $a1 -Action Apply -AdditionalArguments $cpArgs
$cpUndo=Invoke-WinSlimAdvancedProvider -Tweak $a1 -Action Undo -BackupData $cpBackup -AdditionalArguments $cpArgs
Assert-Fase5R3 ([int]$cpBackup.AC -eq 25 -and [int]$cpBackup.DC -eq 50) 'bridge captura CoreParking original antes do Apply'
Assert-Fase5R3 ($cpApply.Success -and $cpUndo.Success -and $script:r3CpAc -eq 25 -and $script:r3CpDc -eq 50) 'bridge aplica 100/100 e restaura 25/50 exatamente'

Write-Host "`n=== TEST 05: bridge CpuAffinity - backup pre-apply + Apply/Undo ==="
$hybrid=New-HybridTopology
$script:r3Task=[PSCustomObject]@{TaskName='WinSlimSuite-AffinityCs2';TaskPath='\';Exists=$true;State='Ready';Xml='<Task>ORIGINAL</Task>'}
$script:r3File=[PSCustomObject]@{Path='X:\affinity-cs2.ps1';Exists=$true;Bytes=[byte[]](7,8,9)}
$script:r3Proc=@([PSCustomObject]@{Id=5001;Affinity=[Int64]255})
$adapter=[PSCustomObject]@{
 GetTaskState={param($TaskName)[PSCustomObject]@{TaskName=$script:r3Task.TaskName;TaskPath='\';Exists=[bool]$script:r3Task.Exists;State=$script:r3Task.State;Xml=$script:r3Task.Xml}}
 RegisterTask={param($TaskName,$Xml)$script:r3Task=[PSCustomObject]@{TaskName=$TaskName;TaskPath='\';Exists=$true;State='Ready';Xml=[string]$Xml}}
 RestoreTask={param($State)$script:r3Task=[PSCustomObject]@{TaskName=$State.TaskName;TaskPath=$State.TaskPath;Exists=[bool]$State.Exists;State=$State.State;Xml=$State.Xml}}
 GetFileState={param($Path)[PSCustomObject]@{Path=$script:r3File.Path;Exists=[bool]$script:r3File.Exists;Bytes=$(if($script:r3File.Bytes){[byte[]]$script:r3File.Bytes.Clone()}else{$null})}}
 WriteFile={param($Path,$Text)$script:r3File=[PSCustomObject]@{Path=$Path;Exists=$true;Bytes=[Text.Encoding]::UTF8.GetBytes([string]$Text)}}
 RestoreFile={param($State)$script:r3File=[PSCustomObject]@{Path=$State.Path;Exists=[bool]$State.Exists;Bytes=$(if($State.Bytes){[byte[]]$State.Bytes.Clone()}else{$null})}}
 GetProcesses={param($ProcessName)@($script:r3Proc|ForEach-Object{[PSCustomObject]@{Id=[int]$_.Id;Affinity=[Int64]$_.Affinity}})}
 SetProcessAffinity={param($ProcessId,$Mask)foreach($p in $script:r3Proc){if($p.Id -eq [int]$ProcessId){$p.Affinity=[Int64]$Mask}}}
}
$cpuArgs=@{Topology=$hybrid;Adapter=$adapter;ScriptPath='X:\affinity-cs2.ps1'}
$cpuBackup=Get-WinSlimAdvancedProviderBackup -Tweak $a2 -AdditionalArguments $cpuArgs
$cpuApply=Invoke-WinSlimAdvancedProvider -Tweak $a2 -Action Apply -AdditionalArguments $cpuArgs
$cpuUndo=Invoke-WinSlimAdvancedProvider -Tweak $a2 -Action Undo -BackupData $cpuBackup -AdditionalArguments $cpuArgs
Assert-Fase5R3 ($cpuBackup.Applicable -and [UInt64]$cpuBackup.Mask -eq [UInt64]0xF -and [Int64]$cpuBackup.Processes[0].Affinity -eq 255) 'bridge captura tarefa/script/processo e máscara P-core antes do Apply'
Assert-Fase5R3 ($cpuApply.Success -and [Int64]$cpuApply.StateBefore.Mask -eq 15) 'bridge executa CpuAffinityProvider com máscara 0xF'
Assert-Fase5R3 ($cpuUndo.Success -and $script:r3Task.Xml -eq '<Task>ORIGINAL</Task>' -and [Int64]$script:r3Proc[0].Affinity -eq 255 -and ([Convert]::ToBase64String($script:r3File.Bytes) -eq [Convert]::ToBase64String([byte[]](7,8,9)))) 'bridge Undo restaura tarefa, worker e afinidade original'

Write-Host "`n=== TEST 06: bridge GPU IRQ - backup pre-apply + rollback byte-a-byte em HKCU ==="
$gpuRoot='HKCU:\Software\WinSlimSuite\Tests\Fase5R3Gpu'
Remove-Item -Path $gpuRoot -Recurse -Force -ErrorAction SilentlyContinue
$gpuIds=@('PCI\VEN_TEST&DEV_0001','PCI\VEN_TEST&DEV_0002')
$p1=Get-WinSlimGpuAffinityPath -RegistryRoot $gpuRoot -InstanceId $gpuIds[0]
New-Item -Path $p1 -Force | Out-Null
New-ItemProperty -Path $p1 -Name 'DevicePolicy' -PropertyType DWord -Value 2 -Force | Out-Null
New-ItemProperty -Path $p1 -Name 'AssignmentSetOverride' -PropertyType Binary -Value ([byte[]](1,2,3,4,5,6,7,8)) -Force | Out-Null
$gpuArgs=@{Topology=(New-SmtTopology);InstanceIds=$gpuIds;RegistryRoot=$gpuRoot}
$gpuBackup=@(Get-WinSlimAdvancedProviderBackup -Tweak $a3 -AdditionalArguments $gpuArgs)
$gpuApply=Invoke-WinSlimAdvancedProvider -Tweak $a3 -Action Apply -AdditionalArguments $gpuArgs
$gpuUndo=Invoke-WinSlimAdvancedProvider -Tweak $a3 -Action Undo -BackupData $gpuBackup -AdditionalArguments $gpuArgs
$orig1=Get-RegistryState -Path $p1 -Name 'DevicePolicy'
$origMask=Get-RegistryState -Path $p1 -Name 'AssignmentSetOverride'
$p2=Get-WinSlimGpuAffinityPath -RegistryRoot $gpuRoot -InstanceId $gpuIds[1]
$abs2=Get-RegistryState -Path $p2 -Name 'DevicePolicy'
Assert-Fase5R3 ($gpuBackup.Count -eq 2 -and $gpuApply.Success) 'bridge captura duas GPUs sintéticas e aplica política derivada da topologia'
Assert-Fase5R3 ($gpuUndo.Success -and [int]$orig1.Value -eq 2 -and (Test-WinSlimByteArrayEqual $origMask.Value ([byte[]](1,2,3,4,5,6,7,8))) -and -not $abs2.Exists) 'bridge GPU Undo restaura bytes existentes e remove valores originalmente ausentes'
Remove-Item -Path $gpuRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== TEST 07: Transaction Manager usa backup do bridge antes do Apply e rollback LIFO ==="
# R3.2: estado sintetico transportado por referencias mutaveis no Context.
# Isto evita o falso negativo da R3/R3.1 causado por estado $script: atravessando
# closures aninhadas no Windows PowerShell 5.1.
$txCpState=[ordered]@{AC=30;DC=40}
$txCpReader={
 param($Sub,$Set)
 [PSCustomObject]@{AC=[int]$txCpState['AC'];DC=[int]$txCpState['DC'];Queryable=$true}
}.GetNewClosure()
$txCpWriter={
 param($Sub,$Set,$Ac,$Dc)
 $txCpState['AC']=[int]$Ac
 $txCpState['DC']=[int]$Dc
}.GetNewClosure()

$txCpuState=[ordered]@{
 Task=[PSCustomObject]@{TaskName='WinSlimSuite-AffinityCs2';TaskPath='\';Exists=$false;State=$null;Xml=$null}
 File=[PSCustomObject]@{Path='X:\tx-affinity.ps1';Exists=$false;Bytes=$null}
 Processes=@([PSCustomObject]@{Id=6001;Affinity=[Int64]255})
}
$txAdapter=[PSCustomObject]@{
 GetTaskState={
  param($TaskName)
  $t=$txCpuState['Task']
  [PSCustomObject]@{TaskName=$TaskName;TaskPath='\';Exists=[bool]$t.Exists;State=$t.State;Xml=$t.Xml}
 }.GetNewClosure()
 RegisterTask={
  param($TaskName,$Xml)
  $txCpuState['Task']=[PSCustomObject]@{TaskName=$TaskName;TaskPath='\';Exists=$true;State='Ready';Xml=[string]$Xml}
 }.GetNewClosure()
 RestoreTask={
  param($State)
  $txCpuState['Task']=[PSCustomObject]@{TaskName=$State.TaskName;TaskPath=$State.TaskPath;Exists=[bool]$State.Exists;State=$State.State;Xml=$State.Xml}
 }.GetNewClosure()
 GetFileState={
  param($Path)
  $f=$txCpuState['File']
  [PSCustomObject]@{Path=$f.Path;Exists=[bool]$f.Exists;Bytes=$(if($f.Bytes){[byte[]]$f.Bytes.Clone()}else{$null})}
 }.GetNewClosure()
 WriteFile={
  param($Path,$Text)
  $txCpuState['File']=[PSCustomObject]@{Path=$Path;Exists=$true;Bytes=[Text.Encoding]::UTF8.GetBytes([string]$Text)}
 }.GetNewClosure()
 RestoreFile={
  param($State)
  $txCpuState['File']=[PSCustomObject]@{Path=$State.Path;Exists=[bool]$State.Exists;Bytes=$(if($State.Bytes){[byte[]]$State.Bytes.Clone()}else{$null})}
 }.GetNewClosure()
 GetProcesses={
  param($ProcessName)
  @($txCpuState['Processes']|ForEach-Object{[PSCustomObject]@{Id=[int]$_.Id;Affinity=[Int64]$_.Affinity}})
 }.GetNewClosure()
 SetProcessAffinity={
  param($ProcessId,$Mask)
  foreach($p in @($txCpuState['Processes'])){if($p.Id -eq [int]$ProcessId){$p.Affinity=[Int64]$Mask}}
 }.GetNewClosure()
}

$txContext=[PSCustomObject]@{
 AdvancedProviderArguments=@{
  'WS-ADV-001'=@{StateReader=$txCpReader;StateWriter=$txCpWriter}
  'WS-ADV-002'=@{Topology=$hybrid;Adapter=$txAdapter;ScriptPath='X:\tx-affinity.ps1'}
 }
}

# Gate de wiring antes da transacao: o bridge deve recuperar os argumentos pelo Context.
$ctxCpArgs=Get-WinSlimAdvancedContextArguments -Context $txContext -TweakId 'WS-ADV-001' -Stage 'Backup'
$ctxCpuArgs=Get-WinSlimAdvancedContextArguments -Context $txContext -TweakId 'WS-ADV-002' -Stage 'Apply'
Assert-Fase5R3 ($ctxCpArgs -and $ctxCpArgs.StateReader -and $ctxCpArgs.StateWriter -and $ctxCpuArgs -and $ctxCpuArgs.Adapter) 'bridge resolve argumentos advanced pelo Context sem closure resolver aninhada'

$failTweak=[PSCustomObject]@{id='F5R3-FAIL';type='synthetic';name='falha sintetica';restartScope='None'}
$fallbackBackup={param($Tweak,$Level,$Context,$Step)[PSCustomObject]@{Marker='before'}}
$fallbackApply={param($Tweak,$Level,$Context)[PSCustomObject]@{Id=$Tweak.id;Action='Apply';Success=$false;Changed=$false;StateBefore=$null;StateAfter=$null;Verification=[PSCustomObject]@{Applicable=$true;Success=$false;Checks=@([PSCustomObject]@{Type='Synthetic';Target='fail';Expected='pass';Actual='fail';Pass=$false})};Restart='None';Warning=$null;Error='falha sintetica esperada'}}
$fallbackUndo={param($Tweak,$Level,$Context,$BackupData,$Step)[PSCustomObject]@{Id=$Tweak.id;Action='Undo';Success=$true;Changed=$false;Verification=[PSCustomObject]@{Applicable=$true;Success=$true;Checks=@([PSCustomObject]@{Type='Synthetic';Target='undo';Expected='pass';Actual='pass';Pass=$true})};Restart='None';Warning=$null;Error=$null}}
$handlers=New-WinSlimAdvancedTransactionHandlers -Context $txContext -FallbackApplyHandler $fallbackApply -FallbackBackupHandler $fallbackBackup -FallbackUndoHandler $fallbackUndo
Assert-Fase5R3 ($handlers.Mode -eq 'ContextBoundStatic') 'handlers advanced usam dispatch estatico/context-bound sem GetNewClosure'
$handlerProbe=& $handlers.Backup $a1 -1 $txContext $null
Assert-Fase5R3 ($handlerProbe -and [int]$handlerProbe.AC -eq 30 -and [int]$handlerProbe.DC -eq 40) 'BackupHandler acessa helpers do bridge quando invocado como ScriptBlock pelo caller'
$tx=Invoke-TransactionPlan -Items @($a1,$a2,$failTweak) -Context $txContext -FailurePolicy RollbackTransaction -NoPersist -ApplyHandler $handlers.Apply -BackupHandler $handlers.Backup -UndoHandler $handlers.Undo

Assert-Fase5R3 ($tx.Status -eq 'RolledBack' -and $tx.Failure -and [string]$tx.Failure.TweakId -eq 'F5R3-FAIL') 'falha ocorre somente no terceiro passo sintetico e dispara rollback'
$txTask=$txCpuState['Task'];$txFile=$txCpuState['File'];$txProc=@($txCpuState['Processes'])
Assert-Fase5R3 ([int]$txCpState['AC'] -eq 30 -and [int]$txCpState['DC'] -eq 40 -and -not [bool]$txTask.Exists -and -not [bool]$txFile.Exists -and [Int64]$txProc[0].Affinity -eq 255) 'rollback usa snapshots pre-apply do bridge e restaura estados originais'

$rolledCp=@($tx.Steps|Where-Object{[string]$_.TweakId -eq 'WS-ADV-001'}|Select-Object -Last 1)
$rolledCpu=@($tx.Steps|Where-Object{[string]$_.TweakId -eq 'WS-ADV-002'}|Select-Object -Last 1)
$rolledOk=($rolledCp.Count -eq 1 -and $rolledCpu.Count -eq 1 -and
    [bool]$rolledCp[0].Changed -and [bool]$rolledCpu[0].Changed -and
    [string]$rolledCp[0].RollbackStatus -eq 'RolledBack' -and
    [string]$rolledCpu[0].RollbackStatus -eq 'RolledBack' -and
    [string]$rolledCp[0].Status -eq 'RolledBack' -and
    [string]$rolledCpu[0].Status -eq 'RolledBack')
if(-not $rolledOk){
    Write-Host '  [DEBUG] Steps apos rollback:' -ForegroundColor DarkYellow
    foreach($s in @($tx.Steps)){
        $applyErr=$null
        try { $applyErr=$s.ApplyResult.Error } catch { }
        Write-Host ("          Seq={0}; Id={1}; Changed={2}; Status={3}; RollbackStatus={4}; Error={5}; ApplyError={6}" -f $s.Sequence,$s.TweakId,$s.Changed,$s.Status,$s.RollbackStatus,$s.Error,$applyErr) -ForegroundColor DarkYellow
    }
}
Assert-Fase5R3 $rolledOk 'Transaction Manager registra os dois advanced aplicados como Changed=true e RolledBack'

Write-Host "`n=== TEST 08: UI legada não auto-carrega o módulo Advanced ==="
$loader=Get-Content -LiteralPath (Join-Path $TestsRoot 'WinSlimSuite.dev.ps1') -Raw -Encoding UTF8
$recursiveLoader=($loader -match 'Get-ChildItem[^\r\n]+-Recurse')
Assert-Fase5R3 (-not $recursiveLoader) 'loader de catalogs continua não-recursivo'
Assert-Fase5R3 ((Split-Path -Parent (Join-Path $TestsRoot 'catalogs\validated\Advanced-Catalog.json')) -match 'validated$') 'módulo Advanced fica em subpasta validated fora do auto-load legado'
Assert-Fase5R3 ($loader -match 'AdvancedProviderBridge\.ps1') 'dev loader já carrega o bridge para integração backend futura'

Write-Host "`n=== RESUMO FASE 5 R3.3 ==="
if($script:failures.Count -eq 0){
 Write-Host 'FASE 5 R3.3 APROVADA - 3 advanced providers promovidos e rollback transacional validado (190 entradas).' -ForegroundColor Green
 Write-Host 'UI legada permanece em 187 entradas até a Fase 7; nenhuma exposição prematura de type=provider.' -ForegroundColor Cyan
 Write-Host 'Proximo subgate: FASE 5 R4 - expansão curada do catálogo real além de 190 entradas.' -ForegroundColor Cyan
 exit 0
}
Write-Host "FASE 5 R3.3 REPROVADA - $($script:failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $script:failures){Write-Host " - $f" -ForegroundColor Red}
exit 1

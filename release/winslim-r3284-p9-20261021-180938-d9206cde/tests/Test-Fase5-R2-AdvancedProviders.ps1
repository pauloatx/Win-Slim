$ErrorActionPreference = 'Stop'

$TestsRoot = Split-Path -Parent $PSScriptRoot
$ProviderContract = Join-Path $TestsRoot 'src\Core\ProviderContract.ps1'
$RegistryProvider = Join-Path $TestsRoot 'src\Providers\RegistryProvider.ps1'
$PowerCfgProvider = Join-Path $TestsRoot 'src\Providers\PowerCfgProvider.ps1'
$ScheduledTaskProvider = Join-Path $TestsRoot 'src\Providers\ScheduledTaskProvider.ps1'
$CoreParkingProvider = Join-Path $TestsRoot 'src\Providers\CoreParkingProvider.ps1'
$CpuAffinityProvider = Join-Path $TestsRoot 'src\Providers\CpuAffinityProvider.ps1'
$GpuIrqProvider = Join-Path $TestsRoot 'src\Providers\GpuInterruptAffinityProvider.ps1'
$PlannerPath = Join-Path $TestsRoot 'src\Core\Planner.ps1'
$TransactionPath = Join-Path $TestsRoot 'src\Core\Transaction.ps1'

. $ProviderContract
. $RegistryProvider
. $PowerCfgProvider
. $ScheduledTaskProvider
. $PlannerPath

$script:failures = @()

function Assert-Fase5R2 {
    param([bool]$Condition,[string]$Message,[string]$Detail=$null)
    if($Condition){ Write-Host "  [OK] $Message" -ForegroundColor Green }
    else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        if($Detail){ Write-Host "         $Detail" -ForegroundColor DarkYellow }
        $script:failures += $(if($Detail){"$Message :: $Detail"}else{$Message})
    }
}

function Get-Sha256 { param([string]$Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-JsonFile { param([string]$Path) Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }

function New-HybridTopology {
    return [PSCustomObject]@{
        Cores=@(
            [PSCustomObject]@{EfficiencyClass=8;Group=0;Mask=[UInt64]0x3},
            [PSCustomObject]@{EfficiencyClass=8;Group=0;Mask=[UInt64]0xC},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x10},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x20},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x40},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x80}
        )
        Groups=@(0); EfficiencyClasses=@(0,8); LogicalProcessorCount=8; PhysicalCoreEntries=6; IsHybrid=$true; SingleProcessorGroup=$true
        Api='GetLogicalProcessorInformationEx(RelationProcessorCore)'
    }
}

function New-HomogeneousTopology {
    return [PSCustomObject]@{
        Cores=@(
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x3},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0xC},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x30},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0xC0}
        )
        Groups=@(0); EfficiencyClasses=@(0); LogicalProcessorCount=8; PhysicalCoreEntries=4; IsHybrid=$false; SingleProcessorGroup=$true
        Api='GetLogicalProcessorInformationEx(RelationProcessorCore)'
    }
}

function New-LowCpuTopology {
    return [PSCustomObject]@{
        Cores=@(
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0x3},
            [PSCustomObject]@{EfficiencyClass=0;Group=0;Mask=[UInt64]0xC}
        )
        Groups=@(0); EfficiencyClasses=@(0); LogicalProcessorCount=4; PhysicalCoreEntries=2; IsHybrid=$false; SingleProcessorGroup=$true
        Api='synthetic'
    }
}

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 5 R2.1 / Advanced Providers'
Write-Host '============================================================'
Write-Host 'R2.1: fix automatic $PID collision + CoreParking + CPU/GPU affinity'

Write-Host "`n=== TEST 00: baseline congelada + parser dos Providers novos ==="
$expected=@{
    'src\Core\Transaction.ps1'='ecee3451af44cef809215d4a9045c2a81d7596e57062273e2860c00171f43619'
    'src\Core\Planner.ps1'='a27ab444744f3011d9ff7c539967c1d75bdcfdbf2a8a81ee2f03d56c48c81ce4'
    'src\Providers\RegistryProvider.ps1'='b01680f038d0eaa075680041ef76a48938bce412991d530fd8cabadf0186a90e'
    'src\Providers\PowerCfgProvider.ps1'='75109f2e5a8fee29ebe7a28e1aeaa0f5052d849a0814c9dfefe0ce5025ab1764'
    'src\Providers\ScheduledTaskProvider.ps1'='b1866212cedbf855df9e05dc54223a2223eb9c320a97357dc43d4ad0bad7b179'
    'src\Providers\GamePriorityProvider.ps1'='4b798f1f332cd3d5febc2c660a32e8fd10cf914242d08693884bf3f5983b7684'
    'src\Providers\MmcssProvider.ps1'='4857381f2ba13261bc0160e7228661b0cd1625a59366e86d8bd7965792efc165'
    'catalogs\Game-Workload.json'='19e5d57eb6ac7501ef5fc782445a44bc1bc5aaf6a59100ae45639aea7e25079d'
}
foreach($rel in $expected.Keys){
    $actual=Get-Sha256 (Join-Path $TestsRoot $rel)
    Assert-Fase5R2 ($actual -eq $expected[$rel]) "baseline R1.1 congelada: $rel" "expected=$($expected[$rel]); actual=$actual"
}
foreach($f in @($CoreParkingProvider,$CpuAffinityProvider,$GpuIrqProvider)){
    $tokens=$null;$errs=$null
    [System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errs)|Out-Null
    Assert-Fase5R2 (@($errs).Count -eq 0) "parser sem erros: $(Split-Path -Leaf $f)" $(if(@($errs).Count){(@($errs|ForEach-Object{$_.Message}) -join '; ')}else{$null})
}
# Regression gate: $PID is a read-only automatic variable in Windows PowerShell 5.1.
# Parameter names are case-insensitive, so param($Pid,...) is invalid for an adapter argument.
$cpuAffinitySource=Get-Content -LiteralPath $CpuAffinityProvider -Raw -Encoding UTF8
Assert-Fase5R2 ($cpuAffinitySource -notmatch 'param\s*\(\s*\$Pid\s*,') 'CpuAffinityProvider evita parametro $Pid (automatic variable read-only)'
if($script:failures.Count -gt 0){ Write-Host 'PRE-FLIGHT R2.1 FALHOU. PROVIDERS NAO SERAO CARREGADOS.' -ForegroundColor Red; exit 1 }
. $CoreParkingProvider
. $CpuAffinityProvider
. $GpuIrqProvider

Write-Host "`n=== TEST 01: CoreParkingProvider 100/100 + Undo exato (sintetico) ==="
$script:cpAc=25; $script:cpDc=50
$cpReader={ param($Sub,$Set) [PSCustomObject]@{AC=$script:cpAc;DC=$script:cpDc;Queryable=$true} }
$cpWriter={ param($Sub,$Set,$Ac,$Dc) $script:cpAc=[int]$Ac; $script:cpDc=[int]$Dc }
$cpa=Invoke-CoreParkingProvider -Id 'F5R2-CP' -Action Apply -StateReader $cpReader -StateWriter $cpWriter
Assert-Fase5R2 ($cpa.Success -and $cpa.Changed -and $script:cpAc -eq 100 -and $script:cpDc -eq 100) 'Core Parking aplica CPMINCORES AC/DC=100'
Assert-Fase5R2 ([int]$cpa.StateBefore.AC -eq 25 -and [int]$cpa.StateBefore.DC -eq 50) 'Core Parking preserva AC/DC originais no backup'
$cpu=Invoke-CoreParkingProvider -Id 'F5R2-CP' -Action Undo -BackupData $cpa.StateBefore -StateReader $cpReader -StateWriter $cpWriter
Assert-Fase5R2 ($cpu.Success -and $script:cpAc -eq 25 -and $script:cpDc -eq 50) 'Core Parking Undo restaura AC/DC exatamente'
$cpa2=Invoke-CoreParkingProvider -Id 'F5R2-CP-IDEMP' -Action Apply -TargetAc 25 -TargetDc 50 -StateReader $cpReader -StateWriter $cpWriter
Assert-Fase5R2 ($cpa2.Success -and -not $cpa2.Changed) 'Core Parking idempotente quando estado ja e o desejado'

Write-Host "`n=== TEST 02: calculo P-core via EfficiencyClass >= 1 ==="
$hybrid=New-HybridTopology
$pm=Get-WinSlimPCoreMaskFromTopology -Topology $hybrid
Assert-Fase5R2 ($pm.Applicable -and [UInt64]$pm.Mask -eq [UInt64]0xF -and $pm.EfficiencyRule -eq 'EfficiencyClass >= 1') 'P-core mask usa somente cores EfficiencyClass >= 1' "mask=$($pm.MaskHex)"
$hom=Get-WinSlimPCoreMaskFromTopology -Topology (New-HomogeneousTopology)
Assert-Fase5R2 (-not $hom.Applicable) 'CPU sem classes P/E distinguiveis vira SKIP seguro' $hom.Reason
$multi=[PSCustomObject]@{Cores=@([PSCustomObject]@{EfficiencyClass=8;Group=0;Mask=[UInt64]3},[PSCustomObject]@{EfficiencyClass=0;Group=1;Mask=[UInt64]3});Groups=@(0,1);LogicalProcessorCount=4}
$multiDecision=Get-WinSlimPCoreMaskFromTopology -Topology $multi
Assert-Fase5R2 (-not $multiDecision.Applicable) 'multi processor-group nao usa ProcessorAffinity simples'

Write-Host "`n=== TEST 03: CpuAffinityProvider - tarefa/script/processo + Undo exato (adapter sintetico) ==="
$script:taskState=[PSCustomObject]@{TaskName='WinSlimSuite-AffinityCs2';TaskPath='\';Exists=$true;State='Ready';Xml='<Task>ORIGINAL</Task>'}
$script:fileState=[PSCustomObject]@{Path='X:\affinity-cs2.ps1';Exists=$true;Bytes=[byte[]](1,2,3,4,5)}
$script:procState=@([PSCustomObject]@{Id=4242;Affinity=[Int64]255})
$adapter=[PSCustomObject]@{
    GetTaskState={ param($TaskName) [PSCustomObject]@{TaskName=$script:taskState.TaskName;TaskPath='\';Exists=[bool]$script:taskState.Exists;State=$script:taskState.State;Xml=$script:taskState.Xml} }
    RegisterTask={ param($TaskName,$Xml) $script:taskState=[PSCustomObject]@{TaskName=$TaskName;TaskPath='\';Exists=$true;State='Ready';Xml=[string]$Xml} }
    RestoreTask={ param($State) $script:taskState=[PSCustomObject]@{TaskName=$State.TaskName;TaskPath=$State.TaskPath;Exists=[bool]$State.Exists;State=$State.State;Xml=$State.Xml} }
    GetFileState={ param($Path) [PSCustomObject]@{Path=$script:fileState.Path;Exists=[bool]$script:fileState.Exists;Bytes=$(if($script:fileState.Bytes){[byte[]]$script:fileState.Bytes.Clone()}else{$null})} }
    WriteFile={ param($Path,$Text) $script:fileState=[PSCustomObject]@{Path=$Path;Exists=$true;Bytes=[Text.Encoding]::UTF8.GetBytes([string]$Text)} }
    RestoreFile={ param($State) $script:fileState=[PSCustomObject]@{Path=$State.Path;Exists=[bool]$State.Exists;Bytes=$(if($State.Bytes){[byte[]]$State.Bytes.Clone()}else{$null})} }
    GetProcesses={ param($ProcessName) @($script:procState | ForEach-Object{[PSCustomObject]@{Id=[int]$_.Id;Affinity=[Int64]$_.Affinity}}) }
    SetProcessAffinity={ param($ProcessId,$Mask) foreach($p in $script:procState){if($p.Id -eq [int]$ProcessId){$p.Affinity=[Int64]$Mask}} }
}
$ca=Invoke-CpuAffinityProvider -Id 'F5R2-AFF' -Action Apply -Topology $hybrid -Adapter $adapter -ScriptPath 'X:\affinity-cs2.ps1'
Assert-Fase5R2 ($ca.Success -and $ca.Changed -and $script:taskState.Exists -and $script:fileState.Exists -and [Int64]$script:procState[0].Affinity -eq 15) 'CpuAffinity Apply instala artefatos e aplica mascara 0xF ao processo sintetico' "Error=$($ca.Error); Affinity=$($script:procState[0].Affinity)"
Assert-Fase5R2 ($ca.StateBefore.Task.Xml -eq '<Task>ORIGINAL</Task>' -and ([BitConverter]::ToString([byte[]]$ca.StateBefore.Script.Bytes) -eq '01-02-03-04-05') -and [Int64]$ca.StateBefore.Processes[0].Affinity -eq 255) 'CpuAffinity backup preserva tarefa, bytes do script e afinidade original'
$cu=Invoke-CpuAffinityProvider -Id 'F5R2-AFF' -Action Undo -BackupData $ca.StateBefore -Topology $hybrid -Adapter $adapter -ScriptPath 'X:\affinity-cs2.ps1'
Assert-Fase5R2 ($cu.Success -and $script:taskState.Xml -eq '<Task>ORIGINAL</Task>' -and [Int64]$script:procState[0].Affinity -eq 255) 'CpuAffinity Undo restaura tarefa e afinidade do PID' "Error=$($cu.Error); Affinity=$($script:procState[0].Affinity)"
Assert-Fase5R2 ([BitConverter]::ToString([byte[]]$script:fileState.Bytes) -eq '01-02-03-04-05') 'CpuAffinity Undo restaura bytes originais do worker'

Write-Host "`n=== TEST 04: CpuAffinityProvider SKIP nao cria artefatos em CPU homogenea ==="
$beforeXml=$script:taskState.Xml; $beforeBytes=[BitConverter]::ToString([byte[]]$script:fileState.Bytes); $beforeAff=$script:procState[0].Affinity
$skip=Invoke-CpuAffinityProvider -Id 'F5R2-AFF-SKIP' -Action Apply -Topology (New-HomogeneousTopology) -Adapter $adapter -ScriptPath 'X:\affinity-cs2.ps1'
Assert-Fase5R2 ($skip.Success -and -not $skip.Changed -and -not $skip.Verification.Applicable) 'CpuAffinity retorna Applicable=false em topologia nao hibrida'
Assert-Fase5R2 ($script:taskState.Xml -eq $beforeXml -and [BitConverter]::ToString([byte[]]$script:fileState.Bytes) -eq $beforeBytes -and $script:procState[0].Affinity -eq $beforeAff) 'CpuAffinity SKIP nao altera tarefa/script/processo'

Write-Host "`n=== TEST 05: mascara GPU dinamica reproduz 0x14 sem hardcode ==="
$gm=Get-WinSlimSuggestedGpuInterruptMask -Topology (New-HomogeneousTopology)
Assert-Fase5R2 ($gm.Applicable -and [UInt64]$gm.Mask -eq [UInt64]0x14) 'politica por dois nucleos fisicos produz 0x14 no layout SMT sintetico' "mask=$($gm.MaskHex)"
Assert-Fase5R2 (([BitConverter]::ToString([byte[]]$gm.Bytes)) -eq '14-00-00-00-00-00-00-00') 'AssignmentSetOverride e serializado em 8 bytes little-endian'

Write-Host "`n=== TEST 06: GpuInterruptAffinityProvider - Apply/Undo exato em HKCU ==="
$root='HKCU:\Software\WinSlimSuite\Tests\Fase5R2\Enum'
Remove-Item 'HKCU:\Software\WinSlimSuite\Tests\Fase5R2' -Recurse -Force -ErrorAction SilentlyContinue
$i1='PCI\VEN_FAKE&DEV_0001\A'; $i2='PCI\VEN_FAKE&DEV_0002\B'
$p1=Get-WinSlimGpuAffinityPath -RegistryRoot $root -InstanceId $i1
New-Item -Path $p1 -Force | Out-Null
New-ItemProperty -Path $p1 -Name DevicePolicy -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $p1 -Name AssignmentSetOverride -PropertyType Binary -Value ([byte[]](1,2,3,4)) -Force | Out-Null
$ga=Invoke-GpuInterruptAffinityProvider -Id 'F5R2-GPU' -Action Apply -InstanceIds @($i1,$i2) -RegistryRoot $root -Topology (New-HomogeneousTopology)
$g1p=Get-RegistryState -Path $p1 -Name DevicePolicy; $g1m=Get-RegistryState -Path $p1 -Name AssignmentSetOverride
$p2=Get-WinSlimGpuAffinityPath -RegistryRoot $root -InstanceId $i2
$g2p=Get-RegistryState -Path $p2 -Name DevicePolicy; $g2m=Get-RegistryState -Path $p2 -Name AssignmentSetOverride
Assert-Fase5R2 ($ga.Success -and $g1p.Value -eq 4 -and $g2p.Value -eq 4) 'GPU IRQ aplica DevicePolicy=4 por instancia PCI'
Assert-Fase5R2 ((Test-WinSlimByteArrayEqual $g1m.Value ([byte[]](0x14,0,0,0,0,0,0,0))) -and (Test-WinSlimByteArrayEqual $g2m.Value ([byte[]](0x14,0,0,0,0,0,0,0)))) 'GPU IRQ aplica AssignmentSetOverride calculado em ambas as GPUs'
$gu=Invoke-GpuInterruptAffinityProvider -Id 'F5R2-GPU' -Action Undo -BackupData $ga.StateBefore -InstanceIds @($i1,$i2) -RegistryRoot $root -Topology (New-HomogeneousTopology)
$r1p=Get-RegistryState -Path $p1 -Name DevicePolicy; $r1m=Get-RegistryState -Path $p1 -Name AssignmentSetOverride
$r2p=Get-RegistryState -Path $p2 -Name DevicePolicy; $r2m=Get-RegistryState -Path $p2 -Name AssignmentSetOverride
Assert-Fase5R2 ($gu.Success -and $r1p.Exists -and $r1p.Value -eq 1 -and (Test-WinSlimByteArrayEqual $r1m.Value ([byte[]](1,2,3,4)))) 'GPU IRQ Undo restaura valor e bytes originais da instancia existente'
Assert-Fase5R2 (-not $r2p.Exists -and -not $r2m.Exists) 'GPU IRQ Undo remove valores originalmente ausentes'
Remove-Item 'HKCU:\Software\WinSlimSuite\Tests\Fase5R2' -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== TEST 07: GPU IRQ guardrail <8 logical processors ==="
$lowRoot='HKCU:\Software\WinSlimSuite\Tests\Fase5R2Low\Enum'
$low=Invoke-GpuInterruptAffinityProvider -Id 'F5R2-GPU-SKIP' -Action Apply -InstanceIds @('PCI\FAKE\LOW') -RegistryRoot $lowRoot -Topology (New-LowCpuTopology)
Assert-Fase5R2 ($low.Success -and -not $low.Changed -and -not $low.Verification.Applicable) 'GPU IRQ com menos de 8 logicos vira SKIP seguro'
Assert-Fase5R2 (-not (Test-Path -LiteralPath $lowRoot)) 'GPU IRQ SKIP nao cria chave de registro'

Write-Host "`n=== TEST 08: topologia real read-only via GetLogicalProcessorInformationEx ==="
$realTopo=$null; $topoErr=$null
try{$realTopo=Get-WinSlimProcessorTopology}catch{$topoErr=$_.Exception.Message}
Assert-Fase5R2 ($null -ne $realTopo -and @($realTopo.Cores).Count -gt 0 -and [int]$realTopo.LogicalProcessorCount -gt 0) 'API nativa retorna topologia real sem mutacao' $topoErr
if($realTopo){
    Write-Host "       CPU real: cores=$($realTopo.PhysicalCoreEntries); logicos=$($realTopo.LogicalProcessorCount); groups=$(@($realTopo.Groups)-join ','); efficiency=$(@($realTopo.EfficiencyClasses)-join ','); hybrid=$($realTopo.IsHybrid)" -ForegroundColor DarkGray
}

Write-Host "`n=== TEST 09: specs Seal preservadas e promovidas apenas a Provider ==="
$adv=Get-JsonFile (Join-Path $TestsRoot 'specs\Workload-advanced-pending.json')
$cp=@($adv.items|Where-Object{$_.id -eq 'WS-ADV-001'})[0]
$cs=@($adv.items|Where-Object{$_.id -eq 'WS-ADV-002'})[0]
$gpu=@($adv.items|Where-Object{$_.id -eq 'WS-ADV-003'})[0]
Assert-Fase5R2 ($adv.status -eq 'ProvidersImplementedAwaitingWindowsValidation') 'spec avancada registra Providers implementados aguardando gate Windows'
Assert-Fase5R2 ($cp.subgroupGuid -eq '54533251-82be-4824-96c1-47b60b740d00' -and $cp.settingGuid -eq '0cc5b647-c1df-4637-891a-dec35c318583' -and [int]$cp.targetAC -eq 100 -and [int]$cp.targetDC -eq 100) 'Core Parking mantem GUIDs e AC/DC=100 exatos'
Assert-Fase5R2 ($cs.topologyApi -eq 'GetLogicalProcessorInformationEx(RelationProcessorCore)' -and $cs.pCoreRule -eq 'EfficiencyClass >= 1' -and $cs.winSlimTaskName -eq 'WinSlimSuite-AffinityCs2') 'CS2 affinity mantem API, criterio e task name especificados'
Assert-Fase5R2 ([int]$gpu.precondition.minLogicalProcessors -eq 8 -and [int]$gpu.devicePolicy.value -eq 4 -and $gpu.assignmentSetOverride.observedTlMaskHex -eq '0x14') 'GPU IRQ mantem precondicao, DevicePolicy=4 e referencia referência técnica 0x14'

Write-Host "`n=== TEST 10: avancados continuam fora do catalogo executavel ate R3 ==="
$base=Get-JsonFile (Join-Path $TestsRoot 'catalog.json')
$tl=Get-JsonFile (Join-Path $TestsRoot 'catalogs\Game-Workload.json')
$combined=@($base.tweaks)+@($tl.tweaks)
$advIds=@($adv.items|Select-Object -ExpandProperty id)
$leaked=@($combined|Where-Object{$advIds -contains $_.id})
Assert-Fase5R2 (@($base.tweaks).Count -eq 177 -and @($tl.tweaks).Count -eq 10 -and $combined.Count -eq 187) 'catalogo executavel permanece em 187 durante gate R2'
Assert-Fase5R2 ($leaked.Count -eq 0) 'nenhum WS-ADV entra na GUI antes da validacao dos Providers'
$audit=Test-WinSlimPlannerCatalog -CatalogTweaks $combined
Assert-Fase5R2 ($audit.Valid) 'Planner R1 continua aceitando catalogo executavel sem regressao'

Write-Host "`n=== TEST 11: contrato ProviderResult dos tres Providers ==="
$contractProps=@('Id','Action','Success','Changed','StateBefore','StateAfter','Verification','Restart','Warning','Error')
$sample=@($cpa,$ca,$ga)
foreach($r in $sample){
    $missing=@($contractProps|Where-Object{$r.PSObject.Properties.Name -notcontains $_})
    Assert-Fase5R2 ($missing.Count -eq 0) "$($r.Id) respeita ProviderResult" $(if($missing.Count){$missing -join ','}else{$null})
}

Write-Host "`n=== RESUMO FASE 5 R2.1 ==="
if($script:failures.Count -eq 0){
    Write-Host 'FASE 5 R2.1 APROVADA - Advanced Providers passaram em todos os gates do harness.' -ForegroundColor Green
    Write-Host 'Proximo subgate: FASE 5 R3 - promover os 3 avancados ao catalogo + expandir catalogo real.' -ForegroundColor Cyan
    return
}
Write-Host "FASE 5 R2.1 REPROVADA - $($script:failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $script:failures){Write-Host " - $f" -ForegroundColor Red}
exit 1

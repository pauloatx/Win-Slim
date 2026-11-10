param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'src\UI\Native\R3_2_73\WinSlimGpu.ps1')
. (Join-Path $Root 'src\UI\Native\R3_2_73\WinSlimGpuTransaction.ps1')
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};Write-Host ('OK: '+$Message)}
function Adapter($Vendor,$Name='Fixture GPU',$Code=0,$Driver='1.0') {[pscustomobject]@{PNPDeviceID=('PCI\VEN_'+$Vendor+'&DEV_0001');Name=$Name;ConfigManagerErrorCode=$Code;DriverVersion=$Driver}}
$script:fixtures=@(Adapter '10DE' 'GeForce fixture')
$nv=Get-WinSlimGpuInventory -Reader {$script:fixtures}
Require ($nv.Vendors -contains 'NVIDIA' -and $nv.Vendors -notcontains 'AMD') 'PCI NVIDIA sem inferir fabricante da CPU'
$services=@([pscustomobject]@{Name='NvTelemetryContainer'},[pscustomobject]@{Name='AUEPLauncher'})
$map=Get-WinSlimHardwareEligibility $nv $services
Require ($map['PRIV-013'].Eligible -and -not $map['PRIV-015'].Eligible) 'somente servico do fabricante detectado'
$map=Get-WinSlimHardwareEligibility $nv @()
Require (-not $map['PRIV-013'].Eligible) 'servico removido nao e recriado'
# Use explicit array to avoid positional argument flattening.
$script:fixtures=@((Adapter '1002' 'Radeon fixture'),(Adapter '8086' 'Intel fixture'))
$amd=Get-WinSlimGpuInventory -Reader {$script:fixtures}
$map=Get-WinSlimHardwareEligibility $amd $services
Require ($map['PRIV-015'].Eligible -and -not $map['PRIV-013'].Eligible -and $amd.Vendors -contains 'Intel') 'AMD + Intel hibrido'
$script:fixtures=@((Adapter '1002'),(Adapter '10DE'))
$both=Get-WinSlimGpuInventory -Reader {$script:fixtures};$map=Get-WinSlimHardwareEligibility $both $services
Require ($map['PRIV-013'].Eligible -and $map['PRIV-015'].Eligible) 'duas GPUs de fabricantes distintos'
foreach($fixture in @((Adapter '15AD' 'VMware'),(Adapter '10DE' 'Basic Display'),(Adapter '1002' 'Radeon' 43),(Adapter '10DE' 'GeForce' 0 ''))){
 $script:fixtures=@($fixture);$v=Get-WinSlimGpuInventory -Reader {$script:fixtures}
 Require (@($v.Vendors).Count -eq 0) ('dispositivo nao confirmado: '+$fixture.Name)
}
$v=Get-WinSlimGpuInventory -Reader {throw 'fixture access denied'}
Require (@($v.Vendors).Count -eq 0 -and $v.Error) 'falha de deteccao nao libera ajustes'
$map=Get-WinSlimHardwareEligibility $both $services
foreach($id in @('MLV-004','PERF-018','PERF-007','WS-ADV-003','WS-ADV-002')){Require (-not $map[$id].Eligible) ('suporte desconhecido bloqueado: '+$id)}
$before=[pscustomobject]@{Name='NvTelemetryContainer';StartMode='Auto';State='Running';DelayedAutoStart=[pscustomobject]@{Exists=$true;Kind='DWord';Encoding='Int32Decimal';Value='1'}}
$after=[pscustomobject]@{Name=$before.Name;StartMode='Disabled';State='Stopped';DelayedAutoStart=$before.DelayedAutoStart}
$script:state=$before;$script:writes=0
$writer={param($s) $script:writes++;$script:state=$s}
$reader={param($n) $script:state}
$result=Invoke-WinSlimGpuStateChange -Before $before -After $after -Writer $writer -Reader $reader
Require ((Test-WinSlimGpuStateEqual $result $after) -and $script:writes -eq 1) 'Apply e Verify com adaptador isolado'
$result=Invoke-WinSlimGpuStateChange -Before $after -After $before -Writer $writer -Reader $reader
Require (Test-WinSlimGpuStateEqual $result $before) 'Undo exato inclusive inicio automatico atrasado'
$script:writes=0;$script:state=$before;$caught=$false
try{Invoke-WinSlimGpuStateChange -Before $before -After $after -Writer {param($s) $script:writes++;if($script:writes -eq 1){throw 'fixture failure'};$script:state=$s} -Reader $reader}catch{$caught=$true}
Require ($caught -and $script:writes -eq 2 -and (Test-WinSlimGpuStateEqual $script:state $before)) 'falha recupera e verifica estado original'
$script:writes=0;$script:state=$before;$caught=$false
try{Invoke-WinSlimGpuStateChange -Before $before -After $after -Writer {param($s) $script:writes++;if($script:writes -gt 1){$script:state=$s}} -Reader $reader}catch{$caught=$true}
Require ($caught -and $script:writes -eq 2) 'Verify rejeita escritor que nao aplicou'
$missing=[pscustomobject]@{Name=$before.Name;StartMode='Auto';State='Running';DelayedAutoStart=[pscustomobject]@{Exists=$false}}
Require (-not (Test-WinSlimGpuStateEqual $before $missing)) 'ausencia diferente de valor de registro'
Write-Host 'GPU fixtures aprovadas; nenhuma configuracao do Windows alterada.'

# Integrate policy + planner without querying or writing the host hardware.
. (Join-Path $Root 'src\UI\Native\R3_2_73\WinSlim.UiBridge.ps1') -RootPath $Root -LibraryOnly
$script:SystemSnapshot=[pscustomobject]@{GPUName='Fixture';CPUThreads=12}
function Get-WinSlimPreviewContext { New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true }
foreach($inventory in @($nv,$amd,$both,$v)){
 $script:GpuInventory=$inventory
 $script:HardwareEligibility=Get-WinSlimHardwareEligibility $inventory $services
 foreach($preset in @('Balanceado','Gamer','Extremo')){
  $beforeBase=@($script:PresetRuntime.PresetSelections[$preset].SelectedIds) -join ','
  $resolved=Resolve-WinSlimHardwarePreset -Preset $preset
  foreach($id in @('PRIV-013','PRIV-015','PERF-007','PERF-018','MLV-004','WS-ADV-003')){
   Require (($resolved.SelectedIds -contains $id) -eq [bool]$script:HardwareEligibility[$id].Automatic) ('preset '+$preset+' respeita disponibilidade '+$id)
  }
  Require ((@($script:PresetRuntime.PresetSelections[$preset].SelectedIds) -join ',') -ceq $beforeBase) 'cache de preset preservado'
  $request=[pscustomobject]@{presetName=$preset;conditionalProfiles=@();allowHighRisk=$false}
  $report=Get-WinSlimHardwarePresetReport $request
  Require ((@($report.Policy.SelectedIds) -join ',') -ceq (@($resolved.SelectedIds) -join ',')) 'preview e resolucao usam os mesmos IDs'
 }
 $rejected=$false
 try{Resolve-WinSlimHardwarePreset -Preset Gamer -Profiles @('HW-HAGS-ON')}catch{$rejected=$true}
 Require $rejected 'overlay sem suporte rejeitado mesmo fora da UI'
 $rejected=$false
 try{Get-WinSlimCustomValidationReport ([pscustomobject]@{selectedIds=@('PERF-007');customName='Fixture';levelSelections=[pscustomobject]@{}})}catch{$rejected=$true}
 Require $rejected 'importacao/custom nao contorna bloqueio hardware'
}
Write-Host 'Integracao GPU/presets/planner aprovada com fixtures.'

# Preview must not report Disabled/Running as fully applied.
$t=[pscustomobject]@{id='PRIV-013';name='Fixture';type='service';service=@([pscustomobject]@{Name='NvTelemetryContainer';StartupType='Disabled';StopNow=$true})}
$plan=[pscustomobject]@{ExecutionOrder=@([pscustomobject]@{TweakId=$t.id;Tweak=$t})}
$live=Get-WinSlimLivePreview -Plan $plan -ServiceReader { [pscustomobject]@{Name='NvTelemetryContainer';StartMode='Disabled';State='Running'} }
Require ($live.Items[0].Status -eq 'NeedsChange') 'Verify da previa exige servico parado'
$live=Get-WinSlimLivePreview -Plan $plan -ServiceReader { [pscustomobject]@{Name='NvTelemetryContainer';StartMode='Disabled';State='Stopped'} }
Require ($live.Items[0].Status -eq 'AlreadyConfigured') 'Verify da previa confirma Disabled/Stopped'
function Get-WinSlimBackupIdentity { [pscustomobject]@{MachineGuid='fixture-machine';UserSid='fixture-user'} }
$op=[pscustomobject]@{Name='NvTelemetryContainer';Exists=$true;StartMode='Auto';State='Running';DelayedAutoStart=[pscustomobject]@{Exists=$false}}
$snapshot=[pscustomobject]@{Profile='GPU/PRIV-013';Identity=(Get-WinSlimBackupIdentity);Coverage='CompleteForPlan';Items=@([pscustomobject]@{TweakId='PRIV-013';Type='service';Operations=@($op)})}
$verified=[pscustomobject]@{Snapshot=$snapshot}
$state=Get-WinSlimGpuBackupState $verified 'PRIV-013'
Require ($state.StartMode -eq 'Auto' -and -not $state.DelayedAutoStart.Exists) 'contrato de backup valido preserva ausencia'
$snapshot.Identity.MachineGuid='different-machine';$blocked=$false
try{Get-WinSlimGpuBackupState $verified 'PRIV-013'}catch{$blocked=$true}
Require $blocked 'Undo recusa backup de outra maquina'
$snapshot.Identity.MachineGuid='fixture-machine';$op.Name='WinDefend';$blocked=$false
try{Get-WinSlimGpuBackupState $verified 'PRIV-013'}catch{$blocked=$true}
Require $blocked 'Undo recusa servico fora da allowlist'
Write-Host 'GPU: todas as verificacoes isoladas concluidas.'

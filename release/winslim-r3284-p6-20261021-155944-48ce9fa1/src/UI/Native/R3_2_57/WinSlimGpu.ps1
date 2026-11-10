#requires -Version 5.1
# Hardware eligibility is data-only. Unknown support never means compatible.
function Get-WinSlimGpuInventory {
 param([scriptblock]$Reader={Get-CimInstance Win32_VideoController -ErrorAction Stop})
 $result=@();$errorText=''
 try {
  foreach($gpu in @(& $Reader)) {
   $pci=[string]$gpu.PNPDeviceID;$vendor='Unknown'
   if($pci -match '^PCI\\VEN_10DE&'){$vendor='NVIDIA'}
   elseif($pci -match '^PCI\\VEN_1002&'){$vendor='AMD'}
   elseif($pci -match '^PCI\\VEN_8086&'){$vendor='Intel'}
   $healthy=$null -ne $gpu.ConfigManagerErrorCode -and [int]$gpu.ConfigManagerErrorCode -eq 0
   $driver=-not [string]::IsNullOrWhiteSpace([string]$gpu.DriverVersion) -and [string]$gpu.Name -notmatch 'Basic Display|Basic Render|Remote|Virtual|VMware|VirtualBox'
   $result += [pscustomobject]@{Name=[string]$gpu.Name;Vendor=$vendor;DeviceId=$pci;DriverVersion=[string]$gpu.DriverVersion;Available=($vendor -ne 'Unknown' -and $healthy -and $driver)}
  }
 }catch{$errorText=$_.Exception.Message}
 [pscustomobject]@{Adapters=@($result);Vendors=@($result | Where-Object {$_.Available} | Select-Object -ExpandProperty Vendor -Unique);Error=$errorText;DetectedAtUtc=[DateTime]::UtcNow.ToString('o')}
}
function Get-WinSlimGpuServiceName {
 param([string]$Id)
 switch($Id){'PRIV-013'{'NvTelemetryContainer'}'PRIV-015'{'AUEPLauncher'}default{throw 'Ajuste GPU sem contrato de servico.'}}
}
function Get-WinSlimHardwareEligibility {
 param($Inventory,[object[]]$Services=@(),$Topology=$null,[bool]$CoreParkingSupported=$false)
 $map=@{};$names=@($Services | ForEach-Object {[string]$_.Name})
 foreach($item in @(@('PRIV-013','NVIDIA','NvTelemetryContainer'),@('PRIV-015','AMD','AUEPLauncher'))){
  $present=$Inventory.Vendors -contains $item[1];$service=$names -contains $item[2]
  $reason=if(-not $present){'GPU '+$item[1]+' com driver operacional não detectada.'}elseif(-not $service){'Serviço opcional '+$item[2]+' não instalado; nenhuma mudança necessária.'}else{'GPU e serviço opcional detectados. Seleção automática; aplicação somente por ação explícita.'}
  $map[$item[0]]=[pscustomobject]@{Eligible=($present -and $service);Reason=$reason;Group=$item[1];Automatic=($present -and $service);Contract='ServiceSnapshotV1'}
 }
 foreach($item in @(
  @('PERF-007','A preferência de GPU do Windows é por aplicativo. O ajuste global antigo foi retirado; use Configurações de gráficos do Windows.'),
  @('MLV-004','Suporte a HAGS ainda não confirmado pelo driver. Use Configurações de gráficos do Windows; fabricante e versão não comprovam suporte.'),
  @('PERF-018','MSI deve ser habilitado pelo driver compatível. Não é seguro forçar suporte apenas pelo fabricante.'),
  @('WS-ADV-003','Afinidade de interrupções exige validação do dispositivo e do driver; indisponível para aplicação automática.')
 )){$map[$item[0]]=[pscustomobject]@{Eligible=$false;Reason=$item[1];Group='Universal';Automatic=$false;Contract='Unavailable'}}
 $pcore=$false;$reason='Topologia P-core/E-core não confirmada.'
 if($null -ne $Topology){try{$decision=Get-WinSlimPCoreMaskFromTopology -Topology $Topology;$pcore=[bool]$decision.Applicable;if(-not $pcore){$reason=[string]$decision.Reason}else{$reason='Topologia híbrida confirmada; requer consentimento de alto risco.'}}catch{}}
 $map['WS-ADV-002']=[pscustomobject]@{Eligible=$pcore;Reason=$reason;Group='CPU';Automatic=$false;Contract='ExistingProvider'}
 $map['WS-ADV-001']=[pscustomobject]@{Eligible=$CoreParkingSupported;Reason=$(if($CoreParkingSupported){'CPMINCORES consultável no plano de energia atual.'}else{'CPMINCORES não pôde ser confirmado neste plano de energia.'});Group='CPU';Automatic=$false;Contract='ExistingProvider'}
 return $map
}
function Initialize-WinSlimHardwarePolicy {
 param([switch]$Refresh)
 if($null -ne $script:HardwareEligibility -and -not $Refresh){return}
 $script:GpuInventory=Get-WinSlimGpuInventory
 $services=@();try{$services=@(Read-WinSlimPreviewServices)}catch{}
 $topology=$null;try{$topology=Get-WinSlimProcessorTopology}catch{}
 $parking=$false;try{$parking=Test-WinSlimCoreParkingSupport}catch{}
 $script:HardwareEligibility=Get-WinSlimHardwareEligibility -CoreParkingSupported $parking -Inventory $script:GpuInventory -Services $services -Topology $topology
}
function Test-WinSlimHardwareSelection {
 param([string[]]$Ids)
 Initialize-WinSlimHardwarePolicy
 foreach($id in $Ids){if($script:HardwareEligibility.ContainsKey($id) -and -not $script:HardwareEligibility[$id].Eligible){throw ($id+': '+$script:HardwareEligibility[$id].Reason)}}
}
function Set-WinSlimGpuCatalogContracts {
 param([object[]]$Tweaks)
 foreach($t in $Tweaks){
  if([string]$t.id -in @('PRIV-013','PRIV-015')){
   $vendor=if($t.id -eq 'PRIV-013'){'NVIDIA'}else{'AMD'}
   $name=Get-WinSlimGpuServiceName $t.id
   $t.type='service';$t.rollbackClass=@('Service');$t.category='Performance / GPU'
   $t.name='Serviço opcional de telemetria '+$vendor+' — desativar'
   $t.plainName='Desativar somente '+$name+'; sem alterar tarefas, driver ou recursos gráficos.'
   $t.description=$t.plainName+' Não promete ganho de FPS. Backup do estado exato, aplicação, verificação e desfazer disponíveis na seção GPU.'
   $t.hardwareRules=[pscustomobject]@{requiresGPU=$true;vendors=@($vendor)}
   $t.PSObject.Properties.Remove('InvokeScript');$t.PSObject.Properties.Remove('UndoScript')
   $t | Add-Member -NotePropertyName service -NotePropertyValue @([pscustomobject]@{Name=$name;StartupType='Disabled';StopNow=$true}) -Force
  }
 }
}
function Resolve-WinSlimHardwarePreset {
 param([string]$Preset,[string[]]$Profiles=@(),[bool]$AllowHigh=$false)
 Initialize-WinSlimHardwarePolicy
 $available=@(Get-WinSlimBridgeOverlayMetadata)
 foreach($name in $Profiles){$p=@($available | Where-Object {$_.name -eq $name});if($p.Count -ne 1 -or -not $p[0].eligible){throw ('Overlay indisponível neste hardware: '+$name)}}
 # Deep copy: the cached base selections must remain immutable.
 $resolved=Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $script:PresetRuntime -PresetName $Preset -ConditionalProfiles $Profiles -AllowHighRiskConditional:$AllowHigh
 $resolved=$resolved | ConvertTo-Json -Depth 30 | ConvertFrom-Json
 $ids=@();$excluded=@()
 foreach($id in @($resolved.SelectedIds)){
  if($script:HardwareEligibility.ContainsKey($id) -and -not $script:HardwareEligibility[$id].Eligible){$excluded += [pscustomobject]@{Code='HardwareUnavailable';Profile=$null;TweakId=$id;Message=$script:HardwareEligibility[$id].Reason}}
  else{$ids += $id}
 }
 foreach($id in @('PRIV-013','PRIV-015')){if($script:HardwareEligibility[$id].Automatic -and $ids -notcontains $id){$ids += $id}}
 $resolved.SelectedIds=@($ids | Sort-Object -Unique)
 $resolved.BaseSelectedIds=@($resolved.BaseSelectedIds | Where-Object {$resolved.SelectedIds -contains $_})
 $resolved.BaseCount=@($resolved.BaseSelectedIds).Count
 $resolved.Warnings=@($resolved.Warnings)+@($excluded)
 $levels=ConvertTo-WinSlimPresetRuntimeLevelMap $resolved.LevelSelections
 foreach($id in @($levels.Keys)){if($resolved.SelectedIds -notcontains $id){$levels.Remove($id)}}
 $resolved.LevelSelections=$levels
 $resolved.Fingerprint=Get-WinSlimPresetPolicyFingerprint -PresetName $Preset -SelectedIds $resolved.SelectedIds -LevelSelections $levels -ConditionalProfiles @($resolved.EnabledConditionalProfiles) -AllowHighRiskConditional $AllowHigh
 return $resolved
}
function Get-WinSlimHardwarePresetReport {
 param($Request)
 $policy=Resolve-WinSlimHardwarePreset -Preset ([string]$Request.presetName) -Profiles @($Request.conditionalProfiles) -AllowHigh ([bool]$Request.allowHighRisk)
 if(-not $policy.CanResolve){throw 'Resolva os conflitos e consentimentos antes de continuar.'}
 $req=[pscustomobject]@{selectedIds=@($policy.SelectedIds);customName=[string]$policy.PresetName;levelSelections=($policy.LevelSelections | ConvertTo-Json | ConvertFrom-Json)}
 $report=Get-WinSlimCustomValidationReport -Request $req
 $report.Policy=$policy;$report.PolicyFingerprint=$policy.Fingerprint;$report.ConditionalProfiles=@($policy.EnabledConditionalProfiles)
 return $report
}
function Get-WinSlimGpuView {
 Initialize-WinSlimHardwarePolicy
 $items=@()
 foreach($id in @('PRIV-013','PRIV-015','MLV-004','PERF-018','WS-ADV-003','PERF-007')){
  $t=$script:PresetRuntime.CatalogRuntime.ById[$id];$e=$script:HardwareEligibility[$id]
  $items += [pscustomobject]@{id=$id;name=$t.name;description=$t.description;risk=$t.risk;group=$e.Group;eligible=$e.Eligible;reason=$e.Reason;automatic=$e.Automatic;contract=$e.Contract}
 }
 $backups=@()
 try{$inventory=Get-WinSlimBackupInventory -Root (Join-Path $script:WinSlimBridgeRoot 'Backups\UI');foreach($b in @($inventory.Items)){if($b.Snapshot.Profile -like 'GPU/*'){$backups += [pscustomobject]@{id=$b.Snapshot.Id;tweakId=([string]$b.Snapshot.Profile).Substring(4);created=$b.Snapshot.CreatedAtUtc}}}}catch{}
 [pscustomobject]@{inventory=$script:GpuInventory;items=@($items);backups=@($backups);selectionOnly=$false}
}

function Test-WinSlimCoreParkingSupport {
 $process=New-Object Diagnostics.Process
 try{
  $process.StartInfo.FileName=Join-Path $env:WINDIR 'System32\powercfg.exe'
  $process.StartInfo.Arguments='/query SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 0cc5b647-c1df-4637-891a-dec35c318583'
  $process.StartInfo.UseShellExecute=$false;$process.StartInfo.CreateNoWindow=$true
  $process.StartInfo.RedirectStandardOutput=$true;$process.StartInfo.RedirectStandardError=$true
  if(-not $process.Start()){return $false}
  $output=$process.StandardOutput.ReadToEndAsync();$errorOutput=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit(3000)){try{$process.Kill()}catch{};return $false}
  $text=$output.GetAwaiter().GetResult()
  if($process.ExitCode -ne 0){return $false}
  $matches=@([regex]::Matches($text,'(?i)0x([0-9a-f]+)'))
  if($matches.Count -lt 2){return $false}
  foreach($m in @($matches | Select-Object -Last 2)){if([Convert]::ToInt64($m.Groups[1].Value,16) -gt 100){return $false}}
  return $true
 }finally{$process.Dispose()}
}

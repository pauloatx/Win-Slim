#requires -Version 5.1
# Explicit, allowlisted service transactions. Never run scripts from imported presets/backups.
function Read-WinSlimGpuService {
 param([string]$Name)
 $s=Get-CimInstance Win32_Service -Filter ("Name='"+$Name+"'") -ErrorAction Stop
 if($null -eq $s -or $s.State -notin @('Running','Stopped') -or $s.StartMode -notin @('Auto','Manual','Disabled')){throw 'Serviço ausente ou em transição. Aguarde e tente novamente.'}
 $delay=Read-WinSlimPreviewRegistry ([pscustomobject]@{Path=('HKLM:\SYSTEM\CurrentControlSet\Services\'+$Name);Name='DelayedAutoStart'})
 [pscustomobject]@{Name=$Name;StartMode=[string]$s.StartMode;State=[string]$s.State;DelayedAutoStart=(ConvertTo-WinSlimBackupValue $delay)}
}
function Set-WinSlimGpuServiceState {
 param($State)
 $name=[string]$State.Name
 if($name -notin @('NvTelemetryContainer','AUEPLauncher')){throw 'Serviço fora do contrato GPU.'}
 $mode=switch([string]$State.StartMode){'Auto'{'Automatic'}'Manual'{'Manual'}'Disabled'{'Disabled'}default{throw 'Modo inválido.'}}
 if($State.State -notin @('Running','Stopped')){throw 'Estado inválido.'}
 # A disabled-but-running original service can be restored by temporarily enabling it.
 if($State.State -eq 'Running' -and $mode -eq 'Disabled'){Set-Service -Name $name -StartupType Manual -ErrorAction Stop}
 else{Set-Service -Name $name -StartupType $mode -ErrorAction Stop}
 $svc=Get-Service -Name $name -ErrorAction Stop
 try{
  $svc.Refresh()
  if($State.State -eq 'Stopped' -and $svc.Status -ne 'Stopped'){$svc.Stop()}
  elseif($State.State -eq 'Running' -and $svc.Status -ne 'Running'){$svc.Start()}
  $target=[ServiceProcess.ServiceControllerStatus]([Enum]::Parse([ServiceProcess.ServiceControllerStatus],[string]$State.State))
  $svc.WaitForStatus($target,[TimeSpan]::FromSeconds(15))
 }finally{$svc.Dispose()}
 if($mode -eq 'Disabled'){Set-Service -Name $name -StartupType Disabled -ErrorAction Stop}
 $view=if([Environment]::Is64BitOperatingSystem){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Registry32}
 $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,$view)
 $key=$null
 try{
  $key=$base.OpenSubKey(('SYSTEM\CurrentControlSet\Services\'+$name),$true)
  if($null -eq $key){throw 'Chave do serviço desapareceu.'}
  if($State.DelayedAutoStart.Exists){
   if($State.DelayedAutoStart.Kind -ne 'DWord' -or $State.DelayedAutoStart.Encoding -ne 'Int32Decimal'){throw 'Backup de atraso inválido.'}
   $key.SetValue('DelayedAutoStart',[int]::Parse([string]$State.DelayedAutoStart.Value,[Globalization.CultureInfo]::InvariantCulture),[Microsoft.Win32.RegistryValueKind]::DWord)
  }else{$key.DeleteValue('DelayedAutoStart',$false)}
 }finally{if($null -ne $key){$key.Dispose()};$base.Dispose()}
}
function Test-WinSlimGpuStateEqual {
 param($A,$B)
 if($A.Name -cne $B.Name -or $A.StartMode -ne $B.StartMode -or $A.State -ne $B.State){return $false}
 $aDelay=$A.DelayedAutoStart;$bDelay=$B.DelayedAutoStart
 if([bool]$aDelay.Exists -ne [bool]$bDelay.Exists){return $false}
 if(-not $aDelay.Exists){return $true}
 return ($aDelay.Kind -ceq $bDelay.Kind -and $aDelay.Encoding -ceq $bDelay.Encoding -and [string]$aDelay.Value -ceq [string]$bDelay.Value)
}
function Invoke-WinSlimGpuStateChange {
 param($Before,$After,[scriptblock]$Writer,[scriptblock]$Reader)
 try{
  & $Writer $After
  $current=& $Reader ([string]$After.Name)
  if(-not (Test-WinSlimGpuStateEqual $current $After)){throw 'Verify: estado final diferente do solicitado.'}
 }catch{
  $failure=$_.Exception.Message
  try{& $Writer $Before;$restored=& $Reader ([string]$Before.Name);if(-not (Test-WinSlimGpuStateEqual $restored $Before)){throw 'Estado original não confirmado.'}}
  catch{throw ('Falha: '+$failure+'; recuperação automática incompleta: '+$_.Exception.Message+'. Preserve o backup.')}
  throw ('Falha: '+$failure+'; estado anterior restaurado e verificado.')
 }
 return $current
}
function Get-WinSlimGpuBackupState {
 param($Verified,[string]$Id)
 $name=Get-WinSlimGpuServiceName $Id
 $s=$Verified.Snapshot;$identity=Get-WinSlimBackupIdentity
 if($s.Identity.MachineGuid -cne $identity.MachineGuid -or $s.Identity.UserSid -cne $identity.UserSid){throw 'Backup pertence a outro computador ou usuário.'}
 if($s.Profile -cne ('GPU/'+$Id) -or @($s.Items).Count -ne 1 -or $s.Coverage -ne 'CompleteForPlan'){throw 'Backup não pertence a esta operação GPU.'}
 $item=$s.Items[0]
 if($item.TweakId -cne $Id -or $item.Type -ne 'service' -or @($item.Operations).Count -ne 1){throw 'Contrato de backup inválido.'}
 $b=$item.Operations[0]
 if($b.Name -cne $name -or -not $b.Exists -or $b.StartMode -notin @('Auto','Manual','Disabled') -or $b.State -notin @('Running','Stopped')){throw 'Estado de backup inválido.'}
 if($b.DelayedAutoStart.Exists -and ($b.DelayedAutoStart.Kind -ne 'DWord' -or $b.DelayedAutoStart.Encoding -ne 'Int32Decimal')){throw 'Tipo de atraso inválido.'}
 if($b.DelayedAutoStart.Exists){$parsed=0;if(-not [int]::TryParse([string]$b.DelayedAutoStart.Value,[ref]$parsed)){throw 'Valor de atraso inválido.'}}
 return $b
}
function Invoke-WinSlimGpuActionCore {
 param($Request)
 $id=[string]$Request.tweakId;$action=[string]$Request.operation
 $name=Get-WinSlimGpuServiceName $id
 if($action -notin @('backup','apply','verify','undo')){throw 'Operação GPU inválida.'}
 $root=Join-Path $script:WinSlimBridgeRoot 'Backups\UI'
 $current=Read-WinSlimGpuService $name
 if($action -eq 'verify'){return [pscustomobject]@{verified=($current.StartMode -eq 'Disabled' -and $current.State -eq 'Stopped');state=$current;message=('Estado lido: '+$current.StartMode+' / '+$current.State)}}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=New-Object Security.Principal.WindowsPrincipal($identity)
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Execute como administrador para preparar e aplicar este ajuste.'}
 if($action -ne 'undo'){
  Initialize-WinSlimHardwarePolicy -Refresh
  Test-WinSlimHardwareSelection -Ids @($id)
 }
 if($action -eq 'backup'){
  $req=[pscustomobject]@{selectedIds=@($id);customName=('GPU/'+$id);levelSelections=[pscustomobject]@{}}
  $report=Get-WinSlimCustomValidationReport -Request $req
  $snapshot=New-WinSlimBackupSnapshot -Plan $report.Plan -Profile ('GPU/'+$id)
  $saved=Save-WinSlimBackupSnapshot -Root $root -Snapshot $snapshot
  return [pscustomobject]@{backupId=$snapshot.Id;message='Backup do serviço criado e conferido. Nenhuma alteração aplicada.';verified=$true}
 }
 $backupId=[string]$Request.backupId
 if($backupId -notmatch '\A[a-f0-9]{32}\z'){throw 'Crie ou selecione um backup GPU válido antes de continuar.'}
 $backup=Read-WinSlimVerifiedBackup -Directory (Join-Path $root $backupId)
 $before=Get-WinSlimGpuBackupState -Verified $backup -Id $id
 $after=[pscustomobject]@{Name=$name;StartMode='Disabled';State='Stopped';DelayedAutoStart=$before.DelayedAutoStart}
 if($action -eq 'apply'){
  if(-not (Test-WinSlimGpuStateEqual $current $before)){throw 'O serviço mudou após o backup. Crie um novo backup antes de aplicar.'}
  $result=Invoke-WinSlimGpuStateChange -Before $before -After $after -Writer {param($s) Set-WinSlimGpuServiceState $s} -Reader {param($n) Read-WinSlimGpuService $n}
 }else{
  if(Test-WinSlimGpuStateEqual $current $before){return [pscustomobject]@{verified=$true;message='Estado original já presente; nenhuma alteração necessária.';backupId=$backupId}}
  if(-not (Test-WinSlimGpuStateEqual $current $after)){throw 'O serviço foi alterado fora desta operação. Desfazer bloqueado para preservar o estado atual.'}
  $result=Invoke-WinSlimGpuStateChange -Before $current -After $before -Writer {param($s) Set-WinSlimGpuServiceState $s} -Reader {param($n) Read-WinSlimGpuService $n}
 }
 [pscustomobject]@{verified=$true;state=$result;backupId=$backupId;message=$(if($action -eq 'undo'){'Estado original restaurado e verificado.'}else{'Ajuste aplicado e verificado. Backup preservado para desfazer.'})}
}

function Invoke-WinSlimGpuAction {
 param($Request)
 # Machine-wide lock also covers separate application instances.
 $mutex=New-Object Threading.Mutex($false,'Global\WinSlimGpuServicesR1')
 $held=$false
 try{
  try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
  if(-not $held){throw 'Outra operação GPU está em andamento. Aguarde e tente novamente.'}
  Invoke-WinSlimGpuActionCore -Request $Request
 }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}

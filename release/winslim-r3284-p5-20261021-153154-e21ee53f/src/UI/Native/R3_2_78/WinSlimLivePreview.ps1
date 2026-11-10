# Read-only observation of structured registry/service entries in the validated execution order.
# This is a time-stamped observation, never a backup or authorization to apply.
function Resolve-WinSlimPreviewRegistryPath {
 param([string]$Path)
 # Catalogs contain both HKU\.DEFAULT and provider-style HKU:\.DEFAULT.
 if($Path -notmatch '^(HKCU|HKLM|HKU):?\\(.+)$'){throw 'Caminho de registro nao suportado nesta etapa.'}
 $root=$Matches[1];$subpath=$Matches[2]
 $hive=switch($root){
  'HKCU'{[Microsoft.Win32.RegistryHive]::CurrentUser}
  'HKLM'{[Microsoft.Win32.RegistryHive]::LocalMachine}
  'HKU'{[Microsoft.Win32.RegistryHive]::Users}
 }
 [pscustomobject]@{Hive=$hive;SubPath=$subpath}
}
function Read-WinSlimPreviewRegistry {
 param($Operation)
 $resolved=Resolve-WinSlimPreviewRegistryPath -Path ([string]$Operation.Path)
 $hive=$resolved.Hive;$subpath=$resolved.SubPath;$baseKey=$null;$key=$null
 try{
  $view=if([Environment]::Is64BitOperatingSystem){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Registry32}
  $baseKey=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
  $key=$baseKey.OpenSubKey($subpath,$false)
  if($null -eq $key -or $key.GetValueNames() -notcontains [string]$Operation.Name){return [pscustomobject]@{Exists=$false;Value=$null;Kind=$null}}
  [pscustomobject]@{Exists=$true;Value=$key.GetValue([string]$Operation.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);Kind=$key.GetValueKind([string]$Operation.Name).ToString()}
 }finally{if($null -ne $key){$key.Dispose()};if($null -ne $baseKey){$baseKey.Dispose()}}
}
function Read-WinSlimPreviewServices {
 @(Get-CimInstance -ClassName Win32_Service -Property Name,StartMode,State -ErrorAction Stop | Select-Object Name,StartMode,State)
}
function Get-WinSlimLivePreview {
 param([Parameter(Mandatory)][AllowNull()]$Plan,[scriptblock]$RegistryReader={param($op) Read-WinSlimPreviewRegistry $op},[scriptblock]$ServiceReader={Read-WinSlimPreviewServices})
 $entries=if($null -eq $Plan){@()}else{@($Plan.ExecutionOrder)};$items=@();$serviceMap=@{};$serviceError=$null
 if(@($entries | Where-Object {$_.Tweak.type -eq 'service'}).Count -gt 0){
  try{foreach($service in @(& $ServiceReader)){$serviceMap[[string]$service.Name]=$service}}catch{$serviceError=$_.Exception.Message}
 }
 foreach($entry in $entries){
  $tweak=$entry.Tweak;$kind=[string]$tweak.type;$operations=@();$state='Unsupported'
  if($kind -eq 'registry' -or $kind -eq 'service'){
   $targets=if($kind -eq 'registry'){@($tweak.registry)}else{@($tweak.service)}
   foreach($op in $targets){
    if($null -eq $op){continue}
    $target=if($kind -eq 'registry'){[string]$op.Path+'\'+[string]$op.Name}else{[string]$op.Name}
    try{
     if($kind -eq 'registry'){
      if([string]::IsNullOrWhiteSpace([string]$op.Path) -or $null -eq $op.Name -or $op.PSObject.Properties.Name -notcontains 'Value' -or $null -eq $op.Value){throw 'Operacao de registro incompleta.'}
      $current=& $RegistryReader $op
      if($null -eq $current -or $current.PSObject.Properties.Name -notcontains 'Exists'){throw 'Leitura de registro sem resultado valido.'}
      $remove=([string]$op.Value -eq '<Remove>')
      if($remove){$same=-not [bool]$current.Exists}else{
       $expectedKind=[string]$op.Type
       if($expectedKind -notin @('DWord','QWord','String','ExpandString','MultiString','Binary')){throw 'Tipo de registro nao suportado.'}
       $actualValue=ConvertTo-Json -InputObject $current.Value -Depth 10 -Compress
       $desiredValue=ConvertTo-Json -InputObject $op.Value -Depth 10 -Compress
       $same=[bool]$current.Exists -and ([string]$current.Kind -eq $expectedKind) -and ($actualValue -ceq $desiredValue)
      }
      $desired=[pscustomobject]@{Exists=(-not $remove);Value=$op.Value;Kind=$op.Type}
     }else{
      if($null -ne $serviceError){throw $serviceError}
      if(-not $serviceMap.ContainsKey([string]$op.Name)){throw 'Servico ausente neste computador.'}
      $current=$serviceMap[[string]$op.Name]
      $desiredMode=switch([string]$op.StartupType){'Automatic'{'Auto'} 'AutomaticDelayedStart'{'Auto'} 'Manual'{'Manual'} 'Disabled'{'Disabled'} default{throw 'Modo de inicio nao suportado.'}}
      # Actions outside StartupType still require their own verification.
      if($op.PSObject.Properties.Name -contains 'DelayedAutoStart'){throw 'Operacao de servico adicional requer verificacao especifica.'}
      if([string]::IsNullOrWhiteSpace([string]$current.StartMode)){throw 'Modo de inicio indisponivel.'}
      $same=([string]$current.StartMode -eq $desiredMode)
      $desired=[pscustomobject]@{StartMode=$desiredMode}
      if($op.PSObject.Properties.Name -contains 'StopNow'){
       if($op.StopNow -isnot [bool]){throw 'StopNow deve ser booleano.'}
       if($op.StopNow){
        if([string]$current.State -notin @('Running','Stopped')){throw 'Estado do servico em transicao ou desconhecido.'}
        $same=$same -and [string]$current.State -eq 'Stopped'
        $desired | Add-Member -NotePropertyName State -NotePropertyValue 'Stopped'
       }
      }
      if($desiredMode -eq 'Auto'){
       if([string]::IsNullOrWhiteSpace([string]$op.Name) -or [string]$op.Name -match '[\\/]'){throw 'Nome de servico invalido.'}
       $delayOperation=[pscustomobject]@{Path=('HKLM:\SYSTEM\CurrentControlSet\Services\'+[string]$op.Name);Name='DelayedAutoStart'}
       $delay=& $RegistryReader $delayOperation
       if($null -eq $delay -or $delay.PSObject.Properties.Name -notcontains 'Exists'){throw 'Leitura da inicializacao atrasada sem resultado valido.'}
       $delayed=$false
       if([bool]$delay.Exists){
        if([string]$delay.Kind -ne 'DWord' -or $null -eq $delay.Value -or $delay.Value -notin @(0,1)){throw 'Valor de inicializacao atrasada invalido.'}
        $delayed=([int]$delay.Value -eq 1)
       }
       $expectedDelayed=([string]$op.StartupType -eq 'AutomaticDelayedStart')
       $same=$same -and ($delayed -eq $expectedDelayed)
       # Copy the snapshot to preserve the shared CIM result and the plan.
       $current=[pscustomobject]@{Name=$current.Name;StartMode=$current.StartMode;State=$current.State;DelayedAutoStart=$delayed;DelayedAutoStartRegistry=$delay}
       $desired=[pscustomobject]@{StartMode=$desiredMode;DelayedAutoStart=$expectedDelayed}
      }
     }
     $operations += [pscustomobject]@{Target=$target;Status=$(if($same){'AlreadyConfigured'}else{'NeedsChange'});Current=$current;Desired=$desired;Error=$null}
    }catch{$operations += [pscustomobject]@{Target=$target;Status='Unknown';Current=$null;Desired=$null;Error=$_.Exception.Message}}
   }
   $state=if($operations.Count -eq 0 -or @($operations | Where-Object {$_.Status -eq 'Unknown'}).Count -gt 0){'Unknown'}elseif(@($operations | Where-Object {$_.Status -eq 'NeedsChange'}).Count -gt 0){'NeedsChange'}else{'AlreadyConfigured'}
  }
  $items += [pscustomobject]@{TweakId=[string]$entry.TweakId;Type=$kind;Status=$state;Operations=@($operations)}
 }
 [pscustomobject]@{SchemaVersion=1;Available=($null -ne $Plan);ObservedAtUtc=[DateTime]::UtcNow.ToString('o');PlanFingerprint=[string]$Plan.Fingerprint;ReadOnly=$true;IsBackup=$false;CanApply=$false;Items=@($items);Summary=[pscustomobject]@{
  AlreadyConfigured=@($items | Where-Object {$_.Status -eq 'AlreadyConfigured'}).Count
  NeedsChange=@($items | Where-Object {$_.Status -eq 'NeedsChange'}).Count
  Unknown=@($items | Where-Object {$_.Status -eq 'Unknown'}).Count
  Unsupported=@($items | Where-Object {$_.Status -eq 'Unsupported'}).Count
 }}
}

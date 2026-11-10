# Typed, data-only backups. Captures registry/services; never applies a tweak.
function ConvertTo-WinSlimBackupValue {
 param($State)
 if($null -eq $State -or $State.PSObject.Properties.Name -notcontains 'Exists'){throw 'Estado de registro invalido.'}
 if(-not [bool]$State.Exists){return [pscustomobject]@{Exists=$false;Kind=$null;Encoding='None';Value=$null}}
 $kind=[string]$State.Kind
 if($null -eq $State.Value){throw 'Valor de registro indisponivel.'}
 switch($kind){
  'Binary' {$value=[Convert]::ToBase64String([byte[]]$State.Value);$encoding='Base64'}
  'MultiString' {$value=[string[]]@($State.Value);$encoding='StringArray'}
  'DWord' {$value=([int]$State.Value).ToString([Globalization.CultureInfo]::InvariantCulture);$encoding='Int32Decimal'}
  'QWord' {$value=([long]$State.Value).ToString([Globalization.CultureInfo]::InvariantCulture);$encoding='Int64Decimal'}
  'String' {$value=[string]$State.Value;$encoding='String'}
  'ExpandString' {$value=[string]$State.Value;$encoding='String'}
  default {throw 'Tipo de registro sem backup suportado.'}
 }
 [pscustomobject]@{Exists=$true;Kind=$kind;Encoding=$encoding;Value=$value}
}
function Get-WinSlimBackupIdentity {
 $windowsIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{$sid=$windowsIdentity.User.Value}finally{$windowsIdentity.Dispose()}
 $machine=Read-WinSlimPreviewRegistry ([pscustomobject]@{Path='HKLM:\SOFTWARE\Microsoft\Cryptography';Name='MachineGuid'})
 if(-not $machine.Exists -or [string]::IsNullOrWhiteSpace([string]$machine.Value)){throw 'Identidade do computador indisponivel.'}
 [pscustomobject]@{ComputerName=[Environment]::MachineName;MachineGuid=[string]$machine.Value;UserSid=$sid;OSVersion=[Environment]::OSVersion.Version.ToString();RegistryView=$(if([Environment]::Is64BitOperatingSystem){'Registry64'}else{'Registry32'})}
}
function New-WinSlimBackupSnapshot {
 param([Parameter(Mandatory)]$Plan,[string]$Profile,
  [scriptblock]$RegistryReader={param($op) Read-WinSlimPreviewRegistry $op},
  [scriptblock]$ServiceReader={Read-WinSlimPreviewServices},
  [scriptblock]$IdentityReader={Get-WinSlimBackupIdentity})
 if(-not $Plan.CanExecute -or [string]::IsNullOrWhiteSpace([string]$Plan.Fingerprint)){throw 'Plano sem autorizacao para preparar backup.'}
 $started=[DateTime]::UtcNow.ToString('o');$items=@();$excluded=@();$services=@{};$serviceError=$null
 $identity=& $IdentityReader
 if(@($Plan.ExecutionOrder | Where-Object {$_.Tweak.type -eq 'service'}).Count -gt 0){
  try{foreach($svc in @(& $ServiceReader)){$services[[string]$svc.Name]=$svc}}catch{$serviceError=$_.Exception.Message}
 }
 foreach($entry in @($Plan.ExecutionOrder)){
  $tweak=$entry.Tweak;$type=[string]$tweak.type;$ops=@()
  try{
   if($type -notin @('registry','service')){throw 'Tipo ainda sem captura de backup nesta etapa.'}
   $targets=@(if($type -eq 'registry'){$tweak.registry}else{$tweak.service})
   if($targets.Count -eq 0){throw 'Ajuste sem operacoes para capturar.'}
   foreach($op in $targets){
    if($type -eq 'registry'){
     if($null -eq $op -or $null -eq $op.Name){throw 'Operacao de registro invalida.'}
     $resolved=Resolve-WinSlimPreviewRegistryPath ([string]$op.Path)
     $state=& $RegistryReader $op
     $value=ConvertTo-WinSlimBackupValue $state
     $ops += [pscustomobject]@{Hive=$resolved.Hive.ToString();SubPath=$resolved.SubPath;Name=[string]$op.Name;Before=$value}
    }else{
     if($null -ne $serviceError){throw $serviceError}
     $name=[string]$op.Name
     if([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/]'){throw 'Nome de servico invalido.'}
     if(-not $services.ContainsKey($name)){throw 'Servico ausente neste computador.'}
     $svc=$services[$name]
     if([string]$svc.StartMode -notin @('Auto','Manual','Disabled') -or [string]::IsNullOrWhiteSpace([string]$svc.State)){throw 'Estado do servico indisponivel.'}
     $delay=& $RegistryReader ([pscustomobject]@{Path=('HKLM:\SYSTEM\CurrentControlSet\Services\'+$name);Name='DelayedAutoStart'})
     $delayValue=ConvertTo-WinSlimBackupValue $delay
     if($delayValue.Exists -and $delayValue.Kind -ne 'DWord'){throw 'Indicador de atraso do servico invalido.'}
     $ops += [pscustomobject]@{Name=$name;Exists=$true;StartMode=[string]$svc.StartMode;State=[string]$svc.State;DelayedAutoStart=$delayValue}
    }
   }
   $items += [pscustomobject]@{TweakId=[string]$entry.TweakId;Name=[string]$tweak.name;Type=$type;Operations=@($ops)}
  }catch{$excluded += [pscustomobject]@{TweakId=[string]$entry.TweakId;Type=$type;Reason=$_.Exception.Message}}
 }
 if($items.Count -eq 0){throw 'Nenhum ajuste teve o estado capturado por completo. Backup nao criado.'}
 [pscustomobject]@{SchemaVersion=1;Kind='WinSlimRegistryServiceBackup';AppVersion='R3.2.73';Id=[Guid]::NewGuid().ToString('N');Profile=$Profile;PlanFingerprint=[string]$Plan.Fingerprint;CaptureStartedUtc=$started;CreatedAtUtc=[DateTime]::UtcNow.ToString('o');Identity=$identity;Applied=$false;CanApply=$false;CanRestore=$false;RestorePointCreated=$false;Coverage=$(if($excluded.Count -gt 0){'Partial'}else{'CompleteForPlan'});CapturedCount=$items.Count;ExcludedCount=$excluded.Count;Items=@($items);Excluded=@($excluded)}
}
function Get-WinSlimBackupHash {
 param([string]$Path)
 (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Read-WinSlimVerifiedBackup {
 param([string]$Directory)
 $info=Get-Item -LiteralPath $Directory -Force -ErrorAction Stop
 if(($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Pasta de backup redirecionada.'}
 $manifestPath=Join-Path $Directory 'manifest.json';$snapshotPath=Join-Path $Directory 'snapshot.json'
 foreach($path in @($manifestPath,$snapshotPath)){
  $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
  if($file.Length -gt 16MB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Arquivo de backup invalido.'}
 }
 $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
 if($manifest.SchemaVersion -ne 1 -or $manifest.Kind -ne 'WinSlimRegistryServiceBackup' -or $manifest.Sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Manifesto de backup invalido.'}
 $bytes=[IO.File]::ReadAllBytes($snapshotPath)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$actualHash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 if($actualHash -cne [string]$manifest.Sha256){throw 'Integridade do backup nao confere.'}
 $snapshot=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop
 if($snapshot.SchemaVersion -ne 1 -or $snapshot.Kind -ne $manifest.Kind -or $snapshot.Id -cne $manifest.Id -or $snapshot.Id -notmatch '^[a-f0-9]{32}$' -or $snapshot.Applied -ne $false -or $snapshot.CanApply -ne $false -or $snapshot.CanRestore -ne $false){throw 'Formato de snapshot invalido.'}
 if(@($snapshot.Items).Count -lt 1 -or @($snapshot.Items).Count -ne $snapshot.CapturedCount -or @($snapshot.Excluded).Count -ne $snapshot.ExcludedCount){throw 'Cobertura do backup invalida.'}
 [pscustomobject]@{Verified=$true;Path=[IO.Path]::GetFullPath($Directory);Sha256=[string]$manifest.Sha256;Snapshot=$snapshot}
}
function Write-WinSlimBackupDataFile {
 param([string]$Path,[string]$Text)
 $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($Text)
 $stream=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Save-WinSlimBackupSnapshot {
 param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)]$Snapshot)
 if($Snapshot.Id -notmatch '^[a-f0-9]{32}$'){throw 'ID de backup invalido.'}
 [void][IO.Directory]::CreateDirectory($Root)
 $pending=Join-Path $Root ('.pending-'+[Guid]::NewGuid().ToString('N'));$final=Join-Path $Root $Snapshot.Id
 [void][IO.Directory]::CreateDirectory($pending)
 try{
  $snapshotPath=Join-Path $pending 'snapshot.json'
  Write-WinSlimBackupDataFile -Path $snapshotPath -Text (ConvertTo-Json -InputObject $Snapshot -Depth 32)
  $manifest=[pscustomobject]@{SchemaVersion=1;Kind='WinSlimRegistryServiceBackup';Id=$Snapshot.Id;Sha256=(Get-WinSlimBackupHash $snapshotPath)}
  Write-WinSlimBackupDataFile -Path (Join-Path $pending 'manifest.json') -Text (ConvertTo-Json -InputObject $manifest -Depth 4)
  $checked=Read-WinSlimVerifiedBackup $pending
  # Unique directory publication: no overwrite of a previous backup.
  [IO.Directory]::Move($pending,$final)
  Read-WinSlimVerifiedBackup $final
 }finally{if(Test-Path -LiteralPath $pending){Remove-Item -LiteralPath $pending -Recurse -Force -ErrorAction SilentlyContinue}}
}
function Get-WinSlimBackupInventory {
 param([string]$Root)
 $items=@();$invalid=0
 if(Test-Path -LiteralPath $Root){
  foreach($folder in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop | Where-Object {$_.Name -match '^[a-f0-9]{32}$'})){
   try{
    $verified=Read-WinSlimVerifiedBackup $folder.FullName
    $snapshot=$verified.Snapshot
    # The list transfers small summaries; full state is requested only in Details.
    $summary=[pscustomobject]@{Id=$snapshot.Id;Profile=$snapshot.Profile;CreatedAtUtc=$snapshot.CreatedAtUtc;Coverage=$snapshot.Coverage;CapturedCount=$snapshot.CapturedCount;ExcludedCount=$snapshot.ExcludedCount;Items=@($snapshot.Items | Select-Object TweakId,Name,Type)}
    $items += [pscustomobject]@{Verified=$true;Path=$verified.Path;Sha256=$verified.Sha256;Snapshot=$summary}
   }catch{$invalid++}
  }
 }
 [pscustomobject]@{readOnly=$true;Items=@($items | Sort-Object {$_.Snapshot.CreatedAtUtc} -Descending);InvalidCount=$invalid}
}

# R3.2.73: data-only restore, bounded by the current catalog and original identity.
function ConvertFrom-WinSlimRestoreValue {
 param($Value)
 if($null -eq $Value -or $Value.Exists -isnot [bool]){throw 'Estado de registro inválido.'}
 if(-not $Value.Exists){if($Value.Encoding -ne 'None' -or $null -ne $Value.Kind -or $null -ne $Value.Value){throw 'Ausência de valor inválida.'};return $null}
 switch([string]$Value.Kind){
  'DWord' {if($Value.Encoding -ne 'Int32Decimal'){throw 'Tipo inválido.'};return [int]::Parse([string]$Value.Value,[Globalization.CultureInfo]::InvariantCulture)}
  'QWord' {if($Value.Encoding -ne 'Int64Decimal'){throw 'Tipo inválido.'};return [long]::Parse([string]$Value.Value,[Globalization.CultureInfo]::InvariantCulture)}
  'Binary' {if($Value.Encoding -ne 'Base64'){throw 'Tipo inválido.'};return ,([Convert]::FromBase64String([string]$Value.Value))}
  'MultiString' {if($Value.Encoding -ne 'StringArray' -or $Value.Value -isnot [array]){throw 'Tipo inválido.'};foreach($v in $Value.Value){if($v -isnot [string]){throw 'Texto inválido.'}};return ,([string[]]$Value.Value)}
  {$_ -in @('String','ExpandString')} {if($Value.Encoding -ne 'String' -or $Value.Value -isnot [string]){throw 'Tipo inválido.'};return [string]$Value.Value}
  default {throw 'Tipo de registro não suportado para restauração.'}
 }
}
function Test-WinSlimRestoreEqual {
 param($A,$B)
 return ((ConvertTo-Json -InputObject $A -Depth 16 -Compress) -ceq (ConvertTo-Json -InputObject $B -Depth 16 -Compress))
}
function Get-WinSlimRestoreTargets {
 param($Snapshot,$Catalog,$Identity,[string]$TweakId='')
 foreach($field in @('MachineGuid','UserSid','RegistryView')){
  if([string]::IsNullOrWhiteSpace([string]$Identity.$field) -or $Snapshot.Identity.$field -cne $Identity.$field){throw 'Backup pertence a outro computador, usuário ou arquitetura de registro.'}
 }
 $items=@($Snapshot.Items);if($items.Count -lt 1 -or $items.Count -gt 1000){throw 'Quantidade de ajustes inválida.'}
 if($TweakId){$items=@($items | Where-Object {$_.TweakId -ceq $TweakId});if($items.Count -ne 1){throw 'Ajuste não encontrado no backup.'}}
 $targets=@();$seen=@{};$ids=@{}
 foreach($item in $items){
  $id=[string]$item.TweakId
  if($ids.ContainsKey($id) -or -not $Catalog.ContainsKey($id)){throw 'ID duplicado ou fora do catálogo.'};$ids[$id]=$true
  $t=$Catalog[$id];$kind=[string]$item.Type
  if($kind -notin @('registry','service') -or $kind -cne [string]$t.type){throw 'Tipo de ajuste não restaurável.'}
  # Keep one operation as an array: Windows PowerShell 5.1 scalar PSCustomObject.Count is not reliable.
  $allowed=@(if($kind -eq 'registry'){$t.registry}else{$t.service})
  $operations=@($item.Operations)
  if($operations.Count -ne $allowed.Count -or $allowed.Count -lt 1){throw 'Operações do backup diferem do catálogo.'}
  for($i=0;$i -lt $allowed.Count;$i++){
   $op=$operations[$i];$a=$allowed[$i]
   if($kind -eq 'registry'){
    $path=Resolve-WinSlimPreviewRegistryPath ([string]$a.Path)
    if($op.Hive -cne $path.Hive.ToString() -or $op.SubPath -cne $path.SubPath -or $op.Name -cne [string]$a.Name){throw 'Destino de registro fora do contrato do ajuste.'}
    $null=ConvertFrom-WinSlimRestoreValue $op.Before
    $target=[pscustomobject]@{Type=$kind;TweakId=$id;Path=[string]$a.Path;Hive=[string]$op.Hive;SubPath=[string]$op.SubPath;Name=[string]$op.Name;Desired=$op.Before}
    $key=$kind+'|'+$op.Hive+'|'+$op.SubPath+'|'+$op.Name
   }else{
    if($op.Name -cne [string]$a.Name -or $op.Exists -ne $true -or $op.State -notin @('Running','Stopped') -or $op.StartMode -notin @('Auto','Manual','Disabled')){throw 'Estado de serviço inválido ou fora do catálogo.'}
    $null=ConvertFrom-WinSlimRestoreValue $op.DelayedAutoStart
    if($op.DelayedAutoStart.Exists -and $op.DelayedAutoStart.Kind -ne 'DWord'){throw 'Atraso de serviço inválido.'}
    $desired=[pscustomobject]@{Name=[string]$op.Name;StartMode=[string]$op.StartMode;State=[string]$op.State;DelayedAutoStart=$op.DelayedAutoStart}
    $target=[pscustomobject]@{Type=$kind;TweakId=$id;Name=[string]$op.Name;Desired=$desired};$key=$kind+'|'+$op.Name
   }
   if($seen.ContainsKey($key)){if(-not (Test-WinSlimRestoreEqual $seen[$key].Desired $target.Desired)){throw 'Backup contém estados conflitantes para o mesmo destino.'};continue}
   $seen[$key]=$target;$targets+= $target
  }
 }
 return $targets
}
function Read-WinSlimRestoreTarget {
 param($Target)
 if($Target.Type -eq 'registry'){return ConvertTo-WinSlimBackupValue (Read-WinSlimPreviewRegistry $Target)}
 return Read-WinSlimGpuService $Target.Name
}
function Set-WinSlimRestoreRegistry {
 param($Target,$State)
 $value=ConvertFrom-WinSlimRestoreValue $State
 $hive=[Microsoft.Win32.RegistryHive]([Enum]::Parse([Microsoft.Win32.RegistryHive],[string]$Target.Hive))
 $view=if([Environment]::Is64BitOperatingSystem){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Registry32}
 $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view);$key=$null
 try{
  if($State.Exists){$key=$base.CreateSubKey([string]$Target.SubPath);$key.SetValue([string]$Target.Name,$value,[Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$State.Kind)))}
  else{$key=$base.OpenSubKey([string]$Target.SubPath,$true);if($null -ne $key){$key.DeleteValue([string]$Target.Name,$false)}}
 }finally{if($null -ne $key){$key.Dispose()};$base.Dispose()}
}
function Set-WinSlimRestoreTarget {
 param($Target,$State)
 if($Target.Type -eq 'registry'){Set-WinSlimRestoreRegistry $Target $State}else{Set-WinSlimRestoreServiceState $State}
}
function Invoke-WinSlimRestoreTransaction {
 param([object[]]$Targets,[scriptblock]$Reader,[scriptblock]$Writer,[scriptblock]$Journal)
 $touched=@();$changed=0
 try{
  # Check every observed state before the first write.
  foreach($t in $Targets){if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Current)){throw 'O estado mudou após a confirmação. Revise novamente.'}}
  & $Journal 'Started' 0
  foreach($t in $Targets){
   if(Test-WinSlimRestoreEqual $t.Current $t.Desired){continue}
   if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Current)){throw 'Alteração externa detectada durante a restauração.'}
   & $Journal 'Writing' ($touched.Count+1)
   $touched+= $t
   & $Writer $t $t.Desired
   if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Desired)){throw ('Verificação falhou: '+$t.TweakId)}
   $changed++
  }
  foreach($t in $Targets){if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Desired)){throw 'Verificação final não confirmou todos os estados.'}}
  & $Journal 'Completed' $changed
  return [pscustomobject]@{verified=$true;changed=$changed;message='Restauração concluída e verificada.'}
 }catch{
  $failure=$_.Exception.Message;$errors=@()
  for($i=$touched.Count-1;$i -ge 0;$i--){$t=$touched[$i];try{& $Writer $t $t.Current;if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Current)){throw 'Estado anterior não confirmado.'}}catch{$errors+=($t.TweakId+': '+$_.Exception.Message)}}
  try{& $Journal $(if($errors.Count){'RecoveryIncomplete'}else{'RolledBack'}) $touched.Count}catch{$errors+='Falha ao registrar o resultado.'}
  return [pscustomobject]@{verified=$false;changed=0;recovered=($errors.Count -eq 0);message=('Restauração não concluída: '+$failure+' '+$(if($errors.Count){'Recuperação incompleta: '+($errors -join '; ')}else{'As alterações desta tentativa foram desfeitas.'}))}
 }
}
function Get-WinSlimRestoreHash {
 param($Value)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 24 -Compress))))).Replace('-','')}finally{$sha.Dispose()}
}
function Get-WinSlimRestoreContext {
 param($Request)
 $id=[string]$Request.backupId
 if($id -notmatch '\A[a-f0-9]{32}\z'){throw 'Selecione um backup real válido.'}
 $verified=Read-WinSlimVerifiedBackup (Join-Path (Join-Path $script:WinSlimBridgeRoot 'Backups\UI') $id)
 if($verified.Snapshot.Id -cne $id){throw 'Identidade da pasta de backup inválida.'}
 $targets=@(Get-WinSlimRestoreTargets $verified.Snapshot $script:PresetRuntime.CatalogRuntime.ById (Get-WinSlimBackupIdentity) ([string]$Request.tweakId))
 foreach($t in $targets){$t | Add-Member NoteProperty Current (Read-WinSlimRestoreTarget $t)}
 [pscustomobject]@{Verified=$verified;Targets=$targets;StateHash=(Get-WinSlimRestoreHash $targets)}
}
function New-WinSlimRestorePreview {
 param($Request)
 $ctx=Get-WinSlimRestoreContext $Request;$token=[Guid]::NewGuid().ToString('N')
 $script:RestoreAuthorization=[pscustomobject]@{Token=$token;BackupId=[string]$Request.backupId;TweakId=[string]$Request.tweakId;Hash=$ctx.Verified.Sha256;StateHash=$ctx.StateHash;Expires=[DateTime]::UtcNow.AddMinutes(10)}
 [pscustomobject]@{token=$token;count=$(if([string]$Request.tweakId){1}else{$ctx.Verified.Snapshot.CapturedCount});operations=$ctx.Targets.Count;changes=@($ctx.Targets | Where-Object {-not (Test-WinSlimRestoreEqual $_.Current $_.Desired)}).Count;excluded=$ctx.Verified.Snapshot.ExcludedCount;profile=$ctx.Verified.Snapshot.Profile}
}
function Invoke-WinSlimBackupRestore {
 param($Request)
 $auth=$script:RestoreAuthorization;$script:RestoreAuthorization=$null
 if($null -eq $auth -or $auth.Token -cne [string]$Request.token -or $auth.Expires -lt [DateTime]::UtcNow -or $auth.BackupId -cne [string]$Request.backupId -or $auth.TweakId -cne [string]$Request.tweakId){throw 'Confirmação ausente ou expirada. Revise a restauração novamente.'}
 if(-not (Test-WinSlimRestoreAdministrator)){throw 'Abra o aplicativo como administrador para restaurar.'}
 $mutex=New-Object Threading.Mutex($false,'Global\WinSlimGpuServicesR1');$held=$false
 try{
  try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
  if(-not $held){throw 'Outra operação está em andamento.'}
  $ctx=Get-WinSlimRestoreContext $Request
  if($ctx.Verified.Sha256 -cne $auth.Hash -or $ctx.StateHash -cne $auth.StateHash){throw 'Backup ou estado atual mudou. Revise antes de restaurar.'}
  # Persist a verified snapshot of the present state before any write.
  $source=$ctx.Verified.Snapshot;$recovery=$source | ConvertTo-Json -Depth 32 | ConvertFrom-Json
  $recovery.Id=[Guid]::NewGuid().ToString('N');$recovery.Profile='Antes da restauração / '+$source.Profile;$recovery.CreatedAtUtc=[DateTime]::UtcNow.ToString('o');$recovery.CaptureStartedUtc=$recovery.CreatedAtUtc
  if($auth.TweakId){$recovery.Items=@($recovery.Items | Where-Object {$_.TweakId -ceq $auth.TweakId})}
  foreach($item in $recovery.Items){foreach($op in $item.Operations){
   $matches=@($ctx.Targets | Where-Object {$_.Type -eq $item.Type -and $_.Name -ceq $op.Name -and ($item.Type -eq 'service' -or ($_.Hive -ceq $op.Hive -and $_.SubPath -ceq $op.SubPath))})
   if($matches.Count -ne 1){throw 'Não foi possível capturar o estado de recuperação.'}
   if($item.Type -eq 'registry'){$op.Before=$matches[0].Current}else{$op.StartMode=$matches[0].Current.StartMode;$op.State=$matches[0].Current.State;$op.DelayedAutoStart=$matches[0].Current.DelayedAutoStart}
  }}
  $recovery.CapturedCount=@($recovery.Items).Count;$recovery.Excluded=@();$recovery.ExcludedCount=0;$recovery.Coverage='CompleteForPlan'
  $saved=Save-WinSlimBackupSnapshot (Join-Path $script:WinSlimBridgeRoot 'Backups\UI') $recovery
  $journalDir=Join-Path $saved.Path 'restore-journal';[void][IO.Directory]::CreateDirectory($journalDir)
  $journal={param($status,$count) $record=[pscustomobject]@{Status=$status;Count=$count;SourceBackupId=$source.Id;RecoveryBackupId=$recovery.Id;Utc=[DateTime]::UtcNow.ToString('o')};Write-WinSlimBackupDataFile (Join-Path $journalDir ([Guid]::NewGuid().ToString('N')+'.json')) (ConvertTo-Json $record)}
  $result=Invoke-WinSlimRestoreTransaction $ctx.Targets {param($t) Read-WinSlimRestoreTarget $t} {param($t,$s) Set-WinSlimRestoreTarget $t $s} $journal
  $result | Add-Member NoteProperty recoveryBackupId $recovery.Id
  return $result
 }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}

function Set-WinSlimRestoreServiceState {
 param($State)
 $name=[string]$State.Name
 if([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/]'){throw 'Nome de serviço inválido.'}
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

function Test-WinSlimRestoreAdministrator {
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 try{$principal=New-Object Security.Principal.WindowsPrincipal($identity);return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
}

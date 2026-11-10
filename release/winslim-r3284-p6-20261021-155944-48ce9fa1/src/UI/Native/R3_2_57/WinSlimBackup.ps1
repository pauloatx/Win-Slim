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
   $targets=if($type -eq 'registry'){@($tweak.registry)}else{@($tweak.service)}
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
 [pscustomobject]@{SchemaVersion=1;Kind='WinSlimRegistryServiceBackup';AppVersion='R3.2.57';Id=[Guid]::NewGuid().ToString('N');Profile=$Profile;PlanFingerprint=[string]$Plan.Fingerprint;CaptureStartedUtc=$started;CreatedAtUtc=[DateTime]::UtcNow.ToString('o');Identity=$identity;Applied=$false;CanApply=$false;CanRestore=$false;RestorePointCreated=$false;Coverage=$(if($excluded.Count -gt 0){'Partial'}else{'CompleteForPlan'});CapturedCount=$items.Count;ExcludedCount=$excluded.Count;Items=@($items);Excluded=@($excluded)}
}
function Get-WinSlimBackupHash {
 param([string]$Path)
 (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Read-WinSlimVerifiedBackup {
 param([string]$Directory)
 $info=Get-Item -LiteralPath $Directory -ErrorAction Stop
 if(($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Pasta de backup redirecionada.'}
 $manifestPath=Join-Path $Directory 'manifest.json';$snapshotPath=Join-Path $Directory 'snapshot.json'
 foreach($path in @($manifestPath,$snapshotPath)){
  $file=Get-Item -LiteralPath $path -ErrorAction Stop
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

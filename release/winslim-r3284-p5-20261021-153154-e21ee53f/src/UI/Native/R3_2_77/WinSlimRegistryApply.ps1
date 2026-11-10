# Pinned low-risk preferences plus two reviewed machine-wide Edge policies.
# A client sends only opaque tokens. Destinations and values come from the reviewed catalog.
function Get-WinSlimRegistryContract {
 param([string]$Id)
 $advanced='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
 switch -Exact ($Id) {
  'UI-001' {return @('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','AppsUseLightTheme','DWord','0','Explorer')}
  'UI-010' {return @($advanced,'ShowSecondsInSystemClock','DWord','1','Explorer')}
  'UI-017' {return @('Control Panel\Mouse','MouseSpeed','String','0','None')}
  'UI-021' {return @('Software\Microsoft\Windows\CurrentVersion\Search','SearchboxTaskbarMode','DWord','0','Explorer')}
  'UI-023' {return @('SOFTWARE\Policies\Microsoft\Windows\Windows Search','EnableDynamicContentInWSB','DWord','0','Explorer','LocalMachine')}
  'UI-024' {return @('SOFTWARE\Policies\Microsoft\Windows\Explorer','HideRecommendedPersonalizedSites','DWord','1','Explorer','LocalMachine')}

  'UI-004' {return @('Software\Microsoft\Windows\CurrentVersion\Search','SearchboxTaskbarMode','DWord','1','None')}
  'UI-006' {return @(($advanced+'\TaskbarDeveloperSettings'),'TaskbarEndTask','DWord','1','Explorer')}
  'EDGE-001' {return @('SOFTWARE\Policies\Microsoft\Edge','StartupBoostEnabled','DWord','0','ProcessRestart','LocalMachine')}
  'EDGE-002' {return @('SOFTWARE\Policies\Microsoft\Edge','BackgroundModeEnabled','DWord','0','ProcessRestart','LocalMachine')}
  'PILOT-003' {return @('Software\Microsoft\GameBar','AutoGameModeEnabled','DWord','1','None')}
  'PILOT-001' {return @('Control Panel\Keyboard','KeyboardDelay','String','0')}
  'PRIV-017' {return @('Software\Policies\Microsoft\Windows\CloudContent','DisableTailoredExperiencesWithDiagnosticData','DWord','1','None')}
  'PERF-001' {return @('Control Panel\Desktop','MenuShowDelay','String','100')}
  'UI-007' {return @($advanced,'LaunchTo','DWord','1')}
  'UI-008' {return @($advanced,'HideFileExt','DWord','0')}
  'UI-009' {return @('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency','DWord','0')}
  'UI-014' {return @('Software\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager','EnthusiastMode','DWord','1','None')}
  'UI-015' {return @($advanced,'DisallowShaking','DWord','1')}
  'UI-016' {return @('Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState','FullPath','DWord','1')}
 }
}
# Multi-value contracts are pinned independently of catalog/client data, in catalog operation order.
function Get-WinSlimRegistryOperationContracts {
 param([string]$Id,[object[]]$Contract)
 [pscustomobject]@{Path=$Contract[0];Name=$Contract[1];Kind=$Contract[2];Value=$Contract[3]}
 switch -Exact ($Id){
  'UI-001' {[pscustomobject]@{Path=$Contract[0];Name='SystemUsesLightTheme';Kind='DWord';Value='0'}}
  'UI-017' {
   [pscustomobject]@{Path=$Contract[0];Name='MouseThreshold1';Kind='String';Value='0'}
   [pscustomobject]@{Path=$Contract[0];Name='MouseThreshold2';Kind='String';Value='0'}
  }
  'UI-021' {[pscustomobject]@{Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='ShowTaskViewButton';Kind='DWord';Value='0'}}
 }
}
function Test-WinSlimUiBatchSupport {
 param([string]$Id,$Environment)
 if($null -eq $Environment -or $Environment.PSObject.Properties.Name -contains 'DetectionError' -or $Environment.InstallationType -cne 'Client'){return $false}
 $minimum=switch -Exact ($Id){'UI-010'{22631};'UI-023'{22621};'UI-024'{22631};default{10240}}
 if([int]$Environment.Build -lt $minimum){return $false}
 if($Id -in @('UI-023','UI-024')){
  # Supported policy editions; intentionally exclude Home and unknown editions.
  return ([string]$Environment.Edition -cmatch '^(Professional(N|Education|EducationN|Workstation|WorkstationN)?|Enterprise(N|S|SN|G|GN)?|Education(N)?|IoTEnterprise(S|K|SK)?)$')
 }
 return $true
}

# Read the actual local OS, never a client-supplied edition/build.
function Get-WinSlimRegistryEnvironment {
 $base=$null;$key=$null
 try{
  $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
  $key=$base.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion',$false)
  if($null -eq $key){throw 'Chave CurrentVersion ausente.'}
  $build=0
  if(-not [int]::TryParse([string]$key.GetValue('CurrentBuildNumber'),[ref]$build)){throw 'Build do Windows ausente ou inválido.'}
  [pscustomobject]@{Edition=[string]$key.GetValue('EditionID');Build=$build;InstallationType=[string]$key.GetValue('InstallationType');DisplayVersion=[string]$key.GetValue('DisplayVersion')}
 }catch{return [pscustomobject]@{Edition='';Build=0;InstallationType='';DetectionError=$_.Exception.Message}}finally{if($null -ne $key){$key.Dispose()};if($null -ne $base){$base.Dispose()}}
}
function Test-WinSlimTailoredPolicySupport {
 param($Environment)
 if($null -eq $Environment -or ($Environment.PSObject.Properties.Name -contains 'DetectionError')){return $false}
 return ($Environment.InstallationType -ceq 'Client' -and [int]$Environment.Build -ge 15063 -and [string]$Environment.Edition -cmatch '^(Professional(N|Education|EducationN|Workstation|WorkstationN)?|Enterprise(N|S|SN|G|GN)?|Education(N)?|IoTEnterprise(S|K|SK)?)$')
}

function Get-WinSlimTailoredPolicyDiagnostic {
 param($Environment)
 if($null -eq $Environment){return 'Detecção do Windows indisponível. Compatibilidade não confirmada; PRIV-017 excluído.'}
 if($Environment.PSObject.Properties.Name -contains 'DetectionError'){return ('Falha ao detectar o Windows: '+[string]$Environment.DetectionError+' Compatibilidade não confirmada; PRIV-017 excluído.')}
 $family=if([int]$Environment.Build -ge 22000 -and $Environment.InstallationType -ceq 'Client'){'Windows 11'}elseif($Environment.InstallationType -ceq 'Client'){'Windows 10'}else{'Windows'}
 $version=if($Environment.PSObject.Properties.Name -contains 'DisplayVersion'){[string]$Environment.DisplayVersion}else{''}
 $detected=$family+'; edição: '+[string]$Environment.Edition+'; versão: '+$version+'; build: '+[string]$Environment.Build+'; instalação: '+[string]$Environment.InstallationType+'. '
 $reasons=@()
 if($Environment.InstallationType -cne 'Client'){$reasons+='Instalação cliente do Windows não confirmada.'}
 if([int]$Environment.Build -lt 15063){$reasons+='Build inferior ao mínimo 15063 (Windows 10 1703).'}
 $editionCheck=[pscustomobject]@{Edition=$Environment.Edition;Build=15063;InstallationType='Client'}
 if(-not (Test-WinSlimTailoredPolicySupport $editionCheck)){$reasons+='Edição fora das edições autorizadas: Pro, Enterprise, Education ou IoT Enterprise.'}
 if($reasons.Count -eq 0){return ($detected+'Compatível com PRIV-017.')}
 return ($detected+($reasons -join ' ')+' PRIV-017 excluído.')
}


function Get-WinSlimEdgePolicyEnvironment {
 # Read installed Stable Edge file metadata; never start the browser or trust a request payload.
 $os=Get-WinSlimRegistryEnvironment
 $major=0
 foreach($folder in @([Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),[Environment]::GetEnvironmentVariable('ProgramFiles'),[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData))){
  if([string]::IsNullOrWhiteSpace($folder)){continue}
  $file=Join-Path $folder 'Microsoft\Edge\Application\msedge.exe'
  try{
   if(-not [IO.File]::Exists($file)){continue}
   $info=[Diagnostics.FileVersionInfo]::GetVersionInfo($file)
   if($info.ProductName -ine 'Microsoft Edge' -or $info.OriginalFilename -ine 'msedge.exe' -or $info.FileMajorPart -le 0){continue}
   $major=[Math]::Max($major,[int]$info.FileMajorPart)
  }catch{}
 }
 [pscustomobject]@{Windows=$os;EdgeMajor=$major}
}
function Test-WinSlimEdgePolicySupport {
 param([string]$Id,$Environment)
 if($null -eq $Environment -or $null -eq $Environment.Windows){return $false}
 $os=$Environment.Windows
 if($os.PSObject.Properties.Name -contains 'DetectionError' -or $os.InstallationType -cne 'Client' -or [int]$os.Build -lt 10240){return $false}
 $minimum=switch -Exact ($Id){'EDGE-001'{88};'EDGE-002'{77};default{return $false}}
 return ([int]$Environment.EdgeMajor -ge $minimum)
}

function Get-WinSlimRegistryApplyScope {
 param($Plan)
 if($null -eq $Plan -or -not $Plan.CanExecute){throw 'Plano bloqueado. Resolva os conflitos antes de aplicar.'}
 $entries=@();$targets=@();$excluded=@();$seen=@{};$edgeEnvironment=$null
 foreach($entry in @($Plan.ExecutionOrder)){
  $id=[string]$entry.TweakId;$t=$entry.Tweak;$contract=@(Get-WinSlimRegistryContract $id)
  if($contract.Count -eq 0){$excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason='Ainda não liberado para aplicação real nesta etapa.'};continue}
  if($seen.ContainsKey($id)){throw 'Ajuste duplicado no plano.'};$seen[$id]=$true
  $restartScope=if($contract.Count -gt 4){$contract[4]}else{'Explorer'}
  $hive=if($contract.Count -gt 5){$contract[5]}else{'CurrentUser'}
  # Only this reviewed conflict declaration is accepted; all other contracts keep requiring none.
  $conflictsValid=(@($t.conflicts).Count -eq 0)
  if($id -in @('UI-004','UI-021')){
   $opposite=if($id -ceq 'UI-004'){'UI-021'}else{'UI-004'}
   $conflictsValid=(@($t.conflicts).Count -eq 1 -and [string]$t.conflicts[0] -ceq $opposite)
   if([string]$t.mutexGroup -cne 'TASKBAR_SEARCH_MODE'){throw 'Grupo de conflito da pesquisa mudou. Aplicação bloqueada.'}
   if(@($Plan.ExecutionOrder | Where-Object {$_.TweakId -ieq $opposite}).Count -gt 0){throw 'UI-004 conflita com UI-021. Resolva a seleção antes de aplicar.'}
  }
  if($t.id -cne $id -or $t.type -cne 'registry' -or $t.risk -cne 'Baixo' -or $t.requiresRestart -ne $false -or [string]$t.restartScope -cne $restartScope -or -not $conflictsValid -or @($t.dependencies).Count -gt 0 -or @($t.levels).Where({$null -ne $_}).Count -gt 0){throw 'Contrato do ajuste mudou. Aplicação bloqueada.'}
  $ops=@($t.registry);$expected=@(Get-WinSlimRegistryOperationContracts $id $contract);$entryTargets=@()
  if($ops.Count -ne $expected.Count){throw 'Número de operações fora do contrato.'}
  for($operationIndex=0;$operationIndex -lt $ops.Count;$operationIndex++){
   $op=$ops[$operationIndex];$pinned=$expected[$operationIndex];$path=Resolve-WinSlimPreviewRegistryPath ([string]$op.Path)
   $canonical=($path.SubPath -replace '\\+','\').TrimStart([char]'\')
   if($path.Hive.ToString() -cne $hive -or $canonical -ine $pinned.Path -or [string]$op.Name -cne $pinned.Name -or [string]$op.Type -cne $pinned.Kind -or [string]$op.Value -cne $pinned.Value){throw 'Destino, tipo ou valor fora do contrato autorizado.'}
   $value=if($op.Type -eq 'DWord'){[int]$op.Value}else{[string]$op.Value}
   $desired=ConvertTo-WinSlimBackupValue ([pscustomobject]@{Exists=$true;Kind=[string]$op.Type;Value=$value})
   $entryTargets+=[pscustomobject]@{Type='registry';TweakId=$id;DisplayName=[string]$t.name;Path=[string]$op.Path;Hive=$path.Hive.ToString();SubPath=$path.SubPath;Name=[string]$op.Name;Desired=$desired}
  }
  if($id -in @('UI-001','UI-010','UI-017','UI-021','UI-023','UI-024')){
   $environment=Get-WinSlimRegistryEnvironment
   if(-not (Test-WinSlimUiBatchSupport $id $environment)){
    $excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason=('Compatibilidade local não confirmada para '+$id+'. Requer Windows cliente e versão/edição suportadas. Consulte o leia-me do lote UI/QoL.')};continue
   }
   if($id -in @('UI-023','UI-024')){
    if($t.requiresAdmin -ne $true){throw 'Contrato de administrador da política mudou.'}
    if(-not (Test-WinSlimRestoreAdministrator)){$excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason='Política de máquina: afeta todos os usuários e requer administrador.'};continue}
   }
  }
  if($id -ceq 'EDGE-001' -or $id -ceq 'EDGE-002'){
   if($t.requiresAdmin -ne $true){throw 'Contrato de administrador do Edge mudou. Aplicação bloqueada.'}
   if($null -eq $edgeEnvironment){$edgeEnvironment=Get-WinSlimEdgePolicyEnvironment}
   if(-not (Test-WinSlimEdgePolicySupport $id $edgeEnvironment)){
    $minimum=if($id -ceq 'EDGE-001'){88}else{77}
    $excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason=('Requer Microsoft Edge Stable instalado, versão '+$minimum+' ou posterior, no Windows 10/11 cliente. Compatibilidade local não confirmada.')};continue
   }
   if(-not (Test-WinSlimRestoreAdministrator)){
    $excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason='Esta política do Edge afeta todos os usuários. Abra o aplicativo como administrador para aplicar.'};continue
   }
  }
  if($id -ceq 'UI-004'){
   $environment=Get-WinSlimRegistryEnvironment
   if($null -eq $environment -or $environment.PSObject.Properties.Name -contains 'DetectionError' -or $environment.InstallationType -cne 'Client' -or [int]$environment.Build -lt 10240){
    $excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason='Ícone de pesquisa requer Windows 10/11 cliente (build 10240+). Compatibilidade local não confirmada.'};continue
   }
  }
  if($id -ceq 'UI-006'){
   $environment=Get-WinSlimRegistryEnvironment
   # Conservative release boundary: Windows 11 23H2+. Do not infer support from client payloads.
   if($null -eq $environment -or $environment.PSObject.Properties.Name -contains 'DetectionError' -or $environment.InstallationType -cne 'Client' -or [int]$environment.Build -lt 22631){
    $excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason='Encerrar tarefa requer Windows 11 cliente 23H2 ou posterior (build 22631+). Compatibilidade local não confirmada.'};continue
   }
  }
  if($id -ceq 'PILOT-003'){
   $environment=Get-WinSlimRegistryEnvironment
   if($null -eq $environment -or $environment.PSObject.Properties.Name -contains 'DetectionError' -or $environment.InstallationType -cne 'Client' -or [int]$environment.Build -lt 15063){
    $excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason='Modo de Jogo requer Windows cliente, build 15063 ou posterior. Compatibilidade local não confirmada.'};continue
   }
  }
  if($id -ceq 'PRIV-017'){
   $environment=Get-WinSlimRegistryEnvironment
   if(-not (Test-WinSlimTailoredPolicySupport $environment)){
    $excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason=(Get-WinSlimTailoredPolicyDiagnostic $environment)};continue
   }
  }
  $targets+=@($entryTargets)
  $entries+=$entry
 }
 foreach($skip in @($Plan.SkippedTweaks)){if($null -ne $skip){$excluded+=[pscustomobject]@{Id=[string]$skip.TweakId;Name=[string]$skip.TweakId;Reason=[string]$skip.Reason}}}
 [pscustomobject]@{Plan=[pscustomobject]@{CanExecute=$true;Fingerprint=[string]$Plan.Fingerprint;ExecutionOrder=@($entries)};Targets=@($targets);Excluded=@($excluded)}
}
function Get-WinSlimRegistryApplyContext {
 param($Source)
 if($Source.PSObject.Properties.Name -contains 'selectedIds'){$report=Get-WinSlimCustomValidationReport $Source}else{$report=Get-WinSlimHardwarePresetReport -Request $Source}
 $scope=Get-WinSlimRegistryApplyScope $report.Plan
 if($scope.Targets.Count -lt 1){throw 'Nenhum dos ajustes selecionados está liberado para aplicação real nesta etapa.'}
 foreach($t in $scope.Targets){$t | Add-Member NoteProperty Current (Read-WinSlimRestoreTarget $t)}
 [pscustomobject]@{Scope=$scope;Profile=[string]$report.PresetName;Fingerprint=[string]$report.Plan.Fingerprint;StateHash=(Get-WinSlimRestoreHash $scope.Targets);IdentityHash=(Get-WinSlimRestoreHash (Get-WinSlimBackupIdentity))}
}
function Assert-WinSlimRegistryRecovery {
 # An interrupted process must not silently start another batch. A successful manual
 # restore of its verified snapshot clears the pending state after exact read-back.
 $root=Join-Path $script:WinSlimBridgeRoot 'Backups\UI'
 if(-not (Test-Path -LiteralPath $root)){return}
 foreach($folder in @(Get-ChildItem -LiteralPath $root -Directory | Where-Object {$_.Name -match '^[a-f0-9]{32}$'})){
  $dir=Join-Path $folder.FullName 'apply-journal';$intent=Join-Path $dir 'intent.json';$outcome=Join-Path $dir 'outcome.json'
  if(-not (Test-Path -LiteralPath $intent)){continue}
  $receipt=Join-Path $dir 'recovered.json'
  if(Test-Path -LiteralPath $receipt){try{$done=Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json;if($done.recovered -eq $true){continue}}catch{}}
  if(Test-Path -LiteralPath $outcome){try{$done=Get-Content -LiteralPath $outcome -Raw -Encoding UTF8 | ConvertFrom-Json;if($done.verified -eq $true -or $done.recovered -eq $true){continue}}catch{}}
  $backup=Read-WinSlimVerifiedBackup $folder.FullName
  $targets=@(Get-WinSlimRestoreTargets $backup.Snapshot $script:PresetRuntime.CatalogRuntime.ById (Get-WinSlimBackupIdentity))
  $restored=$true
  foreach($t in $targets){if(-not (Test-WinSlimRestoreEqual (Read-WinSlimRestoreTarget $t) $t.Desired)){$restored=$false;break}}
  if(-not $restored){throw ('Aplicação anterior interrompida ou recuperação incompleta. Em Backup / Restauração, restaure o backup '+$folder.Name+' antes de continuar.')}
  # Keep a failed outcome intact for diagnostics; use a separate recovery receipt.
  $receipt=Join-Path $dir 'recovered.json'
  if(Test-Path -LiteralPath $receipt){[IO.File]::Move($receipt,($receipt+'.invalid-'+[Guid]::NewGuid().ToString('N')))}
  Write-WinSlimRegistryReceipt $receipt ('{"recovered":true,"utc":"'+[DateTime]::UtcNow.ToString('o')+'"}')
 }
}
function Write-WinSlimRegistryReceipt {
 param([string]$Path,[string]$Text)
 $pending=$Path+'.pending-'+[Guid]::NewGuid().ToString('N')
 try{Write-WinSlimBackupDataFile $pending $Text;[IO.File]::Move($pending,$Path)}finally{if(Test-Path -LiteralPath $pending){[IO.File]::Delete($pending)}}
}
function New-WinSlimRegistryApplyPreview {
 param($Request)
 $script:RegistryApplyAuthorization=$null
 $session=$script:RegistryPreviewSession
 if($null -eq $session -or [string]$Request.previewToken -cne $session.Token -or ([DateTime]::UtcNow-$session.CreatedUtc).TotalMinutes -gt 10){throw 'Prévia expirada. Revise a seleção novamente.'}
 Assert-WinSlimRegistryRecovery
 $ctx=Get-WinSlimRegistryApplyContext $session.Request
 if($ctx.Fingerprint -cne $session.Fingerprint){throw 'O plano mudou. Revise a seleção novamente.'}
 $token=[Guid]::NewGuid().ToString('N')
 $script:RegistryApplyAuthorization=[pscustomobject]@{Token=$token;Expires=[DateTime]::UtcNow.AddMinutes(5);Source=$session.Request;Fingerprint=$ctx.Fingerprint;StateHash=$ctx.StateHash;IdentityHash=$ctx.IdentityHash}
 [pscustomobject]@{token=$token;items=@($ctx.Scope.Targets);excluded=@($ctx.Scope.Excluded);count=$ctx.Scope.Targets.Count;changes=@($ctx.Scope.Targets | Where-Object {-not (Test-WinSlimRestoreEqual $_.Current $_.Desired)}).Count;profile=$ctx.Profile;risk='Baixo';tweakCount=@($ctx.Scope.Plan.ExecutionOrder).Count;uiMachinePolicyCount=@($ctx.Scope.Targets | Where-Object {$_.TweakId -in @('UI-023','UI-024')}).Count;machinePolicyCount=@($ctx.Scope.Targets | Where-Object {$_.TweakId -in @('EDGE-001','EDGE-002')}).Count}
}
function Send-WinSlimRegistryProgress {
 param([string]$Stage,[int]$Completed,[int]$Total,[string]$TweakId='')
 if($Server -and $script:RegistryRequestId){
  $frame=[pscustomobject]@{id=$script:RegistryRequestId;event='registryProgress';data=[pscustomobject]@{stage=$Stage;completed=$Completed;total=$Total;tweakId=$TweakId}}
  # UI transport failure must not interrupt recovery or turn a verified write into an error.
  try{[Console]::Out.WriteLine(($frame | ConvertTo-Json -Depth 6 -Compress));[Console]::Out.Flush()}catch{}
 }
}
function Invoke-WinSlimRegistryTransaction {
 param([object[]]$Targets,[scriptblock]$Reader,[scriptblock]$Writer,[scriptblock]$Journal,[scriptblock]$Progress={param($s,$n,$total,$id)})
 $touched=@();$items=@();$completed=0
 try{
  foreach($t in $Targets){if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Current)){throw 'O estado mudou após a confirmação. Revise novamente.'}}
  & $Journal 'Started' $null
  foreach($t in $Targets){
   & $Progress 'Applying' $completed $Targets.Count $t.TweakId
   if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Current)){throw ('Alteração externa detectada: '+$t.TweakId)}
   $same=Test-WinSlimRestoreEqual $t.Current $t.Desired
   if(-not $same){
    & $Journal 'Writing' $t
    $touched+=$t
    & $Writer $t $t.Desired
   }
   if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Desired)){throw ('Verificação falhou: '+$t.TweakId)}
   & $Journal 'Verified' $t
   $items+=[pscustomobject]@{Id=$t.TweakId;Name=$t.DisplayName;Status=$(if($same){'AlreadyConfigured'}else{'AppliedVerified'})}
   $completed++; & $Progress 'Verified' $completed $Targets.Count $t.TweakId
  }
  foreach($t in $Targets){if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Desired)){throw ('Verificação final falhou: '+$t.TweakId)}}
  & $Journal 'Completed' $null
  return [pscustomobject]@{verified=$true;recovered=$false;changed=$touched.Count;unchanged=($Targets.Count-$touched.Count);items=@($items);errors=@();message='Aplicação concluída e verificada.'}
 }catch{
  $failure=$_.Exception.Message;$errors=@();$recoveredIds=@()
  & $Progress 'Recovering' 0 $touched.Count ''
  for($i=$touched.Count-1;$i -ge 0;$i--){
   $t=$touched[$i]
   try{& $Writer $t $t.Current;if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Current)){throw 'Estado anterior não confirmado.'};$recoveredIds+=$t.TweakId}catch{$errors+=($t.TweakId+': '+$_.Exception.Message)}
  }
  # Verify the entire touched set again, rather than only each immediate write-back.
  foreach($t in $touched){try{if(-not (Test-WinSlimRestoreEqual (& $Reader $t) $t.Current)){throw 'Recuperação final não confirmada.'}}catch{$errors+=($t.TweakId+': '+$_.Exception.Message);$recoveredIds=@($recoveredIds | Where-Object {$_ -cne $t.TweakId})}}
  try{& $Journal $(if($errors.Count){'RecoveryIncomplete'}else{'RolledBack'}) $null}catch{$errors+='Falha ao persistir o resultado da recuperação.'}
  $items=@($Targets | ForEach-Object {[pscustomobject]@{Id=$_.TweakId;Name=$_.DisplayName;Status=$(if($recoveredIds -contains $_.TweakId){'RolledBack'}elseif(@($touched.TweakId) -contains $_.TweakId){'RecoveryIncomplete'}else{'NotApplied'})}})
  return [pscustomobject]@{verified=$false;recovered=($errors.Count -eq 0);changed=0;unchanged=0;items=@($items);errors=@($errors);message=($failure+' '+$(if($errors.Count){'Recuperação incompleta. Consulte o backup e o relatório.'}else{'As alterações desta tentativa foram desfeitas.'}))}
 }
}
function Invoke-WinSlimRegistryApply {
 param($Request)
 $auth=$script:RegistryApplyAuthorization;$script:RegistryApplyAuthorization=$null
 if($null -eq $auth -or [string]$Request.token -cne $auth.Token -or $auth.Expires -lt [DateTime]::UtcNow){throw 'Confirmação ausente ou expirada. Revise a aplicação novamente.'}
 if(-not (Test-WinSlimRestoreAdministrator)){throw 'Abra o aplicativo como administrador para aplicar.'}
 $mutex=New-Object Threading.Mutex($false,'Global\WinSlimGpuServicesR1');$held=$false
 try{
  try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
  if(-not $held){throw 'Outra operação está em andamento.'}
  Assert-WinSlimRegistryRecovery
  $ctx=Get-WinSlimRegistryApplyContext $auth.Source
  if($ctx.Fingerprint -cne $auth.Fingerprint -or $ctx.StateHash -cne $auth.StateHash -or $ctx.IdentityHash -cne $auth.IdentityHash){throw 'Plano, usuário ou estado atual mudou. Revise antes de aplicar.'}
  Send-WinSlimRegistryProgress 'Backup' 0 $ctx.Scope.Targets.Count
  $snapshot=New-WinSlimBackupSnapshot -Plan $ctx.Scope.Plan -Profile ('Antes da aplicação / '+$ctx.Profile)
  if($snapshot.ExcludedCount -ne 0 -or $snapshot.CapturedCount -ne @($ctx.Scope.Plan.ExecutionOrder).Count){throw 'Backup incompleto. Nenhum ajuste foi aplicado.'}
  $captured=@(Get-WinSlimRestoreTargets $snapshot $script:PresetRuntime.CatalogRuntime.ById (Get-WinSlimBackupIdentity))
  if($captured.Count -ne $ctx.Scope.Targets.Count){throw 'Cobertura do backup difere da aplicação.'}
  for($i=0;$i -lt $captured.Count;$i++){
   $t=$ctx.Scope.Targets[$i];$b=$captured[$i]
   if($b.TweakId -cne $t.TweakId -or $b.Hive -cne $t.Hive -or $b.SubPath -cne $t.SubPath -or $b.Name -cne $t.Name -or -not (Test-WinSlimRestoreEqual $b.Desired $t.Current)){throw 'Estado mudou durante o backup. Nenhum ajuste foi aplicado.'}
  }
  $saved=Save-WinSlimBackupSnapshot (Join-Path $script:WinSlimBridgeRoot 'Backups\UI') $snapshot
  if(-not $saved.Verified){throw 'Backup não verificado. Nenhum ajuste foi aplicado.'}
  $dir=Join-Path $saved.Path 'apply-journal';[void][IO.Directory]::CreateDirectory($dir)
  $intent=[pscustomobject]@{version=1;backupId=$snapshot.Id;utc=[DateTime]::UtcNow.ToString('o');targets=$ctx.Scope.Targets;excluded=$ctx.Scope.Excluded}
  Write-WinSlimBackupDataFile (Join-Path $dir 'intent.json') (ConvertTo-Json $intent -Depth 24)
  Send-WinSlimRegistryProgress 'BackupVerified' 0 $ctx.Scope.Targets.Count
  $journal={param($stage,$target) $record=[pscustomobject]@{stage=$stage;utc=[DateTime]::UtcNow.ToString('o');tweakId=$(if($null -ne $target){$target.TweakId}else{''})};Write-WinSlimBackupDataFile (Join-Path $dir ([Guid]::NewGuid().ToString('N')+'.json')) (ConvertTo-Json $record)}
  $result=Invoke-WinSlimRegistryTransaction $ctx.Scope.Targets {param($t) Read-WinSlimRestoreTarget $t} {param($t,$s) Set-WinSlimRestoreRegistry $t $s} $journal {param($s,$n,$total,$id) Send-WinSlimRegistryProgress $s $n $total $id}
  $result | Add-Member NoteProperty backupId $snapshot.Id
  $result | Add-Member NoteProperty excluded @($ctx.Scope.Excluded)
  $result | Add-Member NoteProperty profile $ctx.Profile
  $result | Add-Member NoteProperty reportPath (Join-Path $dir 'outcome.json')
  $result | Add-Member NoteProperty utc ([DateTime]::UtcNow.ToString('o'))
  try{Write-WinSlimRegistryReceipt $result.reportPath (ConvertTo-Json $result -Depth 24)}catch{$result | Add-Member NoteProperty reportError $_.Exception.Message}
  return $result
 }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}

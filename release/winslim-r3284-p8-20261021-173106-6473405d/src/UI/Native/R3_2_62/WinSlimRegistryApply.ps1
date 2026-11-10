# First real registry release: five pinned, low-risk, per-user preferences.
# A client sends only opaque tokens. Destinations and values come from the reviewed catalog.
function Get-WinSlimRegistryContract {
 param([string]$Id)
 $advanced='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
 switch -Exact ($Id) {
  'PERF-001' {return @('Control Panel\Desktop','MenuShowDelay','String','100')}
  'UI-007' {return @($advanced,'LaunchTo','DWord','1')}
  'UI-008' {return @($advanced,'HideFileExt','DWord','0')}
  'UI-009' {return @('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency','DWord','0')}
  'UI-016' {return @('Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState','FullPath','DWord','1')}
 }
}
function Get-WinSlimRegistryApplyScope {
 param($Plan)
 if($null -eq $Plan -or -not $Plan.CanExecute){throw 'Plano bloqueado. Resolva os conflitos antes de aplicar.'}
 $entries=@();$targets=@();$excluded=@();$seen=@{}
 foreach($entry in @($Plan.ExecutionOrder)){
  $id=[string]$entry.TweakId;$t=$entry.Tweak;$contract=@(Get-WinSlimRegistryContract $id)
  if($contract.Count -eq 0){$excluded+=[pscustomobject]@{Id=$id;Name=[string]$t.name;Reason='Ainda não liberado para aplicação real nesta etapa.'};continue}
  if($seen.ContainsKey($id)){throw 'Ajuste duplicado no plano.'};$seen[$id]=$true
  if($t.id -cne $id -or $t.type -cne 'registry' -or $t.risk -cne 'Baixo' -or $t.requiresRestart -ne $false -or [string]$t.restartScope -cne 'Explorer' -or @($t.conflicts).Count -gt 0 -or @($t.dependencies).Count -gt 0 -or @($t.levels).Where({$null -ne $_}).Count -gt 0){throw 'Contrato do ajuste mudou. Aplicação bloqueada.'}
  $ops=@($t.registry)
  if($ops.Count -ne 1){throw 'Número de operações fora do contrato.'}
  $op=$ops[0];$path=Resolve-WinSlimPreviewRegistryPath ([string]$op.Path)
  $canonical=($path.SubPath -replace '\\+','\').TrimStart([char]'\')
  if($path.Hive.ToString() -cne 'CurrentUser' -or $canonical -ine $contract[0] -or [string]$op.Name -cne $contract[1] -or [string]$op.Type -cne $contract[2] -or [string]$op.Value -cne $contract[3]){throw 'Destino, tipo ou valor fora do contrato autorizado.'}
  $value=if($op.Type -eq 'DWord'){[int]$op.Value}else{[string]$op.Value}
  $desired=ConvertTo-WinSlimBackupValue ([pscustomobject]@{Exists=$true;Kind=[string]$op.Type;Value=$value})
  $targets+=[pscustomobject]@{Type='registry';TweakId=$id;DisplayName=[string]$t.name;Path=[string]$op.Path;Hive=$path.Hive.ToString();SubPath=$path.SubPath;Name=[string]$op.Name;Desired=$desired}
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
 [pscustomobject]@{token=$token;items=@($ctx.Scope.Targets);excluded=@($ctx.Scope.Excluded);count=$ctx.Scope.Targets.Count;changes=@($ctx.Scope.Targets | Where-Object {-not (Test-WinSlimRestoreEqual $_.Current $_.Desired)}).Count;profile=$ctx.Profile;risk='Baixo'}
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
  if($snapshot.ExcludedCount -ne 0 -or $snapshot.CapturedCount -ne $ctx.Scope.Targets.Count){throw 'Backup incompleto. Nenhum ajuste foi aplicado.'}
  $captured=@(Get-WinSlimRestoreTargets $snapshot $script:PresetRuntime.CatalogRuntime.ById (Get-WinSlimBackupIdentity))
  if($captured.Count -ne $ctx.Scope.Targets.Count){throw 'Cobertura do backup difere da aplicação.'}
  for($i=0;$i -lt $captured.Count;$i++){
   $t=$ctx.Scope.Targets[$i];$b=$captured[$i]
   if($b.TweakId -cne $t.TweakId -or -not (Test-WinSlimRestoreEqual $b.Desired $t.Current)){throw 'Estado mudou durante o backup. Nenhum ajuste foi aplicado.'}
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

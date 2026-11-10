#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
trap {Write-Host ('[ERRO] UiBatch: '+$_.Exception.ToString());Write-Host $_.InvocationInfo.PositionMessage;Write-Host $_.ScriptStackTrace;exit 1}
. (Join-Path $Root 'src/UI/Native/R3_2_81/WinSlim.UiBridge.ps1') -LibraryOnly -RootPath $Root
$script:checks=0
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};$script:checks++;Write-Host ('[OK] UiBatch: '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}
function Copy-Data($x){ConvertTo-Json -InputObject $x -Depth 40 | ConvertFrom-Json}
$script:environment=[pscustomobject]@{Build=22631;Edition='Professional';InstallationType='Client'};$script:admin=$true
function Get-WinSlimRegistryEnvironment {$script:environment}
function Test-WinSlimRestoreAdministrator {$script:admin}
$ids=@('UI-001','UI-010','UI-017','UI-021','UI-023','UI-024')
function New-BatchPlan($Selected){[pscustomobject]@{CanExecute=$true;Fingerprint=($Selected -join ',');ExecutionOrder=@($Selected | ForEach-Object {[pscustomobject]@{TweakId=$_;Tweak=$script:PresetRuntime.CatalogRuntime.ById[$_]}})}}
$script:plan=New-BatchPlan $ids
$scope=Get-WinSlimRegistryApplyScope $script:plan
Check ($scope.Targets.Count -eq 10 -and $scope.Plan.ExecutionOrder.Count -eq 6) 'seis ajustes e dez valores distintos'
foreach($entry in $script:plan.ExecutionOrder){
 $one=New-BatchPlan @($entry.TweakId);$ops=@($entry.Tweak.registry)
 Check ((Get-WinSlimRegistryApplyScope $one).Targets.Count -eq $ops.Count) ('contrato real '+$entry.TweakId)
 for($i=0;$i -lt $ops.Count;$i++){
  foreach($field in @('Path','Name','Type','Value')){
   $bad=Copy-Data $one;$bad.ExecutionOrder[0].Tweak.registry[$i].$field='Unauthorized'
   Reject {Get-WinSlimRegistryApplyScope $bad} ('adulteracao rejeitada '+$entry.TweakId+' op '+$i+' '+$field)
  }
 }
 $bad=Copy-Data $one;$bad.ExecutionOrder[0].Tweak.registry+=Copy-Data $ops[0]
 Reject {Get-WinSlimRegistryApplyScope $bad} ('operacao extra rejeitada '+$entry.TweakId)
 $bad=Copy-Data $one;$bad.ExecutionOrder[0].Tweak.restartScope='System'
 Reject {Get-WinSlimRegistryApplyScope $bad} ('reinicio adulterado rejeitado '+$entry.TweakId)
 if($ops.Count -gt 1){
  $bad=Copy-Data $one;$bad.ExecutionOrder[0].Tweak.registry=@($ops[0])
  Reject {Get-WinSlimRegistryApplyScope $bad} ('captura parcial do contrato rejeitada '+$entry.TweakId)
 }
}
foreach($os in @('10','11')){
 $script:environment.Build=if($os -eq '10'){19045}else{22631}
 $real=New-WinSlimExecutionPlan -CatalogTweaks $script:AllTweaks -SelectedIds $ids -Context @{OS=$os;IsAdmin=$true} -ConflictPolicy Block
 $expected=if($os -eq '10'){7}else{10}
 Check ($real.CanExecute -and (Get-WinSlimRegistryApplyScope $real).Targets.Count -eq $expected) ('Planner e filtro local Windows '+$os)
}
$script:environment.Build=22631
$conflict=New-WinSlimExecutionPlan -CatalogTweaks $script:AllTweaks -SelectedIds @('UI-004','UI-021') -Context @{OS='11';IsAdmin=$true} -ConflictPolicy Block
Check (-not $conflict.CanExecute) 'modos de pesquisa mutuamente exclusivos'
$bad=Copy-Data $script:plan;$bad.ExecutionOrder+=[pscustomobject]@{TweakId='UI-004';Tweak=$script:PresetRuntime.CatalogRuntime.ById['UI-004']}
Reject {Get-WinSlimRegistryApplyScope $bad} 'plano conflitante marcado como executavel rejeitado'
foreach($edition in @('Core','CoreSingleLanguage','Unknown')){
 $script:environment.Edition=$edition;$filtered=Get-WinSlimRegistryApplyScope $script:plan
 Check ($filtered.Targets.Count -eq 8 -and $filtered.Excluded.Count -eq 2) ('politicas excluidas em '+$edition)
}
foreach($edition in @('Professional','ProfessionalN','Enterprise','EnterpriseS','Education','IoTEnterpriseS')){
 $script:environment.Edition=$edition
 Check ((Get-WinSlimRegistryApplyScope $script:plan).Targets.Count -eq 10) ('politicas aceitas em '+$edition)
}
$script:environment.Edition='Professional'
foreach($build in @(10239,10240,22000,22620,22621,22630,22631)){
 $script:environment.Build=$build;$count=if($build -lt 10240){0}elseif($build -lt 22621){7}elseif($build -lt 22631){8}else{10}
 Check ((Get-WinSlimRegistryApplyScope $script:plan).Targets.Count -eq $count) ('limites conservadores build '+$build)
}
$script:environment.Build=22631;$script:environment.InstallationType='Server'
Check ((Get-WinSlimRegistryApplyScope $script:plan).Targets.Count -eq 0) 'Server excluido'
$script:environment.InstallationType='Client';$script:environment | Add-Member NoteProperty DetectionError 'fixture'
Check ((Get-WinSlimRegistryApplyScope $script:plan).Targets.Count -eq 0) 'falha de deteccao exclui lote'
$script:environment=$null;Check ((Get-WinSlimRegistryApplyScope $script:plan).Targets.Count -eq 0) 'deteccao ausente exclui lote'
$script:environment=[pscustomobject]@{Build=22631;Edition='Professional';InstallationType='Client'}
$script:admin=$false;Check ((Get-WinSlimRegistryApplyScope $script:plan).Targets.Count -eq 8) 'sem elevacao exclui politicas de maquina';$script:admin=$true
$script:identity=[pscustomobject]@{ComputerName='Fixture';MachineGuid='Fixture';UserSid='Fixture';RegistryView='Registry64'}
function Get-WinSlimBackupIdentity {Copy-Data $script:identity}
function Get-WinSlimCustomValidationReport {param($Request) [pscustomobject]@{Plan=(Copy-Data $script:plan);PresetName='UI batch fixture'}}
$absent=[pscustomobject]@{Exists=$false;Kind=$null;Encoding='None';Value=$null}
function Target-Key($Target){return ($Target.Hive+'|'+$Target.SubPath+'|'+$Target.Name)}
$script:db=@{};$script:original=@{};$script:writes=0;$script:failRead=$false;$script:failBackup=$false;$script:failAt=-1;$script:attempts=0
$i=0
foreach($target in $scope.Targets){
 $key=Target-Key $target
 $state=if(($i % 2) -eq 0){Copy-Data $absent}else{[pscustomobject]@{Exists=$true;Kind=$target.Desired.Kind;Encoding=$(if($target.Desired.Kind -eq 'DWord'){'Int32Decimal'}else{'String'});Value='9'}}
 $script:original[$key]=Copy-Data $state;$script:db[$key]=Copy-Data $state;$i++
}
# Sentinel detects accidental writes outside the declared values.
$script:db['sentinel']='preserved'
function Read-WinSlimPreviewRegistry {
 param($Operation)
 if($script:failRead){throw 'fixture read failed'}
 $path=Resolve-WinSlimPreviewRegistryPath ([string]$Operation.Path)
 $key=$path.Hive.ToString()+'|'+$path.SubPath+'|'+$Operation.Name
 if(-not $script:db.ContainsKey($key)){throw 'unexpected read destination'}
 $state=$script:db[$key]
 [pscustomobject]@{Exists=$state.Exists;Kind=$state.Kind;Value=(ConvertFrom-WinSlimRestoreValue $state)}
}
function Set-WinSlimRestoreRegistry {
 param($Target,$State)
 $key=Target-Key $Target
 if(-not $script:original.ContainsKey($key)){throw 'unexpected write destination'}
 $inventory=@(Get-WinSlimBackupInventory (Join-Path $script:WinSlimBridgeRoot 'Backups/UI'))
 if($inventory.Count -lt 1){throw 'verified backup missing'}
 $script:writes++;$script:attempts++;$script:db[$key]=Copy-Data $State
 if($script:failAt -eq $script:attempts){$script:failAt=-1;throw 'partial write fixture'}
}
$script:originalWriter=${function:Write-WinSlimBackupDataFile}
function Write-WinSlimBackupDataFile {param([string]$Path,[string]$Text) if($script:failBackup){throw 'disk fixture failed'};& $script:originalWriter $Path $Text}
function Authorize {
 $script:RegistryPreviewSession=[pscustomobject]@{Token='batch-fixture';CreatedUtc=[DateTime]::UtcNow;Request=[pscustomobject]@{selectedIds=$ids};Fingerprint=$script:plan.Fingerprint}
 New-WinSlimRegistryApplyPreview ([pscustomobject]@{previewToken='batch-fixture'})
}
function Check-Original {
 foreach($key in $script:original.Keys){Check (Test-WinSlimRestoreEqual $script:db[$key] $script:original[$key]) ('original exato '+$key)}
 Check ($script:db['sentinel'] -ceq 'preserved') 'estado nao relacionado preservado'
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('WinSlimUiBatch-'+[guid]::NewGuid().ToString('N'));$script:WinSlimBridgeRoot=$temp
try{
 $p=Authorize
 Check ($p.count -eq 10 -and $p.tweakCount -eq 6 -and $p.uiMachinePolicyCount -eq 2 -and $p.machinePolicyCount -eq 0) 'previa distingue ajustes valores e politicas Windows'
 $script:environment.Edition='Core'
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token;Edition='Professional'})} 'edicao alterada bloqueia sem confiar no cliente'
 $script:environment.Edition='Professional';$p=Authorize;$script:failRead=$true
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})} 'leitura falha bloqueia';$script:failRead=$false
 $p=Authorize;$script:failBackup=$true
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})} 'backup falha bloqueia';$script:failBackup=$false
 Check ($script:writes -eq 0) 'falhas de preflight nao escrevem'
 # Every setting is applied/restored individually, followed by the complete batch.
 foreach($selection in @(@{Ids=@('UI-001')},@{Ids=@('UI-010')},@{Ids=@('UI-017')},@{Ids=@('UI-021')},@{Ids=@('UI-023')},@{Ids=@('UI-024')},@{Ids=$ids})){
  $script:plan=New-BatchPlan $selection.Ids;$n=(Get-WinSlimRegistryApplyScope $script:plan).Targets.Count
  $p=Authorize;$result=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})
  Check ($result.verified -and $result.changed -eq $n) ('Apply Verify '+($selection.Ids -join ','))
  $saved=Read-WinSlimVerifiedBackup (Join-Path (Join-Path $temp 'Backups/UI') $result.backupId)
  Check ($saved.Verified -and $saved.Snapshot.CapturedCount -eq $selection.Ids.Count -and $saved.Snapshot.ExcludedCount -eq 0) 'backup conta ajustes e cobre todos os valores'
  $back=@(Get-WinSlimRestoreTargets $saved.Snapshot $script:PresetRuntime.CatalogRuntime.ById $script:identity)
  Check ($back.Count -eq $n) 'backup tem todas as operacoes autorizadas'
  $before=$script:writes;$p=Authorize;$same=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})
  Check ($same.verified -and $same.changed -eq 0 -and $same.unchanged -eq $n -and $before -eq $script:writes) 'idempotencia sem escrita'
  $rp=New-WinSlimRestorePreview ([pscustomobject]@{backupId=$result.backupId})
  $undo=Invoke-WinSlimBackupRestore ([pscustomobject]@{backupId=$result.backupId;token=$rp.token})
  Check ($undo.verified -and $undo.changed -eq $n) 'restauracao completa verificada'
  Check-Original
 }
 $script:plan=New-BatchPlan $ids
 # Fail after each possible write, including later values of multi-value tweaks.
 for($failure=1;$failure -le 10;$failure++){
  $script:attempts=0;$script:failAt=$failure;$p=Authorize
  $failed=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})
  Check (-not $failed.verified -and $failed.recovered) ('recuperacao depois da escrita '+$failure)
  Check-Original
 }
 # Partial multi-value snapshots must block all writes.
 $script:originalSnapshot=${function:New-WinSlimBackupSnapshot}
 function New-WinSlimBackupSnapshot {param($Plan,$Profile) $v=& $script:originalSnapshot -Plan $Plan -Profile $Profile;$v.Items[0].Operations=@($v.Items[0].Operations[0]);return $v}
 $before=$script:writes;$p=Authorize
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})} 'backup incompleto de ajuste multivalor rejeitado'
 Check ($before -eq $script:writes) 'snapshot incompleto nao autoriza escrita'
 Set-Item function:New-WinSlimBackupSnapshot $script:originalSnapshot
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
Write-Host ('UiBatch: '+$script:checks+' verificacoes. Seis ajustes; dez valores. IO de Registro simulado; nenhum ajuste de producao aplicado.')
